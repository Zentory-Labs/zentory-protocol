// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ZENT} from "../src/ZENT.sol";
import {ZENTVesting} from "../src/ZENTVesting.sol";
import {ZENTStaking} from "../src/staking/ZENTStaking.sol";
import {ModelBonding} from "../src/staking/ModelBonding.sol";
import {FeeDistributor} from "../src/fees/FeeDistributor.sol";
import {BaseVault} from "../src/vaults/BaseVault.sol";
import {HyperCoreAdapter} from "../src/keeper/HyperCoreAdapter.sol";
import {StrategyExecutor} from "../src/keeper/StrategyExecutor.sol";
import {Timelock} from "../src/governance/Timelock.sol";
import {Zentroller} from "../src/governance/Zentroller.sol";
import {ZentGovernor} from "../src/governance/ZentGovernor.sol";

/// @notice Minimal ERC20 mock for deployment tests (provides decimals() for vault constructor).
contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(msg.sender, type(uint256).max);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

/// @notice Tests that exercise the full protocol deployment wiring without env vars.
/// @dev  These are unit tests that call the deployment logic directly.
///       For integration testing with env vars, use `forge script` from the shell:
///         forge script script/DeployPipeline.s.sol --rpc-url $HYPEREVM_TESTNET
///              --private-key $PRIVATE_KEY --broadcast -vvv
contract DeployPipelineTest is Test {
    // ─── Constants matching .env.example ─────────────────────────────────────
    address constant TREASURY   = address(0xabcd);
    address constant TEAM_1     = address(0x1111);
    address constant TEAM_2     = address(0x1112);
    address constant TEAM_3     = address(0x1113);
    address constant TEAM_4     = address(0x1114);
    address constant TEAM_5     = address(0x1115);
    address constant BACKER_1   = address(0x2221);
    address constant BACKER_2   = address(0x2222);
    address constant BACKER_3   = address(0x2223);
    address constant PROPOSER   = address(0x3333);
    address constant KEEPER     = address(0x4444);
    address constant GUARDIAN   = address(0x5555);
    // In Forge tests, msg.sender = address(this). We use a separate constant
    // to represent the intended deployer (multisig) identity.
    address constant DEPLOYER   = address(0xeeee);

    // ─── Deployment state ───────────────────────────────────────────────────
    ZENT       public zent;
    ZENTVesting public vesting;
    ZENTStaking public staking;
    ModelBonding public bonding;
    FeeDistributor public zethFees;
    FeeDistributor public zbtcFees;
    FeeDistributor public zxrpFees;
    FeeDistributor public zsolFees;
    BaseVault  public zeth;
    BaseVault  public zbtc;
    BaseVault  public zxrp;
    BaseVault  public zsol;
    Timelock    public timelock;
    Zentroller  public zentroller;
    ZentGovernor public governor;
    HyperCoreAdapter public adapter;
    StrategyExecutor public executor;

    // ─── Test config ────────────────────────────────────────────────────────
    uint256 constant MIN_STAKE       = 100e18;
    uint64  constant UNBOND_COOLDOWN = 14 days;
    uint256 constant VOTING_DELAY    = 1 days;
    uint256 constant VOTING_PERIOD   = 7 days;
    uint256 constant PROPOSAL_THRESHOLD = 1_000_000e18;
    uint256 constant QUORUM_BPS      = 1500;
    uint256 constant TIMELOCK_DELAY  = 48 hours;

    function setUp() external {
        // In Forge tests, msg.sender = address(this) (the test contract).
        // No prank needed for deployment.
        // NOTE: In --isolate mode, address(this) differs from DEPLOYER (address(0xeeee)).
        // To avoid AccessControl issues, Timelock uses address(this) as admin.

        // ─── PHASE 1: CORE ───────────────────────────────────────────────────
        zent    = new ZENT();
        vesting = new ZENTVesting(address(zent));

        // Fund team vesting
        address[] memory teamWallets    = new address[](5);
        uint256[] memory teamAmounts    = new uint256[](5);
        uint64[] memory teamCliffs      = new uint64[](5);
        uint64[] memory teamDurations   = new uint64[](5);
        bool[]   memory teamRevocable  = new bool[](5);

        teamWallets[0] = TEAM_1; teamWallets[1] = TEAM_2; teamWallets[2] = TEAM_3;
        teamWallets[3] = TEAM_4; teamWallets[4] = TEAM_5;
        for (uint256 i = 0; i < 5; i++) {
            teamAmounts[i]   = 36_000_000e18;
            teamCliffs[i]    = 365 days;
            teamDurations[i] = 1095 days;
            teamRevocable[i] = true;
        }
        // Give deployer enough ZENT for team + backer vesting
        // Deployer has all 1B ZENT; approve and fund
        zent.approve(address(vesting), type(uint256).max);
        vesting.fund(teamWallets, teamAmounts, teamCliffs, teamDurations, teamRevocable, uint64(block.timestamp));

        // Fund backer vesting
        address[] memory backerWallets   = new address[](3);
        uint256[] memory backerAmounts   = new uint256[](3);
        uint64[] memory backerCliffs     = new uint64[](3);
        uint64[] memory backerDurations  = new uint64[](3);
        bool[]   memory backerRevocable  = new bool[](3);

        backerWallets[0] = BACKER_1; backerAmounts[0] = 75_000_000e18;
        backerWallets[1] = BACKER_2; backerAmounts[1] = 50_000_000e18;
        backerWallets[2] = BACKER_3; backerAmounts[2] = 25_000_000e18;
        for (uint256 i = 0; i < 3; i++) {
            backerCliffs[i]    = 182 days;
            backerDurations[i] = 730 days;
            backerRevocable[i] = false;
        }
        vesting.fund(backerWallets, backerAmounts, backerCliffs, backerDurations, backerRevocable, uint64(block.timestamp));

        // ─── PHASE 2: VAULTS ─────────────────────────────────────────────────
        // Use address(1) as placeholder asset. Since BaseVault calls
        // IERC20Metadata(asset).decimals() in its constructor, we deploy a mock
        // ERC20 first so the call succeeds.
        MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK");
        zeth = new BaseVault(address(mockAsset), "zETH Share", "zETH",
            30000, 10000, 2000, 500, 2000, TREASURY, DEPLOYER);
        zbtc = new BaseVault(address(mockAsset), "zBTC Share", "zBTC",
            30000, 10000, 2000, 500, 2000, TREASURY, DEPLOYER);
        zxrp = new BaseVault(address(mockAsset), "zXRP Share", "zXRP",
            30000, 10000, 2000, 500, 2000, TREASURY, DEPLOYER);
        zsol = new BaseVault(address(mockAsset), "zSOL Share", "zSOL",
            30000, 10000, 2000, 500, 2000, TREASURY, DEPLOYER);

        // ─── PHASE 3: STAKING ─────────────────────────────────────────────────
        // Temp governor = DEPLOYER, replaced in Phase 6
        staking = new ZENTStaking(address(zent), DEPLOYER, MIN_STAKE);
        bonding = new ModelBonding(address(zent), DEPLOYER, DEPLOYER, TREASURY, UNBOND_COOLDOWN);
        zethFees = new FeeDistributor(address(mockAsset), address(zent), DEPLOYER, KEEPER, TREASURY, TREASURY);
        zbtcFees = new FeeDistributor(address(mockAsset), address(zent), DEPLOYER, KEEPER, TREASURY, TREASURY);
        zxrpFees = new FeeDistributor(address(mockAsset), address(zent), DEPLOYER, KEEPER, TREASURY, TREASURY);
        zsolFees = new FeeDistributor(address(mockAsset), address(zent), DEPLOYER, KEEPER, TREASURY, TREASURY);

        // ─── PHASE 4: GOVERNANCE ─────────────────────────────────────────────
        // Pass PROPOSER and address(0) as proposers/executors; we will grant roles
        // impersonating the Timelock (which has DEFAULT_ADMIN_ROLE after construction).
        address[] memory proposers = new address[](1);
        address[] memory executors  = new address[](1);
        proposers[0] = PROPOSER;
        executors[0]  = address(0); // anyone can execute

        // Deploy Timelock with DEPLOYER as admin (DEPLOYER will get DEFAULT_ADMIN_ROLE).
        timelock  = new Timelock(TIMELOCK_DELAY, proposers, executors, DEPLOYER);

        // Impersonate DEPLOYER (the admin) to grant roles.
        // Since TimelockController grants PROPOSER_ROLE to admin and EXECUTOR_ROLE to each
        // executor address, and executors is empty, we must grant EXECUTOR_ROLE manually.
        vm.stopPrank();
        vm.startPrank(DEPLOYER);
        // Open execution: anyone can execute via Timelock.
        timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(0));

        zentroller = new Zentroller(address(staking), address(0));
        governor  = new ZentGovernor(
            address(zent),
            address(staking),
            address(timelock),
            address(zentroller),
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_BPS
        );

        // Grant governor PROPOSER_ROLE on Timelock
        timelock.grantRole(keccak256("PROPOSER_ROLE"), address(governor));

        // ─── PHASE 5: KEEPER ─────────────────────────────────────────────────
        adapter  = new HyperCoreAdapter(address(governor));
        executor = new StrategyExecutor(address(adapter), address(governor));

        // Governor grants KEEPER_ROLE and GUARDIAN_ROLE.
        vm.startPrank(address(governor));
        executor.grantRole(keccak256("KEEPER_ROLE"), KEEPER);
        executor.grantRole(keccak256("GUARDIAN_ROLE"), GUARDIAN);
        executor.setAuthorizedSigner(address(0x9999)); // placeholder for tests that don't execute signals
        vm.stopPrank();

        // ─── PHASE 6: WIRING ─────────────────────────────────────────────────
        // DEPLOYER grants GOVERNOR_ROLE to the real governor and transfers
        // DEFAULT_ADMIN_ROLE to governor. In the production DeployPipeline script,
        // DEPLOYER renounces its admin after this step.

        vm.startPrank(DEPLOYER);
        // Staking
        staking.grantRole(staking.GOVERNOR_ROLE(), address(governor));
        staking.grantRole(staking.DEFAULT_ADMIN_ROLE(), address(governor));

        // Bonding
        bonding.grantRole(bonding.GOVERNOR_ROLE(), address(governor));
        bonding.grantRole(bonding.DEFAULT_ADMIN_ROLE(), address(governor));
        bonding.grantRole(bonding.RISK_COUNCIL_ROLE(), GUARDIAN);

        // FeeDistributors
        zethFees.grantRole(zethFees.GOVERNOR_ROLE(), address(governor));
        zethFees.grantRole(zethFees.DEFAULT_ADMIN_ROLE(), address(governor));

        zbtcFees.grantRole(zbtcFees.GOVERNOR_ROLE(), address(governor));
        zbtcFees.grantRole(zbtcFees.DEFAULT_ADMIN_ROLE(), address(governor));

        zxrpFees.grantRole(zxrpFees.GOVERNOR_ROLE(), address(governor));
        zxrpFees.grantRole(zxrpFees.DEFAULT_ADMIN_ROLE(), address(governor));

        zsolFees.grantRole(zsolFees.GOVERNOR_ROLE(), address(governor));
        zsolFees.grantRole(zsolFees.DEFAULT_ADMIN_ROLE(), address(governor));

        // Vaults
        zeth.grantRole(zeth.DEFAULT_ADMIN_ROLE(), address(governor));
        zbtc.grantRole(zbtc.DEFAULT_ADMIN_ROLE(), address(governor));
        zxrp.grantRole(zxrp.DEFAULT_ADMIN_ROLE(), address(governor));
        zsol.grantRole(zsol.DEFAULT_ADMIN_ROLE(), address(governor));

        zeth.setFeeRecipient(address(zethFees));
        zbtc.setFeeRecipient(address(zbtcFees));
        zxrp.setFeeRecipient(address(zxrpFees));
        zsol.setFeeRecipient(address(zsolFees));

        zeth.setStaking(address(staking));
        zbtc.setStaking(address(staking));
        zxrp.setStaking(address(staking));
        zsol.setStaking(address(staking));
        vm.stopPrank();

        // Governor sets risk limits on executor
        vm.startPrank(address(governor));
        executor.setMaxLeverageBPS(address(zeth), 30000);
        executor.setMaxLeverageBPS(address(zbtc), 30000);
        executor.setMaxLeverageBPS(address(zxrp), 30000);
        executor.setMaxLeverageBPS(address(zsol), 30000);
        vm.stopPrank();
    }

    // ─── Basic sanity checks ─────────────────────────────────────────────────

    function test_coreTokensDeployed() external view {
        // Total supply is correctly minted
        assertEq(zent.totalSupply(), 1_000_000_000e18);
        // Vesting received exactly 330M (180M team + 150M backers)
        assertEq(zent.balanceOf(address(vesting)), 330_000_000e18);
    }

    function test_vaultsDeployed() external view {
        assertTrue(address(zeth) != address(0));
        assertTrue(address(zbtc) != address(0));
        assertTrue(address(zxrp) != address(0));
        assertTrue(address(zsol) != address(0));
    }

    function test_stakingDeployed() external view {
        assertEq(address(staking.zent()), address(zent));
        assertEq(staking.minStake(), MIN_STAKE);
    }

    function test_governanceDeployed() external view {
        assertTrue(address(timelock) != address(0));
        assertTrue(address(zentroller) != address(0));
        assertTrue(address(governor) != address(0));
        assertEq(address(zentroller.staking()), address(staking));
    }

    function test_keeperDeployed() external view {
        assertTrue(address(adapter) != address(0));
        assertTrue(address(executor) != address(0));
    }

    function test_governorHasProposerRoleOnTimelock() external view {
        assertTrue(timelock.hasRole(keccak256("PROPOSER_ROLE"), address(governor)));
    }

    function test_governorIsAdminOfVaults() external view {
        assertTrue(zeth.hasRole(zeth.DEFAULT_ADMIN_ROLE(), address(governor)));
        assertTrue(zbtc.hasRole(zbtc.DEFAULT_ADMIN_ROLE(), address(governor)));
        assertTrue(zxrp.hasRole(zxrp.DEFAULT_ADMIN_ROLE(), address(governor)));
        assertTrue(zsol.hasRole(zsol.DEFAULT_ADMIN_ROLE(), address(governor)));
    }

    function test_keeperHasKeeperRole() external view {
        assertTrue(executor.hasRole(keccak256("KEEPER_ROLE"), KEEPER));
        assertTrue(executor.hasRole(keccak256("GUARDIAN_ROLE"), GUARDIAN));
    }

    function test_governorIsAdminOfStrategyExecutor() external view {
        assertTrue(executor.hasRole(executor.DEFAULT_ADMIN_ROLE(), address(governor)));
    }

    function test_stakingHasGovernorRole() external view {
        assertTrue(staking.hasRole(staking.GOVERNOR_ROLE(), address(governor)));
    }

    function test_bondingHasGovernorAndRiskCouncilRoles() external view {
        assertTrue(bonding.hasRole(bonding.GOVERNOR_ROLE(), address(governor)));
        assertTrue(bonding.hasRole(bonding.RISK_COUNCIL_ROLE(), GUARDIAN));
    }

    function test_feeDistributorsHaveGovernorRole() external view {
        assertTrue(zethFees.hasRole(zethFees.GOVERNOR_ROLE(), address(governor)));
        assertTrue(zbtcFees.hasRole(zbtcFees.GOVERNOR_ROLE(), address(governor)));
        assertTrue(zxrpFees.hasRole(zxrpFees.GOVERNOR_ROLE(), address(governor)));
        assertTrue(zsolFees.hasRole(zsolFees.GOVERNOR_ROLE(), address(governor)));
    }

    function test_riskLimitsSetOnExecutor() external view {
        assertEq(executor.maxLeverageBPS(address(zeth)), 30000);
        assertEq(executor.maxLeverageBPS(address(zbtc)), 30000);
        assertEq(executor.maxLeverageBPS(address(zxrp)), 30000);
        assertEq(executor.maxLeverageBPS(address(zsol)), 30000);
    }

    function test_governorIsAdminOfAllContracts() external view {
        // Governor holds DEFAULT_ADMIN_ROLE on all protocol contracts after wiring
        assertTrue(staking.hasRole(staking.DEFAULT_ADMIN_ROLE(), address(governor)));
        assertTrue(bonding.hasRole(bonding.DEFAULT_ADMIN_ROLE(), address(governor)));
        assertTrue(zethFees.hasRole(zethFees.DEFAULT_ADMIN_ROLE(), address(governor)));
        assertTrue(zbtcFees.hasRole(zbtcFees.DEFAULT_ADMIN_ROLE(), address(governor)));
        assertTrue(zxrpFees.hasRole(zxrpFees.DEFAULT_ADMIN_ROLE(), address(governor)));
        assertTrue(zsolFees.hasRole(zsolFees.DEFAULT_ADMIN_ROLE(), address(governor)));
        assertTrue(executor.hasRole(executor.DEFAULT_ADMIN_ROLE(), address(governor)));
    }
}
