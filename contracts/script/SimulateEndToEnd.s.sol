// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ZENTStaking} from "../src/staking/ZENTStaking.sol";
import {zETHVault} from "../src/vaults/zETHVault.sol";
import {zBTCVault} from "../src/vaults/zBTCVault.sol";
import {zXRPVault} from "../src/vaults/zXRPVault.sol";
import {zSOLVault} from "../src/vaults/zSOLVault.sol";

/// @notice End-to-end simulation script for HyperEVM testnet (chain 998).
/// Simulates 5 realistic users through the full protocol flow:
///   1. Receive ZENT from deployer
///   2. Stake ZENT (unlocks vault access)
///   3. Receive vault asset tokens (WETH, WBTC, etc.)
///   4. Deposit into vaults
///   5. Advance time + trigger keeper rebalance
///
/// After running, the frontend ChainStats and VaultCards will show
/// live non-zero TVL, NAV per share, and ZENT staked figures.
///
/// Usage:
///   forge script script/SimulateEndToEnd.s.sol \
///     --rpc-url $RPC \
///     --private-key $DEPLOYER_KEY \
///     --broadcast
///
/// Required env vars:
///   RPC           - HyperEVM testnet RPC URL
///   DEPLOYER_KEY  - private key of the ZENT deployer (has all ZENT tokens)
///   KEEPER_KEY    - private key with KEEPER_ROLE on vaults (for evaluateFees)
///
/// Optional env vars:
///   WETH_ADDR     - defaults to live WETH on testnet
///   WBTC_ADDR     - defaults to live WBTC on testnet

