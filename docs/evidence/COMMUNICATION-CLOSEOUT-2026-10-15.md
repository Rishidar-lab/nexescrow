# NexEscrow integration communication closeout — 15 October 2026

## Scope and provenance

Application code baseline inspected: `69115757f272a5d47eee0f849ec855c0abdd5e41`.
Its matching CI run 38751672786 completed successfully. This closeout adds a
reproducible adapter integration check and corrects communication/evidence scope;
it does not change escrow contracts, runtime application code, or mainnet guards.
The latest PR metadata and the technical reply identify the resulting repository
snapshot and its own matching CI separately.

Two existing fixes are present: typed permanent-RPC classification (`a149a0d`)
and HTTP discovery chain/contract validation (`60c8809`). The retry policy also
retains a narrow plain transport-error fallback (`network error`, `fetch failed`,
`failed to fetch`); saying it accepts only typed HTTP/timeouts is inaccurate.

## Checks performed in this closeout

| Check | Result and scope |
| --- | --- |
| Frozen frontend dependency installation | PASS; Node 24.19.0, pnpm 11.25.0 |
| Frontend unit tests | PASS, 44/44 |
| ESLint and TypeScript/type generation | PASS, including the new verification script |
| Default chain safety | PASS; selected 968, mainnet false, offered 3945/968 |
| Existing finality-policy regression | PASS |
| Isolated-process adapter replay | PASS; cold process, new process retaining checkpoint, new process clearing checkpoint converge |
| Replay event identity | PASS; 10 agreement events from the 11-log historical fixture, which also contains OwnershipTransferred; deliberate duplicate input removed |
| Range cap during replay | PASS; three ranges of 2,000, 2,000 and 33 blocks |
| HTTP adapter integration | PASS; actual local HTTP server returns a valid row and wrong-chain, wrong-contract and legacy unscoped rows; only valid row retained |
| Official Bohr RPC identity | Read-only `eth_chainId` returned `0x3c8` (968) |
| Whitespace | `git diff --check` PASS |

Reproduce adapter checks from `frontend/`:

```sh
pnpm dlx esbuild@0.28.2 scripts/verify-indexer-integration.ts --bundle --platform=node --format=esm --outfile=/tmp/nexescrow-indexer-check.mjs
node /tmp/nexescrow-indexer-check.mjs
```

These checks use committed historical log data, a simulated RPC client, simulated
localStorage, isolated Node processes, and a real local HTTP fixture server.
They are not a browser check, a live indexer acceptance test, or a fresh on-chain
lifecycle. There is no wallet or transaction submission.

## HTTP indexer compatibility

Repository defaults leave `NEXT_PUBLIC_INDEXER_URL` unset; the default adapter is
direct RPC log scanning. No HTTP-indexer service implementation is present in this
branch. A remotely configured deployment could override those defaults; its
environment was not inspected here. Therefore compatibility with a live external
producer is **unverified**, not assumed. Before enabling HTTP mode, require numeric
`chainId`, an exact `contractAddress`, and the documented role/id fields in each
discovery record. Legacy unscoped rows intentionally fail closed.

## Remaining verification limits

- Browser checkpoint/reload/clear testing remains unexecuted. The environment has
  no installed Chromium; Playwright's browser download failed archive validation.
  Isolated-process replay reduces the gap but does not close it.
- The existing Python live verifier could not complete here because `cast` is
  unavailable. Its first five local checks passed before that dependency error.
  The earlier reported 34/34 live result is historical evidence, not a new result
  from this closeout. Contract tests likewise rely on the matching remote CI;
  Foundry is not installed locally.
- No fresh stateful Bohr run, chain-677 deployment/transaction, or customer funds.
- No new security audit or production-readiness claim.

## Remaining BOT-owned answers and decision gate

Confirmed guidance remains 2,000 blocks per log query, 2 receipt confirmations on
968/677 and Cancun targeting. The 12-block indexing depth and three-total-attempt
read retry are application policies, not BOT guarantees. Pending questions are:

1. Recommended retry/backoff or explicit absence of a recommendation.
2. Reorg/finality and indexing-depth guidance beyond receipt confirmations, for
   each chain, or explicit absence of a guarantee/recommendation.
3. Cancun opcode/precompile limitations affecting Solidity 0.8.26 + Cancun, or
   explicit absence of known limitations/recommendations.

The controlled plan in `BOT-CONTROLLED-VALIDATION-2026-10-14.md` is a proposal.
Chain 677 remains disabled. No agreement by BOT is asserted. Record the eventual
answers and accepted assumptions in Discussion #2 before any separately authorised
mainnet validation. The builder-controlled review checkpoint is ready on
15 October 2026; a response date for BOT/Cisco is not promised.
