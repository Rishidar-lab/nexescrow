"use client";

import Link from "next/link";
import { useAccount } from "wagmi";
import { useMyAgreements } from "@/hooks/useMyAgreements";
import { AgreementCard } from "@/components/AgreementCard";
import { formatTokenAmount } from "@/lib/format";
import { useTokenMeta } from "@/hooks/useTokenMeta";

export default function DashboardPage() {
  const { isConnected, address } = useAccount();
  const { rows, isLoading, error } = useMyAgreements();
  const walletTokenMeta = useTokenMeta(undefined);

  const involved = rows.length;
  const asBuyer = rows.filter((r) => r.role === "buyer").length;
  const asSeller = rows.filter((r) => r.role === "seller").length;
  const active = rows.filter((r) => r.agreement?.status === 1).length;
  const escrowed = rows.reduce((sum, r) => sum + (r.agreement?.totalAmount ?? 0n), 0n);

  if (!isConnected || !address) {
    return (
      <div className="flex flex-col items-center justify-center gap-4 rounded-2xl border border-dashed border-white/15 px-6 py-24 text-center">
        <div className="rounded-full border border-indigo-400/40 bg-indigo-500/10 p-3">
          <WalletIcon />
        </div>
        <h1 className="text-xl font-semibold">Connect a wallet</h1>
        <p className="max-w-sm text-sm text-white/50">
          Connect to Nexus L1 to see agreements where you&apos;re the buyer, seller, or arbiter — and
          to fund, approve, and resolve them.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">Your agreements</h1>
          <p className="mt-0.5 text-sm text-white/50">Everything you&apos;re involved in, on Nexus L1.</p>
        </div>
        <Link href="/create" className="btn-primary px-5 py-2.5">
          <PlusIcon /> New agreement
        </Link>
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatCard label="Involved" value={involved.toString()} />
        <StatCard label="As buyer" value={asBuyer.toString()} />
        <StatCard label="As seller" value={asSeller.toString()} />
        <StatCard label="Active" value={active.toString()} />
      </div>

      <div className="card flex items-center justify-between px-4 py-3 text-sm">
        <span className="text-white/50">Total value locked in your agreements</span>
        <span className="font-semibold">
          {formatTokenAmount(escrowed, walletTokenMeta.decimals)} {walletTokenMeta.symbol}
        </span>
      </div>

      {error && (
        <p className="rounded-lg border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-300">
          Failed to load agreements: {error.message}
        </p>
      )}

      {!error && isLoading && (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {[0, 1, 2].map((i) => (
            <div key={i} className="card h-32 animate-pulse" />
          ))}
        </div>
      )}

      {!error && !isLoading && rows.length === 0 && (
        <div className="flex flex-col items-center gap-3 rounded-2xl border border-dashed border-white/15 px-6 py-16 text-center">
          <p className="text-sm text-white/50">No agreements yet.</p>
          <Link href="/create" className="btn-ghost">
            Create your first one
          </Link>
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

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="card px-4 py-3">
      <div className="gradient-text text-2xl font-bold">{value}</div>
      <div className="mt-0.5 text-xs text-white/45">{label}</div>
    </div>
  );
}

function PlusIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
      <path d="M7 1v12M1 7h12" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
  );
}

function WalletIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" className="text-indigo-300">
      <rect x="3" y="6" width="18" height="14" rx="3" stroke="currentColor" strokeWidth="1.6" />
      <path d="M16 12h3" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <path d="M3 9h18" stroke="currentColor" strokeWidth="1.2" opacity="0.5" />
    </svg>
  );
}