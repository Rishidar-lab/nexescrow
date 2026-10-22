import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { keccak256, stringToHex, type Address, type Hex } from "viem";
import type { ResolutionPolicy } from "../demo1/intent";

const {
  AGREEMENT_INTENT_TYPE_STRING,
  buildAgreementIntent,
  hashAgreementIntent,
  hashMilestones,
  hashResolutionPolicy,
} = await import(new URL("../demo1/intent.ts", import.meta.url).href);

const vector = JSON.parse(
  readFileSync(new URL("../demo1/intent-vectors.json", import.meta.url), "utf8"),
);

const policy: ResolutionPolicy = {
  primaryResolver: vector.resolutionPolicy.primaryResolver as Address,
  appellateResolver: vector.resolutionPolicy.appellateResolver as Address,
  evidenceWindow: Number(vector.resolutionPolicy.evidenceWindow),
  rulingWindow: Number(vector.resolutionPolicy.rulingWindow),
  appealWindow: Number(vector.resolutionPolicy.appealWindow),
  timeoutBuyerBps: vector.resolutionPolicy.timeoutBuyerBps,
  policyHash: vector.resolutionPolicy.policyHash as Hex,
};

const intent = buildAgreementIntent({
  buyer: vector.buyer as Address,
  seller: vector.seller as Address,
  settlementAsset: vector.settlementAsset as Address,
  totalAmount: BigInt(vector.totalAmount),
  milestoneAmounts: vector.milestoneAmounts.map((value: string) => BigInt(value)),
  termsHash: vector.termsHash as Hex,
  resolutionPolicy: policy,
  fundingDeadline: BigInt(vector.fundingDeadline),
  executionDeadline: BigInt(vector.executionDeadline),
  nonce: BigInt(vector.nonce),
});

test("Demo 1 canonical vector matches Solidity ABI/EIP-712 commitments", () => {
  assert.equal(
    keccak256(stringToHex(AGREEMENT_INTENT_TYPE_STRING)),
    vector.expected.agreementIntentTypehash,
  );
  assert.equal(
    hashMilestones(vector.milestoneAmounts.map((value: string) => BigInt(value))),
    vector.expected.milestonesHash,
  );
  assert.equal(hashResolutionPolicy(policy), vector.expected.resolutionPolicyHash);
  assert.equal(
    hashAgreementIntent(vector.chainId, vector.verifyingContract as Address, intent),
    vector.expected.intentDigest,
  );
});

test("Demo 1 intent digest is domain separated and nonce separated", () => {
  const canonical = hashAgreementIntent(vector.chainId, vector.verifyingContract as Address, intent);

  assert.notEqual(
    hashAgreementIntent(vector.chainId + 1, vector.verifyingContract as Address, intent),
    canonical,
    "chainId must bind the signature domain",
  );
  assert.notEqual(
    hashAgreementIntent(vector.chainId, "0x9999999999999999999999999999999999999999", intent),
    canonical,
    "verifying contract must bind the signature domain",
  );
  assert.notEqual(
    hashAgreementIntent(vector.chainId, vector.verifyingContract as Address, {
      ...intent,
      nonce: intent.nonce + 1n,
    }),
    canonical,
    "nonce must change the signed digest",
  );
});
