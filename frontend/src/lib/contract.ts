import type { Address } from "viem";
import { nexusEscrowAbi } from "./nexusEscrowAbi";

export const escrowAbi = nexusEscrowAbi;

export const escrowAddress = (process.env.NEXT_PUBLIC_ESCROW_ADDRESS ||
  "0x0000000000000000000000000000000000000000") as Address;

export const NATIVE_TOKEN = "0x0000000000000000000000000000000000000000" as Address;

export const AgreementStatus = {
  AwaitingFunding: 0,
  Active: 1,
  Completed: 2,
  Cancelled: 3,
} as const;

export const agreementStatusLabels: Record<number, string> = {
  0: "Awaiting funding",
  1: "Active",
  2: "Completed",
  3: "Cancelled",
};

export const MilestoneStatus = {
  Pending: 0,
  Released: 1,
  Disputed: 2,
  Resolved: 3,
} as const;

export const milestoneStatusLabels: Record<number, string> = {
  0: "Pending",
  1: "Released",
  2: "Disputed",
  3: "Resolved",
};

export interface Agreement {
  buyer: Address;
  seller: Address;
  arbiter: Address;
  token: Address;
  totalAmount: bigint;
  feeBps: number;
  status: number;
  createdAt: number;
  fundingDeadline: number;
  milestoneCount: number;
  nextMilestone: number;
}

export interface Milestone {
  amount: bigint;
  status: number;
}
