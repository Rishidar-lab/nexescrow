"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useState } from "react";
import { parseEther, formatEther } from "viem";
import { ShieldCheck, Plus, CheckCircle2, AlertCircle, RefreshCcw, ArrowRightLeft } from "lucide-react";
import { contracts } from "@/contracts";

export default function Home() {
  const { isConnected, address } = useAccount();
  const [payee, setPayee] = useState("");
  const [arbiter, setArbiter] = useState("");
  const [amount, setAmount] = useState("");
  const [deadlineHours, setDeadlineHours] = useState("24");
  const [escrowIdToFund, setEscrowIdToFund] = useState("");
  const [escrowIdToRelease, setEscrowIdToRelease] = useState("");

  const { writeContract: writeCreate, data: createHash, isPending: isCreating } = useWriteContract();
  const { writeContract: writeFund, data: fundHash, isPending: isFunding } = useWriteContract();
  const { writeContract: writeRelease, data: releaseHash, isPending: isReleasing } = useWriteContract();

  const { isLoading: isCreateConfirming, isSuccess: isCreateSuccess } = useWaitForTransactionReceipt({ hash: createHash });
  const { isLoading: isFundConfirming, isSuccess: isFundSuccess } = useWaitForTransactionReceipt({ hash: fundHash });
  const { isLoading: isReleaseConfirming, isSuccess: isReleaseSuccess } = useWaitForTransactionReceipt({ hash: releaseHash });

  // Read reputation for connected user
  const { data: reputationData } = useReadContract({
    address: contracts.addresses.ReputationRegistry as `0x${string}`,
    abi: contracts.abis.ReputationRegistry,
    functionName: "reputationOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const handleCreate = (e: React.FormEvent) => {
    e.preventDefault();
    if (!payee || !deadlineHours) return;

    const deadline = Math.floor(Date.now() / 1000) + parseInt(deadlineHours) * 3600;
    
    writeCreate({
      address: contracts.addresses.Escrow as `0x${string}`,
      abi: contracts.abis.Escrow,
      functionName: "createEscrow",
      args: [
        payee as `0x${string}`,
        (arbiter || "0x0000000000000000000000000000000000000000") as `0x${string}`,
        BigInt(deadline),
      ],
    });
  };

  const handleFund = (e: React.FormEvent) => {
    e.preventDefault();
    if (!escrowIdToFund || !amount) return;

    writeFund({
      address: contracts.addresses.Escrow as `0x${string}`,
      abi: contracts.abis.Escrow,
      functionName: "fund",
      args: [BigInt(escrowIdToFund)],
      value: parseEther(amount),
    });
  };

  const handleRelease = (e: React.FormEvent) => {
    e.preventDefault();
    if (!escrowIdToRelease) return;

    writeRelease({
      address: contracts.addresses.Escrow as `0x${string}`,
      abi: contracts.abis.Escrow,
      functionName: "release",
      args: [BigInt(escrowIdToRelease)],
    });
  };

  return (
    <main className="flex-1 flex flex-col p-8 max-w-6xl mx-auto w-full">
      <header className="flex justify-between items-center mb-12">
        <div className="flex items-center gap-3">
          <div className="bg-blue-600 p-2 rounded-lg">
            <ShieldCheck className="w-6 h-6 text-white" />
          </div>
          <h1 className="text-2xl font-bold tracking-tight">NexEscrow</h1>
        </div>
        <ConnectButton />
      </header>

      {!isConnected ? (
        <div className="flex-1 flex flex-col items-center justify-center text-center max-w-2xl mx-auto">
          <ShieldCheck className="w-24 h-24 text-blue-500 mb-6 opacity-80" />
          <h2 className="text-4xl font-extrabold mb-4">Verifiable Escrow on Nexus</h2>
          <p className="text-xl text-slate-400 mb-8">
            Secure, trustless transactions with on-chain reputation tracking. 
            Connect your wallet to start creating or managing escrows.
          </p>
          <ConnectButton />
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Left Column: Reputation & Stats */}
          <div className="space-y-6">
            <div className="bg-slate-900 border border-slate-800 rounded-2xl p-6">
              <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <CheckCircle2 className="w-5 h-5 text-green-500" />
                Your Reputation
              </h3>
              
              {reputationData ? (
                <div className="grid grid-cols-2 gap-4">
                  <div className="bg-slate-950 rounded-xl p-4 border border-slate-800">
                    <p className="text-sm text-slate-400 mb-1">Settled Escrows</p>
                    <p className="text-2xl font-bold">{(reputationData as any[])[0]?.toString() || "0"}</p>
                  </div>
                  <div className="bg-slate-950 rounded-xl p-4 border border-slate-800">
                    <p className="text-sm text-slate-400 mb-1">Total Volume</p>
                    <p className="text-2xl font-bold text-blue-400">
                      {(reputationData as any[])[1] ? formatEther((reputationData as any[])[1]) : "0"} <span className="text-sm text-slate-500">NEX</span>
                    </p>
                  </div>
                </div>
              ) : (
                <div className="animate-pulse flex space-x-4">
                  <div className="flex-1 space-y-4 py-1">
                    <div className="h-20 bg-slate-800 rounded"></div>
                  </div>
                </div>
              )}
            </div>

            <div className="bg-slate-900 border border-slate-800 rounded-2xl p-6">
              <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <AlertCircle className="w-5 h-5 text-orange-500" />
                Network Info
              </h3>
              <ul className="space-y-3 text-sm">
                <li className="flex justify-between">
                  <span className="text-slate-400">Network</span>
                  <span className="font-mono">Nexus Mainnet</span>
                </li>
                <li className="flex justify-between">
                  <span className="text-slate-400">Escrow Contract</span>
                  <span className="font-mono text-blue-400" title={contracts.addresses.Escrow}>
                    {contracts.addresses.Escrow.slice(0, 6)}...{contracts.addresses.Escrow.slice(-4)}
                  </span>
                </li>
                <li className="flex justify-between">
                  <span className="text-slate-400">Registry Contract</span>
                  <span className="font-mono text-blue-400" title={contracts.addresses.ReputationRegistry}>
                    {contracts.addresses.ReputationRegistry.slice(0, 6)}...{contracts.addresses.ReputationRegistry.slice(-4)}
                  </span>
                </li>
              </ul>
            </div>
          </div>

          {/* Middle/Right Column: Actions */}
          <div className="lg:col-span-2 space-y-8">
            {/* Create Escrow */}
            <div className="bg-slate-900 border border-slate-800 rounded-2xl p-6">
              <h3 className="text-xl font-semibold mb-6 flex items-center gap-2">
                <Plus className="w-6 h-6 text-blue-500" />
                Create New Escrow
              </h3>
              <form onSubmit={handleCreate} className="space-y-4">
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-slate-400 mb-1">Payee Address</label>
                    <input 
                      type="text" 
                      required
                      placeholder="0x..." 
                      className="w-full bg-slate-950 border border-slate-800 rounded-lg px-4 py-2.5 text-slate-100 focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm"
                      value={payee}
                      onChange={(e) => setPayee(e.target.value)}
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-slate-400 mb-1">Arbiter Address (Optional)</label>
                    <input 
                      type="text" 
                      placeholder="0x..." 
                      className="w-full bg-slate-950 border border-slate-800 rounded-lg px-4 py-2.5 text-slate-100 focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm"
                      value={arbiter}
                      onChange={(e) => setArbiter(e.target.value)}
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-slate-400 mb-1">Refund Deadline (Hours from now)</label>
                  <input 
                    type="number" 
                    min="1"
                    required
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-4 py-2.5 text-slate-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    value={deadlineHours}
                    onChange={(e) => setDeadlineHours(e.target.value)}
                  />
                </div>
                <button 
                  type="submit" 
                  disabled={isCreating || isCreateConfirming}
                  className="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-3 px-4 rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex justify-center items-center gap-2"
                >
                  {isCreating || isCreateConfirming ? (
                    <><RefreshCcw className="w-5 h-5 animate-spin" /> Creating...</>
                  ) : "Create Escrow"}
                </button>
                {isCreateSuccess && (
                  <p className="text-green-500 text-sm mt-2 flex items-center gap-1">
                    <CheckCircle2 className="w-4 h-4" /> Escrow created successfully!
                  </p>
                )}
              </form>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
              {/* Fund Escrow */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-6">
                <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                  <ArrowRightLeft className="w-5 h-5 text-purple-500" />
                  Fund Escrow
                </h3>
                <form onSubmit={handleFund} className="space-y-4">
                  <div>
                    <label className="block text-sm font-medium text-slate-400 mb-1">Escrow ID</label>
                    <input 
                      type="number" 
                      min="1"
                      required
                      className="w-full bg-slate-950 border border-slate-800 rounded-lg px-4 py-2.5 text-slate-100 focus:outline-none focus:ring-2 focus:ring-purple-500"
                      value={escrowIdToFund}
                      onChange={(e) => setEscrowIdToFund(e.target.value)}
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-slate-400 mb-1">Amount (NEX)</label>
                    <input 
                      type="number" 
                      step="0.000000000000000001"
                      min="0"
                      required
                      className="w-full bg-slate-950 border border-slate-800 rounded-lg px-4 py-2.5 text-slate-100 focus:outline-none focus:ring-2 focus:ring-purple-500"
                      value={amount}
                      onChange={(e) => setAmount(e.target.value)}
                    />
                  </div>
                  <button 
                    type="submit" 
                    disabled={isFunding || isFundConfirming}
                    className="w-full bg-purple-600 hover:bg-purple-700 text-white font-medium py-3 px-4 rounded-lg transition-colors disabled:opacity-50 flex justify-center items-center gap-2"
                  >
                    {isFunding || isFundConfirming ? (
                      <><RefreshCcw className="w-5 h-5 animate-spin" /> Funding...</>
                    ) : "Fund Escrow"}
                  </button>
                  {isFundSuccess && (
                    <p className="text-green-500 text-sm mt-2 flex items-center gap-1">
                      <CheckCircle2 className="w-4 h-4" /> Funded successfully!
                    </p>
                  )}
                </form>
              </div>

              {/* Release Escrow */}
              <div className="bg-slate-900 border border-slate-800 rounded-2xl p-6">
                <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                  <ShieldCheck className="w-5 h-5 text-green-500" />
                  Release Escrow
                </h3>
                <form onSubmit={handleRelease} className="space-y-4">
                  <div>
                    <label className="block text-sm font-medium text-slate-400 mb-1">Escrow ID</label>
                    <input 
                      type="number" 
                      min="1"
                      required
                      className="w-full bg-slate-950 border border-slate-800 rounded-lg px-4 py-2.5 text-slate-100 focus:outline-none focus:ring-2 focus:ring-green-500"
                      value={escrowIdToRelease}
                      onChange={(e) => setEscrowIdToRelease(e.target.value)}
                    />
                  </div>
                  <button 
                    type="submit" 
                    disabled={isReleasing || isReleaseConfirming}
                    className="w-full bg-green-600 hover:bg-green-700 text-white font-medium py-3 px-4 rounded-lg transition-colors disabled:opacity-50 flex justify-center items-center gap-2 mt-8"
                  >
                    {isReleasing || isReleaseConfirming ? (
                      <><RefreshCcw className="w-5 h-5 animate-spin" /> Releasing...</>
                    ) : "Release Funds"}
                  </button>
                  {isReleaseSuccess && (
                    <p className="text-green-500 text-sm mt-2 flex items-center gap-1">
                      <CheckCircle2 className="w-4 h-4" /> Released successfully!
                    </p>
                  )}
                </form>
              </div>
            </div>
          </div>
        </div>
      )}
    </main>
  );
}
