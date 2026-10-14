# EMAIL DRAFT — NOT SENT

> **STATUS: DRAFT ONLY. DO NOT SEND.**
> Leon and Cisco were already contacted on 14 October 2026. This draft exists for
> manual review and manual sending by the operator. It was **not** sent by this
> execution, and no mail transport was invoked.
>
> - To: `leon@botchain.ai`
> - Cc: `cisco@botchain.info`
> - Subject: `Re: NexEscrow × BOT Chain — additional network inquiry`

---

To: leon@botchain.ai
Cc: cisco@botchain.info
Subject: Re: NexEscrow × BOT Chain — additional network inquiry

Hi Leon, copying Cisco,

Short update on NexEscrow from our side. All builder-controlled work is now complete
and the repository is in a reviewer-ready state.

**Final state**

- Branch: `feat/botchain-integration`
- Final SHA: `7d1832b5f09845703938e8eb10cc049956e8ede3`
- CI: run 38105145398 — green (Scripts, Contracts, Frontend)
- PR: https://github.com/Rishidar-lab/nexescrow/pull/1 (open, not merged)

**Final test metrics**

- Contracts: 8 suites, 130 tests, 130 passed, 0 failed
- Fuzz: 4 property tests, 1,024 runs default / 4,096 CI profile
- Invariants: 3 stateful invariants, 128×64 default / 256×128 CI
  (32,768 handler calls per invariant at CI, 0 reverts, 0 discards)
- Coverage of the escrow contract: 98.56% lines / 98.37% statements /
  97.44% branches / 100% functions
- Frontend: lint, typecheck, 35/35 unit tests, 8/8 chain-safety checks,
  finality-policy checks, production build — all pass
- Scripts: YAML, Python, shell syntax, 6/6 validator unit tests, JSON validation

**Bohr 968 evidence re-verified**

We re-queried the existing validated deployment from chain (read-only, no new
transactions) and all 34 checks passed:

- Contract `0x6448668ae9cbbc41617c2bd5e4f29279320a2700`
- Deployment tx `0x4216d1e1eb33e296e3a3040baa723b507ce2da449d60e6ffe9456cecacf6da61`,
  block 26178651, receipt success, on-chain bytecode hash matches the manifest
- All 8 lifecycle receipts confirmed `status=1`; 11 emitted events re-queried and
  matched against the committed evidence
- Both agreements terminal `Completed`; accrued fees 0.0014 BOT == escrow balance
- Conservation exact: 0.2 BOT funded = 0.1386 to seller + 0.06 refunded to buyer
  + 0.0014 fees. Principal retained in escrow: **0 wei**.

A *fresh* validation run was **not** performed: we no longer hold the burner testnet
keys for that instance. We have recorded that as an explicit blocker rather than
relabelling old transaction hashes as new.

**Defects fixed:** none. We found no genuine builder-controlled defect in this pass,
and we did not invent one.

**Two things we want to be explicit about**

1. **BOT 677 remains disabled.** Not deployed, not enabled, not production ready. The
   deploy script refuses mainnet unconditionally, and the frontend fails closed to
   Bohr 968 unless mainnet is explicitly opted in.
2. **No audit and no production-readiness claim is being made.** The contract is
   unaudited. An independent security review is still an open gate.

**The only remaining dependencies are on your side**

1. `eth_getLogs` policy — supported ranges, official limits, rate limits, recommended
   retry behaviour.
2. Finality — recommended receipt confirmations and reorg/indexing safety depth for
   968 and for 677.
3. Cancun/EVM — official Cancun support, recommended compiler `evmVersion`, and any
   opcode/precompile limitations.

To be clear about what we have and have not: we have empirical measurements from our
own testnet traffic (including an observed lack of a hard `eth_getLogs` range cap on
both public endpoints, and a transient nginx 503 window that recovered under retry).
Those are observations from our usage only. We are not treating them as a
specification, and we would rather adopt your documented guidance than our own
generalisation from a few probes.

Happy to re-run and re-verify against whatever you send over.

Best regards,
NexEscrow
