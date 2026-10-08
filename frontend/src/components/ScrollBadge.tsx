export function ScrollBadge() {
  return (
    <div className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.03] px-3 py-1 text-xs text-white/50">
      <span className="relative flex h-2 w-2">
        <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-indigo-400 opacity-60" />
        <span className="relative inline-flex h-2 w-2 rounded-full bg-indigo-400" />
      </span>
      Live on Nexus L1 · chain 3946
    </div>
  );
}