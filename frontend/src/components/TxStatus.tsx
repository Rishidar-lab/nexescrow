"use client";

import { selectedChainId, txExplorerUrl } from "@/lib/chain";
import { shortenAddress } from "@/lib/format";
import type { EscrowTxState, TxPhase } from "@/hooks/useEscrowWrite";

const STEP_ORDER: TxPhase[] = ["awaiting-signature", "pending", "mined", "confirmed", "reconciled"];

const STEP_LABELS: Partial<Record<TxPhase, string>> = {
  "awaiting-signature": "Wallet",
  pending: "Pending",
  mined: "Mined",
  confirmed: "Confirmed",
  reconciled: "Synced",
};

const FAILURE_PHASES: TxPhase[] = ["wrong-network", "unconfigured", "reverted", "error"];

/** Renders the wallet → pending → mined → confirmed → synced lifecycle, or the failure. */
export function TxStatus({ state }: { state: EscrowTxState }) {
  if (state.phase === "idle") return null;

  if (FAILURE_PHASES.includes(state.phase)) {
    const tone =
      state.phase === "reverted" || state.phase === "wrong-network"
        ? "border-rose-500/30 bg-rose-500/10 text-rose-300"
        : "border-amber-500/30 bg-amber-500/10 text-amber-200";
    return (
      <div className={`rounded-lg border px-3 py-2 text-sm ${tone}`}>
        {state.error ?? state.phaseLabel}
        {state.hash && (
          <a
            href={txExplorerUrl(selectedChainId, state.hash)}
            target="_blank"
            rel="noreferrer"
            className="ml-2 underline decoration-dotted"
          >
            {shortenAddress(state.hash, 8)} ↗
          </a>
        )}
      </div>
    );
  }

  const currentIndex = STEP_ORDER.indexOf(state.phase);
  return (
    <div className="card px-4 py-3 text-xs">
      <div className="flex flex-wrap items-center gap-2">
        {STEP_ORDER.map((step, i) => (
          <span key={step} className="flex items-center gap-2">
            <span
              className={
                i < currentIndex
                  ? "text-emerald-300"
                  : i === currentIndex
                    ? "font-medium text-white"
                    : "text-white/30"
              }
            >
              {i < currentIndex ? "✓ " : i === currentIndex ? "● " : "○ "}
              {STEP_LABELS[step]}
            </span>
            {i < STEP_ORDER.length - 1 && <span className="text-white/20">→</span>}
          </span>
        ))}
      </div>
      {state.hash && (
        <a
          href={txExplorerUrl(selectedChainId, state.hash)}
          target="_blank"
          rel="noreferrer"
          className="mt-1.5 inline-block font-mono text-white/40 hover:text-white/70"
        >
          {shortenAddress(state.hash, 12)} ↗
        </a>
      )}
    </div>
  );
}
