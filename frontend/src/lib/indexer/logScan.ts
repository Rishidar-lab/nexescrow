import type { Address, Hex, PublicClient } from "viem";
import { escrowAbi } from "@/lib/contract";
import {
  dedupeEvents,
  eventId,
  type AgreementDiscovery,
  type AgreementIndexAdapter,
  type EscrowEventRecord,
  type IndexerStats,
} from "./types";

/**
 * Direct-RPC agreement discovery with bounded, chunked log queries.
 *
 * Properties (the subset of the production ingestion contract that can be
 * honoured client-side — see docs/INDEXING.md for the full server design):
 *
 *  - BOUNDED QUERIES: never asks an RPC for a single unbounded range; scans in
 *    `chunkSize` windows from the contract's deploy block.
 *  - IDEMPOTENT + DEDUPED: records are keyed by
 *    (chainId, contractAddress, txHash, logIndex) and deduplicated on merge.
 *  - REORG RECONCILIATION: a full rescan replaces records rather than appending;
 *    overlapping windows re-fetch recently-seen ranges, so reorged logs
 *    disappear on the next sync. Checkpoints are only advanced to a
 *    `confirmations`-deep safe head.
 *  - CHAIN + CONTRACT SEPARATION: cache keys and identity include both; the
 *    adapter refuses a public client on a different chain.
 */

export interface LogScanOptions {
  chainId: number;
  contractAddress: Address;
  publicClient: PublicClient;
  /** First block to scan; use the contract's deployment block to bound work. */
  startBlock: bigint;
  /** Reorg safety depth. Default 12. */
  confirmations?: number;
  /** Block window per eth_getLogs call. Default 2,000. */
  chunkSize?: bigint;
  /** How long a completed scan is reused before re-syncing. Default 15s. */
  staleAfterMs?: number;
}

interface ScanCache {
  records: EscrowEventRecord[];
  safeHead: bigint;
  fetchedAt: number;
}

const cache = new Map<string, ScanCache>();

function cacheKey(chainId: number, address: Address): string {
  return `${chainId}:${address.toLowerCase()}`;
}

/** Observability only; the authoritative resume state is the in-memory cache. */
export function readCheckpoint(chainId: number, address: Address): bigint | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(`nexescrow:logscan:v1:${cacheKey(chainId, address)}`);
    return raw && /^\d+$/.test(raw) ? BigInt(raw) : null;
  } catch {
    return null;
  }
}

function writeCheckpoint(chainId: number, address: Address, block: bigint): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(
      `nexescrow:logscan:v1:${cacheKey(chainId, address)}`,
      block.toString(),
    );
  } catch {
    // storage unavailable — scan still works, just without a persisted hint
  }
}

export function createLogScanAdapter(options: LogScanOptions): AgreementIndexAdapter {
  const {
    chainId,
    contractAddress,
    publicClient,
    startBlock,
    confirmations = 12,
    chunkSize = 2_000n,
    staleAfterMs = 15_000,
  } = options;

  async function sync(): Promise<ScanCache> {
    if (publicClient.chain && publicClient.chain.id !== chainId) {
      throw new Error(
        `log-scan adapter configured for chain ${chainId} but received a client for chain ${publicClient.chain.id}`,
      );
    }

    const key = cacheKey(chainId, contractAddress);
    const existing = cache.get(key);
    const now = Date.now();

    const latest = await publicClient.getBlockNumber();
    const confirmationsBig = BigInt(confirmations);
    const safeHead = latest > confirmationsBig ? latest - confirmationsBig : 0n;

    if (existing && existing.safeHead === safeHead && now - existing.fetchedAt < staleAfterMs) {
      return existing;
    }

    const collected = new Map<string, EscrowEventRecord>();
    const head = safeHead >= startBlock ? safeHead : latest;

    for (let cursor = startBlock; cursor <= head; cursor += chunkSize) {
      const to = cursor + chunkSize - 1n > head ? head : cursor + chunkSize - 1n;
      const logs = await publicClient.getContractEvents({
        address: contractAddress,
        abi: escrowAbi,
        fromBlock: cursor,
        toBlock: to,
      });

      for (const log of logs) {
        if (log.blockNumber === null || log.blockHash === null || log.transactionHash === null) {
          continue;
        }
        const identity = {
          chainId,
          contractAddress,
          transactionHash: log.transactionHash as Hex,
          logIndex: log.logIndex,
        };
        const record: EscrowEventRecord = {
          ...identity,
          id: eventId(identity),
          blockNumber: log.blockNumber,
          blockHash: log.blockHash,
          name: log.eventName ?? "Unknown",
          args: (log.args ?? {}) as Record<string, unknown>,
        };
        // Idempotent merge: same canonical id replaces, never duplicates.
        collected.set(record.id, record);
      }
    }

    const records = dedupeEvents(
      [...collected.values()].sort((a, b) =>
        a.blockNumber === b.blockNumber
          ? a.logIndex - b.logIndex
          : a.blockNumber < b.blockNumber
            ? -1
            : 1,
      ),
    );

    const next: ScanCache = { records, safeHead, fetchedAt: now };
    cache.set(key, next);
    // Checkpoint only moves to a confirmed head; a stale checkpoint can never
    // cause records to be "skipped" because the in-memory cache is authoritative.
    if (safeHead >= startBlock) writeCheckpoint(chainId, contractAddress, safeHead + 1n);
    return next;
  }

  return {
    kind: "log-scan",
    chainId,
    contractAddress,

    async discoverAgreementsForParticipant(participant: Address): Promise<AgreementDiscovery[]> {
      const { records } = await sync();
      const who = participant.toLowerCase();
      const out: AgreementDiscovery[] = [];
      for (const record of records) {
        if (record.name !== "AgreementCreated") continue;
        const buyer = String(record.args.buyer ?? "").toLowerCase();
        const seller = String(record.args.seller ?? "").toLowerCase();
        const arbiter = String(record.args.arbiter ?? "").toLowerCase();
        if (buyer !== who && seller !== who && arbiter !== who) continue;
        const id = record.args.id;
        if (typeof id !== "bigint") continue;
        out.push({
          id,
          buyer: record.args.buyer as Address,
          seller: record.args.seller as Address,
          arbiter: record.args.arbiter as Address,
        });
      }
      return out.sort((a, b) => (a.id < b.id ? 1 : a.id > b.id ? -1 : 0));
    },

    async eventsForAgreement(agreementId: bigint): Promise<EscrowEventRecord[]> {
      const { records } = await sync();
      return records.filter((record) => {
        const id = record.args.id;
        return typeof id === "bigint" && id === agreementId;
      });
    },

    async stats(): Promise<IndexerStats | null> {
      // Client-side log scanning is for discovery/compatibility; protocol-wide
      // stats belong to the HTTP indexer (see docs/INDEXING.md). Returning null
      // tells the UI to hide stat panels rather than invent numbers.
      return null;
    },
  };
}
