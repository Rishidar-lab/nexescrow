export interface FinalityPolicy {
  /**
   * UI/write lifecycle stage: number of receipt confirmations required before a
   * submitted transaction is labelled confirmed and application state is reconciled.
   */
  writeReceiptConfirmations: number;
  /**
   * Indexing stage: number of newest blocks excluded from log discovery so only
   * a reorg-safety-depth head is scanned/checkpointed.
   */
  indexingSafetyDepth: number;
}

/**
 * Provisional policy values while chain-specific guidance is being confirmed.
 *
 * These are deliberately two different stages, not two names for the same
 * finality guarantee. The values preserve NexEscrow's previously measured/tested
 * behaviour (2 write confirmations, 12-block indexing safety depth) without
 * claiming that either value is BOT Chain's recommended production finality.
 * Update the individual network entries when authoritative guidance is agreed.
 */
const DEFAULT_FINALITY_POLICY: FinalityPolicy = Object.freeze({
  writeReceiptConfirmations: 2,
  indexingSafetyDepth: 12,
});

export const FINALITY_POLICY_BY_CHAIN: Readonly<Record<number, FinalityPolicy>> = Object.freeze({
  3945: Object.freeze({ ...DEFAULT_FINALITY_POLICY }), // Nexus testnet
  3946: Object.freeze({ ...DEFAULT_FINALITY_POLICY }), // Nexus mainnet
  968: Object.freeze({ ...DEFAULT_FINALITY_POLICY }), // BOT Bohr testnet
  677: Object.freeze({ ...DEFAULT_FINALITY_POLICY }), // BOT mainnet
});

export function finalityPolicyFor(chainId: number): FinalityPolicy {
  return FINALITY_POLICY_BY_CHAIN[chainId] ?? DEFAULT_FINALITY_POLICY;
}

export function confirmedSafeHead(
  latestBlock: bigint,
  indexingSafetyDepth: number,
): bigint | null {
  if (!Number.isSafeInteger(indexingSafetyDepth) || indexingSafetyDepth < 0) {
    throw new Error(`Invalid indexing safety depth: ${indexingSafetyDepth}`);
  }

  const depth = BigInt(indexingSafetyDepth);
  return latestBlock >= depth ? latestBlock - depth : null;
}

export type ScanReadiness =
  | { ready: false; safeHead: bigint | null }
  | { ready: true; safeHead: bigint };

/**
 * Decide whether a deployment is deep enough to be included in log discovery.
 *
 * Critical invariant: when startBlock is newer than the confirmed safe head we
 * remain pending. We never substitute `latestBlock`, because doing so would
 * expose unconfirmed deployment/events through the discovery path.
 */
export function scanReadiness(
  startBlock: bigint,
  latestBlock: bigint,
  indexingSafetyDepth: number,
): ScanReadiness {
  const safeHead = confirmedSafeHead(latestBlock, indexingSafetyDepth);
  if (safeHead === null || safeHead < startBlock) {
    return { ready: false, safeHead };
  }
  return { ready: true, safeHead };
}
