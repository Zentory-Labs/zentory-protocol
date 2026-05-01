# ZENT Buyback & Burn Mechanism Design

> **Classification:** ZENTORY Labs Internal — Legal & Protocol Design
> **Version:** 1.0
> **Date:** April 2026
> **Status:** Design Specification — Not Yet Implemented

---

## 1. Executive Summary

ZENT's existing `FeeDistributor.triggerBuyback()` already routes 50% of vault performance fees to a buyback pool, but the mechanism is a placeholder and the overall architecture has a structural Howey test risk: the `FeeDistributor` distributes rewards to stakers in a way that creates profit-sharing with a common enterprise. The March 2026 SEC/CFTC joint interpretation gives us a clear path to fix this: **reframe the buyback as protocol-owned supply management, not profit distribution to holders.**

The recommended approach:
1. Replace the direct staking reward distribution with a **treasury-first model** — fees accumulate to contracts the protocol controls, not directly to staker wallets.
2. Implement a **rule-based, automated `ZENTBuyback` contract** that purchases ZENT from the open market using stablecoin/USDC reserves (collected from vault fees), then **burns** the purchased ZENT.
3. Explicitly **do not route buyback-derived value to stakers or any ZENT holder** as a right — value accrues through **supply scarcity**, not account-balance increases.
4. Keep all execution **automated and non-discretionary** — no foundation can "decide" to buy or not buy based on price.

---

## 2. Howey Test Analysis for ZENT Buyback

### 2.1 The Four Prongs of Howey

| Prong | ZENT Status | Risk Level |
|-------|------------|------------|
| (1) Investment of money | ZENT was purchased/acquired in a primary sale | ✅ Already satisfied (past; secondary market now) |
| (2) In a common enterprise | The protocol/foundation runs the vault, staking, and fee distribution | ⚠️ Medium — "common enterprise" argument exists |
| (3) Expectation of profit | Stakers expect ZENT appreciation from buyback pressure | ⚠️ High — current `distribute()` pushes rewards to stakers directly |
| (4) From managerial efforts of others | ZENT Foundation / governor controls fee routing, buyback execution | ⚠️ High — foundation controls `triggerBuyback()`, treasury, fee parameters |

### 2.2 Why Current FeeDistributor Creates Howey Risk

The current `FeeDistributor.distribute()` splits fees and immediately sends portions to:
- **GP Engine** (25%) — direct transfer to an external address
- **Insurance** (15%) — direct transfer
- **Treasury** (10%) — direct transfer
- **Buyback pool (50%)** — accumulated, then `triggerBuyback()` swaps and burns

The **direct reward routing** to stakers (via whatever mechanism currently receives the 50% buyback pool value) is the core Howey problem. When stakers receive asset increments because the protocol generated fees, regulators can characterize that as **profit from the managerial efforts of a common enterprise** — exactly the definition of an investment contract.

Under the **March 2026 SEC/CFTC Interpretation (Release No. 33-11412)**:
- The SEC explicitly states that a non-security crypto asset *may* become subject to an investment contract depending on representations made to purchasers about future managerial efforts creating profit.
- The critical distinction: **value accrual through supply scarcity vs. value distribution as a claim on earnings**.

### 2.3 Why a Buyback + Burn Is NOT a Security

Under the March 2026 framework, the following structure avoids the security classification:

```
Fees collected → Protocol treasury (NOT distributed to holders as earnings)
                → Rule-based contract auto-purchases ZENT on open market
                → Purchased ZENT is burned (permanently removed)
                → Value accrues to ALL holders through reduced supply, not account balances
```

**Key distinctions from a security:**

| Characteristic | Dividend / Profit Distribution | Buyback + Burn |
|---|---|---|
| Who receives value | Current holders at distribution time | All future holders equally |
| Type of value | Specific asset deposited to wallet | Supply reduction (price impact on all tokens) |
| Managerial discretion | Often discretionary | Rule-based, non-discretionary |
| Legal characterization | "Earnings distribution" | "Monetary policy / supply management" |
| SEC/CFTC 2026 view | Investment contract risk | Supply management tool |

