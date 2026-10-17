"use client";

import { useMemo } from "react";
import { useAccount, usePublicClient, useReadContracts } from "wagmi";
import { useQuery } from "@tanstack/react-query";
import type { Address } from "viem";
import { escrowAbi, escrowAddress, escrowConfigured, type Agreement } from "@/lib/contract";
import { selectedChainId } from "@/lib/chain";
import { createIndexer } from "@/lib/indexer";

interface DiscoveredAgreement {
  id: bigint;
  buyer: Address;
  seller: Address;
  arbiter: Address;
}

export interface MyAgreementRow {
  id: bigint;
  role: "buyer" | "seller" | "arbiter";
  agreement?: Agreement;
}

// Discovery goes through the agreement-index abstraction (bounded RPC log scan
// by default; HTTP indexer when configured). Contract-state reads are batched
// directly against the configured chain.
export function useMyAgreements() {
  const { address } = useAccount();
  const publicClient = usePublicClient({ chainId: selectedChainId });

  const index = useMemo(() => createIndexer(publicClient), [publicClient]);

  const logsQuery = useQuery({
    queryKey: ["agreement-discovery", selectedChainId, escrowAddress, address],
    queryFn: async (): Promise<DiscoveredAgreement[]> => {
      if (!index || !address) return [];
      return index.discoverAgreementsForParticipant(address);
    },
    enabled: !!index && !!address,
    staleTime: 15_000,
  });

  const mine = useMemo(() => {
    if (!address || !logsQuery.data) return [];
    const addr = address.toLowerCase();
    return logsQuery.data
      .map((a) => {
        const buyer = a.buyer.toLowerCase();
        const seller = a.seller.toLowerCase();
        const arbiter = a.arbiter.toLowerCase();
        const role: MyAgreementRow["role"] | null =
          buyer === addr ? "buyer" : seller === addr ? "seller" : arbiter === addr ? "arbiter" : null;
        return role ? { id: a.id, role } : null;
      })
      .filter((row): row is { id: bigint; role: MyAgreementRow["role"] } => row !== null)
      .sort((a, b) => Number(b.id - a.id));
  }, [address, logsQuery.data]);

  const contracts = mine.map((a) => ({
    chainId: selectedChainId,
    address: escrowAddress,
    abi: escrowAbi,
    functionName: "agreements" as const,
    args: [a.id] as const,
  }));

  const detailsQuery = useReadContracts({
    contracts,
    query: { enabled: mine.length > 0 && escrowConfigured },
  });

  const rows: MyAgreementRow[] = mine.map((a, i) => {
    const result = detailsQuery.data?.[i]?.result as readonly unknown[] | undefined;
    if (!result) return { id: a.id, role: a.role };

    const [buyer, seller, arbiter, token, totalAmount, feeBps, status, createdAt, fundingDeadline, milestoneCount, nextMilestone] =
      result as [Address, Address, Address, Address, bigint, number, number, number, number, number, number];

    return {
      id: a.id,
      role: a.role,
      agreement: {
        buyer,
        seller,
        arbiter,
        token,
        totalAmount,
        feeBps,
        status,
        createdAt,
        fundingDeadline,
        milestoneCount,
        nextMilestone,
      },
    };
  });

  return {
    rows,
    isLoading: logsQuery.isLoading || detailsQuery.isLoading,
    error: logsQuery.error,
    configured: escrowConfigured,
  };
}
