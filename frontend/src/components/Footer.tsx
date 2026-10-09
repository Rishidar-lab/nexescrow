import Link from "next/link";
import { explorerBaseUrl, selectedChain, selectedChainId } from "@/lib/chain";

export function Footer() {
  return (
    <footer className="border-t border-white/8">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-3 px-4 py-6 text-xs text-white/35 sm:flex-row">
        <div>
          NexEscrow · <span className="font-mono">0.1.0</span> · testnet / unaudited — not
          production ready, not security reviewed
        </div>
        <div className="flex gap-4">
          <Link href="https://github.com/Rishidar-lab/nexescrow" className="hover:text-white/70">
            GitHub
          </Link>
          <Link
            href={explorerBaseUrl(selectedChainId)}
            className="hover:text-white/70"
            target="_blank"
            rel="noreferrer"
          >
            {selectedChain.name} explorer
          </Link>
        </div>
      </div>
    </footer>
  );
}
