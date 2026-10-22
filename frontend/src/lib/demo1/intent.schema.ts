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
