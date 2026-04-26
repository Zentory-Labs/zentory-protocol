/**
 * Wallet types for the Zentory Protocol wallet integration layer.
 *
 * This module defines the core wallet state model. All wagmi hooks are
 * encapsulated inside this layer — page components import from here.
 */

import type { Address } from "viem";

/** Known wallet connector families */
export type WalletConnectorFamily =
  | "injected"    // MetaMask, Rabby, Trust, etc. (EIP-6963 detected)
  | "coinbase"    // Coinbase Wallet
  | "walletconnect" // WalletConnect v2
  | "safe"        // Safe{Wallet}
  | "hardware";   // Ledger, Trezor

/**
 * Stable wallet record — one per connected (connector, address) pair.
 * connectorType stores either an EIP-6963 RDNS identifier (for injected wallets)
 * or a WalletConnectorFamily value (for non-EIP-6963 connectors).
 */
export interface WalletRecord {
  /** Stable unique id for this (connector, address) pair */
  id: string;
  /** Ethereum address */
  address: Address;
  /**
   * EIP-6963 RDNS identifier for injected wallets (e.g. "io.metamask").
   * For non-EIP-6963 connectors: "coinbase" | "walletconnect" | "safe" | "hardware"
   */
  connectorType: string;
  /** Chain ID the wallet was connected on */
  chainId: number;
  /** Unix timestamp of when this wallet was first connected */
  connectedAt: number;
  /** Whether this wallet is currently signing transactions */
  isActive: boolean;
}

/** Normalized wallet connection error */
export interface WalletError {
  code: string;
  message: string;
}

/** Chain state */
export interface ChainState {
  id: number;
  name: string;
  isSupported: boolean;
}

/** Active (signing) wallet */
export interface ActiveWalletInfo {
  address: Address;
  connectorType: string;
  chainId: number;
  isConnected: boolean;
  isReconnecting: boolean;
}

/** Actions exposed by useWalletState */
export interface WalletActions {
  /** Connect a specific connector (by connector object) */
  connect(connector: { id?: string }): Promise<void>;
  /** Try each available connector until one succeeds */
  connectFirstAvailable(): Promise<void>;
  /** Disconnect a specific wallet by its stable wallet id */
  disconnect(walletId: string): void;
  /** Set the active (signing) wallet by its stable wallet id */
  setActiveWallet(walletId: string): void;
  /** Switch to a supported chain by chain id */
  switchToChain(chainId: number): Promise<void>;
}

/** Top-level wallet state exposed by useWalletState */
export interface WalletState extends WalletActions {
  activeWallet: ActiveWalletInfo;
  connectedWallets: WalletRecord[];
  activeWalletId: string | null;
  chain: ChainState;
  connectionError: WalletError | null;
}
