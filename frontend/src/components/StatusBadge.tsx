const AGREEMENT_STYLES: Record<number, string> = {
  0: "bg-amber-500/15 text-amber-300 ring-amber-500/30",
  1: "bg-sky-500/15 text-sky-300 ring-sky-500/30",
  2: "bg-emerald-500/15 text-emerald-300 ring-emerald-500/30",
  3: "bg-neutral-500/15 text-neutral-300 ring-neutral-500/30",
};

const MILESTONE_STYLES: Record<number, string> = {
  0: "bg-neutral-500/15 text-neutral-300 ring-neutral-500/30",
  1: "bg-emerald-500/15 text-emerald-300 ring-emerald-500/30",
  2: "bg-rose-500/15 text-rose-300 ring-rose-500/30",
  3: "bg-violet-500/15 text-violet-300 ring-violet-500/30",
};

export function StatusBadge({
  label,
  status,
  kind = "agreement",
}: {
  label: string;
  status: number;
  kind?: "agreement" | "milestone";
}) {
  const styles = kind === "agreement" ? AGREEMENT_STYLES : MILESTONE_STYLES;
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 ring-inset ${styles[status] ?? styles[0]}`}
    >
      {label}
    </span>
  );
}
