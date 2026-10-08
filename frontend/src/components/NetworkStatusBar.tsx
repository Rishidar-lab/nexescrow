"use client";

import { useAccount, useChainId, useSwitchChain } from "wagmi";
import {
  ALLOW_MAINNET,
  addressExplorerUrl,
  chainConfigWarning,
  chainStatusLabel,
  escrowAddress,
  escrowConfigured,
  selectedChain,
  selectedChainId,
} from "@/lib/chain";
import { shortenAddress } from "@/lib/format";
import { CopyButton } from "./CopyButton";

/**
 * Persistent network/protocol status strip: which chain this build transacts on,
 * testnet/mainnet + audit status, the configured contract address, the connected
 * wallet, and a hard wrong-network warning with a one-click switch.
 */
export function NetworkStatusBar() {
  const { address, isConnected } = useAccount();
  const walletChainId = useChainId();
  const { switchChain } = useSwitchChain();

  const status = chainStatusLabel(selectedChainId);
  const wrongNetwork = isConnected && walletChainId !== selectedChainId;

  return (
    <div className="border-b border-white/8 bg-white/[0.02]">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-4 gap-y-1.5 px-4 py-2 text-[11px] text-white/45">
        <span className="rounded-full border border-white/10 bg-white/[0.04] px-2 py-0.5 text-white/70">
          {selectedChain.name} · chain {selectedChainId}
        </span>

        {status === "TESTNET" && (
          <span className="rounded-full border border-amber-400/30 bg-amber-400/10 px-2 py-0.5 font-medium text-amber-300">
            TESTNET · UNAUDITED
          </span>
        )}
        {status === "MAINNET" && (
          <span className="rounded-full border border-rose-400/40 bg-rose-500/15 px-2 py-0.5 font-medium text-rose-300">
            MAINNET · REAL FUNDS · UNAUDITED
          </span>
        )}

        <span className="flex items-center gap-1">
          Contract:
          {escrowConfigured ? (
            <>
              <span className="font-mono text-white/70">{shortenAddress(escrowAddress, 6)}</span>
              <CopyButton value={escrowAddress} label="contract address" />
              <a
                href={addressExplorerUrl(selectedChainId, escrowAddress)}
                target="_blank"
                rel="noreferrer"
                className="hover:text-white/80"
                title="View contract on explorer"
              >
                ↗
              </a>
            </>
          ) : (
            <span className="text-amber-300">
              not configured for this chain — writes disabled
            </span>
          )}
        </span>

        {isConnected && address && (
          <span className="flex items-center gap-1">
            Wallet: <span className="font-mono text-white/70">{shortenAddress(address, 6)}</span>
          </span>
        )}

        {wrongNetwork && (
          <button
            onClick={() => switchChain({ chainId: selectedChainId })}
            className="rounded-full border border-rose-400/40 bg-rose-500/15 px-2.5 py-0.5 font-medium text-rose-200 transition hover:bg-rose-500/25"
          >
            Wrong network ({walletChainId}) — switch to {selectedChain.name}
          </button>
        )}

        {!ALLOW_MAINNET && <span className="text-white/25">mainnet disabled in this build</span>}

        {chainConfigWarning && <span className="text-amber-300">{chainConfigWarning}</span>}
      </div>
    </div>
  );
}
