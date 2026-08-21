// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SpotVault, AggregatorV3Interface} from "../../src/vaults/SpotVault.sol";
import {HyperSwapRouterAdapter, ISwapRouterV3} from "../../src/adapters/HyperSwapRouterAdapter.sol";
import {StrategyExecutor} from "../../src/keeper/StrategyExecutor.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

/// @dev Chainlink-style mock feed (settable price, fresh updatedAt).
contract IntegOracle is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public constant decimals = 8;

    constructor(int256 a) { answer = a; updatedAt = block.timestamp; }
    function setPrice(int256 a) external { answer = a; updatedAt = block.timestamp; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

/// @dev Uniswap-V3-style router mock that fills at the oracle price (zero slippage),
///      mirroring SpotVault's own decimal math so minOut always clears. Holds reserves.
contract OraclePricedRouterV3 is ISwapRouterV3 {
    address public immutable asset;
    address public immutable cash;
    IntegOracle public immutable oracle;
    uint8 immutable aDec;
    uint8 immutable cDec;
    uint8 immutable pDec;

    constructor(address a, address c, address o) {
        asset = a; cash = c; oracle = IntegOracle(o);
        aDec = IERC20Metadata(a).decimals();
        cDec = IERC20Metadata(c).decimals();
        pDec = IntegOracle(o).decimals();
    }

    function exactInputSingle(ExactInputSingleParams calldata p)
        external payable override returns (uint256 out)
    {
        IERC20(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        uint256 px = uint256(oracle.answer());
        if (p.tokenIn == asset) {
            out = (p.amountIn * (10 ** cDec) * px) / ((10 ** aDec) * (10 ** pDec));
        } else {
            out = (p.amountIn * (10 ** aDec) * (10 ** pDec)) / ((10 ** cDec) * px);
        }
        require(out >= p.amountOutMinimum, "Too little received");
        IERC20(p.tokenOut).transfer(p.recipient, out);
    }
}

/// @notice END-TO-END proof that the production spot loop composes through the REAL
///         signed path: SpotVault + StrategyExecutor.executeRebalance (signed) +
///         HyperSwapRouterAdapter (atomic) + a UniV3-style router. A depositor sits in
///         cash through a 50% drawdown and ends with ~2x the underlying vs HOLD —
///         i.e. shares actually move with signal PnL. This is the loop that did NOT
///         exist before this session's three changes.
contract SpotRebalanceLoopTest is Test {
    MockERC20 wbtc;   // underlying, 8 dec
    MockERC20 usdc;   // cash, 6 dec
    IntegOracle oracle;
    OraclePricedRouterV3 router;
    HyperSwapRouterAdapter adapter;
    SpotVault vault;
    StrategyExecutor exec;

    address alice = makeAddr("alice");
    address keeper = makeAddr("keeper");      // holds StrategyExecutor.KEEPER_ROLE (submits txs)
    address governor = makeAddr("governor");

    uint256 constant SIGNER_PK = 0xA11CE;     // GP engine signer
    address signer;

    int256 constant PRICE_50K = 50_000 * 1e8;
    int256 constant PRICE_25K = 25_000 * 1e8;
    uint256 constant TEN_BTC = 10 * 1e8;

    function setUp() public {
        vm.warp(1_700_000_000);
        signer = vm.addr(SIGNER_PK);

        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new IntegOracle(PRICE_50K);
        router = new OraclePricedRouterV3(address(wbtc), address(usdc), address(oracle));
        adapter = new HyperSwapRouterAdapter(address(router), address(wbtc), address(usdc), 500, address(this));

        vault = new SpotVault(
            address(wbtc), address(usdc), address(oracle), 1 hours,
            "Zentory BTC Spot Vault", "zBTCs",
            0,      // rebalanceThresholdBps (always rebalance, for the test)
            100,    // maxSlippageBps (1%)
            0,      // performanceFee off for clarity
            address(this), address(this),
            1 hours, // emergencyRedeemCooldown (1h)
            30 minutes, // twapWindow
            0  // maxOracleDeviationBps (DISABLED — these integration tests exercise
               // 50% price drops to validate the signed rebalance loop; the Q9
               // guard is exercised in TwapCheck.t.sol)
        );
        exec = new StrategyExecutor(makeAddr("hyperCore"), governor);

        // ── Wire the production loop (mirrors DeploySpotStack) ──
        adapter.grantRole(adapter.VAULT_ROLE(), address(vault));
        vault.setSwapAdapter(address(adapter));
        vault.grantRole(vault.KEEPER_ROLE(), address(exec));   // executor drives rebalanceTo
        exec.setAuthorizedSigner(signer);                       // GP engine signer
        exec.grantRole(exec.KEEPER_ROLE(), keeper);             // keeper bot submits txs

        // Fund the router with deep reserves on both legs.
        wbtc.mint(address(router), 1_000 * 1e8);
        usdc.mint(address(router), 100_000_000 * 1e6);

        // Alice's capital.
        wbtc.mint(alice, TEN_BTC);
    }

    function _signRebalance(uint16 bps, uint256 nonce, uint256 expiry) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(exec.REBALANCE_TYPEHASH(), address(vault), bps, nonce, expiry)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", exec.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
        return abi.encodePacked(r, s, v);
    }

    function _rebalance(uint16 bps, uint256 nonce) internal {
        uint256 expiry = block.timestamp + 1 hours;
        bytes memory sig = _signRebalance(bps, nonce, expiry); // precompute (view calls would eat the prank)
        vm.prank(keeper);
        exec.executeRebalance(address(vault), bps, nonce, expiry, sig);
    }

    function test_signedLoop_sitsInCashThroughDrawdown_beatsHold() public {
        // 1) Deposit 10 BTC.
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        uint256 shares = vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
        assertApproxEqRel(vault.convertToAssets(shares), TEN_BTC, 1e12);

        // 2) SIGNED rebalance to FLAT (sell BTC → USDC at $50k) via executeRebalance.
        _rebalance(0, 1);
        assertEq(wbtc.balanceOf(address(vault)), 0, "vault went flat");
        assertGt(usdc.balanceOf(address(vault)), 0, "vault holds cash");
        assertEq(exec.nonces(address(vault)), 1);

        // 3) Price halves. NAV in BTC ~doubles while sitting in cash.
        oracle.setPrice(PRICE_25K);
        assertApproxEqRel(vault.totalAssets(), 2 * TEN_BTC, 1e12);

        // 4) SIGNED rebalance to FULL LONG (rebuy BTC at $25k → ~20 BTC).
        _rebalance(10000, 2);
        assertApproxEqRel(wbtc.balanceOf(address(vault)), 2 * TEN_BTC, 1e12);
        assertEq(exec.nonces(address(vault)), 2);

        // 5) Alice redeems → ~20 BTC. A HOLDer would still have 10.
        vm.prank(alice);
        uint256 received = vault.redeem(shares, alice, alice);
        assertApproxEqRel(received, 2 * TEN_BTC, 1e12, "depositor's BTC ~doubled");
        assertGt(received, TEN_BTC, "beats HOLD in underlying");
    }

    function test_signedLoop_rejectsUnauthorizedSigner() public {
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        vault.deposit(TEN_BTC, alice);
        vm.stopPrank();

        // Sign with the WRONG key → executor rejects, vault untouched.
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(exec.REBALANCE_TYPEHASH(), address(vault), uint16(0), uint256(1), expiry)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", exec.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBADBAD, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(keeper);
        vm.expectRevert(StrategyExecutor.InvalidSignature.selector);
        exec.executeRebalance(address(vault), 0, 1, expiry, badSig);

        assertEq(wbtc.balanceOf(address(vault)), TEN_BTC, "vault unchanged");
        assertEq(exec.nonces(address(vault)), 0, "nonce not consumed");
    }
}
