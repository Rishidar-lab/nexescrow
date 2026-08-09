"use client";

import Link from "next/link";
import { agreementStatusLabels } from "@/lib/contract";
import { useTokenMeta } from "@/hooks/useTokenMeta";
import { formatTokenAmount, shortenAddress } from "@/lib/format";
import { StatusBadge } from "./StatusBadge";
import type { MyAgreementRow } from "@/hooks/useMyAgreements";

export function AgreementCard({ row }: { row: MyAgreementRow }) {
  const { agreement, id, role } = row;
  const tokenMeta = useTokenMeta(agreement?.token);

  return (
    <Link
      href={`/agreement/${id.toString()}`}
      className="block rounded-lg border border-white/10 bg-white/[0.03] p-4 transition hover:border-white/20 hover:bg-white/[0.05]"
    >
      <div className="flex items-center justify-between">
        <span className="font-mono text-sm text-white/60">#{id.toString()}</span>
        <span className="rounded-full bg-white/10 px-2 py-0.5 text-xs capitalize text-white/70">{role}</span>
      </div>

      {agreement ? (
        <>
          <div className="mt-2 text-lg font-semibold">
            {formatTokenAmount(agreement.totalAmount, tokenMeta.decimals)} {tokenMeta.symbol}
          </div>
          <div className="mt-1 text-sm text-white/50">
            {agreement.milestoneCount} milestone{agreement.milestoneCount === 1 ? "" : "s"} · buyer{" "}
            {shortenAddress(agreement.buyer)} · seller {shortenAddress(agreement.seller)}
          </div>
          <div className="mt-3">
            <StatusBadge label={agreementStatusLabels[agreement.status]} status={agreement.status} />
          </div>
        </>
      ) : (
        <div className="mt-2 text-sm text-white/40">Loading…</div>
      )}
    </Link>
  );
}
