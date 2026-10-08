import type { Address, Hex } from "viem";
import {
  eventId,
  type AgreementDiscovery,
  type AgreementIndexAdapter,
  type EscrowEventRecord,
  type IndexerStats,
} from "./types";

/**
 * Adapter for a production indexer service. The wire contract (documented in
 * docs/INDEXING.md) is chain- and contract-scoped by construction:
 *
 *   GET /v1/chains/{chainId}/contracts/{address}/agreements?participant=0x..
 *   GET /v1/chains/{chainId}/contracts/{address}/agreements/{id}/events
 *   GET /v1/chains/{chainId}/contracts/{address}/stats
 *
 * Events carry their full identity; the adapter re-checks chainId and
 * contractAddress and drops anything that does not match, so a misconfigured
 * indexer cannot leak another chain's agreements into this UI.
 */

interface WireEvent {
  chainId: number;
  contractAddress: string;
  transactionHash: string;
  logIndex: number;
  blockNumber: string;
  blockHash: string;
  name: string;
  args: Record<string, unknown>;
}

interface WireDiscovery {
  id: string;
  buyer: string;
  seller: string;
  arbiter: string;
}

export interface HttpIndexerOptions {
  baseUrl: string;
  chainId: number;
  contractAddress: Address;
  timeoutMs?: number;
}

async function getJson<T>(url: string, timeoutMs: number): Promise<T | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal, cache: "no-store" });
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

export function createHttpIndexerAdapter(options: HttpIndexerOptions): AgreementIndexAdapter {
  const { baseUrl, chainId, contractAddress, timeoutMs = 10_000 } = options;
  const root = `${baseUrl.replace(/\/$/, "")}/v1/chains/${chainId}/contracts/${contractAddress.toLowerCase()}`;

  return {
    kind: "http",
    chainId,
    contractAddress,

    async discoverAgreementsForParticipant(participant: Address): Promise<AgreementDiscovery[]> {
      const wire = await getJson<WireDiscovery[]>(
        `${root}/agreements?participant=${participant.toLowerCase()}`,
        timeoutMs,
      );
      if (!wire) return [];
      return wire
        .filter((row) => /^\d+$/.test(row.id))
        .map((row) => ({
          id: BigInt(row.id),
          buyer: row.buyer as Address,
          seller: row.seller as Address,
          arbiter: row.arbiter as Address,
        }));
    },

    async eventsForAgreement(agreementId: bigint): Promise<EscrowEventRecord[]> {
      const wire = await getJson<WireEvent[]>(
        `${root}/agreements/${agreementId.toString()}/events`,
        timeoutMs,
      );
      if (!wire) return [];
      return wire
        .filter(
          (row) =>
            row.chainId === chainId &&
            row.contractAddress.toLowerCase() === contractAddress.toLowerCase(),
        )
        .map((row) => {
          const identity = {
            chainId,
            contractAddress,
            transactionHash: row.transactionHash as Hex,
            logIndex: row.logIndex,
          };
          return {
            ...identity,
            id: eventId(identity),
            blockNumber: BigInt(row.blockNumber),
            blockHash: row.blockHash as Hex,
            name: row.name,
            args: row.args ?? {},
          };
        });
    },

    async stats(): Promise<IndexerStats | null> {
      return getJson<IndexerStats>(`${root}/stats`, timeoutMs);
    },
  };
}
