export interface IndexerEvent {
  id: number;
  agreementId: number | null;
  name: string;
  txHash: string;
  blockNumber: string;
  blockTimestamp: string;
  args: Record<string, unknown>;
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

const BASE_URL = process.env.NEXT_PUBLIC_INDEXER_URL?.replace(/\/$/, "") || "";

export const indexerConfigured = BASE_URL.length > 0;

async function get<T>(path: string): Promise<T | null> {
  if (!BASE_URL) return null;
  try {
    const res = await fetch(`${BASE_URL}${path}`, { next: { revalidate: 10 } });
    if (!res.ok) return null;
    return (await res.json()) as T;
  } catch {
    return null;
  }
}

export function fetchAgreementEvents(agreementId: bigint): Promise<IndexerEvent[] | null> {
  return get<IndexerEvent[]>(`/api/agreements/${agreementId.toString()}/events`);
}

export function fetchStats(): Promise<IndexerStats | null> {
  return get<IndexerStats>("/api/stats");
}