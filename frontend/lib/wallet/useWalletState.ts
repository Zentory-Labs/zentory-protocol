"use client";

/**
 * useWalletState — the primary wallet hook for page components.
 *
 * Replaces direct useAccount() / useConnect() / useDisconnect() calls.
 * All wagmi hook imports live exclusively in this module and lib/wallet/.
 *
 * IMPORTANT: This hook must be used by all page components.
 * Do NOT import useAccount, useConnect, or useDisconnect directly in page components.
 */

import {
  useAccount,
  useConnect,
  useDisconnect,
  useChainId,
  useSwitchChain,
} from "wagmi";
import { useState, useCallback, useEffect, useMemo } from "react";
import type { WalletState, WalletRecord, ChainState, WalletError } from "./types";
import { isChainSupported, SUPPORTED_CHAINS } from "./chainManager";

/** Stable wallet id based on connector type + address */
function makeWalletId(connectorType: string, address: string): string {
  return `${connectorType}:${address.toLowerCase()}`;
}

/** Get the connector type string from a connector */
function getConnectorType(connector: { id?: string; name?: string; type?: string }): string {
  // EIP-6963 RDNS identifier when available
  if (connector.id && connector.id !== "injected") {
    return `injected.${connector.id}`;
  }
  // Fall back to the connector's name or type
  return connector.name?.toLowerCase().replace(/\s+/g, "_") ?? connector.type ?? "unknown";
}

/**
 * Primary wallet state hook for the Zentory Protocol.
 *
 * Replaces: useAccount(), useConnect(), useDisconnect()
 *
 * Returns:
 * - activeWallet: the currently-signing wallet
 * - connectedWallets: all retained connections (from wagmi)
 * - chain: current chain state
 * - connectionError: most recent error
 * - connect / disconnect: action functions
 * - switchChain: chain switching with error-code-aware messaging
 */
export function useWalletState(): WalletState {
  const { address, isConnected, isDisconnected, connector } = useAccount();
  const { connect: wagmiConnect, connectors, pendingConnector } = useConnect();
  const { disconnect: wagmiDisconnect } = useDisconnect();
  const { switchChain, isPending: isSwitchingChain } = useSwitchChain();

  // Track all seen wallet records (keyed by stable id)
  const [walletRecords, setWalletRecords] = useState<Map<string, WalletRecord>>(new Map());

  // Track the active wallet id — null when disconnected
  const [activeWalletId, setActiveWalletId] = useState<string | null>(null);

  // Connection error
  const [connectionError, setConnectionError] = useState<WalletError | null>(null);

  // Track if we're in a reconnecting state (previously connected, now reconnecting)
  const [isReconnecting, setIsReconnecting] = useState(false);

  // Current chain from wagmi
  const chainId = useChainId();

  // When wagmi reports a new connection, record it
  useEffect(() => {
    if (isConnected && address && connector) {
      const connectorType = getConnectorType(connector);
      const id = makeWalletId(connectorType, address);

      setWalletRecords((prev) => {
        const next = new Map(prev);
        const existing = next.get(id);
        next.set(id, {
          id,
          address,
          connectorType,
          chainId,
          connectedAt: existing?.connectedAt ?? Date.now(),
          isActive: true,
        });
        return next;
      });

      setActiveWalletId(id);
      setConnectionError(null);
      setIsReconnecting(false);
    }
  }, [address, isConnected, connector, chainId]);

  // Reconciliation: when wagmi reports disconnection, update the active wallet
  useEffect(() => {
    if (isDisconnected && activeWalletId !== null) {
      // The previously-active wallet is now disconnected
      // Find the next reconnectable wallet in the records
      const records = Array.from(walletRecords.values());
      const nextActive = records.find(
        (r) => r.id !== activeWalletId && r.isActive
      );

      if (nextActive) {
        setActiveWalletId(nextActive.id);
      } else {
        setActiveWalletId(null);
      }

      // Mark the disconnected wallet as no longer active
      setWalletRecords((prev) => {
        const next = new Map(prev);
        const record = next.get(activeWalletId);
        if (record) {
          next.set(activeWalletId, { ...record, isActive: false });
        }
        return next;
      });
    }
  }, [isDisconnected, activeWalletId, walletRecords]);

  /** Connect a specific connector */
  const connect = useCallback(
    async (connector: { id?: string }) => {
      setConnectionError(null);
      setIsReconnecting(true);
      try {
        wagmiConnect({ connector });
      } catch (err: any) {
        setConnectionError({
          code: "CONNECT_ERROR",
          message: err.shortMessage ?? err.message ?? "Connection failed",
        });
        setIsReconnecting(false);
      }
    },
    [wagmiConnect]
  );

  /** Try each available connector until one succeeds */
  const connectFirstAvailable = useCallback(async () => {
    setConnectionError(null);
    setIsReconnecting(true);
    for (const connector of connectors) {
      try {
        wagmiConnect({ connector });
        return; // success — let wagmi handle the async connection result
      } catch {
        // try next connector
      }
    }
    setConnectionError({
      code: "NO_CONNECTOR",
      message: "No wallet connectors available",
    });
    setIsReconnecting(false);
  }, [wagmiConnect, connectors]);

  /** Disconnect a specific wallet record */
  const disconnect = useCallback(
    (walletId: string) => {
      const record = walletRecords.get(walletId);
      if (record) {
        wagmiDisconnect({ address: record.address });
      }
      // Optimistically clear — reconciliation in useEffect handles cleanup
      setWalletRecords((prev) => {
        const next = new Map(prev);
        next.delete(walletId);
        return next;
      });
      if (activeWalletId === walletId) {
        setActiveWalletId(null);
      }
    },
    [wagmiDisconnect, walletRecords, activeWalletId]
  );

  /** Set the active (signing) wallet */
  const setActiveWallet = useCallback(
    (walletId: string) => {
      setWalletRecords((prev) => {
        const next = new Map(prev);
        for (const [id, record] of next) {
          next.set(id, { ...record, isActive: id === walletId });
        }
        return next;
      });
      setActiveWalletId(walletId);
    },
    []
  );

  /** Switch to a supported chain */
  const switchToChain = useCallback(
    async (targetChainId: number) => {
      setConnectionError(null);
      try {
        switchChain({ chainId: targetChainId });
      } catch (err: any) {
        setConnectionError({
          code: "CHAIN_SWITCH_ERROR",
          message: err.shortMessage ?? err.message ?? "Chain switch failed",
        });
      }
    },
    [switchChain]
  );

  // Derived state
  const activeWalletRecord = useMemo(
    () => (activeWalletId ? walletRecords.get(activeWalletId) ?? null : null),
    [activeWalletId, walletRecords]
  );

  const chain: ChainState = useMemo(
    () => ({
      id: chainId,
      name: isChainSupported(chainId)
        ? (SUPPORTED_CHAINS[chainId]?.name ?? `Chain ${chainId}`)
        : "Unsupported",
      isSupported: isChainSupported(chainId),
    }),
    [chainId]
  );

  return {
    activeWallet: {
      address: activeWalletRecord?.address ?? address ?? "0x" as const,
      connectorType: activeWalletRecord?.connectorType ?? "unknown",
      chainId: activeWalletRecord?.chainId ?? chainId,
      isConnected: !isDisconnected && isConnected,
      isReconnecting,
    },
    connectedWallets: Array.from(walletRecords.values()),
    activeWalletId,
    chain,
    connectionError,
    // Actions
    connect,
    disconnect,
    setActiveWallet,
    switchToChain,
  };
}