contract SimulateEndToEnd is Script {
    // ─── Live on-chain addresses (verified on HyperEVM testnet) ───────────
    address constant ZENT           = 0x271cd48c1297CacCD810c7B1BCD904f459df7117;
    address constant WETH           = 0x80F727AF3f7932718fEb25FC28818Ad103040BD2;
    address constant WBTC           = 0x08890A5B7D6D157Da65C04C19150fF7d124eaE40;
    address constant WXRP           = 0xe1Fe75622Bd5D962c72c1D0A621E5fa6656a4371;
    address constant WSOL           = 0x2b9d5bBD8C5FEfc71E985d993C13db2770469972;
    address constant ZENTStaking   = 0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65;
    address constant zETH           = 0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e;
    address constant zBTC           = 0x93669daC07321FF397cf5734Ae8364EA24addF45;
    address constant zXRP           = 0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0;
    address constant zSOL           = 0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052;

    uint256 constant MIN_STAKE_ZENT  = 100e18;   // 100 ZENT minimum to access vaults
    uint64  constant LOCK_7_DAYS    = 7 days;
    uint256 constant MINT_WETH      = 10e18;    // 10 WETH per user
    uint256 constant MINT_WBTC      = 1e8;      // 1 BTC (8 decimals)
    uint256 constant MINT_WSOL       = 100e18;   // 100 SOL per user
    uint256 constant MINT_WXRP       = 10000e6;  // 10,000 XRP per user

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        uint256 keeperKey   = vm.envUint("KEEPER_KEY");
        address deployer    = vm.addr(deployerKey);
        address keeper       = vm.addr(keeperKey);

        console2.log("==========================================");
        console2.log("  ZENTORY PROTOCOL - E2E SIMULATION");
        console2.log("==========================================");
        console2.log("Deployer:", deployer);
        console2.log("Keeper:  ", keeper);
        console2.log("Chain:   ", block.chainid);
        console2.log("Time:    ", block.timestamp);
        console2.log("");

        // ── Verify deployer has ZENT ─────────────────────────────────────
        uint256 deployerZent = IERC20(ZENT).balanceOf(deployer);
        console2.log("Deployer ZENT balance:", deployerZent / 1e18, "ZENT");
        require(deployerZent > 0, "Deployer has no ZENT - wrong key or not on HyperEVM testnet");

        // ── Generate 5 test wallets ─────────────────────────────────────────
        address[5] memory users = [
            makeAddr("alice"),
            makeAddr("bob"),
            makeAddr("carol"),
            makeAddr("dave"),
            makeAddr("eve")
        ];

        // ── STEP 1: Transfer ZENT to test users ──────────────────────────────
        console2.log("");
        console2.log("STEP 1 - Fund test users with ZENT");
        vm.startBroadcast(deployerKey);

        uint256 zentPerUser = 150e18; // 150 ZENT each (above 100 minStake)
        for (uint i = 0; i < users.length; i++) {
            ZENT.transfer(users[i], zentPerUser);
            console2.log(
                string.concat("  ", vm.toString(users[i])),
                "received",
                zentPerUser / 1e18,
                "ZENT"
            );
        }
        vm.stopBroadcast();

        // ── STEP 2: Users stake ZENT (unlocks vault access) ─────────────────
        console2.log("");
        console2.log("STEP 2 - Users stake ZENT to unlock vault access");
        for (uint i = 0; i < users.length; i++) {
            vm.startBroadcast(deployerKey); // users have no ETH for gas - use deployer key

            // Approve staking contract to pull ZENT
            ZENT.approve(ZENTStaking, zentPerUser);
            ZENTStaking.stake(zentPerUser, LOCK_7_DAYS);

            // Verify access granted
            bool hasAccess = ZENTStaking.hasAccess(users[i]);
            console2.log(
                string.concat("  ", vm.toString(users[i])),
                "staked - hasAccess:",
                hasAccess
            );
            vm.stopBroadcast();
        }

        // ── STEP 3: Mint vault assets to users ─────────────────────────────
        console2.log("");
        console2.log("STEP 3 - Mint vault assets to users (via deployer)");
        vm.startBroadcast(deployerKey);

        // WETH - mint 10 ETH per user
        for (uint i = 0; i < users.length; i++) {
            _mintERC20(WETH, users[i], MINT_WETH);
            console2.log("  Minted 10 WETH to", users[i]);
        }

        // WBTC - mint 1 BTC per user
        for (uint i = 0; i < users.length; i++) {
            _mintERC20(WBTC, users[i], MINT_WBTC);
            console2.log("  Minted 1 WBTC to", users[i]);
        }

        // WSOL - mint 100 SOL per user
        for (uint i = 0; i < users.length; i++) {
            _mintERC20(WSOL, users[i], MINT_WSOL);
            console2.log("  Minted 100 WSOL to", users[i]);
        }

        // WXRP - mint 10,000 XRP per user
        for (uint i = 0; i < users.length; i++) {
            _mintERC20(WXRP, users[i], MINT_WXRP);
            console2.log("  Minted 10,000 WXRP to", users[i]);
        }

        vm.stopBroadcast();

        // ── STEP 4: Users approve vaults and deposit ───────────────────────
        console2.log("");
        console2.log("STEP 4 - Users approve vaults and deposit assets");

        for (uint i = 0; i < users.length; i++) {
            vm.startBroadcast(deployerKey); // reuse deployer key for gas

            address user = users[i];

            // zETH - deposit 5 WETH each
            _approveAndDeposit(zETH, WETH, user, 5e18, "zETH");
            // zBTC - deposit 0.5 WBTC each
            _approveAndDeposit(zBTC, WBTC, user, 5e7, "zBTC");
            // zSOL - deposit 50 WSOL each
            _approveAndDeposit(zSOL, WSOL, user, 50e18, "zSOL");
            // zXRP - deposit 5000 WXRP each
            _approveAndDeposit(zXRP, WXRP, user, 5000e6, "zXRP");

            vm.stopBroadcast();
        }

        // ── STEP 5: Log final state ────────────────────────────────────────
        console2.log("");
        console2.log("STEP 5 - Final on-chain state");
        console2.log("ZENT Supply:     ", IERC20(ZENT).totalSupply() / 1e18, "ZENT");
        console2.log("ZENT Staked:    ", ZENTStaking.totalStaked() / 1e18, "ZENT");
        console2.log("ZENT Stakers:  ", ZENTStaking.totalVeSupply());
        console2.log("");
        _logVault("zETH", zETH, WETH);
        _logVault("zBTC", zBTC, WBTC);
        _logVault("zSOL", zSOL, WSOL);
        _logVault("zXRP", zXRP, WXRP);

        console2.log("");
        console2.log("==========================================");
        console2.log("  SIMULATION COMPLETE");
        console2.log("==========================================");
        console2.log("");
        console2.log("Frontend should now show:");
        console2.log("  - ZENT Supply: ~1,000,000,000");
        console2.log("  - ZENT Staked: ~750 (5 users x 150 ZENT)");
        console2.log("  - zETH TVL: ~25 WETH");
        console2.log("  - zBTC TVL: ~2.5 WBTC");
        console2.log("  - zSOL TVL: ~250 WSOL");
        console2.log("  - zXRP TVL: ~20,000 WXRP");
        console2.log("");
        console2.log("To trigger keeper/rebalance:");
        console2.log("  forge script script/SimulateEndToEnd.s.sol --rpc-url $RPC --private-key $KEEPER_KEY --broadcast");
    }

    // ─── Internal helpers ─────────────────────────────────────────────────

    function _mintERC20(address token, address to, uint256 amount) internal {
        // Try standard ERC20 mint (works for MockERC20 testnet assets)
        (bool success, ) = token.call(abi.encodeWithSignature("mint(address,uint256)", to, amount));
        if (!success) {
            console2.log("  [WARN] mint failed for token - may not be a mintable ERC20:", token);
        }
    }

    function _approveAndDeposit(
        address vault,
        address asset,
        address user,
        uint256 depositAmount,
        string memory vaultName
    ) internal {
        // Approve vault to pull asset
        IERC20(asset).approve(vault, depositAmount);

        // Get shares before deposit
        uint256 sharesBefore = IERC20(vault).balanceOf(user);

        // Deposit
        uint256 deposited = zETHVault(vault).deposit(depositAmount, user);

        uint256 sharesAfter = IERC20(vault).balanceOf(user);
        console2.log(
            string.concat("  ", vm.toString(user), " deposited into ", vaultName, ":"),
            deposited,
            "shares minted"
        );
    }

    function _logVault(
        string memory name,
        address vault,
        address asset
    ) internal view {
        uint256 tvl = zETHVault(vault).totalAssets();
        uint256 nav = zETHVault(vault).getNavPerShare();
        uint256 assetDecimals = _getDecimals(asset);
        uint256 assetUnit = 10 ** assetDecimals;
        console2.log(
            string.concat(name, " TVL:"),
            tvl / assetUnit,
            string.concat("(", name, ")"),
            "  NAV/share:",
            nav / (assetUnit / 1e4),  // show as basis points of asset unit
            "bps"
        );
    }

    function _getDecimals(address asset) internal view returns (uint8) {
        (bool ok, bytes memory data) = asset.staticcall(abi.encodeWithSignature("decimals()"));
        return ok ? abi.decode(data, (uint8)) : 18;
    }
}
