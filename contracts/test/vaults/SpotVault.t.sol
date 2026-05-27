// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SpotVault, ISpotSwapAdapter, ISpotPriceOracle} from "../../src/vaults/SpotVault.sol";
import {MockERC20} from "../invariants/mocks/MockERC20.sol";

contract MockOracle is ISpotPriceOracle {
    uint256 public priceUsd;          // USD per 1 whole underlying, 8 decimals
    uint8 public constant decimals = 8;
    constructor(uint256 p) { priceUsd = p; }
    function setPrice(uint256 p) external { priceUsd = p; }
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
        uint256 p = oracle.priceUsd();
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
    uint256 constant PRICE_50K = 50_000 * 1e8;
    uint256 constant PRICE_25K = 25_000 * 1e8;
    uint256 constant TEN_BTC = 10 * 1e8;

    function setUp() public {
        wbtc = new MockERC20("Wrapped BTC", "WBTC", 8);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new MockOracle(PRICE_50K);
        adapter = new MockSpotAdapter(address(wbtc), address(usdc), address(oracle));

        vault = new SpotVault(
            address(wbtc), address(usdc), address(oracle),
            "Zentory BTC Vault", "zBTC",
            0,      // rebalanceThresholdBps (0 = always rebalance, for the test)
            100,    // maxSlippageBps (1%)
            0,      // performanceFee (off for clarity)
            address(this), address(this)
        );
        vault.setSwapAdapter(address(adapter));
        vault.grantRole(vault.KEEPER_ROLE(), address(this));

        // Fund the venue deeply so swaps always fill.
        wbtc.mint(address(adapter), 1_000 * 1e8);
        usdc.mint(address(adapter), 100_000_000 * 1e6);

        // Alice's capital.
        wbtc.mint(alice, TEN_BTC);
    }

    function _deposit() internal returns (uint256 shares) {
        vm.startPrank(alice);
        wbtc.approve(address(vault), TEN_BTC);
        shares = vault.deposit(TEN_BTC, alice);
        vm.stopPrank();
    }

    /// The core proof: by sitting in cash through a 50% drawdown and rebuying
    /// lower, the vault ends with ~2x the underlying per share — beating a
    /// passive HOLDer who still has 10 BTC.
    function test_NavMovesWithPnL_andBeatsHoldInUnderlying() public {
        uint256 shares = _deposit();
        assertApproxEqRel(vault.convertToAssets(shares), TEN_BTC, 1e12, "start = 10 BTC");

        // FLAT at $50k: sell all BTC -> USDC. NAV in BTC unchanged at same price.
        vault.rebalanceTo(0);
        assertApproxEqRel(vault.totalAssets(), TEN_BTC, 1e12, "flat: value preserved in BTC");
        assertEq(wbtc.balanceOf(address(vault)), 0, "no BTC while flat");

        // Price halves to $25k while the vault sits in USDC.
        oracle.setPrice(PRICE_25K);

        // The cash now buys 2x BTC -> NAV in BTC ~doubles.
        assertApproxEqRel(vault.totalAssets(), 2 * TEN_BTC, 1e12, "flat through drop: 2x BTC value");

        // LONG at $25k: rebuy BTC with the cash -> ~20 BTC held.
        vault.rebalanceTo(10000);
        assertApproxEqRel(wbtc.balanceOf(address(vault)), 2 * TEN_BTC, 1e12, "long: ~20 BTC");

        // Alice redeems: receives ~20 BTC vs the 10 BTC a HOLDer would have.
        vm.prank(alice);
        uint256 received = vault.redeem(shares, alice, alice);
        assertApproxEqRel(received, 2 * TEN_BTC, 1e12, "depositor doubled their BTC");
        assertGt(received, TEN_BTC, "beats passive HOLD in underlying");
    }

    /// Withdrawals are honoured even when the vault is flat (in cash): it swaps
    /// USDC -> WBTC to pay out the underlying.
    function test_WithdrawWhileFlat() public {
        uint256 shares = _deposit();
        vault.rebalanceTo(0); // go to cash
        assertEq(wbtc.balanceOf(address(vault)), 0, "flat");

        vm.prank(alice);
        uint256 received = vault.redeem(shares, alice, alice);
        // Same price as deposit -> ~10 BTC back.
        assertApproxEqRel(received, TEN_BTC, 1e12, "withdraw while flat returns underlying");
    }
}
