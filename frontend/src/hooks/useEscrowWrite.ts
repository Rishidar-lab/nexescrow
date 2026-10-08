"use client";

import { useCallback, useState } from "react";
import { useChainId, usePublicClient, useSwitchChain, useWriteContract } from "wagmi";
import { isCorrectChain, selectedChain, selectedChainId } from "@/lib/chain";
import { escrowConfigured } from "@/lib/contract";

/** Full transaction lifecycle. Nothing writes until the chain guard passes. */
export type TxPhase =
  | "idle"
  | "wrong-network"
  | "unconfigured"
  | "awaiting-signature"
  | "pending"
  | "mined"
  | "confirmed"
  | "reconciled"
  | "reverted"
  | "error";

export interface EscrowTxState {
  phase: TxPhase;
  hash?: `0x${string}`;
  error?: string;
  phaseLabel: string;
}

const CONFIRMATIONS = 2;

const PHASE_LABELS: Record<TxPhase, string> = {
  idle: "",
  "wrong-network": "Wrong network — transaction blocked",
  unconfigured: "Contract not configured for this chain",
  "awaiting-signature": "Waiting for wallet confirmation",
  pending: "Pending — submitted, not yet mined",
  mined: "Mined — awaiting confirmations",
  confirmed: "Confirmed",
  reconciled: "Synced with application state",
  reverted: "Reverted on-chain",
  error: "Transaction failed",
};

/**
 * Contract-write request as consumed by this app. Kept loose on purpose: the
 * hook's job is the chain guard and lifecycle, not ABI generic inference.
 */
export interface EscrowWriteRequest {
  address: `0x${string}`;
  abi: readonly unknown[];
  functionName: string;
  args?: readonly unknown[];
  value?: bigint;
}

export function useEscrowWrite() {
  const walletChainId = useChainId();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient({ chainId: selectedChainId });
  const [state, setState] = useState<EscrowTxState>({ phase: "idle", phaseLabel: "" });

  const reset = useCallback(() => setState({ phase: "idle", phaseLabel: "" }), []);

  const switchToSelectedChain = useCallback(async () => {
    await switchChainAsync({ chainId: selectedChainId });
  }, [switchChainAsync]);

  const write = useCallback(
    async (
      request: EscrowWriteRequest,
      onConfirmed?: () => Promise<void> | void,
    ): Promise<`0x${string}`> => {
      const fail = (phase: TxPhase, error: string): never => {
        setState({ phase, error, phaseLabel: PHASE_LABELS[phase] });
        throw new Error(error);
      };

      if (!escrowConfigured) {
        return fail(
          "unconfigured",
          `No NexusEscrow contract is configured for ${selectedChain.name} (chain ${selectedChainId}). ` +
            `Set NEXT_PUBLIC_ESCROW_ADDRESS_${selectedChainId} in the frontend environment.`,
        );
      }
      // The hard guard: never submit unless the wallet is on the exact selected chain.
      if (!isCorrectChain(walletChainId)) {
        return fail(
          "wrong-network",
          `Wallet is connected to chain ${walletChainId ?? "unknown"}; ` +
            `${selectedChain.name} (chain ${selectedChainId}) is required. Transaction blocked.`,
        );
      }
      if (!publicClient) {
        return fail("error", "No RPC client for the configured chain.");
      }

      try {
        setState({ phase: "awaiting-signature", phaseLabel: PHASE_LABELS["awaiting-signature"] });

        // `chainId` is passed explicitly: wagmi/viem will refuse rather than fall
        // back if the wallet is on a different chain.
        const hash = await writeContractAsync({
          ...request,
          chainId: selectedChainId,
        } as Parameters<typeof writeContractAsync>[0]);

        setState({ phase: "pending", hash, phaseLabel: PHASE_LABELS.pending });

        const mined = await publicClient.waitForTransactionReceipt({ hash, confirmations: 1 });
        if (mined.status === "reverted") {
          setState({
            phase: "reverted",
            hash,
            error: "Transaction reverted on-chain.",
            phaseLabel: PHASE_LABELS.reverted,
          });
          throw new Error("Transaction reverted on-chain.");
        }
        setState({ phase: "mined", hash, phaseLabel: PHASE_LABELS.mined });

        await publicClient.waitForTransactionReceipt({ hash, confirmations: CONFIRMATIONS });
        setState({ phase: "confirmed", hash, phaseLabel: PHASE_LABELS.confirmed });

        // Application reconciliation: refetch contract state after confirmation.
        if (onConfirmed) await onConfirmed();
        setState({ phase: "reconciled", hash, phaseLabel: PHASE_LABELS.reconciled });

        return hash;
      } catch (err) {
        const message = err instanceof Error ? err.message : "Transaction failed.";
        setState((prev) =>
          prev.phase === "reverted"
            ? prev
            : { phase: "error", hash: prev.hash, error: message, phaseLabel: PHASE_LABELS.error },
        );
        throw err;
      }
    },
    [publicClient, walletChainId, writeContractAsync],
  );

  return {
    state,
    write,
    reset,
    switchToSelectedChain,
    walletChainId,
    correctChain: isCorrectChain(walletChainId),
    confirmations: CONFIRMATIONS,
  };
}