**The legal key:** ZENT holders do not have a **specific, enforceable claim** on the protocol's fee revenue. The buyback is a **policy decision** (made by governance) to reduce supply — not an obligation. There is no contract that guarantees a ZENT holder will receive WBTC, USDC, or any asset as a result of the buyback. This is identical to how a government might buy back its own currency — a monetary policy tool, not a security.

### 2.4 Specific ZENT Risk Factors to Eliminate

| Risk Factor | Current State | Fix Required |
|---|---|---|
| Direct staking rewards from fees | `FeeDistributor.distribute()` sends assets to staker-facing contracts | Change to treasury accumulation; staking rewards come from inflation or governance allocation, not fee profit-sharing |
| Foundation discretion over buyback | `triggerBuyback()` is governor-controlled | Make execution automatic/trigger-based, not governance-callable |
| Unclear "common enterprise" link | Protocol runs vaults AND collects fees AND routes value | Separate concerns: vaults are independent service; fees are protocol revenue; value accrual is structural, not contractual |
| Promise of profit from buyback | Public materials may frame buyback as "holder benefit" | Legal framing: buyback is a supply management tool; no promise of price support |

---

## 3. Recommended Mechanism: Treasury-Funded Rule-Based Buyback + Burn

### 3.1 Architecture Overview

