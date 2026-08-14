import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { createServer, type Server, type IncomingMessage, type ServerResponse } from 'node:http';
import { AddressInfo } from 'node:net';

/**
 * Verifies the viem `fallback` transport wiring in chain.ts.
 *
 * Strategy: stand up two tiny HTTP servers on localhost, one returning 502 on
 * every call, one returning a valid JSON-RPC response (eth_chainId=0x3e6 = 998).
 * Configure HYPEREVM_RPC_URL -> the 502 server, HYPEREVM_RPC_URL_FALLBACK -> the
 * working server. A fresh `getPublicClient()` should chain through and read
 * chainId 998 from the fallback.
 *
 * This catches the regression that motivated the PR: previously chain.ts only
 * imported `http`, so even when a fallback URL was set, the keeper would still
 * 502-fail on the primary.
 */

// Mock config BEFORE importing chain, so the module's eager `config` snapshot
// picks up our env vars.
const PRIMARY_PORT_RANGE_START = 35000;
let primaryServer: Server;
let fallbackServer: Server;
let primaryUrl = '';
let fallbackUrl = '';

function jsonRpcResponse(body: string, status = 200): Record<string, unknown> {
  // Minimal valid JSON-RPC envelope so viem's transport accepts it.
  return {
    status,
    headers: { 'content-type': 'application/json' },
    payload: body,
  };
}

async function startServers(): Promise<void> {
  // Primary: every request 502s.
  primaryServer = createServer((_req: IncomingMessage, res: ServerResponse) => {
    res.statusCode = 502;
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify(jsonRpcResponse(JSON.stringify({ error: 'bad gateway' }), 502)));
  });

  // Fallback: returns a valid eth_chainId=998 response.
  fallbackServer = createServer((_req: IncomingMessage, res: ServerResponse) => {
    res.statusCode = 200;
    res.setHeader('content-type', 'application/json');
    res.end(
      JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        result: '0x3e6', // 998 in hex
      })
    );
  });

  await new Promise<void>((resolve) => primaryServer.listen(0, '127.0.0.1', resolve));
  await new Promise<void>((resolve) => fallbackServer.listen(0, '127.0.0.1', resolve));
  const primaryAddr = primaryServer.address() as AddressInfo;
  const fallbackAddr = fallbackServer.address() as AddressInfo;
  primaryUrl = `http://127.0.0.1:${primaryAddr.port}`;
  fallbackUrl = `http://127.0.0.1:${fallbackAddr.port}`;
}

function stopServers(): Promise<void> {
  return Promise.all([
    new Promise<void>((resolve) => primaryServer.close(() => resolve())),
    new Promise<void>((resolve) => fallbackServer.close(() => resolve())),
  ]).then(() => undefined);
}

describe('getPublicClient() fallback transport', () => {
  beforeEach(async () => {
    process.env.HYPEREVM_RPC_URL = 'http://placeholder-will-be-set-below';
    process.env.KEEPER_PRIVATE_KEY =
      '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d'; // anvil[0]
    process.env.SIGNAL_REGISTRY_ADDRESS = '0x0000000000000000000000000000000000000001';
    process.env.EPOCH_SCORING_ADDRESS = '0x0000000000000000000000000000000000000002';
    process.env.ZENT_STAKING_ADDRESS = '0x0000000000000000000000000000000000000003';
    process.env.ZENT_TOKEN_ADDRESS = '0x0000000000000000000000000000000000000004';
    process.env.SCORING_ORACLE_ADDRESS = '0x0000000000000000000000000000000000000005';
    process.env.SUPABASE_URL = 'https://example.supabase.co';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'placeholder';

    await startServers();
    process.env.HYPEREVM_RPC_URL = primaryUrl;
    process.env.HYPEREVM_RPC_URL_FALLBACK = fallbackUrl;
  });

  afterEach(async () => {
    delete process.env.HYPEREVM_RPC_URL_FALLBACK;
    await stopServers();
    vi.resetModules();
  });

  it('reads chainId via the fallback URL when the primary 502s', async () => {
    // Fresh import after env vars are set.
    const { getPublicClient } = await import('../src/chain');
    const client = getPublicClient();
    const chainId = await client.getChainId();
    expect(chainId).toBe(998);
  });

  it('does NOT require a fallback URL (single-URL mode still works)', async () => {
    delete process.env.HYPEREVM_RPC_URL_FALLBACK;
    // Restart only the working server as primary.
    await stopServers();
    primaryServer = createServer((_req, res) => {
      res.statusCode = 200;
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ jsonrpc: '2.0', id: 1, result: '0x3e6' }));
    });
    await new Promise<void>((resolve) => primaryServer.listen(0, '127.0.0.1', resolve));
    const addr = primaryServer.address() as AddressInfo;
    process.env.HYPEREVM_RPC_URL = `http://127.0.0.1:${addr.port}`;

    vi.resetModules();
    const { getPublicClient } = await import('../src/chain');
    const client = getPublicClient();
    const chainId = await client.getChainId();
    expect(chainId).toBe(998);
  });
});
