"use client";

import { useState } from "react";

export function CopyButton({ value, label }: { value: string; label?: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // clipboard unavailable (e.g. non-secure context) — no-op
    }
  }

  return (
    <button
      onClick={copy}
      title={`Copy ${label ?? value}`}
      className="shrink-0 rounded px-1.5 py-0.5 text-white/35 transition hover:bg-white/10 hover:text-white"
    >
      {copied ? (
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" className="text-emerald-400">
          <path
            d="M4 12.5l5 5L20 6.5"
            stroke="currentColor"
            strokeWidth="2.5"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      ) : (
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none">
          <rect
            x="9"
            y="9"
            width="11"
            height="11"
            rx="2"
            stroke="currentColor"
            strokeWidth="1.8"
          />
          <path
            d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"
            stroke="currentColor"
            strokeWidth="1.8"
          />
        </svg>
      )}
    </button>
  );
}