# REVIEW DRAFTS — NOT SENT OR POSTED

> **Status:** review only. No email or GitHub comment was sent by this work.
>
> Proposed email routing:
>
> - To: `leon@botchain.ai`
> - Cc: `cisco@botchain.info`
> - Subject: `Re: NexEscrow × BOT Chain — additional network inquiry`
>
> This is a reply in the existing technical thread. Cisco was a participant in the
> earlier thread and is copied only for the remaining BOT-owner questions.

## Email reply draft

Hi Leon, copying Cisco,

Thank you. I have prepared the smallest controlled validation plan and kept the
completed network-setting items out of the remaining decision gate.

The builder-side checkpoint is ready for review:

- Evidence/plan commit:
  https://github.com/Rishidar-lab/nexescrow/commit/4396172bc0d2979e6d2ea47dd9988cf95b6cff1d
- Controlled plan:
  https://github.com/Rishidar-lab/nexescrow/blob/4396172bc0d2979e6d2ea47dd9988cf95b6cff1d/docs/evidence/BOT-CONTROLLED-VALIDATION-2026-10-14.md
- PR #1: https://github.com/Rishidar-lab/nexescrow/pull/1
- Matching CI: https://github.com/Rishidar-lab/nexescrow/actions/runs/38750307860
  (Scripts, Frontend and Contracts all green for that exact commit)

The plan separates checks possible now on local tooling/Bohr 968 from a proposed
chain-677 exercise. For Bohr, it covers chain and endpoint identity, exact artifact
and EVM provenance, native BOT asset behaviour, role/wallet control, the previously
validated funding/release/dispute-directed-refund flows, balance conservation,
frontend/indexer consistency, bounded log polling, replay behaviour and transient
read handling. Each step records prerequisites, owner, procedure, expected evidence,
pass/fail criteria, stop conditions and cleanup.

The chain-677 section is a proposal only. It requires prior agreement on the exact
artifact, asset/address/decimals, roles and wallet control, funding source, fees and
maximum exposure. It permits no customer funds and no activity unless every missing
prerequisite and approval is recorded. The shared stops include wrong chain or
contract, asset/permission mismatch, unexplained balances, duplicate or missing
events, unexpected RPC/EVM behaviour, a violated finality assumption, a missing
approval, or an exceeded pre-agreed limit. Cleanup disables 677 again and requires
reconciliation of any test assets.

One reproducible application defect was corrected in commit
`a149a0d8100e8dd88b087ff5d80aaa530db5e46a`: the read-side retry classifier could
misclassify a typed permanent JSON-RPC error as transient when its message happened
to contain text such as `429` or `502`. Typed RPC errors now fail immediately;
retries remain limited to typed timeouts and allow-listed transient HTTP failures.
State-changing writes are not automatically resubmitted.

For clarity, the 2-block receipt-confirmation setting and the 2,000-block maximum
`eth_getLogs` window are implemented from the previously supplied BOT guidance. The
12-block indexing safety depth and three-total-attempt read retry policy are
NexEscrow application choices, not BOT guarantees.

Cisco, could you please clarify only the remaining network-owner items, and state
explicitly where BOT has no published guarantee or recommendation?

1. Is there a recommended retry/backoff policy beyond respecting the confirmed
   2,000-block log-query window?
2. Are there reorganisation/finality or indexing-depth recommendations beyond the
   confirmed 2 receipt confirmations, for chains 968 and 677?
3. Are there Cancun opcode or precompile limitations that affect a Solidity 0.8.26
   contract compiled with `evmVersion = "cancun"`?

Chain 677 remains disabled pending agreement on those assumptions and the proposed
validation steps. No mainnet validation was performed. A successful controlled test
would not establish a universal finality guarantee or constitute a security audit.

As the solo maintainer, I can action builder-controlled follow-ups once the guidance
is available. The builder-side checkpoint completed on 15 October 2026 UTC; the next
measurable checkpoint is BOT's answer plus agreement on the chain-677 prerequisites,
so I cannot responsibly assign a date to that external response.

Best regards,
Rishidar
NexEscrow

## Discussion #2 update draft — not posted

**Controlled-validation decision checkpoint — draft for review**

PR #1 remains open and unmerged. The current evidence/plan commit is
`4396172bc0d2979e6d2ea47dd9988cf95b6cff1d`; matching CI run
https://github.com/Rishidar-lab/nexescrow/actions/runs/38750307860 is green for
Scripts, Frontend and Contracts.

The smallest controlled validation plan is now reviewable at:
https://github.com/Rishidar-lab/nexescrow/blob/4396172bc0d2979e6d2ea47dd9988cf95b6cff1d/docs/evidence/BOT-CONTROLLED-VALIDATION-2026-10-14.md

Decision boundary:

- Bohr 968/local checks may use the existing authorised deployment and evidence.
  Read-only re-verification passed 34/34 checks. No fresh stateful flow was run.
- The browser checkpoint/replay exercise remains an explicitly unexecuted local
  validation step.
- Chain 677 remains disabled. Its proposed validation is unexecuted and requires
  prior agreement on the exact artifact, asset, roles/wallets, funding source, fees,
  maximum exposure, evidence owners and approvals. It permits no customer funds.
- Any 677 exercise must stop on a wrong chain/contract, unresolved asset or permission
  mismatch, unexplained balance discrepancy, inconsistent events, unexpected RPC/EVM
  behaviour, violated finality assumption, missing approval or exceeded limit. It
  must end by disabling 677 again and reconciling test assets.

Application correction: commit `a149a0d8100e8dd88b087ff5d80aaa530db5e46a`
makes the read retry policy type-aware so permanent JSON-RPC errors cannot be retried
merely because their message contains a gateway status code. There are no automatic
transaction resubmission retries.

Confirmed BOT guidance currently implemented: 2,000 blocks maximum per
`eth_getLogs` query, 2 receipt confirmations on 968 and 677, and Cancun targeting.
The 12-block indexing safety depth and three-total-attempt transient read retry are
NexEscrow application policy, not BOT finality/capacity guarantees.

Awaiting BOT technical-owner guidance, or an explicit statement that none is
published, on:

1. recommended retry/backoff behaviour;
2. reorganisation/finality and indexing depth beyond receipt confirmation; and
3. Cancun opcode or precompile limitations.

Builder-controlled work reached its review checkpoint on 15 October 2026 UTC. The
next measurable decision point is receipt of that guidance and agreement on the
chain-677 prerequisites; no BOT response date is assumed.
