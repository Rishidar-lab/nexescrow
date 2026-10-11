# NexEscrow — Demo 1 Whitepaper

## Deterministic milestone settlement with recoverable disputes, signed intent, agent adapters, and explicit migration

**Status:** design specification / implementation target.  
**Baseline evidence:** BOT Chain Bohr testnet (chain 968), validated 2026-10-08.  
**Security status:** **UNAUDITED. NOT PRODUCTION READY. BOT mainnet 677 NOT DEPLOYED.**  
**Canonical project name:** **NexEscrow**.  
**Legacy Solidity class name:** `NexusEscrow` (Demo 0 / existing validated deployment only).

---

## 0. What this document is — and is not

This document is the **Demo 1 design target** for NexEscrow. It does not rewrite history and it does not relabel unimplemented ideas as validated features.

The currently validated contract is the existing `NexusEscrow.sol` deployment on BOT Bohr 968. That implementation proved the basic settlement kernel: exact funding, ordered milestone release, basis-point dispute splits, role separation, fee conservation, chain guards, bounded log discovery, and reproducible testnet evidence.

Demo 1 exists because the baseline also exposes important weaknesses that must be solved before real-value deployment:

- a silent arbiter can freeze a disputed milestone indefinitely;
- one arbiter has final authority, with no appeal, quorum, or enforceable evidence process;
- agreement intent is not cryptographically bound to a rich terms object;
- the current core is not yet interoperable with agent-payment / agent-identity standards;
- the contract is immutable but has no user-consented migration path;
- direct log scanning is deliberately testnet-scale;
- the project has a single maintainer and no independent audit or community track record;
- branding and legal-operating boundaries need to be made explicit.

Demo 1 treats those points as engineering requirements rather than hiding them as footnotes.

---

# 1. Executive thesis

Escrow itself is not the moat.

A chain operator can ship escrow. A payments network can add hold/release semantics. Kleros can arbitrate. Request Network can coordinate payments. x402 can monetize agent/API calls. AP2 can carry agent authorization mandates. ERC-8004 can provide agent identity, reputation and validation signals.

NexEscrow therefore should not compete by claiming to be "the escrow contract." Its defensible role is narrower and more useful:

> **A deterministic settlement kernel that binds human or agent intent to milestone funds, supports replaceable resolution policies, records verifiable evidence commitments, and composes with external payment / identity / arbitration protocols without putting nondeterministic logic inside the fund-moving core.**

The core remains intentionally boring. The differentiation moves to **portable agreement semantics, dispute recovery, signed intent, adapter interoperability, reproducible evidence, and chain-independent deployment discipline**.

---

# 2. Claim boundary: Demo 0 vs Demo 1

| Capability | Demo 0: validated baseline | Demo 1 target |
|---|---|---|
| Ordered milestone escrow | Implemented + Bohr validated | Preserve |
| Native + ERC-20 settlement | Implemented | Preserve |
| Fee-on-transfer rejection | Implemented | Preserve |
| Exact conservation invariants | Implemented + tested | Preserve + extend |
| Single named arbiter | Implemented | Replace with pluggable resolution policy |
| Dispute timeout | **Not implemented** | Required |
| Appeal | **Not implemented** | Optional policy module |
| Quorum arbitration | **Not implemented** | Reference resolver module |
| Evidence commitments | **Not implemented** | Required event/hash layer |
| Seller acceptance / bilateral signed terms | **Not implemented** | Required |
| EIP-712 terms commitment | **Not implemented** | Required |
| EIP-1271 smart-account signatures | **Not implemented** | Required for smart-wallet agents |
| x402 | **Not implemented** | Optional adapter |
| AP2 | **Not implemented** | Optional mandate-hash adapter |
| ERC-8004 | **Not implemented** | Optional identity / reputation adapter; standard currently Draft |
| Migration | **Not implemented** | Explicit, bilateral, non-admin migration path |
| Hosted production indexer | **Not implemented** | Required before mainnet |
| Independent audit | **Not performed** | Mandatory pre-mainnet gate |
| Mainnet 677 deployment | **Not deployed** | Gated after audit + operator readiness |

