import Link from "next/link";
import { ScrollBadge } from "@/components/ScrollBadge";
import { chainStatusLabel, selectedChain, selectedChainId } from "@/lib/chain";
import { escrowConfigured } from "@/lib/contract";

const FEATURES = [
  {
    title: "Non-custodial by design",
    text: "Funds live in the escrow contract, never in a platform wallet. Neither party can unilaterally seize them, and no clock can grief the other side.",
  },
  {
    title: "Milestone-based release",
    text: "Payments unlock milestone by milestone as the buyer approves each one — not one all-or-nothing payout at the very end.",
  },
  {
    title: "Human arbitration",
    text: "Disagreement on a milestone? You pick a trusted arbiter at creation time; they split the disputed milestone in basis points, and the decision is final on-chain.",
  },
  {
    title: "Native asset or any ERC-20",
    text: "Settle in the chain's native asset or any ERC-20 token, via SafeERC20. Fee-on-transfer tokens are rejected at funding time rather than silently under-collateralized.",
  },
  {
    title: "Capped protocol fee",
    text: "A 1% default fee — hard-capped at 10% in the contract — is snapshotted at creation, so later fee changes never touch agreements already in flight.",
  },
  {
    title: "Chain-agnostic",
    text: "The settlement core has no chain, native-symbol or chain-id assumptions. Deployable to EVM environments such as Nexus and BOT Chain; this build targets testnets only.",
  },
];

const STEPS = [
  {
    n: "01",
    title: "Create",
    text: "Define the milestone amounts, add your seller and a neutral arbiter, and pick the settlement token.",
  },
  {
    n: "02",
    title: "Fund",
    text: "As buyer, deposit the full amount into the escrow contract. One transaction, funds locked and visible to both sides.",
  },
  {
    n: "03",
    title: "Deliver & approve",
    text: "The seller delivers each milestone; the buyer approves it to release that payout — fees deducted only from what the seller actually receives.",
  },
  {
    n: "04",
    title: "Dispute or complete",
    text: "If a milestone is contested, the arbiter splits it. Otherwise approvals run until the last milestone completes the agreement.",
  },
];

export default function LandingPage() {
  const status = chainStatusLabel(selectedChainId);
  return (
    <div className="space-y-24 pb-10">
      <section className="relative pt-16 text-center sm:pt-24">
        <div className="mx-auto mb-6 max-w-2xl space-y-6">
          <ScrollBadge />
          <h1 className="text-4xl font-bold leading-tight tracking-tight sm:text-6xl">
            Milestones, <span className="gradient-text">not trust me bro</span>
          </h1>
          <p className="mx-auto max-w-xl text-base text-white/60 sm:text-lg">
            NexEscrow is non-custodial, milestone-based escrow for on-chain agreements. The buyer
            locks funds, the seller is paid milestone by milestone, and a trusted arbiter settles
            disputes — all enforced by a single, test-covered, non-upgradeable contract.
          </p>
          <p className="mx-auto max-w-xl text-sm text-amber-300/80">
            This build is configured for {selectedChain.name} (chain {selectedChainId}, {status}).
            Unaudited — do not use with real funds.
          </p>
          <div className="flex flex-wrap items-center justify-center gap-3">
            <Link href="/dashboard" className="btn-primary px-6 py-3 text-base">
              Open the dApp
            </Link>
            <Link href="/create" className="btn-ghost px-6 py-3 text-base">
              Create an agreement
            </Link>
          </div>
        </div>

        <div className="mx-auto mt-12 grid max-w-3xl grid-cols-3 gap-3">
          <Stat value="112" label="Foundry tests" />
          <Stat value="100%" label="Fee from seller only" />
          <Stat value="4" label="Networks known" />
        </div>
      </section>

      <section className="mx-auto max-w-5xl">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map((f) => (
            <div key={f.title} className="card p-5">
              <h3 className="text-sm font-semibold text-white">{f.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-white/50">{f.text}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mx-auto max-w-3xl">
        <h2 className="mb-8 text-center text-2xl font-semibold sm:text-3xl">Supported networks</h2>
        <div className="card overflow-hidden">
          <table className="w-full text-left text-sm">
            <thead className="bg-white/[0.03] text-xs text-white/45">
              <tr>
                <th className="px-4 py-3 font-medium">Network</th>
                <th className="px-4 py-3 font-medium">Chain ID</th>
                <th className="px-4 py-3 font-medium">Status</th>
              </tr>
            </thead>
            <tbody className="text-white/70">
              <tr className="border-t border-white/5">
                <td className="px-4 py-3">BOT Chain Bohr</td>
                <td className="px-4 py-3 font-mono">968</td>
                <td className="px-4 py-3 text-amber-300">Testnet — integration target</td>
              </tr>
              <tr className="border-t border-white/5">
                <td className="px-4 py-3">Nexus Testnet</td>
                <td className="px-4 py-3 font-mono">3945</td>
                <td className="px-4 py-3 text-amber-300">Testnet</td>
              </tr>
              <tr className="border-t border-white/5">
                <td className="px-4 py-3">BOT Chain</td>
                <td className="px-4 py-3 font-mono">677</td>
                <td className="px-4 py-3 text-white/35">Mainnet — configured, opt-in only, not deployed</td>
              </tr>
              <tr className="border-t border-white/5">
                <td className="px-4 py-3">Nexus</td>
                <td className="px-4 py-3 font-mono">3946</td>
                <td className="px-4 py-3 text-white/35">Mainnet — configured, opt-in only, not deployed</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p className="mt-4 text-center text-xs text-white/35">
          {escrowConfigured
            ? `This deployment targets ${selectedChain.name}. Mainnet deployment requires an explicit operator flag and independent security review.`
            : `No contract address is configured for ${selectedChain.name}; the dApp is read-only until one is set.`}
        </p>
      </section>

      <section className="mx-auto max-w-4xl">
        <h2 className="mb-8 text-center text-2xl font-semibold sm:text-3xl">How it works</h2>
        <div className="grid gap-4 sm:grid-cols-4">
          {STEPS.map((s) => (
            <div key={s.n} className="card relative p-5">
              <span className="gradient-text font-mono text-2xl font-bold">{s.n}</span>
              <h3 className="mt-3 text-sm font-semibold text-white">{s.title}</h3>
              <p className="mt-2 text-xs leading-relaxed text-white/50">{s.text}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mx-auto max-w-2xl rounded-2xl border border-indigo-500/25 bg-indigo-500/[0.06] p-8 text-center shadow-[0_0_60px_rgba(99,102,241,0.12)]">
        <h2 className="text-2xl font-semibold">Ready to hold both sides honest?</h2>
        <p className="mx-auto mt-3 max-w-md text-sm text-white/55">
          Connect your wallet on a testnet, name a milestone plan and a trusted arbiter, and let the
          contract do the enforcing.
        </p>
        <div className="mt-6 flex justify-center gap-3">
          <Link href="/create" className="btn-primary px-6 py-3">
            Create your first agreement
          </Link>
        </div>
      </section>
    </div>
  );
}

function Stat({ value, label }: { value: string; label: string }) {
  return (
    <div className="card px-3 py-4">
      <div className="gradient-text text-2xl font-bold">{value}</div>
      <div className="mt-1 text-xs text-white/45">{label}</div>
    </div>
  );
}