```
┌──────────────────────────────────────────────────────────────┐
│                       FEE FLOW (NEW)                          │
│                                                               │
│  Vault performance fees (20% of alpha)                        │
│       │                                                      │
│       ▼                                                      │
│  FeeDistributor.accumulate()  ──► 100% to ProtocolTreasury   │
│                                    │                         │
│                      ┌─────────────┼─────────────┐          │
│                      ▼             ▼             ▼          │
│               GP Engine(25%)  Insurance(15%)  Buyback(50%)  │
│                 direct          sink           direct        │
│               transfer                        accumulation    │
│                                                   │          │
│                                                   ▼          │
│                                    ZENTBuyback.trigger()    │
│                                           │                  │
│              ┌────────────────────────────┼────────────┐  │
│              ▼                            ▼            ▼     │
│         DEX swap                 TWAP/FOK        Direct   │
│      (USDC → ZENT)              limit order    market buy  │
│              │                            │            │     │
│              └────────────────────────────┴────────────┘     │
│                               │                              │
│                               ▼                              │
│                        ZENT → 0xdead (BURN)                   │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 Key Design Decisions

#### Why USDC as the intermediate asset?
- Vault fees are collected in the vault's asset (WBTC, WETH, WSOL,WXRP) — not USDC
- The current `triggerBuyback()` is a placeholder that doesn't actually execute a DEX swap
- **Best practice:** Convert vault assets to USDC via a DEX (e.g., HyperEVM native swap or 1inch), then use USDC to buy ZENT
- This is what GMX does: fees → USDC → GMX buyback

#### Why burn rather than stake or distribute?
- **Burn = permanent supply reduction** = value to all holders through scarcity
- **Stake in treasury** = governance-controlled reserve = more complex (may look like savings)
- **Distribute to stakers** = exactly what the March 2026 guidance says NOT to do without clear arms-length structure
- **Grant to builders** = acceptable but does not create direct holder value

#### Why rule-based over governor-callable?
- Any governance call that "triggers" a buyback introduces **discretion**
- Regulators look at whether the foundation/team/governance can **decide** to buy or not buy
- A **cron/job/schedule trigger** that fires every N blocks or when a USDC threshold is met removes discretion
- Execution can still be permissioned (only keeper or a specific role can call), but the **trigger condition** is formulaic, not discretionary

#### Why not direct yield/distribution to stakers?
- The March 2026 SEC/CFTC interpretation on **protocol staking** clarifies that PoS validation rewards are not securities
- However, **DeFi protocol revenue distribution** to stakers is a different structure
- If stakers receive a share of vault fees *because* they staked, that is a profit-sharing arrangement
- The fix: stakers are incentivized by **ZENT inflation** (emissions) and **governance power**, not by **fee revenue share**

### 3.3 Gas-Efficient Solidity Sketch

#### ZENTBuyback.sol

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ZENTBuyback
 * @notice Protocol-owned buyback contract. Accumulates USDC from FeeDistributor,
 *         purchases ZENT from DEX (TWAP or direct), and burns the proceeds.
 *
 *         COMPLIANCE NOTES (April 2026):
 *         - This contract does NOT distribute value to any address except 0xdead.
 *         - No address has a contractual right to receive ZENT or any asset from this contract.
 *         - Execution is trigger-based (not discretionary), reducing manager discretion risk.
 *         - Value accrues to all ZENT holders through supply reduction, not balance increases.
 */
contract ZENTBuyback {
    using SafeERC20 for IERC20;

    // ─── Immutable config ───────────────────────────────────────────────────
    IERC20 public immutable ZENT;          // ZENT token address
    IERC20 public immutable USDC;          // USDC (fee intermediate)
    address public immutable deadAddress = 0x000000000000000000000000000000000000dEaD;

    // ─── Mutable config (governance-adjustable) ─────────────────────────────
    /// @notice Minimum USDC balance before a buyback is triggered
    uint256 public minTriggerUsdc = 1_000e6;  // 1,000 USDC

    /// @notice Maximum ZENT to purchase per trigger (capped for safety)
    uint256 public maxZentPerTrigger = 1_000_000e18; // 1M ZENT

    /// @notice TWAP epoch duration in seconds (for TWAP-based execution)
    uint256 public twapEpochSeconds = 5 minutes;

    /// @notice Role that can call trigger()
    bytes32 public constant TRIGGER_ROLE = keccak256("TRIGGER_ROLE");

    // ─── State ───────────────────────────────────────────────────────────────
    uint256 public lastBuybackTimestamp;
    uint256 public totalZentBurned;

    // ─── Events ──────────────────────────────────────────────────────────────
    event BuybackTriggered(
        uint256 usdcSpent,
        uint256 zentPurchased,
        uint256 zentBurned,
        bytes32 indexed triggerRole
    );
    event MinTriggerUpdated(uint256 oldMin, uint256 newMin);
    event MaxZentUpdated(uint256 oldMax, uint256 newMax);
    event EmergencyPause(bool paused);

    // ─── Errors ───────────────────────────────────────────────────────────────
    error InsufficientBalance();
    error InsufficientOutput();
    error Paused();
    error DeadlineExceeded();

    // ─── Modifiers ───────────────────────────────────────────────────────────
    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }

    bool public paused;

    // ═══════════════════════════════════════════════════════════════════════
    //  CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════

    constructor(address _zent, address _usdc) {
        ZENT = IERC20(_zent);
        USDC = IERC20(_usdc);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  GOVERNANCE (only governance should hold TRIGGER_ROLE globally)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Set minimum USDC threshold to trigger a buyback.
     *         Setting this too low means frequent small buys (more gas, worse price).
     *         Setting this too high means infrequent large buys (better TWAP, less consistent).
     *         Recommended: 5,000–10,000 USDC minimum for HyperEVM gas costs.
     */
    function setMinTriggerUsdc(uint256 _min) external {
        // Gate: implement Ownable or AccessControl as needed
        uint256 old = minTriggerUsdc;
        minTriggerUsdc = _min;
        emit MinTriggerUpdated(old, _min);
    }

    /**
     * @notice Set maximum ZENT purchase per trigger.
     *         Prevents accidental large purchases in thin liquidity.
     */
    function setMaxZentPerTrigger(uint256 _max) external {
        uint256 old = maxZentPerTrigger;
        maxZentPerTrigger = _max;
        emit MaxZentUpdated(old, _max);
    }

    function setPaused(bool _paused) external {
        paused = _paused;
        emit EmergencyPause(_paused);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  FEE COLLECTION (called by FeeDistributor)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Pull accumulated USDC from FeeDistributor.
     *         FeeDistributor.transferToBuyback() calls this.
     *         No direct transfer to any holder — all USDC stays here for buyback.
     */
    function topUp(address from, uint256 amount) external {
        USDC.safeTransferFrom(from, address(this), amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  BUYBACK EXECUTION
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Execute buyback. Can be called by any address with TRIGGER_ROLE.
     *         TWAP mode (default): purchases ZENT at or near market price via DEX.
     *         GAS OPTIMIZATION: No external oracle calls on every trigger.
     *         Price validation done off-chain or via Uniswap V3 TWAP oracle.
     *
     * COMPLIANCE: This function does not distribute ZENT to any address.
     *             ZENT purchased is immediately burned to deadAddress.
     *             No person or contract has a contractual right to receive ZENT from this contract.
     *
     * @param minZentOut Minimum ZENT to receive for slippage protection
     * @param deadline   Max timestamp for execution
     */
    function trigger(
        uint256 minZentOut,
        uint256 deadline
    ) external whenNotPaused {
        if (block.timestamp > deadline) revert DeadlineExceeded();

        uint256 usdcBalance = USDC.balanceOf(address(this));
        if (usdcBalance < minTriggerUsdc) revert InsufficientBalance();

        // Cap at max purchase (slippage + liquidity protection)
        uint256 usdcToSpend = usdcBalance > _maxUsdcPerTrigger()
            ? _maxUsdcPerTrigger()
            : usdcBalance;

        // Pull ZENT into this contract via DEX swap
        // Implementation note: For HyperEVM, use the native swap or 1inch Aggregator.
        // The exact swap router is deployment-specific; interface is kept generic.
        uint256 zentReceived = _swapUsdcForZent(usdcToSpend, minZentOut, deadline);

        // Burn received ZENT to dead address
        if (zentReceived > 0) {
            ZENT.safeTransfer(deadAddress, zentReceived);
            totalZentBurned += zentReceived;
        }

        lastBuybackTimestamp = block.timestamp;
        emit BuybackTriggered(usdcToSpend, zentReceived, zentReceived, TRIGGER_ROLE);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TWAP-AWARE SWAP (Uniswap V3 style, or HyperEVM native AMM)
    //  Override this function with the actual DEX integration for HyperEVM.
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @dev Override with actual DEX swap logic.
     *      Must return actual ZENT received.
     *      Recommended: Uniswap V3 TwapRouter or HyperEVM native pool.
     *
     * @param usdcAmount Amount of USDC to spend
     * @param minZentOut Minimum ZENT expected (slippage guard)
     * @param deadline   Execution deadline
     * @return zentOut   Actual ZENT received
     */
    function _swapUsdcForZent(
        uint256 usdcAmount,
        uint256 minZentOut,
        uint256 deadline
    ) internal virtual returns (uint256 zentOut) {
        // ─── PLACEHOLDER: Replace with actual HyperEVM DEX integration ───
        // Example (Uniswap V3 style):
        //
        // ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
        //     tokenIn: address(USDC),
        //     tokenOut: address(ZENT),
        //     fee: 3000,  // 0.30% pool
        //     recipient: address(this),
        //     deadline: deadline,
        //     amountIn: usdcAmount,
        //     amountOutMinimum: minZentOut,
        //     sqrtPriceLimitX96: 0
        // });
        // zentOut = swapRouter.exactInput(params);
        //
        // ─── PLACEHOLDER ────────────────────────────────────────────────

        revert("ZENTBuyback: _swapUsdcForZent must be implemented");
    }

    function _maxUsdcPerTrigger() internal view returns (uint256) {
        // 1% of ZENT total supply per trigger as a safety cap
        return IERC20(address(ZENT)).totalSupply() / 100;
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  VIEW FUNCTIONS (for off-chain monitoring)
    // ═══════════════════════════════════════════════════════════════════════

    function getBuybackStats()
        external
        view
        returns (
            uint256 usdcBalance,
            uint256 lastTimestamp,
            uint256 totalBurned,
            uint256 minTrigger
        )
    {
        return (
            USDC.balanceOf(address(this)),
            lastBuybackTimestamp,
            totalZentBurned,
            minTriggerUsdc
        );
    }
}
```

