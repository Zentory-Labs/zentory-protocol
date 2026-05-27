// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SpotVault, ISpotSwapAdapter, AggregatorV3Interface} from "../../src/vaults/SpotVault.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

/// @dev Chainlink-style mock feed with settable answer + updatedAt (for staleness).
contract MockOracle is AggregatorV3Interface {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public constant decimals = 8;

    constructor(int256 a) { answer = a; updatedAt = block.timestamp; }
    function setPrice(int256 a) external { answer = a; updatedAt = block.timestamp; }
    function setUpdatedAt(uint256 t) external { updatedAt = t; }   // for staleness tests
    function setAnswer(int256 a) external { answer = a; }          // without refreshing time

    function latestRoundData()
        external view returns (uint80, int256, uint256, uint256, uint80)
    {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

/// @dev Perfect-fill spot venue priced off the oracle (no slippage), for tests.
contract MockSpotAdapter is ISpotSwapAdapter {
    address public immutable asset;
    address public immutable cash;
    MockOracle public immutable oracle;
    uint8 immutable aDec; uint8 immutable cDec; uint8 immutable pDec;

    constructor(address asset_, address cash_, address oracle_) {
        asset = asset_; cash = cash_; oracle = MockOracle(oracle_);
        aDec = IERC20Metadata(asset_).decimals();
        cDec = IERC20Metadata(cash_).decimals();
        pDec = MockOracle(oracle_).decimals();
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut)
        external returns (uint256 out)
    {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        uint256 p = uint256(oracle.answer());
        if (tokenIn == asset && tokenOut == cash) {
            out = (amountIn * (10 ** cDec) * p) / ((10 ** aDec) * (10 ** pDec));
        } else if (tokenIn == cash && tokenOut == asset) {
            out = (amountIn * (10 ** aDec) * (10 ** pDec)) / ((10 ** cDec) * p);
        } else {
            revert("unsupported pair");
        }
        require(out >= minOut, "mock slippage");
        IERC20(tokenOut).transfer(msg.sender, out);
    }
}

contract SpotVaultTest is Test {
    MockERC20 wbtc;   // underlying, 8 dec
    MockERC20 usdc;   // cash, 6 dec
    MockOracle oracle;
    MockSpotAdapter adapter;
    SpotVault vault;

    address alice = makeAddr("alice");
    int256 constant PRICE_50K = 50_000 * 1e8;
    int256 constant PRICE_25K = 25_000 * 1e8;
    uint256 constant TEN_BTC = 10 * 1e8;
    uint256 constant MAX_STALE = 1 hours;

    function setUp() public {
        vm.warp(1_700_000_000); // a sane non-zero timestamp
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new MockOracle(PRICE_50K);
        adapter = new MockSpotAdapter(address(wbtc), address(usdc), address(oracle));

        vault = new SpotVault(
            address(wbtc), address(usdc), address(oracle), MAX_STALE,
            "Zentory BTC Vault", "zBTC",
            0,      // rebalanceThresholdBps (0 = always rebalance, for the test)
            100,    // maxSlippageBps (1%)
            0,      // performanceFee (off for clarity)
            address(this), address(this)
        );
        vault.setSwapAdapter(address(adapter));
        vault.grantRole(vault.KEEPER_ROLE(), address(this));

        wbtc.mint(address(adapter), 1_000 * 1e8);
        usdc.mint(address(adapter), 100_000_000 * 1e6);
        wbtc.mint(alice, TEN_BTC);
    }

    function _deposit() internal returns (uint256 shares) {
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        shares = vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
    }

    function test_NavMovesWithPnL_andBeatsHoldInUnderlying() public {
        uint256 shares = _deposit();
        assertApproxEqRel(vault.convertToAssets(shares), TEN_BTC, 1e12, "start = 10 BTC");

        vault.rebalanceTo(0);
        assertApproxEqRel(vault.totalAssets(), TEN_BTC, 1e12, "flat: value preserved in BTC");
        assertEq(wbtc.balanceOf(address(vault)), 0, "no BTC while flat");

        oracle.setPrice(PRICE_25K); // 50% drop while in cash
        assertApproxEqRel(vault.totalAssets(), 2 * TEN_BTC, 1e12, "flat through drop: 2x BTC value");

        vault.rebalanceTo(10000);
        assertApproxEqRel(wbtc.balanceOf(address(vault)), 2 * TEN_BTC, 1e12, "long: ~20 BTC");

        vm.prank(alice);
        uint256 received = vault.redeem(shares, alice, alice);
        assertApproxEqRel(received, 2 * TEN_BTC, 1e12, "depositor doubled their BTC");
        assertGt(received, TEN_BTC, "beats passive HOLD in underlying");
    }

    function test_WithdrawWhileFlat() public {
        uint256 shares = _deposit();
        vault.rebalanceTo(0);
        assertEq(wbtc.balanceOf(address(vault)), 0, "flat");
        vm.prank(alice);
        uint256 received = vault.redeem(shares, alice, alice);
        assertApproxEqRel(received, TEN_BTC, 1e12, "withdraw while flat returns underlying");
    }

    // ─── Oracle safety (the #1 NAV risk) ─────────────────────────────────────

    function test_StaleOracleReverts_whenHoldingCash() public {
        _deposit();
        vault.rebalanceTo(0);                 // now holds USDC -> NAV needs the oracle
        vm.warp(block.timestamp + MAX_STALE + 1);   // feed goes stale
        vm.expectRevert();                    // fail-closed: NAV reverts on stale feed
        vault.totalAssets();
    }

    function test_FullyLongNeedsNoOracle_evenIfStale() public {
        _deposit();                           // fully long (all WBTC), no cash leg
        vm.warp(block.timestamp + MAX_STALE + 1);
        // NAV is just the WBTC balance -> no oracle call -> does not revert.
        assertApproxEqRel(vault.totalAssets(), TEN_BTC, 1e12, "long NAV oracle-independent");
    }

    function test_InvalidPriceReverts() public {
        _deposit();
        vault.rebalanceTo(0);                 // holds cash
        oracle.setAnswer(0);                  // bad feed value (no time refresh)
        vm.expectRevert();
        vault.totalAssets();
    }

    function test_ConstructorRejectsZeroStaleness() public {
        vm.expectRevert(bytes("zero staleness"));
        new SpotVault(address(wbtc), address(usdc), address(oracle), 0,
            "x", "x", 0, 100, 0, address(this), address(this));
    }
}
