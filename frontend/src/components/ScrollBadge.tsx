import { chainStatusLabel, escrowConfigured, selectedChain, selectedChainId } from "@/lib/chain";

export function ScrollBadge() {
  const status = chainStatusLabel(selectedChainId);
  const label = escrowConfigured
    ? `${status} deployment · ${selectedChain.name} · chain ${selectedChainId}`
    : `${status} build · ${selectedChain.name} · contract not configured`;

  return (
    <div className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.03] px-3 py-1 text-xs text-white/50">
      <span className="relative flex h-2 w-2">
        <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-indigo-400 opacity-60" />
        <span className="relative inline-flex h-2 w-2 rounded-full bg-indigo-400" />
      </span>
      {label} · unaudited
    </div>
  );
}
