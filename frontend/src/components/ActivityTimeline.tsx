"use client";

import { useMemo } from "react";
import { usePublicClient } from "wagmi";
import { useQuery } from "@tanstack/react-query";
import { selectedChainId, txExplorerUrl } from "@/lib/chain";
import { escrowAddress } from "@/lib/contract";
import { createIndexer } from "@/lib/indexer";
import { formatDate, shortenAddress } from "@/lib/format";

const EVENT_COLORS: Record<string, string> = {
  AgreementCreated: "text-indigo-300",
  Funded: "text-amber-300",
  MilestoneReleased: "text-emerald-300",
  DisputeRaised: "text-rose-300",
  DisputeResolved: "text-violet-300",
  AgreementCancelled: "text-neutral-400",
  AgreementCompleted: "text-emerald-300",
  FeesWithdrawn: "text-neutral-400",
};

export function ActivityTimeline({ agreementId }: { agreementId: bigint }) {
  const publicClient = usePublicClient({ chainId: selectedChainId });
  const index = useMemo(() => createIndexer(publicClient), [publicClient]);

  const { data, isLoading } = useQuery({
    queryKey: ["activity", selectedChainId, escrowAddress, agreementId.toString()],
    queryFn: () => index!.eventsForAgreement(agreementId),
    enabled: !!index,
    staleTime: 15_000,
  });

  if (!index) return null;

  if (isLoading) {
    return (
      <div className="card space-y-3 p-4">
        <div className="h-4 w-1/3 animate-pulse rounded bg-white/[0.06]" />
        {[0, 1, 2].map((i) => (
          <div key={i} className="h-8 animate-pulse rounded bg-white/[0.04]" />
        ))}
      </div>
    );
  }

  if (!data || data.length === 0) return null;

  return (
    <div className="card p-5">
      <h2 className="mb-4 text-sm font-medium text-white/70">Activity</h2>
      <ol className="relative ml-2 space-y-4 border-l border-white/10 pl-5">
        {data.map((event) => (
          <li key={event.id} className="relative">
            <span className="absolute -left-[26px] top-1.5 h-2 w-2 rounded-full bg-white/25" />
            <div className="flex flex-wrap items-center gap-2 text-sm">
              <span className={`font-medium ${EVENT_COLORS[event.name] ?? "text-white/70"}`}>
                {humanize(event.name)}
              </span>
              <a
                href={txExplorerUrl(selectedChainId, event.transactionHash)}
                target="_blank"
                rel="noreferrer"
                className="font-mono text-xs text-white/35 hover:text-white/70"
              >
                {shortenAddress(event.transactionHash)}
              </a>
            </div>
            <div className="mt-0.5 text-xs text-white/40">
              {formatDate(Number(event.args.blockTimestamp ?? 0)) !== "—"
                ? formatDate(Number(event.args.blockTimestamp))
                : `block ${event.blockNumber.toString()}`}{" "}
              · {eventTitles(event.name, event.args) ?? "—"}
            </div>
          </li>
        ))}
      </ol>
    </div>
  );
}

function humanize(name: string): string {
  return name.replace(/([a-z])([A-Z])/g, "$1 $2");
}

function eventTitles(name: string, args: Record<string, unknown>): string | null {
  switch (name) {
    case "MilestoneReleased": {
      const amount = String(args.amount ?? "0");
      const fee = String(args.fee ?? "0");
      return `${amount} released, ${fee} protocol fee`;
    }
    case "DisputeResolved": {
      const buyer = String(args.buyerAmount ?? "0");
      const seller = String(args.sellerAmount ?? "0");
      return `buyer refund ${buyer} · seller receives ${seller}`;
    }
    case "DisputeRaised":
      return `raised by ${shortenAddress(String(args.raisedBy ?? ""))}`;
    case "AgreementCreated": {
      const count = (args.milestoneAmounts as unknown[] | undefined)?.length ?? "?";
      return `${count} milestones, total ${String(args.totalAmount ?? "?")}`;
    }
    case "FeesWithdrawn":
      return `${String(args.amount ?? "0")} to fee recipient`;
    default:
      return null;
  }
}
