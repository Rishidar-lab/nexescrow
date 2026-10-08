import type { PublicClient } from "viem";
import { escrowAddress, escrowConfigured, getDeployBlock, selectedChainId } from "@/lib/chain";
import { createHttpIndexerAdapter } from "./http";
import { createLogScanAdapter } from "./logScan";
import type { AgreementIndexAdapter } from "./types";

export type { AgreementDiscovery, AgreementIndexAdapter, EscrowEventRecord, IndexerStats } from "./types";
export { dedupeEvents, eventId } from "./types";

export const indexerBaseUrl = (process.env.NEXT_PUBLIC_INDEXER_URL ?? "").replace(/\/$/, "");

/**
 * Selects the agreement index for this build:
 *
 *   1. HTTP indexer when NEXT_PUBLIC_INDEXER_URL is configured (production path).
 *   2. Bounded direct-RPC log scan otherwise (works without infrastructure).
 *
 * Returns null when the selected chain has no configured contract — the UI must
 * render an "unconfigured" state, never query against the zero address.
 */
export function createIndexer(publicClient: PublicClient | undefined): AgreementIndexAdapter | null {
  if (!escrowConfigured) return null;

  if (indexerBaseUrl) {
    return createHttpIndexerAdapter({
      baseUrl: indexerBaseUrl,
      chainId: selectedChainId,
      contractAddress: escrowAddress,
    });
  }

  if (!publicClient) return null;

  return createLogScanAdapter({
    chainId: selectedChainId,
    contractAddress: escrowAddress,
    publicClient,
    startBlock: getDeployBlock(selectedChainId),
  });
}
