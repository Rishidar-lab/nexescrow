"use client";

import { useMemo } from "react";
import { useAccount, usePublicClient, useReadContracts } from "wagmi";
import { useQuery } from "@tanstack/react-query";
import type { Address } from "viem";
import { escrowAbi, escrowAddress, type Agreement } from "@/lib/contract";

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

// Discovers agreements by scanning AgreementCreated logs from genesis and
// filtering client-side for the connected wallet. Fine for a testnet-scale
// deployment; a production build should back this with an indexer/subgraph
// instead of a full log scan.
export function useMyAgreements() {
  const { address } = useAccount();
  const publicClient = usePublicClient();

  const logsQuery = useQuery({
    queryKey: ["agreement-logs", escrowAddress, publicClient?.chain.id],
    queryFn: async (): Promise<DiscoveredAgreement[]> => {
      if (!publicClient) return [];
      const logs = await publicClient.getContractEvents({
        address: escrowAddress,
        abi: escrowAbi,
        eventName: "AgreementCreated",
        fromBlock: 0n,
        toBlock: "latest",
      });
      return logs
        .filter((log) => log.args.id !== undefined)
        .map((log) => ({
          id: log.args.id as bigint,
          buyer: log.args.buyer as Address,
          seller: log.args.seller as Address,
          arbiter: log.args.arbiter as Address,
        }));
    },
    enabled: !!publicClient,
    staleTime: 15_000,
  });

  const mine = useMemo(() => {
    if (!address || !logsQuery.data) return [];
    const addr = address.toLowerCase();
    return logsQuery.data
      .filter((a) => a.buyer.toLowerCase() === addr || a.seller.toLowerCase() === addr || a.arbiter.toLowerCase() === addr)
      .map((a) => ({
        id: a.id,
        role: (a.buyer.toLowerCase() === addr
          ? "buyer"
          : a.seller.toLowerCase() === addr
            ? "seller"
            : "arbiter") as MyAgreementRow["role"],
      }))
      .sort((a, b) => Number(b.id - a.id));
  }, [address, logsQuery.data]);

  const contracts = mine.map((a) => ({
    address: escrowAddress,
    abi: escrowAbi,
    functionName: "agreements" as const,
    args: [a.id] as const,
  }));

  const detailsQuery = useReadContracts({
    contracts,
    query: { enabled: mine.length > 0 },
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
  };
}
