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
  const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
  const text = message.toLowerCase();

  return (
    text.includes("429") ||
    text.includes("502") ||
    text.includes("503") ||
    text.includes("504") ||
    text.includes("timeout") ||
    text.includes("timed out") ||
    text.includes("network error") ||
    text.includes("fetch failed") ||
    text.includes("failed to fetch") ||
    text.includes("temporarily unavailable")
  );
}

export function rpcRetryDelayMs(attempt: number): number {
  if (!Number.isSafeInteger(attempt) || attempt < 0) {
    throw new Error(`Invalid retry attempt: ${attempt}`);
  }
  return Math.min(250 * 2 ** attempt, 2_000);
}
