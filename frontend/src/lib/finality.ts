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
 * Generic fallback for chains without an explicit network-specific policy.
 *
 * BOT Chain engineering guidance received 2026-10-14 is represented explicitly
 * below rather than being hidden in this fallback. Nexus entries retain the
 * previously measured/tested application defaults until Nexus-specific guidance
 * says otherwise.
 */
const DEFAULT_FINALITY_POLICY: FinalityPolicy = Object.freeze({
  writeReceiptConfirmations: 2,
  indexingSafetyDepth: 12,
});

/**
 * BOT Chain guidance (Cisco, relayed by Leon on 2026-10-14):
 *
 * - receipt confirmations: 2 blocks on both Bohr 968 and mainnet 677;
 * - reorganisation handling / finality guarantees: not yet clarified.
 *
 * NexEscrow therefore treats the 2-block receipt count as network guidance, while
 * retaining 12 blocks as its own conservative indexing safety depth. The latter is
 * an application policy, NOT a BOT Chain finality guarantee.
 */
const BOT_INDEXING_SAFETY_DEPTH = 12;

export const FINALITY_POLICY_BY_CHAIN: Readonly<Record<number, FinalityPolicy>> = Object.freeze({
  3945: Object.freeze({ ...DEFAULT_FINALITY_POLICY }), // Nexus testnet
  3946: Object.freeze({ ...DEFAULT_FINALITY_POLICY }), // Nexus mainnet
  968: Object.freeze({
    writeReceiptConfirmations: 2,
    indexingSafetyDepth: BOT_INDEXING_SAFETY_DEPTH,
  }), // BOT Bohr testnet
  677: Object.freeze({
    writeReceiptConfirmations: 2,
    indexingSafetyDepth: BOT_INDEXING_SAFETY_DEPTH,
  }), // BOT mainnet (still disabled in this build)
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
