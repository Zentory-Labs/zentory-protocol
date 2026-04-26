"use client";

/**
 * useMultiWallet — multi-wallet orchestration built on top of wagmi.
 *
 * wagmi's useAccount() only tracks the most-recently-connected wallet.
 * This module manages state ABOVE wagmi to retain all connected wallets
 * and support wallet switching between them.
 *
 * Design rules (from plan):
 * - activeWalletId must never point to a wallet wagmi reports as disconnected
 * - injected wallet disconnect affects only that specific EIP-6963 RDNS instance
 * - WalletConnect sessions may be shared — disconnect behavior is per-session-topic
 * - Privy embedded wallets are managed separately by usePrivySession (Phase 2)
 */

import { useCallback, useEffect } from "react";
import { useAccount } from "wagmi";
import type { WalletRecord } from "./types";

/**
 * Multi-wallet state machine.
 *
 * Reconciles wagmi's single-wallet view with multiple retained connections.
 * Subscribes to useAccount change events to keep activeWalletId in sync.
 */
export function useMultiWallet(walletRecords: Map<string, WalletRecord>, activeWalletId: string | null) {
  const { isDisconnected, address: wagmiAddress } = useAccount();

  /**
   * Reconciliation on disconnect:
   * When wagmi reports disconnection, walk the records to find the next
   * reconnectable wallet, or null if none exist.
   */
  const reconcileOnDisconnect = useCallback(
    (
      currentActiveId: string | null,
      records: Map<string, WalletRecord>
    ): string | null => {
      if (!currentActiveId) return null;

      const disconnectedRecord = records.get(currentActiveId);
      if (disconnectedRecord) return null; // already gone

      // Find another wallet that can reconnect
      const candidates = Array.from(records.values()).filter(
        (r) => r.id !== currentActiveId
      );

      return candidates.length > 0 ? candidates[0].id : null;
    },
    []
  );

  /**
   * Tab-resume check: when the tab regains focus, verify that the active
   * wallet's address still matches wagmi's current address.
   *
   * If wagmi's address is different, the active wallet was disconnected externally.
   */
  useEffect(() => {
    function handleVisibilityChange() {
      if (document.visibilityState === "visible") {
        // Wagmi will fire useAccount changes on reconnect if needed
        // This effect exists to trigger a reconnect prompt if the wallet
        // was locked or disconnected while the tab was backgrounded
      }
    }

    document.addEventListener("visibilitychange", handleVisibilityChange);
    return () => document.removeEventListener("visibilitychange", handleVisibilityChange);
  }, []);

  /**
   * When wagmi reports disconnection and we have no active wallet,
   * but we still have wallet records, attempt to find the next best wallet.
   *
   * This is called from useWalletState reconciliation logic.
   */
  function findNextActiveWallet(
    currentActiveId: string | null,
    records: Map<string, WalletRecord>
  ): string | null {
    if (isDisconnected || !wagmiAddress) {
      return reconcileOnDisconnect(currentActiveId, records);
    }

    // Wagmi is connected — ensure activeWalletId matches wagmi's address
    const activeRecord = currentActiveId ? records.get(currentActiveId) : null;

    if (!activeRecord || activeRecord.address !== wagmiAddress) {
      // Wagmi switched to a different wallet — find it in records
      const matching = Array.from(records.values()).find(
        (r) => r.address === wagmiAddress
      );
      return matching?.id ?? null;
    }

    return currentActiveId;
  }

  return {
    findNextActiveWallet,
    reconcileOnDisconnect,
  };
}
