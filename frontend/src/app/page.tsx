"use client";

import Link from "next/link";
import { useAccount } from "wagmi";
import { useMyAgreements } from "@/hooks/useMyAgreements";
import { AgreementCard } from "@/components/AgreementCard";

export default function DashboardPage() {
  const { isConnected } = useAccount();
  const { rows, isLoading, error } = useMyAgreements();

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center gap-3 rounded-lg border border-dashed border-white/15 py-20 text-center">
        <h1 className="text-xl font-semibold">Connect a wallet</h1>
        <p className="max-w-sm text-sm text-white/50">
          Connect to Nexus L1 to see agreements where you&apos;re the buyer, seller, or arbiter.
        </p>
      </div>
    );
  }

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold">Your agreements</h1>
        <Link
          href="/create"
          className="rounded-md bg-indigo-500 px-3 py-1.5 text-sm font-medium text-white hover:bg-indigo-400"
        >
          New agreement
        </Link>
      </div>

      {error && (
        <p className="rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-300">
          Failed to load agreements: {error.message}
        </p>
      )}

      {!error && isLoading && <p className="text-sm text-white/50">Loading agreements…</p>}

      {!error && !isLoading && rows.length === 0 && (
        <div className="rounded-lg border border-dashed border-white/15 py-16 text-center text-sm text-white/50">
          No agreements yet.{" "}
          <Link href="/create" className="text-indigo-300 hover:underline">
            Create one
          </Link>
          .
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {rows.map((row) => (
          <AgreementCard key={row.id.toString()} row={row} />
        ))}
      </div>
    </div>
  );
}