Nothing in the Demo 1 column should be described as production-ready until code, tests and independent review exist.

---

# 3. Demo 1 architecture

Demo 1 separates four concerns that were too tightly implied by the original narrative.

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         AGREEMENT / INTENT                          │
│  EIP-712 terms hash · seller acceptance · agent / wallet identity  │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ immutable commitment
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        NexEscrowCore                                │
│ exact funding · milestone cursor · accounting · final settlement    │
│ NO AI · NO oracle inference · NO arbitrary admin principal access  │
└───────────────┬───────────────────────────────┬─────────────────────┘
                │                               │
                ▼                               ▼
┌──────────────────────────┐       ┌──────────────────────────────────┐
│ ResolutionPolicy /       │       │ Evidence + interoperability     │
│ IResolver                │       │ commitments                     │
│ single / quorum / ERC792 │       │ ERC-1497-style evidence events │
│ appeal / fallback        │       │ AP2 / x402 / ERC-8004 refs     │
└──────────────────────────┘       └──────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                 Indexing / observability layer                     │
│ confirmed checkpoints · adaptive windows · reorg repair · API      │
└─────────────────────────────────────────────────────────────────────┘
```

The contract that moves principal should never need to understand LLM outputs, HTTP APIs, social reputation scores, or merchant checkout logic.

---

# 4. Dispute liveness: remove the permanent-freeze failure mode

## 4.1 Current defect

In Demo 0, `raiseDispute()` changes the current milestone to `Disputed`, and only the named arbiter can call `resolveDispute()`. There is no timeout or alternate path. A dead key, lost wallet, malicious arbiter, deceased operator, or unavailable service can therefore freeze that milestone forever.

That is acceptable as a disclosed testnet limitation. It is not acceptable as the default real-funds design.

## 4.2 Demo 1 resolution policy

Each agreement commits to an immutable `ResolutionPolicy` at acceptance time:

```solidity
struct ResolutionPolicy {
    address primaryResolver;
    address appellateResolver;   // optional
    uint40 evidenceWindow;
    uint40 rulingWindow;
    uint40 appealWindow;
    uint16 timeoutBuyerBps;      // deterministic fallback split
    bytes32 policyHash;
}
```

The exact implementation can change after review, but the semantics should satisfy four rules:

1. **Every disputed milestone has a finite state path.**
2. **Timeout behavior is agreed before funding.** No owner/admin invents it later.
3. **No timeout can silently release seller funds merely because the buyer disappeared.**
4. **No timeout path can transfer funds to the resolver.**

A deterministic fallback split (`timeoutBuyerBps`) is preferable to an owner-controlled emergency sweep. The safest default for a high-risk service contract may be full buyer refund, but Demo 1 should not hard-code that as universally correct. It should be a signed agreement parameter with policy constraints.

## 4.3 Proposed dispute state machine

```text
Pending
  │
  ├─ buyer approves ──────────────────────────────> Released
  │
  └─ either party disputes
              │
              ▼
        EvidenceWindow
              │ evidence hashes / URIs
              ▼
         AwaitingRuling
          │          │
          │ ruling   │ ruling deadline expires
          ▼          ▼
     RulingProposed  TimeoutEligible
          │              │
          │ appeal       └─ anyone finalizes pre-agreed timeout split
          ▼
       Appealed ──> AppellateResolver
          │
          ▼
      FinalRuling
          │
          ▼
        Resolved
