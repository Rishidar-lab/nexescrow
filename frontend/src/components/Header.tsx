"use client";

import Link from "next/link";
import { ConnectButton } from "@rainbow-me/rainbowkit";

export function Header() {
  return (
    <header className="border-b border-white/10">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-4 py-4">
        <div className="flex items-center gap-8">
          <Link href="/" className="text-lg font-semibold tracking-tight">
            NexEscrow
          </Link>
          <nav className="flex gap-5 text-sm text-white/70">
            <Link href="/" className="hover:text-white">
              Dashboard
            </Link>
            <Link href="/create" className="hover:text-white">
              New agreement
            </Link>
          </nav>
        </div>
        <ConnectButton showBalance={false} />
      </div>
    </header>
  );
}
