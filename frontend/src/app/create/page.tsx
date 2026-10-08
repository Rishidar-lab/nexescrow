"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { isAddress, parseEventLogs, type Address } from "viem";
import { escrowAbi, escrowAddress, NATIVE_TOKEN } from "@/lib/contract";
import { useTokenMeta } from "@/hooks/useTokenMeta";
import { formatTokenAmount, parseTokenAmount } from "@/lib/format";

interface MilestoneInput {
  key: number;
  amount: string;
}

let milestoneKeySeq = 0;
function newMilestone(): MilestoneInput {
  return { key: milestoneKeySeq++, amount: "" };
}

export default function CreateAgreementPage() {
  const router = useRouter();
  const { address, isConnected } = useAccount();
  const publicClient = usePublicClient();
  const { writeContractAsync } = useWriteContract();

  const [seller, setSeller] = useState("");
  const [arbiter, setArbiter] = useState("");
  const [tokenType, setTokenType] = useState<"native" | "erc20">("native");
  const [tokenAddress, setTokenAddress] = useState("");
  const [milestones, setMilestones] = useState<MilestoneInput[]>([newMilestone()]);
  const [deadline, setDeadline] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const effectiveToken = tokenType === "native" ? NATIVE_TOKEN : (tokenAddress as Address);
  const tokenMeta = useTokenMeta(
    tokenType === "erc20" && isAddress(tokenAddress) ? (tokenAddress as Address) : undefined,
  );

  const milestoneValues = milestones.map((m) =>
    m.amount && !Number.isNaN(Number(m.amount)) && Number(m.amount) > 0
      ? parseTokenAmount(m.amount, tokenMeta.decimals)
      : 0n,
  );
  const totalRaw = milestoneValues.reduce((sum, v) => sum + v, 0n);
  const fmtAmount = (raw: bigint) => formatTokenAmount(raw, tokenMeta.decimals);

  function updateMilestone(key: number, amount: string) {
    setMilestones((prev) => prev.map((m) => (m.key === key ? { ...m, amount } : m)));
  }

  function addMilestone() {
    setMilestones((prev) => [...prev, newMilestone()]);
  }

  function removeMilestone(key: number) {
    setMilestones((prev) => (prev.length > 1 ? prev.filter((m) => m.key !== key) : prev));
  }

  function validate(): string | null {
    if (!isConnected || !address) return "Connect a wallet first.";
    if (!isAddress(seller)) return "Enter a valid seller address.";
    if (!isAddress(arbiter)) return "Enter a valid arbiter address.";
    if (seller.toLowerCase() === address.toLowerCase()) return "Seller can't be you (the buyer).";
    if (
      arbiter.toLowerCase() === address.toLowerCase() ||
      arbiter.toLowerCase() === seller.toLowerCase()
    ) {
      return "Arbiter must be a neutral third party, not the buyer or seller.";
    }
    if (tokenType === "erc20" && !isAddress(tokenAddress)) return "Enter a valid ERC-20 token address.";
    for (const m of milestones) {
      const value = Number(m.amount);
      if (!m.amount || Number.isNaN(value) || value <= 0) return "Every milestone needs a positive amount.";
    }
    return totalRaw > 0n ? null : "Milestone amounts don't add up to anything yet.";
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setFormError(null);

    const validationError = validate();
    if (validationError) {
      setFormError(validationError);
      return;
    }
    if (!publicClient) {
      setFormError("No RPC connection available.");
      return;
    }

    setSubmitting(true);
    try {
      const fundingDeadline = deadline ? Math.floor(new Date(deadline).getTime() / 1000) : 0;

      const hash = await writeContractAsync({
        address: escrowAddress,
        abi: escrowAbi,
        functionName: "createAgreement",
        args: [seller as Address, arbiter as Address, effectiveToken, milestoneValues, fundingDeadline],
      });

      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      const events = parseEventLogs({ abi: escrowAbi, eventName: "AgreementCreated", logs: receipt.logs });
      const id = events[0]?.args.id;

      if (id !== undefined) {
        router.push(`/agreement/${id.toString()}`);
      } else {
        router.push("/dashboard");
      }
    } catch (err) {
      setFormError(err instanceof Error ? err.message : "Transaction failed.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <h1 className="text-xl font-semibold">New escrow agreement</h1>
        <p className="mt-1 text-sm text-white/50">
          Define the payout plan, add a seller and a neutral arbiter. Funding happens in the next
          step.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="card space-y-5 p-6">
        <Field label="Seller address" hint="Receives milestone payouts as you approve them.">
          <input
            className="input font-mono"
            placeholder="0x…"
            value={seller}
            onChange={(e) => setSeller(e.target.value)}
          />
        </Field>

        <Field
          label="Arbiter address"
          hint="A neutral third party who resolves disputes. Cannot be you or the seller."
        >
          <input
            className="input font-mono"
            placeholder="0x…"
            value={arbiter}
            onChange={(e) => setArbiter(e.target.value)}
          />
        </Field>

        <Field label="Settlement asset">
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setTokenType("native")}
              className={`chip ${tokenType === "native" ? "chip-active" : ""}`}
            >
              Native NEX
            </button>
            <button
              type="button"
              onClick={() => setTokenType("erc20")}
              className={`chip ${tokenType === "erc20" ? "chip-active" : ""}`}
            >
              ERC-20
            </button>
          </div>
          {tokenType === "erc20" && (
            <input
              className="input mt-2 font-mono"
              placeholder="Token contract address (0x…)"
              value={tokenAddress}
              onChange={(e) => setTokenAddress(e.target.value)}
            />
          )}
        </Field>

        <Field label="Milestones" hint={`Amounts in ${tokenMeta.symbol}, released in order.`}>
          <div className="space-y-2">
            {milestones.map((m, i) => (
              <div key={m.key} className="flex items-center gap-2">
                <span className="w-8 shrink-0 text-sm text-white/40">{i + 1}.</span>
                <input
                  className="input"
                  type="number"
                  min="0"
                  step="any"
                  placeholder="0.0"
                  value={m.amount}
                  onChange={(e) => updateMilestone(m.key, e.target.value)}
                />
                <button
                  type="button"
                  onClick={() => removeMilestone(m.key)}
                  disabled={milestones.length === 1}
                  className="shrink-0 rounded-lg px-2 py-1.5 text-sm text-white/40 transition hover:bg-rose-500/10 hover:text-rose-300 disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-white/40"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                    <path
                      d="M6 6l12 12M18 6L6 18"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                    />
                  </svg>
                </button>
              </div>
            ))}
          </div>
          <button type="button" onClick={addMilestone} className="mt-2 text-sm text-indigo-300 hover:underline">
            + Add milestone
          </button>
        </Field>

        <Field
          label="Funding deadline"
          hint="Optional — anyone can cancel after this passes. Leave blank for none."
        >
          <input
            className="input"
            type="datetime-local"
            value={deadline}
            onChange={(e) => setDeadline(e.target.value)}
          />
        </Field>

        <div className="rounded-lg border border-white/10 bg-white/[0.03] px-4 py-3 text-sm">
          <div className="flex justify-between">
            <span className="text-white/50">Total to fund</span>
            <span className="font-semibold">
              {totalRaw > 0n ? `${fmtAmount(totalRaw)} ${tokenMeta.symbol}` : "—"}
            </span>
          </div>
          <div className="mt-1 flex justify-between text-xs text-white/40">
            <span>Protocol fee (1%, taken from seller payouts)</span>
            <span>
              ≈ {totalRaw > 0n ? `${fmtAmount((totalRaw * 100n) / 10_000n)} ${tokenMeta.symbol}` : "—"}
            </span>
          </div>
        </div>

        {formError && (
          <p className="rounded-lg border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-300">
            {formError}
          </p>
        )}

        <button
          type="submit"
          disabled={submitting || !isConnected}
          className="btn-primary w-full py-3"
        >
          {submitting ? "Creating…" : isConnected ? "Create agreement" : "Connect a wallet first"}
        </button>
      </form>
    </div>
  );
}

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-medium text-white/80">{label}</span>
      {children}
      {hint && <span className="mt-1 block text-xs text-white/40">{hint}</span>}
    </label>
  );
}