```

The finalization function should be callable by **anyone** once objective time conditions are satisfied. Liveness should not require the original caller to return.

---

# 5. Single-arbiter concentration: resolver modules, quorum and appeal

The current contract bakes one `address arbiter` into every agreement. Demo 1 should replace that with a resolver interface so the settlement kernel does not care how a ruling was produced.

## 5.1 `IResolver`

A minimal resolver boundary can expose dispute creation / status / ruling retrieval, inspired by the separation used in ERC-792-style arbitration systems.

Possible resolver implementations:

- **SingleResolver** — simple named resolver for low-value agreements;
- **QuorumResolver** — M-of-N signed ruling, e.g. 2-of-3 or 3-of-5;
- **SafeResolver** — a Safe/multisig address as resolver;
- **ERC792Adapter** — forwards disputes to an ERC-792-compatible arbitrator such as a Kleros-style service;
- **PrimaryPlusAppealResolver** — one first-instance resolver plus a separate appeal resolver.

The core only accepts a final `buyerBps` ruling from the committed resolution policy.

## 5.2 Quorum is a policy, not an admin power

If a quorum resolver is used, members, threshold and replacement rules are committed before funding. Changing resolver membership for an in-flight agreement should require the same consent threshold as changing the commercial terms.

## 5.3 Appeal is optional but explicit

Not every $5 transaction needs appellate arbitration. Demo 1 should support an `appealWindow == 0` low-cost policy and a non-zero appellate policy for higher-value agreements.

The whitepaper should present this as **risk-tiered arbitration**, not as one universal court design.

---

# 6. Evidence standard: hash the evidence, do not put evidence on-chain

Demo 0 stores no evidence and no reason. Demo 1 should keep private / large evidence off-chain while anchoring integrity on-chain.

At minimum, emit:

```solidity
event EvidenceSubmitted(
    uint256 indexed agreementId,
    uint256 indexed milestoneIndex,
    address indexed party,
    bytes32 evidenceHash,
    string evidenceURI
);
```

The URI may point to IPFS, encrypted object storage, or another agreed evidence system. The hash commits to exact bytes.

Where useful, the adapter layer should follow the event semantics of the ERC-1497 evidence ecosystem so external arbitration systems can consume the dispute package.

The whitepaper must be precise: **NexEscrow verifies integrity, not truth.** A hash proves that submitted evidence has not changed; it does not prove that the evidence is accurate.

---

# 7. Signed intent: EIP-712 + EIP-1271

## 7.1 Why the current model is insufficient

Today the buyer creates an agreement directly on-chain. The seller can observe it, but there is no canonical cryptographic object proving that both parties accepted the same rich terms before funding.

That becomes especially weak for agents: an autonomous wallet needs a machine-verifiable statement of exactly what it was authorized to do.

## 7.2 `AgreementIntent`

Demo 1 should define an EIP-712 typed structure such as:

```text
AgreementIntent
- buyer
- seller
- settlementAsset
- totalAmount
- milestonesHash
- termsHash
- resolutionPolicyHash
- fundingDeadline
- executionDeadline / expiry policy
- nonce
- chainId
- verifyingContract
```

Both counterparties sign the intent before activation. Smart accounts / contract wallets must be supported through **EIP-1271** signature validation.

This provides:

- non-ambiguous terms commitment;
- domain separation by chain and verifying contract;
- replay protection when combined with nonce / consumed-intent tracking;
- human-readable wallet signing compared with opaque byte blobs;
- a clean bridge to autonomous-agent authorization.

EIP-712 itself does **not** provide replay protection; NexEscrow must enforce its own nonce / intent-consumption rules.

---

# 8. Agent-native without putting AI in the escrow core

"Agent-native" should mean **protocol interoperability and verifiable delegated intent**, not "the smart contract calls an LLM."

## 8.1 x402 adapter

x402 is an HTTP-native payment protocol. It is optimized for payment-required → signed payment → settlement flows, especially APIs and agent services.

NexEscrow should not pretend that x402 and milestone escrow are identical. They solve different problems.

A Demo 1 adapter can bind an x402 resource/payment request to an escrow milestone:

```text
x402 PaymentRequired / resource descriptor
        │ hash / reference
        ▼
AgreementIntent.milestonesHash
        │
        ▼
