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
import { erc20Abi } from "@/lib/erc20Abi";

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
    return <p className="text-sm text-white/50">Loading agreement #{id.toString()}…</p>;
  }

  const isBuyer = address?.toLowerCase() === agreement.buyer.toLowerCase();
  const isSeller = address?.toLowerCase() === agreement.seller.toLowerCase();
  const isArbiter = address?.toLowerCase() === agreement.arbiter.toLowerCase();
  const isParty = isBuyer || isSeller;
  const isNative = agreement.token.toLowerCase() === NATIVE_TOKEN;

  const currentIndex = agreement.nextMilestone;
  const currentMilestone = milestones?.[currentIndex];

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
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-semibold">Agreement #{id.toString()}</h1>
          <StatusBadge label={agreementStatusLabels[agreement.status]} status={agreement.status} />
        </div>
        <p className="mt-1 text-sm text-white/50">
          {formatTokenAmount(agreement.totalAmount, tokenMeta.decimals)} {tokenMeta.symbol} total · created{" "}
          {formatDate(agreement.createdAt)} · protocol fee {(agreement.feeBps / 100).toFixed(2)}%
        </p>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3 text-sm">
        <RoleField label="Buyer" address={agreement.buyer} you={isBuyer} />
        <RoleField label="Seller" address={agreement.seller} you={isSeller} />
        <RoleField label="Arbiter" address={agreement.arbiter} you={isArbiter} />
      </div>

      {agreement.fundingDeadline > 0 && (
        <p className="text-sm text-white/50">Funding deadline: {formatDate(agreement.fundingDeadline)}</p>
      )}

      <div>
        <h2 className="mb-2 text-sm font-medium text-white/70">Milestones</h2>
        <div className="space-y-2">
          {milestones?.map((m, i) => (
            <div
              key={i}
              className={`flex items-center justify-between rounded-md border px-3 py-2 text-sm ${
                i === currentIndex ? "border-indigo-400/40 bg-indigo-500/5" : "border-white/10"
              }`}
            >
              <span>
                #{i + 1} — {formatTokenAmount(m.amount, tokenMeta.decimals)} {tokenMeta.symbol}
              </span>
              <StatusBadge kind="milestone" label={milestoneStatusLabels[m.status]} status={m.status} />
            </div>
          ))}
        </div>
      </div>

      {actionError && (
        <p className="rounded-md border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-300">
          {actionError}
        </p>
      )}

      <div className="flex flex-wrap items-center gap-2">
        {isBuyer && agreement.status === AgreementStatus.AwaitingFunding && (
          <ActionButton onClick={handleFund} pending={pending === "fund" || pending === "approve"}>
            {needsApproval ? `Approve ${tokenMeta.symbol}` : "Fund agreement"}
          </ActionButton>
        )}

        {isParty && agreement.status === AgreementStatus.AwaitingFunding && (
          <ActionButton onClick={handleCancel} pending={pending === "cancel"} variant="ghost">
            Cancel
          </ActionButton>
        )}

        {isBuyer &&
          agreement.status === AgreementStatus.Active &&
          currentMilestone?.status === MilestoneStatus.Pending && (
            <ActionButton onClick={handleApprove} pending={pending === "approve-milestone"}>
              Approve milestone #{currentIndex + 1}
            </ActionButton>
          )}

        {isParty &&
          agreement.status === AgreementStatus.Active &&
          currentMilestone?.status === MilestoneStatus.Pending && (
            <ActionButton onClick={handleDispute} pending={pending === "dispute"} variant="ghost">
              Raise dispute
            </ActionButton>
          )}

        {isArbiter &&
          agreement.status === AgreementStatus.Active &&
          currentMilestone?.status === MilestoneStatus.Disputed && (
            <div className="flex items-center gap-2">
              <label className="text-sm text-white/60">
                Buyer gets
                <input
                  type="number"
                  min="0"
                  max="100"
                  step="1"
                  value={buyerPercent}
                  onChange={(e) => setBuyerPercent(e.target.value)}
                  className="input mx-2 inline-block w-20"
                />
                %
              </label>
              <ActionButton onClick={handleResolve} pending={pending === "resolve"}>
                Resolve dispute
              </ActionButton>
            </div>
          )}
      </div>
    </div>
  );
}

function RoleField({ label, address, you }: { label: string; address: Address; you: boolean }) {
  return (
    <div className="rounded-md border border-white/10 px-3 py-2">
      <div className="text-xs text-white/40">{label}</div>
      <div className="font-mono text-xs">
        {shortenAddress(address)} {you && <span className="text-indigo-300">(you)</span>}
      </div>
    </div>
  );
}

function ActionButton({
  children,
  onClick,
  pending,
  variant = "solid",
}: {
  children: ReactNode;
  onClick: () => void;
  pending: boolean;
  variant?: "solid" | "ghost";
}) {
  return (
    <button
      onClick={onClick}
      disabled={pending}
      className={
        variant === "solid"
          ? "rounded-md bg-indigo-500 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-400 disabled:opacity-50"
          : "rounded-md border border-white/15 px-4 py-2 text-sm text-white/70 hover:text-white disabled:opacity-50"
      }
    >
      {pending ? "Confirming…" : children}
    </button>
  );
}
