"use client";

import type { Address } from "viem";
import { useReadContract } from "wagmi";
import { escrowAbi, escrowAddress, type Agreement, type Milestone } from "@/lib/contract";

export function useAgreement(id: bigint) {
  const agreementResult = useReadContract({
    address: escrowAddress,
    abi: escrowAbi,
    functionName: "agreements",
    args: [id],
  });

  const milestonesResult = useReadContract({
    address: escrowAddress,
    abi: escrowAbi,
    functionName: "getMilestones",
    args: [id],
  });

  const raw = agreementResult.data as readonly unknown[] | undefined;
  const agreement: Agreement | undefined = raw
    ? {
        buyer: raw[0] as Address,
        seller: raw[1] as Address,
        arbiter: raw[2] as Address,
        token: raw[3] as Address,
        totalAmount: raw[4] as bigint,
        feeBps: raw[5] as number,
        status: raw[6] as number,
        createdAt: raw[7] as number,
        fundingDeadline: raw[8] as number,
        milestoneCount: raw[9] as number,
        nextMilestone: raw[10] as number,
      }
    : undefined;

  const milestones = (milestonesResult.data as readonly { amount: bigint; status: number }[] | undefined)?.map(
    (m): Milestone => ({ amount: m.amount, status: m.status }),
  );

  return {
    agreement,
    milestones,
    isLoading: agreementResult.isLoading || milestonesResult.isLoading,
    refetch: () => {
      agreementResult.refetch();
      milestonesResult.refetch();
    },
  };
}

export function useAllowance(token: Address, owner: Address | undefined) {
  return useReadContract({
    address: token,
    abi: [
      {
        type: "function",
        name: "allowance",
        inputs: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
        ],
        outputs: [{ name: "", type: "uint256" }],
        stateMutability: "view",
      },
    ] as const,
    functionName: "allowance",
    args: owner ? [owner, escrowAddress] : undefined,
    query: { enabled: !!owner },
  });
}
