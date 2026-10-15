# Reviewed technical reply template — 15 October 2026

This file is a reviewed template, not proof of email delivery. The actual reply
must resolve the PR head, controlled plan, closeout report and matching CI to the
same immutable final snapshot at send time. Do not reuse the superseded
4396172 evidence/CI pair as evidence for the later HTTP-indexer fix.

To: leon@botchain.ai
Cc: cisco@botchain.info
Subject: Re: NexEscrow × BOT Chain — additional network inquiry

Hi Leon and Cisco,

The smallest controlled-validation plan is ready for review. Its completed-network
settings are separate from the remaining decision gate. The final reply links the
exact snapshot, controlled plan, closeout evidence and matching CI.

The plan reuses the existing Bohr funding/release/dispute-refund evidence and
requires chain/artifact/asset/role verification, exact balance and event
reconciliation, and explicit stops for mismatches, unexpected RPC/EVM behaviour
or exceeded pre-agreed limits. Any future 677 exercise requires agreement on
assumptions, wallets, funding and maximum exposure; no customer funds are permitted.

Two application fixes are included: permanent typed RPC errors are not retried
merely because their message contains a gateway code, and HTTP discovery records
must match the configured chain and contract. Read retries remain bounded for
selected transient failures, including a narrow plain transport-error fallback.
Writes are not automatically resubmitted.

Frontend tests passed 44/44 with lint, type checks and chain/finality checks.
An isolated-process, fixture-backed replay check produced identical agreement
events after cold start, retained checkpoint and cleared checkpoint; a local HTTP
server check confirmed wrong-scope rows are rejected. These are not browser or
live-indexer tests. Browser replay remains outstanding, and the previous 34/34
Bohr verification is historical; no fresh lifecycle or mainnet transaction occurred.

Cisco, could you clarify the remaining network-owner questions, explicitly stating
where BOT has no published guarantee or recommendation:
1. Recommended retry/backoff.
2. Reorg/finality or indexing-depth guidance beyond two receipt confirmations,
   separately for chains 968 and 677.
3. Cancun opcode/precompile limitations affecting Solidity 0.8.26 + Cancun.

The 12-block indexing depth and three-total-attempt read retry remain NexEscrow
policies. Chain 677 remains disabled. The builder checkpoint is ready on 15 October;
the next checkpoint is your guidance and agreement on the proposed prerequisites.
The resulting decision will be recorded in Discussion #2; no BOT response date is
assumed.

Best regards,
Rishidar
NexEscrow
