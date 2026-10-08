import type { Address, Hex } from "viem";

/**
 * Canonical escrow event identity. An event is only unique across the whole
 * multi-chain deployment when all four components are present:
 *
 *   (chainId, contractAddress, transactionHash, logIndex)
 *
 * Never key by transactionHash alone: the same hash can exist on different
 * chains, and one transaction can emit several escrow logs.
 */
export interface EscrowEventIdentity {
  chainId: number;
  contractAddress: Address;
  transactionHash: Hex;
  logIndex: number;
}

export function eventId(identity: EscrowEventIdentity): string {
  return [
    identity.chainId,
    identity.contractAddress.toLowerCase(),
    identity.transactionHash.toLowerCase(),
    identity.logIndex,
  ].join(":");
}

export interface EscrowEventRecord extends EscrowEventIdentity {
  /** Canonical `eventId(...)` — the idempotency key for ingestion. */
  id: string;
  blockNumber: bigint;
  blockHash: Hex;
  name: string;
  args: Record<string, unknown>;
}

export interface AgreementDiscovery {
  id: bigint;
  buyer: Address;
  seller: Address;
  arbiter: Address;
}

export interface IndexerStats {
  agreementCount: number;
  awaitingFunding: number;
  active: number;
  completed: number;
  cancelled: number;
  inEscrow: string;
  totalReleased: string;
}

/**
 * Storage-agnostic agreement index. Two implementations exist:
 *
 *   - `logScan` — direct RPC with bounded, chunked queries (works today, no infra)
 *   - `http`    — a real indexer service (production path; see docs/INDEXING.md)
 */
export interface AgreementIndexAdapter {
  readonly kind: "log-scan" | "http";
  readonly chainId: number;
  readonly contractAddress: Address;
  discoverAgreementsForParticipant(participant: Address): Promise<AgreementDiscovery[]>;
  eventsForAgreement(agreementId: bigint): Promise<EscrowEventRecord[]>;
  stats(): Promise<IndexerStats | null>;
}

/** Deduplicate an event stream by canonical identity. Order is preserved. */
export function dedupeEvents(events: EscrowEventRecord[]): EscrowEventRecord[] {
  const seen = new Set<string>();
  const out: EscrowEventRecord[] = [];
  for (const event of events) {
    if (seen.has(event.id)) continue;
    seen.add(event.id);
    out.push(event);
  }
  return out;
}