NexEscrow milestone funds held until acceptance / resolution
```

For immediate, low-value API calls, x402 should remain direct settlement. For longer work with deliverables, x402 can provide discovery/payment metadata while NexEscrow provides conditional settlement.

## 8.2 AP2 adapter

AP2 defines cryptographically verifiable Checkout and Payment Mandates for agent-performed commerce and explicitly treats those signed mandates / receipts as dispute evidence.

Demo 1 should store **hash references**, not full AP2 payloads:

- `checkoutMandateHash`;
- `paymentMandateHash`;
- optional receipt hash / URI;
- mapping to `AgreementIntent` / milestone.

This lets a resolver verify what the user or agent was authorized to buy without forcing the escrow core to implement AP2 itself.

## 8.3 ERC-8004 adapter

ERC-8004 is currently a **Draft** ERC for agent discovery, reputation and validation. It should be treated as optional / experimental, not as a production dependency.

A NexEscrow adapter can reference:

- `agentRegistry`;
- `agentId`;
- validation request / response references;
- post-settlement feedback metadata tied to the agreement / milestone evidence hash.

Payments are explicitly outside ERC-8004's scope, which makes it complementary rather than a replacement for NexEscrow.

## 8.4 Design rule

If x402, AP2 or ERC-8004 changes, the fund-moving core must not require redeployment merely to follow a new off-chain schema version. Versioned adapters should absorb protocol churn.

---

# 9. Immutability without permanent dead ends: explicit migration

"Non-upgradeable" is a security property only if users also have a safe exit when a better version exists.

Demo 0 has no proxy and no admin upgrade path, which correctly prevents an owner from replacing code underneath depositors. But it also has no funded migration mechanism.

Demo 1 should keep **no proxy / no admin upgrade** and add **user-consented migration**.

## 9.1 Migration rules

A funded agreement may migrate only when:

- destination contract implements a known `INexEscrowMigrationReceiver` interface;
- destination `codehash` / version is displayed and signed in the migration intent;
- buyer and seller both authorize migration using EIP-712 signatures;
- if a milestone is disputed, the committed resolution policy also authorizes or first resolves the dispute;
- the migration is atomic: remaining principal either arrives at the destination or the transaction reverts;
- accrued protocol fees are not disguised as principal and remain separately accounted.

No owner/admin should have a unilateral `migrateAll()` or principal sweep.

## 9.2 Version model

- **Demo 0 / v0.x:** current `NexusEscrow` testnet evidence.
- **Demo 1 / v1 candidate:** `NexEscrowCore` with signed intent + liveness + migration.
- Future versions are new immutable deployments, with voluntary per-agreement migration.

That gives us immutable code **and** an operational upgrade story.

---

# 10. Indexing: client scan remains fallback, not mainnet architecture

The existing indexer abstraction is directionally correct: chain events remain the source of truth and the index is rebuildable. The weakness is operational scale, not correctness.

## 10.1 Mainnet requirement

Before real mainnet use, Demo 1 requires a hosted indexer with:

- deployment-block-scoped ingestion;
- adaptive bounded windows rather than one fixed range forever;
- exponential backoff + jitter for 5xx / rate limits;
- result-size / latency-based window shrinking;
- idempotent key `(chainId, contractAddress, txHash, logIndex)`;
- transactional checkpoints;
- block-hash reorg detection and rollback;
- provider failover where more than one reliable RPC is available;
- ingestion lag / RPC error / decode error monitoring;
- reproducible full rebuild from chain events.

The browser `log-scan` adapter remains a read-only degraded-mode fallback and a testnet tool. It should not be presented as the primary high-volume production ingestion path.

## 10.2 RPC uncertainty is a chain dependency

Measured BOT RPC behavior showed `eth_getLogs` working despite published documentation saying otherwise, and a transient 503 window was observed. Demo 1 therefore treats RPC availability and limits as **external dependencies that require monitoring**, not assumptions encoded forever in the client.

---

# 11. Branding: one project, one canonical name

The project currently mixes:

- **NexEscrow** — product / repository name;
- **NexusEscrow** — Solidity class name;
- **Nexus L1** — an original deployment target.

This creates unnecessary ambiguity.

Demo 1 canonical naming:

- Project: **NexEscrow**
- New core contract: **`NexEscrowCore`**
- Old contract: **`NexusEscrow` (legacy Demo 0 implementation)**
- Network names always prefixed explicitly: `Nexus L1`, `BOT Chain Bohr`, `BOT Chain mainnet`

The legacy testnet bytecode and evidence must not be rewritten merely for branding. New code should use the canonical name.

---

# 12. Legal / operating boundary

A smart contract being non-custodial does not automatically answer every legal, consumer-protection, tax, sanctions, dispute, or payment-services question in every jurisdiction.

Demo 1 should therefore stop short of making legal-status claims it cannot prove.

Before a real-funds public mainnet service, the operator layer should have:

- identified responsible operator / entity or an explicit statement that none exists;
- Terms of Use;
- Privacy Policy for any hosted frontend / indexer / evidence service;
- sanctions / prohibited-use policy where legally required;
- documented distinction between protocol software, frontend operator, resolver, and users;
- jurisdiction-specific legal review for the intended launch market;
- clear statement that on-chain arbitration is a contractual mechanism, not necessarily statutory arbitration.

The whitepaper can say the code is non-custodial. It should **not** say "therefore no licence or legal obligations exist" without qualified legal advice.

---

# 13. Solo-maintainer / continuity risk

Repository popularity is not a security proof, but **0 stars / 0 forks and one maintainer do correctly signal zero demonstrated external adoption today**.

We cannot fix that with wording. We can reduce continuity risk with process:

1. reproducible builds and deterministic release artefacts;
2. signed release tags / checksums;
3. `SECURITY.md` with private disclosure path;
4. `GOVERNANCE.md` defining release / emergency authority;
5. `BUS_FACTOR.md` / continuity runbook documenting how another maintainer can reproduce deployment and operations;
6. public RFCs for material protocol changes;
7. independent review before real funds;
8. owner / fee-recipient moved to a documented multisig before mainnet;
9. no mainnet dependency on one developer's laptop, API account or private database.

A future whitepaper should report external contributors, reviews, stars/forks, users or integrations only when those facts actually exist.

---

# 14. Competitive threat model

## 14.1 BOT Chain can ship its own escrow

This is the strongest strategic threat because a chain-native implementation can receive privileged ecosystem placement and direct integration.

Response: NexEscrow should be useful **even if BOT Chain publishes settlement primitives**. The differentiator becomes portable terms, resolution modules, evidence commitments, agent adapters and cross-chain semantics. A future backend adapter could even route to a BOT-native settlement contract if it exposes sufficient guarantees.

Do not build a moat around the assumption that BOT Chain lacks an escrow contract forever.

## 14.2 Kleros

Kleros is not merely a theoretical threat; it already supplies arbitration infrastructure, appeal mechanisms, evidence flows and an ERC-792-style separation between arbitrable contracts and arbitrators.

Response: integrate rather than imitate the whole court. NexEscrow should support an `ERC792Adapter` / external resolver path and retain a simpler quorum resolver for deployments that do not want Kleros economics.

## 14.3 Boson Protocol

Boson has experience with escrow-like commerce state machines, mutual resolution and escalation to external dispute resolvers.

Response: NexEscrow remains horizontal milestone settlement rather than a physical-commerce protocol. Borrow the lesson: mutual resolution should be cheap, escalation should be explicit, and the fund-moving core should remain deterministic.

## 14.4 Request Network

Request Network is a mature non-custodial payment coordination system with payment requests, SDKs, indexing/payment detection and cross-chain stablecoin UX.

Response: do not compete on "payment request" alone. NexEscrow's value proposition is **conditional milestone settlement + dispute policy + intent/evidence binding**, which is different from direct request/payment detection.

## 14.5 x402 facilitators / Meridian

Meridian currently demonstrates x402 facilitation, including same-chain and cross-chain settlement flows. That is adjacent infrastructure, not proof of milestone escrow.

Response: x402 should be an adapter / ingress path, not something NexEscrow attempts to replace.

## 14.6 CaryPact

Current public CaryPact material describes decentralized compute infrastructure. We do **not** currently have enough evidence to label CaryPact a direct escrow competitor.

Response: keep it on an ecosystem-watch list, not in the whitepaper's verified competitor table unless an actual settlement/escrow product is published.

---

# 15. BOT Chain dependency and market/liquidity risk

Chain risk must be disclosed independently of smart-contract correctness.

A perfectly correct escrow can still be a poor product if its chain has weak liquidity, unreliable infrastructure, thin exchange markets, unstable bridges, or uncertain asset support.

Important correction to an earlier risk note: a current CoinMarketCap page for **BOT Chain (BOT)** shows a price around **$12.35**, rank around **#4875**, and very low 24-hour reported volume (~$1k at the time checked). That does **not** support a statement that BOT's price is "near zero." There are multiple similarly named BOT/Botchain assets, so ticker confusion itself is a risk.

The whitepaper should therefore avoid volatile rank/price claims in the core narrative. Instead use a dated chain-risk appendix covering:

- canonical token contract / native-asset identity;
- circulating supply source and whether market cap is independently verifiable;
- actual 24h liquidity / venue depth;
- bridge trust model and bridged-stablecoin issuer / canonicality;
- RPC uptime / rate limits;
- explorer availability;
- validator / finality assumptions;
- stablecoin liquidity needed for realistic escrow usage.

Mainnet should initially cap value-at-risk until those dependencies are measured in production conditions.

---

# 16. Grant chicken-and-egg: restructure the ask

The BOT Chain public Ecosystem Support Program explicitly describes support for **early-stage projects** and allows applications through the portal or official email. Its public FAQ does not establish a universal rule that every applicant must already be on mainnet.

Therefore the proposal should not frame the situation as "grant requires mainnet, but mainnet requires audit" unless the programme reviewers explicitly impose that condition on NexEscrow.

Instead request staged support:

### Stage A — pre-mainnet security milestone

- independent contract review / audit sponsorship;
- BOT engineering guidance on finality, RPC limits and EVM target;
- testnet gas / integration assistance;
- resolver / indexing review.

### Stage B — controlled mainnet pilot

Only after Stage A exits:

- multisig operator configuration;
- hosted indexer + monitoring;
- capped value-at-risk;
- limited users / agreements;
- bug-bounty window;
- incident and migration runbook.

### Stage C — activity-linked ecosystem incentives

Only after real activity exists:

- agreements settled;
- distinct counterparties / resolvers;
- value escrowed / released;
- dispute rate / resolution latency;
- Sybil-resistant usage measurements.

This removes the false incentive to deploy unaudited code merely to qualify for a programme.

---

# 17. Demo 1 implementation gates

Demo 1 is not "done" when the PDF looks convincing. It is done only when the following proof exists.

## Contract / protocol

- bilateral EIP-712 agreement intent;
- EIP-1271 contract-wallet support;
- finite dispute timeout state machine;
- resolution-policy interface;
- at least one tested quorum resolver;
- optional appeal resolver path;
- evidence commitment events / integrity verification;
- deterministic timeout disposition;
- bilateral atomic migration to a compatible future deployment;
- no owner principal sweep;
- conservation invariant extended across timeout / appeal / migration paths.

## Agent adapters

- x402 reference flow demonstrating a paid service mapped to a milestone without claiming x402 itself is escrow;
- AP2 mandate-hash binding prototype;
- ERC-8004 identity reference prototype marked experimental while the ERC remains Draft;
- replay and domain-separation tests for all signed intents.

## Operations

- hosted event indexer;
- reorg simulation / repair tests;
- RPC backoff / failover tests;
- reproducible deployment bundle;
- multisig owner / fee-recipient plan;
- continuity runbook;
- legal-operating boundary documents;
- independent audit / review report.

## Mainnet

- BOT engineering questions resolved in writing;
- audit high/medium findings closed;
- public testnet Demo 1 deployment;
- bug-bounty / external review window;
- explicit go/no-go document;
- initial value-at-risk cap.

---

# 18. Security invariants added for Demo 1

The following should become executable invariants / property tests, not prose only:

1. `principal_out + principal_remaining == principal_in` across release, dispute, timeout, appeal and migration.
2. Resolver can never receive escrow principal unless it is also a legitimate buyer/seller payout address under the committed terms.
3. No dispute can remain permanently non-finalizable after all committed deadlines have passed.
4. A timeout cannot change the pre-signed timeout split.
5. Appeal cannot alter an unrelated milestone.
6. Migration cannot change buyer, seller, token, remaining principal, or already-finalized milestone history.
7. The same EIP-712 intent cannot activate twice.
8. A signature valid on one chain / contract cannot activate on another domain.
9. ERC-1271 validation failure is fail-closed.
10. Adapter data (x402/AP2/ERC-8004) cannot directly move funds; only committed core state transitions can.
11. Indexer compromise cannot alter on-chain settlement; the UI must expose source contract / chain and support direct read verification.

---

# 19. Positioning after hardening

The Demo 1 narrative should become:

> NexEscrow is not a marketplace, payment processor, court, AI agent, or chain-specific grant wrapper. It is an immutable milestone-settlement kernel plus versioned adapters for intent, identity, evidence and resolution. The settlement path is deterministic; external systems can inform authorization and disputes without receiving arbitrary custody powers over principal.

This positioning survives more competitive futures:

- if BOT Chain ships native escrow, NexEscrow can become a semantics / adapter layer;
- if Kleros is preferred, NexEscrow can route disputes to Kleros;
- if x402 dominates agent payments, NexEscrow can add conditional settlement above x402 request semantics;
- if AP2 becomes dominant for agent authorization, NexEscrow can bind mandates as evidence;
- if ERC-8004 matures, NexEscrow can consume identity / reputation without making it a trusted settlement oracle.

---

# 20. What we should not claim in Demo 1

Until independently true, the whitepaper must continue to say:

- no audit completed;
- no BOT mainnet deployment;
- no production-readiness claim;
- no users / TVL / revenue / partnerships claimed;
- no official BOT Chain endorsement unless explicitly granted;
- no legal/regulatory status conclusion;
- no x402 / AP2 / ERC-8004 implementation until the adapters exist and are tested;
- no community traction based on stars/forks until external contributors actually appear.

Transparency is part of the product.

---

# 21. External standards / competitive references

Primary references used for this Demo 1 design:

- EIP-712 — Typed structured data hashing and signing: https://eips.ethereum.org/EIPS/eip-712
- EIP-1271 — Standard Signature Validation Method for Contracts: https://eips.ethereum.org/EIPS/eip-1271
- ERC-8004 — Trustless Agents (**Draft**): https://eips.ethereum.org/EIPS/eip-8004
- x402 — protocol / HTTP transport: https://www.x402.org/ and https://github.com/x402-foundation/x402
- Google Agent Payments Protocol (AP2): https://github.com/google-agentic-commerce/AP2
- A2A x402 extension: https://github.com/google-agentic-commerce/a2a-x402
- Kleros ERC-792 / escrow documentation: https://docs.kleros.io/developer/arbitration-development/erc-792-arbitration-standard and https://docs.kleros.io/products/escrow/kleros-escrow-specifications
- Boson dispute / escrow architecture: https://www.bosonprotocol.io/blog/how-boson-protocol-v2-really-works/
- Request Network: https://request.network/ and https://docs.request.network/
- BOT Chain developer guide: https://dev-docs.botchain.ai/docs/Developers/quick-guide/
- BOT Chain Ecosystem Support Program: https://www.botchain.ai/en/ecosystem-support/

---

# 22. Immediate engineering order

**Do not modify the already validated Demo 0 contract and pretend the old evidence covers the new design.**

Recommended execution order:

1. freeze / tag Demo 0 evidence;
2. implement EIP-712 bilateral intent + replay protection in a new Demo 1 contract;
3. introduce finite dispute deadlines and deterministic timeout finalization;
4. extract resolution behind an interface and build a quorum resolver;
5. add evidence commitments and optional ERC-1497-compatible adapter semantics;
6. add bilateral migration;
7. extend fuzz / invariant suite for all new paths;
8. build the hosted indexer and reorg tests;
9. build x402 / AP2 / ERC-8004 adapters outside the core;
10. deploy Demo 1 to Bohr 968 under new addresses;
11. reproduce the full validation dossier from zero;
12. obtain independent review before any BOT 677 deployment.

**Demo 0 proved the primitive. Demo 1 must prove survivability, interoperability and operational discipline.**
