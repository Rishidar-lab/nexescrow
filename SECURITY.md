# Security Policy — NexEscrow

**Status: UNAUDITED, TESTNET STAGE. This software has not been independently reviewed
and is not production ready. Do not use it to custody real funds.**

## Reporting a vulnerability

- Preferred: open a **private** GitHub Security Advisory on
  `Rishidar-lab/nexescrow` (Security → Report a vulnerability). This keeps details
  private until a fix or mitigation is ready.
- Please do not open a public issue for a suspected vulnerability.
- There is currently **no bug bounty** and no promise of compensation.
- Include: affected commit, contract/address if deployed, exact reproduction steps,
  raw outputs, and expected vs observed behaviour.

## Scope

| Component | Files |
|---|---|
| Escrow contract | `contracts/src/NexusEscrow.sol` |
| Deployment scripts | `contracts/script/` |
| Contracts tests/mocks | `contracts/test/` |
| Frontend | `frontend/src/` |
| Docs | `docs/` |

Out of scope: third-party dependencies (OpenZeppelin, wagmi/viem/RainbowKit, Next.js)
unless the issue is caused by how NexEscrow uses them; social engineering; denial of
service on public RPC endpoints; issues requiring a compromised owner key (documented
as a trust assumption, not a vulnerability).

## Security guarantees (as designed)

- Escrow never pays out more than was deposited per agreement and token
  (invariant-tested).
- Buyer + seller + protocol fees conserve escrowed value exactly for every action.
- A milestone cannot be released twice; states cannot regress.
- Unauthorized addresses cannot cause value transfer.
- The owner cannot seize escrow principal, resolve disputes, or change in-flight
  agreement terms.
- Fee changes cannot mutate historical agreements (per-agreement snapshot).
- Pause affects availability, never accounting.
- Every terminal state leaves accounting internally consistent.

## Known risks (accepted, disclosed)

See `docs/THREAT_MODEL.md` §3.4 and `docs/BOTCHAIN_INTEGRATION.md` §13. Highlights: a
silent arbiter freezes a disputed milestone; there is no funded mutual-cancel; pause is
a liveness lever; rebasing/blocklist tokens are unsupported; the contract is
non-upgradeable; the arbiter's independence is only enforced as an address inequality.

## Operational security practices in this repository

- No private keys, mnemonics, or API secrets are committed. `.env` files are
  gitignored; only `.env.example` placeholders are tracked.
- Deployment is guarded: mainnet chains require an explicit
  `ALLOW_MAINNET_DEPLOYMENT=true`, never enabled by default.
- The frontend is guarded: testnet by default, mainnet opt-in, and every write asserts
  `connectedChainId === selectedChainId`.
- CI runs formatting, build, the full test suite (including fuzz/invariant campaigns),
  frontend lint, typecheck, and build. Failing tests are not ignored.

## Audit status

No independent audit has been performed. Any statement to the contrary is false. A
mainnet deployment requires an independent review with findings resolved before it can
be considered (see `docs/BOTCHAIN_INTEGRATION.md` §21).