#### Modified FeeDistributor (changes to accumulate/distribute)

The key change: **remove the direct `distribute()` transfers to GP Engine, Insurance, and Treasury from FeeDistributor**. Instead, route all fees through a unified `ProtocolTreasury` contract. The `ProtocolTreasury` then handles the split and routing.

```solidity
// ─── Changes to FeeDistributor.sol ─────────────────────────────────────────

// BEFORE (problematic):
function distribute(address vault) external {
    uint256 fees = pendingFees[vault];
    if (fees == 0) return;

    pendingFees[vault] = 0;

    // Direct transfers create profit-sharing narrative
    _transferAsset(fees * 25 / 100, gpEngine);     // ← Direct to external address
    _transferAsset(fees * 15 / 100, insurance);   // ← Direct to external address
    _transferAsset(fees * 10 / 100, treasury);    // ← Direct to external address
    // Buyback pool sits here and triggerBuyback() is governor-called
    pendingBuyback[vault] += fees * 50 / 100;
}

// AFTER (compliant):
// All fee revenue goes to ProtocolTreasury. No direct distributions.
// GP Engine, Insurance, Treasury are funded via separate governance proposals
// from the ProtocolTreasury, not as automatic profit-sharing.

mapping(address => uint256) public pendingFees;

function accumulate(address vault, uint256 amount) external {
    // Called by vault.accumulateFees()
    // Pulls asset tokens from vault
    pendingFees[vault] += amount;
    // Tokens sit in FeeDistributor — NOT auto-distributed
}

// New: transfer all accumulated fees to ProtocolTreasury
function sweepToTreasury(address vault) external onlyGovernor {
    uint256 fees = pendingFees[vault];
    if (fees == 0) return;
    pendingFees[vault] = 0;

    // Transfer accumulated asset to ProtocolTreasury
    IERC20 asset = IERC20(vault); // underlying asset (WETH, WBTC, etc.)
    asset.safeTransfer(protocolTreasury, fees);

    // ProtocolTreasury handles conversion to USDC, then routes:
    // 25% → GP Engine (via governance withdrawal from treasury)
    // 15% → Insurance  (via governance withdrawal from treasury)
    // 10% → Treasury  (via governance withdrawal from treasury)
    // 50% → ZENTBuyback (via ZENTBuyback.topUp())
}
```

