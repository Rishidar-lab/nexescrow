"use client";

import Link from "next/link";
import { agreementStatusLabels, AgreementStatus } from "@/lib/contract";
import { useTokenMeta } from "@/hooks/useTokenMeta";
import { formatTokenAmount, shortenAddress } from "@/lib/format";
import { StatusBadge } from "./StatusBadge";
import type { MyAgreementRow } from "@/hooks/useMyAgreements";

const ROLE_CHIP: Record<MyAgreementRow["role"], string> = {
  buyer: "bg-indigo-500/15 text-indigo-300",
  seller: "bg-emerald-500/15 text-emerald-300",
  arbiter: "bg-violet-500/15 text-violet-300",
};

export function AgreementCard({ row }: { row: MyAgreementRow }) {
  const { agreement, id, role } = row;
  const tokenMeta = useTokenMeta(agreement?.token);

  const progress =
    agreement && agreement.milestoneCount > 0
      ? (agreement.nextMilestone / agreement.milestoneCount) * 100
      : 0;

  return (
    <Link
      href={`/agreement/${id.toString()}`}
      className="card group relative overflow-hidden p-4 transition hover:border-white/20 hover:bg-white/[0.05]"
    >
      <div className="flex items-center justify-between">
        <span className="font-mono text-sm text-white/45">#{id.toString()}</span>
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-medium capitalize ${ROLE_CHIP[role]}`}
        >
          {role}
        </span>
      </div>

      {agreement ? (
        <>
          <div className="mt-3 text-xl font-semibold tracking-tight">
            {formatTokenAmount(agreement.totalAmount, tokenMeta.decimals)}{" "}
            <span className="text-sm font-medium text-white/45">{tokenMeta.symbol}</span>
          </div>
          <div className="mt-1.5 text-sm text-white/45">
            {agreement.milestoneCount} milestone{agreement.milestoneCount === 1 ? "" : "s"} ·
            buyer {shortenAddress(agreement.buyer)}
            {role !== "seller" && <> · seller {shortenAddress(agreement.seller)}</>}
          </div>

          <div className="mt-4 flex items-center justify-between gap-3">
            <StatusBadge label={agreementStatusLabels[agreement.status]} status={agreement.status} />
            {agreement.status === AgreementStatus.Active && (
              <span className="text-xs text-white/40">
                {agreement.nextMilestone}/{agreement.milestoneCount}
              </span>
            )}
          </div>

          {agreement.status === AgreementStatus.Active && (
            <div className="mt-2 h-1 w-full overflow-hidden rounded-full bg-white/[0.06]">
              <div
                className="h-full rounded-full bg-gradient-to-r from-indigo-500 to-violet-500 transition-all"
                style={{ width: `${progress}%` }}
              />
            </div>
          )}
        </>
      ) : (
        <div className="mt-3 space-y-2">
          <div className="h-6 w-2/3 animate-pulse rounded bg-white/[0.06]" />
          <div className="h-4 w-1/2 animate-pulse rounded bg-white/[0.05]" />
        </div>
      )}
    </Link>
  );
}