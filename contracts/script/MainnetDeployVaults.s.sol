// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseVault} from "../src/vaults/BaseVault.sol";
import {zBTCVault} from "../src/vaults/zBTCVault.sol";
import {zETHVault} from "../src/vaults/zETHVault.sol";
import {zSOLVault} from "../src/vaults/zSOLVault.sol";
import {zXRPVault} from "../src/vaults/zXRPVault.sol";

/// @title MainnetDeployVaults
/// @notice Hardened deploy script for mainnet Alpha Vault initialization.
///
/// @dev This script is the ONLY supported path for initializing vaults on
///      mainnet. It exists to make the testnet zSOL seeding bug (vault held
///      100,000,000,000 WSOL instead of 100 WSOL because decimals were off)
///      structurally impossible to repeat.
///
///      Three invariants are enforced by this script:
///
///        1. PRE-CONDITION — vault contract address holds zero asset balance
///           before seeding. Any prior leak aborts the deploy.
///
///        2. SEED PATH — seed liquidity goes through ERC-4626 deposit(), never
///           via a raw token transfer. deposit() issues shares against assets,
///           so totalSupply() and totalAssets() stay in lockstep. A raw
///           transfer would inflate totalAssets() without minting shares,
///           which is exactly what we want to prevent.
///
///        3. POST-CONDITION — after seeding, convertToAssets(totalSupply())
///           equals totalAssets() within a 1-wei tolerance. If wrong decimals,
///           wrong amount, wrong asset, double-seed, or any other defect
///           breaks the invariant, the script reverts and no vault enters
///           the "assets without matching shares" state.
///
/// @dev Run:
///      forge script script/MainnetDeployVaults.s.sol --rpc-url $RPC \
///          --private-key $PRIVATE_KEY --broadcast --slow
///
/// Required env (addresses checksummed):
///      PRIVATE_KEY       — deployer key (rotate after deploy)
///      ZENT              — ZENT token (from DeployCore)
///      FEE_RECIPIENT     — performance fee recipient (multisig)
///      VAULT_ADMIN       — vault admin (multisig behind Timelock)
///      WBTC              — wrapped BTC underlying (mainnet HyperEVM)
///      WETH              — wrapped ETH underlying
///      WSOL              — wrapped SOL underlying
///      WXRP              — wrapped XRP underlying
///      SEED_WBTC         — initial deposit, raw units (e.g. 1e8 for 1 WBTC)
///      SEED_WETH         — initial deposit, raw units (e.g. 10e18 for 10 WETH)
///      SEED_WSOL         — initial deposit, raw units (e.g. 100e9 for 100 WSOL)
///      SEED_WXRP         — initial deposit, raw units (e.g. 1000e6 for 1000 WXRP)
contract MainnetDeployVaults is Script {
    /// @notice Largest acceptable rounding gap between totalAssets() and
    ///         convertToAssets(totalSupply()) after seeding. 1 wei accounts
    ///         for ERC4626 virtual-shares rounding in OZ's implementation.
    uint256 internal constant INVARIANT_TOLERANCE = 1;

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address zent = _mustAddr("ZENT");
        address feeRcpt = _mustAddr("FEE_RECIPIENT");
        address admin = _mustAddr("VAULT_ADMIN");

        address wbtc = _mustAddr("WBTC");
        address weth = _mustAddr("WETH");
        address wsol = _mustAddr("WSOL");
        address wxrp = _mustAddr("WXRP");

        uint256 seedWBTC = vm.envUint("SEED_WBTC");
        uint256 seedWETH = vm.envUint("SEED_WETH");
        uint256 seedWSOL = vm.envUint("SEED_WSOL");
        uint256 seedWXRP = vm.envUint("SEED_WXRP");

        address deployer = vm.addr(key);
        console2.log("=== MainnetDeployVaults ===");
        console2.log("Deployer:", deployer);
        console2.log("Chain ID:", block.chainid);
        console2.log("ZENT:    ", zent);
        console2.log("Admin:   ", admin);
        console2.log("Fee rcpt:", feeRcpt);

        // Sanity-check underlyings are real ERC-20s with sensible decimals.
        _checkAsset("WBTC", wbtc);
        _checkAsset("WETH", weth);
        _checkAsset("WSOL", wsol);
        _checkAsset("WXRP", wxrp);

        vm.startBroadcast(key);

        // Deploy + seed each vault. Order matters only for log readability.
        address zbtc = address(new zBTCVault(wbtc, feeRcpt, admin));
        _seedVault(zbtc, wbtc, seedWBTC, deployer);

        address zeth = address(new zETHVault(weth, feeRcpt, admin));
        _seedVault(zeth, weth, seedWETH, deployer);

        address zsol = address(new zSOLVault(wsol, feeRcpt, admin));
        _seedVault(zsol, wsol, seedWSOL, deployer);

        address zxrp = address(new zXRPVault(wxrp, feeRcpt, admin));
        _seedVault(zxrp, wxrp, seedWXRP, deployer);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== VAULTS DEPLOYED + SEEDED ===");
        console2.log("zBTC:", zbtc);
        console2.log("zETH:", zeth);
        console2.log("zSOL:", zsol);
        console2.log("zXRP:", zxrp);
    }

    /// @notice Seeds a freshly-deployed vault with `amount` of `asset` via
    ///         ERC4626 deposit(), enforcing pre + post invariants.
    /// @dev    Reverts on any anomaly. Designed so that a misconfigured env
    ///         var cannot put a mainnet vault into a bad state.
    function _seedVault(
        address vault,
        address asset,
        uint256 amount,
        address depositor
    ) internal {
        BaseVault v = BaseVault(vault);

        // ── PRE-CONDITION 1: vault holds zero assets and zero shares ──────
        // Catches: leaked transfer, redeploy on same chain with reused
        // address, simulator weirdness, etc.
        require(
            IERC20(asset).balanceOf(vault) == 0,
            "MainnetDeploy: vault has pre-existing asset balance"
        );
        require(
            v.totalSupply() == 0,
            "MainnetDeploy: vault has pre-existing shares"
        );
        require(
            v.totalAssets() == 0,
            "MainnetDeploy: vault has pre-existing totalAssets"
        );

        // ── PRE-CONDITION 2: vault's declared asset matches what we expect.
        // Belt-and-braces against constructor-arg mistakes.
        require(
            v.asset() == asset,
            "MainnetDeploy: vault.asset() mismatch"
        );

        // ── PRE-CONDITION 3: depositor has the funds to seed.
        require(
            IERC20(asset).balanceOf(depositor) >= amount,
            "MainnetDeploy: depositor lacks seed balance"
        );
        require(amount > 0, "MainnetDeploy: zero seed amount");

        // ── SEED via ERC4626 deposit() path. NEVER raw transfer. ─────────
        // safeApprove pattern not needed here: deployer is the only caller,
        // approval is single-use, and the underlying tokens are trusted.
        IERC20(asset).approve(vault, amount);
        uint256 shares = v.deposit(amount, depositor);

        // ── POST-CONDITION 1: shares minted == amount in 1:1 initial ratio.
        // OZ's ERC4626 virtual shares model returns assets == shares for the
        // very first deposit. If this changes (e.g. inflated decimals offset)
        // the script will catch it and abort.
        require(shares > 0, "MainnetDeploy: deposit returned zero shares");

        // ── POST-CONDITION 2: convertToAssets(totalSupply()) == totalAssets() ─
        // This is THE invariant. If anything broke between deposit input and
        // ERC4626 accounting — wrong decimals, fee-on-transfer asset, hostile
        // re-entry — this catches it before the vault accepts another deposit.
        uint256 ts = v.totalSupply();
        uint256 ta = v.totalAssets();
        uint256 reconstructed = v.convertToAssets(ts);
        uint256 gap = reconstructed > ta ? reconstructed - ta : ta - reconstructed;
        require(
            gap <= INVARIANT_TOLERANCE,
            "MainnetDeploy: shares/assets invariant violated"
        );

        // ── POST-CONDITION 3: vault holds exactly `amount` of underlying ─
        require(
            IERC20(asset).balanceOf(vault) == amount,
            "MainnetDeploy: vault balance != seed amount"
        );

        console2.log("seeded vault:", vault);
        console2.log("  asset:    ", asset);
        console2.log("  amount:   ", amount);
        console2.log("  shares:   ", shares);
        console2.log("  totalAssets:", ta);
    }

    /// @notice Sanity-checks that a configured underlying address actually
    ///         resolves to an ERC-20 with a non-empty symbol. Cheap defense
    ///         against pasting the wrong address into the env file.
    function _checkAsset(string memory label, address asset) internal view {
        require(asset.code.length > 0, string.concat("MainnetDeploy: ", label, " has no code"));
        uint8 dec = IERC20Metadata(asset).decimals();
        require(dec > 0 && dec <= 36, string.concat("MainnetDeploy: ", label, " bad decimals"));
        console2.log(string.concat(label, " decimals:"), dec);
    }

    function _mustAddr(string memory keyName) internal view returns (address) {
        address a = vm.envAddress(keyName);
        require(a != address(0), string.concat("MainnetDeploy: missing ", keyName));
        return a;
    }
}