#### ProtocolTreasury.sol (new contract)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ProtocolTreasury
 * @notice Central fee accumulator. Converts all vault asset fees to USDC,
 *         then distributes to GP Engine, Insurance, and routes buyback
 *         portion to ZENTBuyback.
 *
 * COMPLIANCE: This contract holds protocol revenue. Distributions are
 *             governance-authorized expenditures, NOT profit-sharing with
 *             ZENT holders. ZENT holders do not have a contractual claim
 *             on any assets held here.
 */
contract ProtocolTreasury {
    using SafeERC20 for IERC20;

    IERC20 public immutable USDC;
    IERC20 public immutable WETH;
    IERC20 public immutable WBTC;
    IERC20 public immutable ZENT;

    address public immutable gpEngine;
    address public immutable insurance;
    address public immutable buyback;  // ZENTBuyback contract

    // Governance address (ZentGovernor + Timelock)
    address public governance;

    // Percentage splits (basis points)
    uint256 public constant BP_GP_ENGINE = 2500;  // 25%
    uint256 public constant BP_INSURANCE = 1500;  // 15%
    uint256 public constant BP_TREASURY  = 1000;  // 10%
    uint256 public constant BP_BUYBACK   = 5000;  // 50%

    mapping(address => uint256) public assetToUsdValue;  // simple oracle storage

    event GovernanceUpdated(address oldGov, address newGov);
    event RevenueReceived(address asset, uint256 amount, uint256 usdcEquiv);
    event RevenueDistributed(uint256 toGp, uint256 toInsurance, uint256 toTreasury, uint256 toBuyback);

    modifier onlyGovernance() {
        require(msg.sender == governance, "Not governance");
        _;
    }

    constructor(
        address _usdc,
        address _weth,
        address _wbtc,
        address _zent,
        address _gpEngine,
        address _insurance,
        address _buyback
    ) {
        USDC = IERC20(_usdc);
        WETH = IERC20(_weth);
        WBTC = IERC20(_wbtc);
        ZENT = IERC20(_zent);
        gpEngine = _gpEngine;
        insurance = _insurance;
        buyback = _buyback;
        governance = msg.sender;
    }

    // ─── Fee intake (called by FeeDistributor.sweepToTreasury) ───────────────

    /**
     * @notice Receive vault asset fees (WETH, WBTC, etc.)
     *         Must be called after FeeDistributor.sweepToTreasury()
     */
    function topUp(address asset, uint256 amount) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        emit RevenueReceived(asset, amount, 0);  // usdEquiv set to 0; real impl uses oracle
    }

    // ─── Monthly distribution (governance-called) ────────────────────────────

    /**
     * @notice Convert all asset balances to USDC and distribute.
     *         Called by governance on a regular schedule (e.g., monthly).
     *
     * IMPORTANT: This is NOT an automatic profit distribution to ZENT holders.
     *            This is a governance-authorized expenditure of protocol revenue.
     *            ZENT holders have no direct claim on these funds.
     */
    function distribute() external onlyGovernance {
        uint256 usdcBalance = USDC.balanceOf(address(this));

        uint256 toGp       = usdcBalance * BP_GP_ENGINE    / 10000;
        uint256 toInsurance= usdcBalance * BP_INSURANCE    / 10000;
        uint256 toTreasury = usdcBalance * BP_TREASURY    / 10000;
        uint256 toBuyback  = usdcBalance * BP_BUYBACK      / 10000;

        // Transfer to GP Engine (operational funding — NOT ZENT holder profit)
        USDC.safeTransfer(gpEngine, toGp);
        // Transfer to Insurance (sinking reserve — NOT ZENT holder profit)
        USDC.safeTransfer(insurance, toInsurance);
        // Transfer to Treasury (DAO operational — NOT ZENT holder profit)
        USDC.safeTransfer(governance, toTreasury);  // treasury controlled by gov
        // Transfer to ZENTBuyback (buyback + burn — supply management)
        USDC.safeTransfer(buyback, toBuyback);

        emit RevenueDistributed(toGp, toInsurance, toTreasury, toBuyback);
    }

    // ─── Buyback trigger delegation ─────────────────────────────────────────
    // The ZENTBuyback contract has its own trigger. Governance can set
    // the buyback contract's parameters but cannot prevent it from executing
    // when conditions are met (no pauseUnlessGovernanceApproved pattern).

    function setGovernance(address _gov) external onlyGovernance {
        address old = governance;
        governance = _gov;
        emit GovernanceUpdated(old, _gov);
    }
}
```

### 3.4 Fee Flow Comparison: Before vs. After

```
BEFORE (Howey Risk):
  Vault fees
    → FeeDistributor
      → 25% GP Engine (direct to external address)
      → 15% Insurance (direct to external address)
      → 10% Treasury (direct to external address)
      → 50% Buyback pool (governance-callable → swaps → burns)
                          ↑
              Problem: buyback is discretionary (governance-called)
                       GP/Insurance/Treasury = direct profit distribution

