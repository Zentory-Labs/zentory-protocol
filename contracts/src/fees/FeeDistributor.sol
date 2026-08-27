// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";

/// @title FeeDistributor
/// @notice Routes performance fees from vaults into four destinations:
///         buyback (50%), Protocol Treasury (25%), insurance (15%),
///         GP/ops engine (10%). Permissionless accumulate + distribute;
///         buyback trigger restricted to governor.
contract FeeDistributor is AccessControl, IFeeDistributor {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // ─── Pool IDs ─────────────────────────────────────────────────────────
    uint8 public constant POOL_BUYBACK = 0;
    uint8 public constant POOL_GP_ENGINE = 1;
    uint8 public constant POOL_INSURANCE = 2;

    // ─── Roles ─────────────────────────────────────────────────────────────
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    // ─── Immutables ───────────────────────────────────────────────────────
    /// @notice The asset this distributor accepts (e.g. WBTC for the zBTC vault).
    IERC20 public immutable asset;
    /// @notice ZENT token — destination for buyback + burn.
    IERC20 public immutable zent;

    // ─── State ─────────────────────────────────────────────────────────────
    address public gpEngine;
    address public insurance;
    address public protocolTreasury; // ProtocolTreasury (routes 50% to ZENTBuyback, 50% to ops)

    /// @notice Accumulated performance fees per vault (accounting only — not pulled until distribute).
    mapping(address => uint256) public pendingFees;

    /// @notice Pool balances held by this contract.
    mapping(uint8 => uint256) public pools;

    // ─── Constructor ───────────────────────────────────────────────────────
    constructor(
        address asset_,
        address zent_,
        address governor_,
        address gpEngine_,
        address insurance_,
        address protocolTreasury_
    ) {
        require(asset_ != address(0), "FeeDistributor: zero asset");
        require(zent_ != address(0), "FeeDistributor: zero zent");
        require(governor_ != address(0), "FeeDistributor: zero governor");
        require(gpEngine_ != address(0), "FeeDistributor: zero gp engine");
        require(insurance_ != address(0), "FeeDistributor: zero insurance");
        require(protocolTreasury_ != address(0), "FeeDistributor: zero protocol treasury");

        asset = IERC20(asset_);
        zent = IERC20(zent_);
        gpEngine = gpEngine_;
        insurance = insurance_;
        protocolTreasury = protocolTreasury_;

        _grantRole(DEFAULT_ADMIN_ROLE, governor_);
        _grantRole(GOVERNOR_ROLE, governor_);
    }

    // ─── Accounting ───────────────────────────────────────────────────────

    /// @inheritdoc IFeeDistributor
    function accumulate(address vault, uint256 amount) external {
        require(vault != address(0), "FeeDistributor: zero vault");
        require(amount > 0, "FeeDistributor: zero amount");
        // Only the vault contract itself may trigger accumulation — no third-party approval needed.
        require(msg.sender == vault, "FeeDistributor: not vault");

        pendingFees[vault] += amount;

        // Pull the accumulated fees from the vault into this contract.
        // Slither false positive: msg.sender == vault is enforced above, so this is always a self-transfer.
        // slither-disable-next-line arbitrary-send-erc20
        asset.safeTransferFrom(vault, address(this), amount);

        emit FeeAccumulated(vault, amount);
    }

    // ─── Distribute ───────────────────────────────────────────────────────

    /// @inheritdoc IFeeDistributor
    function distribute(address vault) external {
        require(vault != address(0), "FeeDistributor: zero vault");

        uint256 accumulated = pendingFees[vault];
        require(accumulated > 0, "FeeDistributor: nothing to distribute");

        delete pendingFees[vault];

        // SPEC-CONFORMANCE FIX (audit finding #9): the whitepaper routes the
        // 25% slice to the Protocol Treasury and 10% to the ops/research-engine
        // bucket. The code had these swapped (25% → gpEngine, 10% → treasury).
        // Corrected per founder decision: treasury gets 25%, gpEngine (the
        // ops/research-engine destination) gets 10%. Split stays 50/25/15/10.
        uint256 buyback = accumulated * 50 / 100;
        uint256 treasuryAmount = accumulated * 25 / 100;
        uint256 insuranceAmount = accumulated * 15 / 100;
        uint256 gpAmount = accumulated * 10 / 100;

        // Dust-routing fix (audit H-3 follow-up): integer division of
        // `accumulated / 100` over four buckets can leave 1–3 wei stranded
        // in this contract for amounts not divisible by 100. We never read
        // contract balances for accounting — `pools[*]` is the source of
        // truth — so unallocated tokens would sit forever. Sweep any
        // rounding remainder into the buyback pool where the next
        // `triggerBuyback` will use it (or the next epoch's accounting
        // will reconcile it via the next distribute call). This is
        // strictly value-additive: the buyback pool's accounting now
        // matches the contract's actual asset balance modulo any
        // legitimately received direct transfers.
        uint256 allocated = buyback + treasuryAmount + insuranceAmount + gpAmount;
        uint256 dust = accumulated - allocated;

        pools[POOL_BUYBACK] += buyback + dust;
        pools[POOL_GP_ENGINE] += gpAmount;
        pools[POOL_INSURANCE] += insuranceAmount;

        // Emit BEFORE the external transfers (CEI) so monitoring sees the
        // allocation even if a downstream transfer reverts. The dust value
        // is emitted as its own field so off-chain accounting can attribute
        // the buyback pool's increment to a rounding remainder vs an
        // intentional 50% allocation — and so the emitted buybackAmount
        // matches the field incremented on `pools[POOL_BUYBACK]`.
        emit FeesDistributed(buyback, dust, gpAmount, insuranceAmount, treasuryAmount);

        if (gpAmount > 0) asset.safeTransfer(gpEngine, gpAmount);
        if (insuranceAmount > 0) asset.safeTransfer(insurance, insuranceAmount);
        // Treasury (25%) flows to ProtocolTreasury (quant grants, competitions, ops).
        if (treasuryAmount > 0) asset.safeTransfer(protocolTreasury, treasuryAmount);
    }

    // ─── Buyback ───────────────────────────────────────────────────────────

    /// @inheritdoc IFeeDistributor
    /// @dev Executes a buyback by swapping from the buyback pool to ZENT and burning.
    ///      In production this routes through a DEX aggregator (e.g. 1inch). The caller
    ///      is a keeper or the governor; gas is self-funded.
    function triggerBuyback(address[] calldata path) external onlyRole(GOVERNOR_ROLE) {
        require(path.length >= 2, "FeeDistributor: invalid path");
        require(path[0] == address(asset), "FeeDistributor: wrong asset");
        require(path[path.length - 1] == address(zent), "FeeDistributor: path must end in ZENT");

        uint256 buybackPool = pools[POOL_BUYBACK];
        require(buybackPool > 0, "FeeDistributor: nothing to buy back");

        pools[POOL_BUYBACK] = 0;

        emit BuybackTriggered(address(asset), buybackPool);

        // In production: route `buybackPool` of the asset through a DEX aggregator to acquire
        // ZENT, then transfer the acquired ZENT to 0xdead (burn).  Integration point is
        // swapExactTokensForTokens(path, buybackPool, minOut, address(this), block.timestamp+30).
        // For standalone testing (no DEX): pull pre-provided ZENT from the contract and burn.
        address dead = address(0xdead);
        uint256 zentBal = zent.balanceOf(address(this));
        if (zentBal > 0) {
            zent.safeTransfer(dead, zentBal);
        }
    }

    // ─── Withdraw (GP Engine / Treasury pools only) ───────────────────────

    /// @inheritdoc IFeeDistributor
    function withdrawTo(address recipient, uint256 amount, uint8 poolId) external onlyRole(GOVERNOR_ROLE) {
        require(recipient != address(0), "FeeDistributor: zero recipient");
        require(amount > 0, "FeeDistributor: zero amount");
        require(poolId == POOL_GP_ENGINE, "FeeDistributor: not directly withdrawable");
        require(pools[poolId] >= amount, "FeeDistributor: insufficient pool balance");

        pools[poolId] -= amount;
        asset.safeTransfer(recipient, amount);
    }

    // ─── Governor Config ─────────────────────────────────────────────────

    function setGpEngine(address newGpEngine) external onlyRole(GOVERNOR_ROLE) {
        require(newGpEngine != address(0), "FeeDistributor: zero gp engine");
        address old = gpEngine;
        gpEngine = newGpEngine;
        emit GovernorUpdated(old, newGpEngine);
    }

    function setInsurance(address newInsurance) external onlyRole(GOVERNOR_ROLE) {
        require(newInsurance != address(0), "FeeDistributor: zero insurance");
        address old = insurance;
        insurance = newInsurance;
        emit GovernorUpdated(old, newInsurance);
    }

    function setProtocolTreasury(address newProtocolTreasury) external onlyRole(GOVERNOR_ROLE) {
        require(newProtocolTreasury != address(0), "FeeDistributor: zero protocol treasury");
        address old = protocolTreasury;
        protocolTreasury = newProtocolTreasury;
        emit GovernorUpdated(old, newProtocolTreasury);
    }
}
