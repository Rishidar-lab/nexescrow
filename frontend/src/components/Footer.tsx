import Link from "next/link";

export function Footer() {
  return (
    <footer className="border-t border-white/8">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-3 px-4 py-6 text-xs text-white/35 sm:flex-row">
        <div>
          NexEscrow · <span className="font-mono">0.1.0</span> · unaudited — use on
          testnet while iterating
        </div>
        <div className="flex gap-4">
          <Link href="https://github.com/Rishidar-lab/nexescrow" className="hover:text-white/70">
            GitHub
          </Link>
          <Link href="https://docs.nexus.xyz" className="hover:text-white/70">
            Nexus docs
          </Link>
        </div>
      </div>
    </footer>
  );
}