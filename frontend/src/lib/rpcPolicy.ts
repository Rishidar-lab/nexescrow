import { HttpRequestError, RpcRequestError, TimeoutError } from "viem";

/**
 * Network-facing RPC policy for the lightweight client-side indexer.
 *
 * BOT Chain engineering guidance received from Cisco via Leon on 2026-10-14:
 * - recommended eth_getLogs range: 2,000 blocks per query;
 * - no configured rate limit was reported;
 * - retry/reorganisation/finality guarantees remain unspecified.
 *
 * NexEscrow therefore enforces the 2,000-block ceiling on BOT networks and uses
 * its own small, bounded retry policy for clearly transient transport/gateway
 * failures. The retry policy is an application choice, not BOT Chain guidance.
 */

export const BOT_CHAIN_IDS = Object.freeze([968, 677] as const);
export const BOT_RECOMMENDED_LOG_QUERY_BLOCKS = 2_000n;
export const RPC_MAX_ATTEMPTS = 3;

export function logQueryChunkSizeFor(chainId: number, requested = 2_000n): bigint {
  if (requested <= 0n) {
    throw new Error(`Invalid log query chunk size: ${requested}`);
  }

  if (
    (chainId === BOT_CHAIN_IDS[0] || chainId === BOT_CHAIN_IDS[1]) &&
    requested > BOT_RECOMMENDED_LOG_QUERY_BLOCKS
  ) {
    return BOT_RECOMMENDED_LOG_QUERY_BLOCKS;
  }

  return requested;
}

export function isRetryableRpcError(error: unknown): boolean {
  let current: unknown = error;

  // viem wraps transport failures. Walk a bounded cause chain so a permanent
  // JSON-RPC response can never become retryable merely because its message
  // happens to contain a gateway status such as "429" or "502".
  for (let depth = 0; current !== null && current !== undefined && depth < 5; depth++) {
    if (current instanceof TimeoutError) return true;
    if (current instanceof HttpRequestError) {
      return (
        current.status === 429 ||
        current.status === 502 ||
        current.status === 503 ||
        current.status === 504
      );
    }
    if (current instanceof RpcRequestError) return false;

    if (typeof current !== "object" && typeof current !== "function") break;
    current = (current as { cause?: unknown }).cause;
  }

  // Some runtimes surface low-level fetch failures as plain Errors. Keep the
  // fallback deliberately narrow: HTTP status and semantic RPC text are handled
  // only through the typed branches above.
  const text = String(error instanceof Error ? error.message : error).toLowerCase();
  return (
    text.includes("network error") ||
    text.includes("fetch failed") ||
    text.includes("failed to fetch")
  );
}

export function rpcRetryDelayMs(attempt: number): number {
  if (!Number.isSafeInteger(attempt) || attempt < 0) {
    throw new Error(`Invalid retry attempt: ${attempt}`);
  }
  return Math.min(250 * 2 ** attempt, 2_000);
}
