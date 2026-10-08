"use client";

import { use, useState, type ReactNode } from "react";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import type { Address } from "viem";
import {
  escrowAbi,
  escrowAddress,
  agreementStatusLabels,
  milestoneStatusLabels,
  AgreementStatus,
  MilestoneStatus,
  NATIVE_TOKEN,
} from "@/lib/contract";
import { useAgreement, useAllowance } from "@/hooks/useAgreement";
import { useTokenMeta } from "@/hooks/useTokenMeta";
import { formatTokenAmount, formatDate, shortenAddress } from "@/lib/format";
import { StatusBadge } from "@/components/StatusBadge";
import { CopyButton } from "@/components/CopyButton";
import { ActivityTimeline } from "@/components/ActivityTimeline";
import { erc20Abi } from "@/lib/erc20Abi";

const MILESTONE_ICON: Record<number, ReactNode> = {
  [MilestoneStatus.Pending]: <span className="h-1.5 w-1.5 rounded-full bg-white/30" />,
  [MilestoneStatus.Released]: (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" className="text-emerald-400">
      <path
        d="M4 12.5l5 5L20 6.5"
        stroke="currentColor"
        strokeWidth="3"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  ),
  [MilestoneStatus.Disputed]: (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" className="text-rose-400">
      <path d="M12 8v5M12 16.5v.5" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.8" />
    </svg>
  ),
  [MilestoneStatus.Resolved]: (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" className="text-violet-400">
      <path d="M12 9v3.5M12 16v.5" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" />
      <circle
        cx="12"
        cy="12"
        r="9"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeDasharray="30 20"
      />
    </svg>
  ),
};