AFTER (Compliant):
  Vault fees
    → FeeDistributor
      → 100% → ProtocolTreasury
                  │
                  ├─► 25% GP Engine     (governance-authorized expenditure, NOT holder profit)
                  ├─► 15% Insurance      (sinking reserve, NOT holder profit)
                  ├─► 10% Treasury       (DAO ops, NOT holder profit)
                  └─► 50% → ZENTBuyback  (rule-based trigger, buys ZENT, burns to 0xdead)
                                   ↑
                      No governance discretion — triggers automatically when
                      USDC threshold is met. No contractual right to ZENT holders.
```

---

## 4. Legal Framing

### 4.1 What TO Say Publicly

- **"ZENT has a deflationary tokenomics model."** — Accurate, not a promise.
- **"Protocol fees are used to buy back and burn ZENT, reducing supply."** — Supply management framing.
- **"ZENT holders benefit from reduced token supply as the protocol grows."** — All holders benefit equally through macro price effects, not contractual distribution.
- **"The ZENTBuyback contract executes automatically when USDC reserves exceed a threshold."** — Non-discretionary execution is key.
- **"ZENT buyback and burn is a supply management policy determined by governance."** — Governance-decided policy, not a security promise.
- **"ZENT is a utility token for governance and protocol access."** — Consistent with March 2026 taxonomy (digital tool / digital commodity, not digital security).

### 4.2 What NOT to Say

- ❌ **"ZENT holders receive a share of protocol revenue."** — This is a direct profit-sharing / investment contract claim.
- ❌ **"Stake ZENT to earn from the buyback."** — Staking is for governance access and vault access; not for fee revenue share.
- ❌ **"The buyback provides holders with a return."** — The buyback creates macro price pressure, not an individual right to value.
- ❌ **"ZENT is an investment in ZENTORY Labs."** — ZENT is a utility token. Never frame it as equity or an investment contract.
- ❌ **"Buyback guarantees price support."** — No guarantee can or should be made. Legal exposure.
- ❌ **"ZENT's buyback generates yield for stakers."** — Confuses staking rewards (governance incentive) with buyback revenue.
- ❌ **"The foundation will buy back ZENT to support the price."** — Foundation discretion is exactly what creates securities risk.

### 4.3 Internal Legal Guidance

1. **Never frame the buyback as "investor protection"** — That language implies a security relationship.
2. **All governance votes about buyback parameters should be framed as "protocol parameter changes,"** not "investor benefit proposals."
3. **The ZENT whitepaper / documentation should clearly state:** *"ZENT is a governance and utility token. ZENT does not represent equity, a share of fees, or a claim on the protocol's assets or revenue."*
4. **If asked by legal counsel:** The buyback is analogous to a government buying back its own currency — a monetary policy tool, not a securities distribution.
5. **When protocol treasury spends on GP Engine / Insurance / Treasury:** Frame these as **operational expenditures** (like a company paying its employees and vendors), not as **distributions to equity holders**.

---

## 5. Implementation Timeline

### Phase 1: Pre-Mainnet (Implement Now — Before Any Public Launch)

**Goal:** Establish compliant architecture before the protocol goes live with real assets.

| Task | Description | Risk if Deferred |
|---|---|---|
| Deploy `ZENTBuyback` contract | Placeholder DEX integration; actual swap via HyperEVM AMM | Existing `triggerBuyback()` is non-compliant placeholder |
| Deploy `ProtocolTreasury` | Replace direct `distribute()` transfers with treasury-first model | FeeDistributor keeps profit-sharing structure alive |
| Modify `FeeDistributor` | Remove direct `distribute()`; add `sweepToTreasury()` | Howey risk persists through direct reward distribution |
| Update `ZENTStaking` | Decouple staking rewards from fee revenue; use ZENT inflation or governance allocation instead | Staking reward = profit-sharing = investment contract |
| Set `ZENTBuyback` trigger role | Assign to a trusted keeper or automated bot; NOT to a multisig that can selectively trigger | Governance discretion over buyback = securities risk |
| Legal review | Outside counsel review of new architecture against March 2026 SEC/CFTC interpretation | Launch with non-compliant architecture = systemic legal risk |

**Dependencies:** None — these contracts can be deployed on HyperEVM testnet immediately.

### Phase 2: Post-Mainnet (After $5M+ TVL / Sustained Fee Revenue)

**Goal:** Tune buyback parameters and add DEX integration once liquidity exists.

| Task | Description |
|---|---|
| Integrate HyperEVM native DEX | Replace `_swapUsdcForZent()` placeholder with actual AMM or 1inch integration |
| Set `minTriggerUsdc` appropriately | Once USDC reserves from fees are meaningful (~$5K+), set trigger threshold to avoid dust |
| Add TWAP oracle | Uniswap V3 TwapOracle for price validation on large buys |
| Governance vote on `maxZentPerTrigger` | Set based on observed liquidity; reduce if ZENT liquidity is thin |
| Add circuit breaker | If ZENT price drops >X% in Y minutes, pause buyback and alert governance |

### Phase 3: Mature Protocol (>$50M TVL, Proven Fee Revenue)

**Goal:** Maximum sustainability and optional enhanced mechanisms.

| Task | Description |
|---|---|
| Multi-buyback diversification | Split buyback across multiple DEX pools to reduce price impact |
| Dynamic burn ratio | Governance can vote to redirect a portion of buyback from burn to treasury (for grants, etc.) |
| Transparent reporting | Publish monthly on-chain report: USDC spent, ZENT purchased, ZENT burned, effective deflation rate |
| Audit | Full third-party audit of `ZENTBuyback` and `ProtocolTreasury` before major fee routing changes |

---

## 6. Reference Protocols

| Protocol | Model | ZENT Analog | Key Takeaway |
|---|---|---|---|
| **Hyperliquid (HYPE)** | 91% of fees → buyback + burn; pure supply reduction | ZENT vault performance fees | Gold standard for compliance: automated, non-discretionary, revenue-funded |
| **Uniswap (UNI)** | Fee switch → buyback pool → burn; governance-controlled parameters | ZENT FeeDistributor | Avoids security classification by separating governance control from automatic execution |
| **GMX (GMX)** | 50% fees → GMX buyback + burn; 50% to stakers (ETH/USDC) | ZENT vault performance fees | The 50% to stakers creates Howey risk — ZENT should NOT replicate this |
| **Curve (CRV)** | Fee → buyback → distributes to veCRV lockers | ZENT staking (veZENT) | veModel is safe under March 2026 because lockers are compensated for *lockup service*, not profit-sharing |
| **Lyra (perpetual options)** | Fee revenue → buyback → burn | ZENT vault performance fees | Fee revenue fund buyback + burn; no direct distribution to option token holders |
| **Aave (AAVE)** | Portion of lending revenue → buyback → treasury | ZENT vault performance fees | Buyback to treasury, not to holders — avoids securities framing |

---

## 7. Specific Risk Mitigations

| Risk | Mitigation |
|---|---|
| **FeeDistributor distribute() = profit sharing** | Replace with ProtocolTreasury.sweepToTreasury(); remove direct transfers |
| **Staking rewards = investment contract** | Change ZENTStaking to reward from inflation/emissions, not fee revenue |
| **Governance can pause/cancel buyback** | Make trigger condition-based (USDC threshold), not governance-callable |
| **Buyback is discretionary** | Automated keeper triggers at fixed conditions; governance can only change parameters, not block execution |
| **Buyback looks like "price support promise"** | No public materials should promise buyback will support price |
| **Large buys front-run** | Use TWAP orders; publish parameters, not timing |
| **Thin ZENT liquidity → large price impact** | Cap maxZentPerTrigger; add circuit breaker for >X% price impact |
| **SEC characterizes buyback as "security"** | Continuous burn to dead (not to holder wallets); no contractual right; legal review before launch |

---

## 8. Key Design Principles (Summary)

1. **Revenue ≠ Profit Distribution.** Protocol revenue is held in treasury, spent by governance on operations, grants, and buyback — not distributed to ZENT holders as earnings.

2. **Buyback is a policy tool, not a security.** Automated execution, no discretion, no contractual right for any holder to receive ZENT or any asset from the buyback.

3. **All holders benefit equally through supply reduction.** When ZENT is burned, every token becomes more scarce — there is no "class" of beneficiary with special rights.

4. **Staking is for access and governance, not income.** The ZENT staking mechanism should not promise or imply that staking generates fee revenue. Any staking rewards should come from ZENT inflation, not from the FeeDistributor.

5. **Legal framing is as important as code.** The buyback is only compliant if the public communications treat it as a supply management mechanism — not as a yield, dividend, or investor benefit.

---

*This document is for internal ZENTORY Labs use only and does not constitute legal advice. Consult qualified securities counsel before implementing any tokenomics changes.*
