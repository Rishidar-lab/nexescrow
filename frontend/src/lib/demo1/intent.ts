import {
  encodeAbiParameters,
  hashTypedData,
  keccak256,
  type Address,
  type Hex,
  type TypedDataDomain,
} from "viem";

export const AGREEMENT_INTENT_TYPE_STRING =
  "AgreementIntent(address buyer,address seller,address settlementAsset,uint256 totalAmount,bytes32 milestonesHash,bytes32 termsHash,bytes32 resolutionPolicyHash,uint64 fundingDeadline,uint64 executionDeadline,uint256 nonce)";

export const agreementIntentTypes = {
  AgreementIntent: [
    { name: "buyer", type: "address" },
    { name: "seller", type: "address" },
    { name: "settlementAsset", type: "address" },
    { name: "totalAmount", type: "uint256" },
    { name: "milestonesHash", type: "bytes32" },
    { name: "termsHash", type: "bytes32" },
    { name: "resolutionPolicyHash", type: "bytes32" },
    { name: "fundingDeadline", type: "uint64" },
    { name: "executionDeadline", type: "uint64" },
    { name: "nonce", type: "uint256" },
  ],
} as const;

export type AgreementIntent = {
  buyer: Address;
  seller: Address;
  settlementAsset: Address;
  totalAmount: bigint;
  milestonesHash: Hex;
  termsHash: Hex;
  resolutionPolicyHash: Hex;
  fundingDeadline: bigint;
  executionDeadline: bigint;
  nonce: bigint;
};

export type ResolutionPolicy = {
  primaryResolver: Address;
  appellateResolver: Address;
  evidenceWindow: bigint;
  rulingWindow: bigint;
  appealWindow: bigint;
  timeoutBuyerBps: number;
  policyHash: Hex;
};

export function demo1Domain(chainId: number, verifyingContract: Address): TypedDataDomain {
  return {
    name: "NexEscrowCore",
    version: "1",
    chainId,
    verifyingContract,
  };
}

export function hashMilestones(amounts: readonly bigint[]): Hex {
  return keccak256(encodeAbiParameters([{ type: "uint128[]" }], [amounts]));
}

export function hashResolutionPolicy(policy: ResolutionPolicy): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "address" },
        { type: "address" },
        { type: "uint40" },
        { type: "uint40" },
        { type: "uint40" },
        { type: "uint16" },
        { type: "bytes32" },
      ],
      [
        policy.primaryResolver,
        policy.appellateResolver,
        policy.evidenceWindow,
        policy.rulingWindow,
        policy.appealWindow,
        policy.timeoutBuyerBps,
        policy.policyHash,
      ],
    ),
  );
}

export function hashAgreementIntent(
  chainId: number,
  verifyingContract: Address,
  intent: AgreementIntent,
): Hex {
  return hashTypedData({
    domain: demo1Domain(chainId, verifyingContract),
    types: agreementIntentTypes,
    primaryType: "AgreementIntent",
    message: intent,
  });
}

export function buildAgreementIntent(input: {
  buyer: Address;
  seller: Address;
  settlementAsset: Address;
  totalAmount: bigint;
  milestoneAmounts: readonly bigint[];
  termsHash: Hex;
  resolutionPolicy: ResolutionPolicy;
  fundingDeadline: bigint;
  executionDeadline: bigint;
  nonce: bigint;
}): AgreementIntent {
  return {
    buyer: input.buyer,
    seller: input.seller,
    settlementAsset: input.settlementAsset,
    totalAmount: input.totalAmount,
    milestonesHash: hashMilestones(input.milestoneAmounts),
    termsHash: input.termsHash,
    resolutionPolicyHash: hashResolutionPolicy(input.resolutionPolicy),
    fundingDeadline: input.fundingDeadline,
    executionDeadline: input.executionDeadline,
    nonce: input.nonce,
  };
}