export default function AgreementDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id: idParam } = use(params);
  const id = BigInt(idParam);

  const { address } = useAccount();
  const { agreement, milestones, isLoading, refetch } = useAgreement(id);
  const tokenMeta = useTokenMeta(agreement?.token);
  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();
  const allowanceResult = useAllowance(agreement?.token ?? NATIVE_TOKEN, address);

  const [pending, setPending] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [buyerPercent, setBuyerPercent] = useState("50");

  if (isLoading || !agreement) {
    return (
      <div className="mx-auto max-w-3xl space-y-4">
        <div className="h-7 w-48 animate-pulse rounded bg-white/[0.07]" />
        <div className="card h-28 animate-pulse" />
        <div className="card h-48 animate-pulse" />
      </div>
    );
  }

  const isBuyer = address?.toLowerCase() === agreement.buyer.toLowerCase();
  const isSeller = address?.toLowerCase() === agreement.seller.toLowerCase();
  const isArbiter = address?.toLowerCase() === agreement.arbiter.toLowerCase();
  const isParty = isBuyer || isSeller;
  const isNative = agreement.token.toLowerCase() === NATIVE_TOKEN;

  const currentIndex = agreement.nextMilestone;
  const currentMilestone = milestones?.[currentIndex];
  const progress = agreement.milestoneCount > 0 ? (currentIndex / agreement.milestoneCount) * 100 : 0;
  const releasedAmount =
    milestones?.reduce(
      (sum, m) => (m.status === MilestoneStatus.Released ? sum + m.amount : sum),
      0n,
    ) ?? 0n;

  async function run(label: string, fn: () => Promise<`0x${string}`>) {
    setActionError(null);
    setPending(label);
    try {
      const hash = await fn();
      await publicClient?.waitForTransactionReceipt({ hash });
      await Promise.all([refetch(), allowanceResult.refetch()]);
    } catch (err) {
      setActionError(err instanceof Error ? err.message : "Transaction failed.");
    } finally {
      setPending(null);
    }
  }

  async function handleFund() {
    if (isNative) {
      await run("fund", () =>
        writeContractAsync({
          address: escrowAddress,
          abi: escrowAbi,
          functionName: "fund",
          args: [id],
          value: agreement!.totalAmount,
        }),
      );
      return;
    }

    const allowance = allowanceResult.data ?? 0n;
    if (allowance < agreement!.totalAmount) {
      await run("approve", () =>
        writeContractAsync({
          address: agreement!.token,
          abi: erc20Abi,
          functionName: "approve",
          args: [escrowAddress, agreement!.totalAmount],
        }),
      );
      return;
    }

    await run("fund", () =>
      writeContractAsync({ address: escrowAddress, abi: escrowAbi, functionName: "fund", args: [id] }),
    );
  }

  async function handleApprove() {
    await run("approve-milestone", () =>
      writeContractAsync({ address: escrowAddress, abi: escrowAbi, functionName: "approveMilestone", args: [id] }),
    );
  }

  async function handleDispute() {
    await run("dispute", () =>
      writeContractAsync({ address: escrowAddress, abi: escrowAbi, functionName: "raiseDispute", args: [id] }),
    );
  }

  async function handleResolve() {
    const bps = Math.round(Number(buyerPercent) * 100);
    await run("resolve", () =>
      writeContractAsync({
        address: escrowAddress,
        abi: escrowAbi,
        functionName: "resolveDispute",
        args: [id, bps],
      }),
    );
  }

  async function handleCancel() {
    await run("cancel", () =>
      writeContractAsync({
        address: escrowAddress,
        abi: escrowAbi,
        functionName: "cancelBeforeFunding",
        args: [id],
      }),
    );
  }

  const needsApproval = !isNative && (allowanceResult.data ?? 0n) < agreement.totalAmount;

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div>
        <div className="flex items-center justify-between gap-3">
          <h1 className="flex items-center gap-2 text-xl font-semibold">
            Agreement #{id.toString()}
            <CopyButton value={id.toString()} label="agreement id" />
          </h1>
          <StatusBadge label={agreementStatusLabels[agreement.status]} status={agreement.status} />
        </div>
        <p className="mt-1 flex flex-wrap items-center gap-x-2 text-sm text-white/50">
          <span>
            {formatTokenAmount(agreement.totalAmount, tokenMeta.decimals)} {tokenMeta.symbol} total
          </span>
          · <span>created {formatDate(agreement.createdAt)}</span> ·{" "}
          <span>protocol fee {(agreement.feeBps / 100).toFixed(2)}%</span>
          {agreement.fundingDeadline > 0 && (
            <>
              · <span>funding deadline {formatDate(agreement.fundingDeadline)}</span>
            </>
          )}
        </p>
      </div>

      <div className="card p-5">
        <div className="mb-3 flex items-center justify-between text-sm">
          <span className="text-white/50">Milestone progress</span>
          <span className="text-white/70">
            {currentIndex}/{agreement.milestoneCount} released ·{" "}
            {formatTokenAmount(releasedAmount, tokenMeta.decimals)} {tokenMeta.symbol}
          </span>
        </div>
        <div className="h-2 w-full overflow-hidden rounded-full bg-white/[0.06]">
          <div
            className="h-full rounded-full bg-gradient-to-r from-indigo-500 to-violet-500 transition-all duration-500"
            style={{ width: `${progress}%` }}
          />
        </div>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <RoleCard label="Buyer" address={agreement.buyer} you={isBuyer} />
        <RoleCard label="Seller" address={agreement.seller} you={isSeller} />
        <RoleCard label="Arbiter" address={agreement.arbiter} you={isArbiter} />
      </div>

      <div className="card p-5">
        <h2 className="mb-4 text-sm font-medium text-white/70">Milestones</h2>
        <ol className="space-y-1">
          {milestones?.map((m, i) => {
            const isCurrent = i === currentIndex && agreement.status === AgreementStatus.Active;
            const done =
              m.status === MilestoneStatus.Released || m.status === MilestoneStatus.Resolved;
            return (
              <li
                key={i}
                className={`flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition ${
                  isCurrent ? "border border-indigo-400/30 bg-indigo-500/[0.07]" : ""
                }`}
              >
                <span
                  className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full ${
                    done
                      ? "bg-emerald-500/15"
                      : isCurrent
                        ? "bg-indigo-500/20 ring-1 ring-indigo-400/40"
                        : "bg-white/[0.05]"
                  }`}
                >
                  {MILESTONE_ICON[m.status]}
                </span>
                <span className="flex-1">
                  <span className="font-mono text-white/40">M{i + 1}</span>
                  <span className="mx-2 text-white/30">·</span>
                  <span className={done ? "" : "text-white/85"}>
                    {formatTokenAmount(m.amount, tokenMeta.decimals)} {tokenMeta.symbol}
                  </span>
                  {isCurrent && <span className="ml-2 text-xs text-indigo-300">current</span>}
                </span>
                <StatusBadge kind="milestone" label={milestoneStatusLabels[m.status]} status={m.status} />
              </li>
            );
          })}
        </ol>
      </div>

      {actionError && (
        <p className="rounded-lg border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-300">
          {actionError}
        </p>
      )}

      <div className="card flex flex-wrap items-center gap-3 p-4">
        {isBuyer && agreement.status === AgreementStatus.AwaitingFunding && (
          <button onClick={handleFund} disabled={pending !== null} className="btn-primary px-6">
            <FundIcon />
            {pending === "fund" || pending === "approve"
              ? "Confirming…"
              : needsApproval
                ? `Approve ${tokenMeta.symbol}`
                : "Fund agreement"}
          </button>
        )}

        {isParty && agreement.status === AgreementStatus.AwaitingFunding && (
          <button onClick={handleCancel} disabled={pending !== null} className="btn-danger">
            Cancel
          </button>
        )}

        {isBuyer &&
          agreement.status === AgreementStatus.Active &&
          currentMilestone?.status === MilestoneStatus.Pending && (
            <button onClick={handleApprove} disabled={pending !== null} className="btn-primary px-6">
              <CheckIcon />
              {pending === "approve-milestone"
                ? "Confirming…"
                : `Approve milestone #${currentIndex + 1}`}
            </button>
          )}

        {isParty &&
          agreement.status === AgreementStatus.Active &&
          currentMilestone?.status === MilestoneStatus.Pending && (
            <button onClick={handleDispute} disabled={pending !== null} className="btn-danger">
              {pending === "dispute" ? "Confirming…" : "Raise dispute"}
            </button>
          )}

        {isArbiter &&
          agreement.status === AgreementStatus.Active &&
          currentMilestone?.status === MilestoneStatus.Disputed && (
            <div className="flex flex-wrap items-center gap-3">
              <label className="flex items-center gap-2 text-sm text-white/70">
                Buyer gets
                <input
                  type="number"
                  min="0"
                  max="100"
                  step="1"
                  value={buyerPercent}
                  onChange={(e) => setBuyerPercent(e.target.value)}
                  className="input inline-block w-20 py-1.5 text-center"
                />
                %
              </label>
              <button onClick={handleResolve} disabled={pending !== null} className="btn-primary">
                {pending === "resolve" ? "Confirming…" : "Resolve dispute"}
              </button>
            </div>
          )}

        {!isParty && !isArbiter && agreement.status === AgreementStatus.Active && (
          <p className="text-sm text-white/40">You&apos;re not a party to this agreement.</p>
        )}
      </div>

      <ActivityTimeline agreementId={id} />
    </div>
  );
}

function RoleCard({ label, address, you }: { label: string; address: Address; you: boolean }) {
  return (
    <div className="card px-4 py-3">
      <div className="flex items-center justify-between text-xs text-white/40">
        <span>{label}</span>
        {you && <span className="rounded-full bg-indigo-500/15 px-2 py-0.5 text-indigo-300">you</span>}
      </div>
      <div className="mt-1.5 flex items-center gap-1 font-mono text-xs text-white/80">
        {shortenAddress(address, 6)}
        <CopyButton value={address} label={label} />
      </div>
    </div>
  );
}

function FundIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
      <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
      <path
        d="M4 12.5l5 5L20 6.5"
        stroke="currentColor"
        strokeWidth="2.4"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}