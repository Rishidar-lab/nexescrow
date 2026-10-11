/**
 * Row validation for the remote indexer adapter.
 *
 * Kept in its own module, with no imports, so it can be unit-tested directly:
 * `http.ts` pulls in `./types`, which Node's ESM resolver will not resolve
 * extensionless. These are pure predicates over untrusted JSON.
 */
// ---------------------------------------------------------------------------
// Row validation
// ---------------------------------------------------------------------------

/** viem's own address check: 0x-prefixed, 40 hex chars, checksum-tolerant. */
function isAddressLike(value: unknown): value is string {
  return typeof value === "string" && /^0x[0-9a-fA-F]{40}$/.test(value);
}

function isSafeUintString(value: unknown): value is string {
  return typeof value === "string" && /^[0-9]+$/.test(value);
}

/**
 * A discovery row is usable only if every field it will be read from is
 * present and well-formed. Anything less is dropped: the caller then treats it
 * as absent rather than crashing on `.toLowerCase()` or `BigInt()`.
 */
export function isValidDiscoveryRow(row: unknown): boolean {
  if (typeof row !== "object" || row === null) return false;
  const r = row as Record<string, unknown>;
  return (
    isSafeUintString(r.id) &&
    isAddressLike(r.buyer) &&
    isAddressLike(r.seller) &&
    isAddressLike(r.arbiter)
  );
}

/**
 * Event rows additionally carry the chain/contract identity the adapter is
 * scoped to, plus a block number and hash that must parse. These are the fields
 * the indexer is trusted to have got right about the chain; everything is checked
 * before it reaches `BigInt(...)` or a hash comparison.
 */
export function isValidEventRow(row: unknown): boolean {
  if (typeof row !== "object" || row === null) return false;
  const r = row as Record<string, unknown>;
  return (
    typeof r.chainId === "number" &&
    Number.isSafeInteger(r.chainId) &&
    r.chainId > 0 &&
    isAddressLike(r.contractAddress) &&
    isSafeUintString(r.blockNumber) &&
    typeof r.blockHash === "string" &&
    /^0x[0-9a-fA-F]{64}$/.test(r.blockHash) &&
    typeof r.transactionHash === "string" &&
    /^0x[0-9a-fA-F]{64}$/.test(r.transactionHash) &&
    typeof r.logIndex === "number" &&
    Number.isSafeInteger(r.logIndex) &&
    r.logIndex >= 0 &&
    typeof r.name === "string" &&
    r.name.length > 0 &&
    typeof r.args === "object" &&
    r.args !== null
  );
}
