# BOT Chain Bohr (968) Live Validation Report

- Generated: 2026-10-08T21:04:07Z -> 2026-10-08T21:05:00Z (UTC)
- RPC: `https://rpc.bohr.life` (LIVE BOT BOHR)
- Chain id: 968
- Contract: `0x6448668ae9cbbc41617c2bd5e4f29279320a2700`
- Deployment: deployed during this harness run
- Buyer: `0xBd44098dF1cE55e4604b8bdC8E4454Ee669364af`  Seller: `0x00669c300511207767dD0556F0575C8d7bbEBF8E`  Arbiter: `0x617BCBCA7d5F42F0cb5a6d03BdA9F1f1A3A6C433`

## Transactions

| Step | Tx hash | Block | Gas used | Status |
|---|---|---|---|---|
| createAgreement(A) | `0xf9f4b64cfd8c7e4f0270889800c15efb9ee6fa66e2622fff495ddb4053d78608` | 26178658 | 213605 | 1 |
| fund(A) | `0xe52792a7054cbfc6b3f74e982e340865109f7417054427e42ca7ba4bf7760a1d` | 26178662 | 37263 | 1 |
| approveMilestone(A,0) | `0x42bcb8608046d459afcdafc6e2909e7e478d3d0db1c07f97781fbfac43ef746e` | 26178664 | 80047 | 1 |
| approveMilestone(A,1) | `0xba6e78551f8d0a27529b87f62de6b440f9d442f940f519d92ea110fc137c39b1` | 26178666 | 64242 | 1 |
| createAgreement(B) | `0x1b49e4e23cd81cc8e970468a9934a46fdb67072f89d834a6c9935f0e4c36d560` | 26178669 | 172303 | 1 |
| fund(B) | `0xb8115ec9c424788564b2259ccfe91c0c1a5d92db9911fda86c49d681ba2774fb` | 26178671 | 37275 | 1 |
| raiseDispute(B,seller) | `0x37275e2a1fa60c2021159b3d7294e961024c2236e080eb889bcd82e1334009bd` | 26178673 | 39707 | 1 |
| resolveDispute(B,6000) | `0x3a53ede3d28fc1a3700d3a7ee2a87df0c465acf832a542dbe5e325bdf3aa2221` | 26178675 | 76801 | 1 |

## Balances (native wei)

| Account | Before | After |
|---|---|---|
| Buyer | 469724380000000000 | 317629680000000000 |
| Seller | 50000000000000000 | 187805860000000000 |
| Arbiter | 50000000000000000 | 48463980000000000 |
| Escrow | 0 | 1400000000000000 |

Balance deltas include gas paid by each signer; conservation is asserted on
event amounts and direct contract state, which are gas-independent.

## Event-derived state vs direct reads

- Agreement A (id 0): 2 `MilestoneReleased` events; direct status Completed,
  cursor 2/2; released gross 100000000000000000 == total 100000000000000000.
- Agreement B (id 1): `DisputeRaised` by seller, `DisputeResolved(buyerBps=6000)`;
  direct status Completed, cursor 1/1; milestone Resolved.
- Accrued fees: direct 1400000000000000 == event-derived 1400000000000000; escrow balance 1400000000000000.
- Conservation: released gross + dispute gross == funded total (200000000000000000).

## Checks

| Check | Result | Detail |
|---|---|---|
| chain id is 968 | PASS | chain 968 |
| deployment has code | PASS | 0x6448668ae9cbbc41617c2bd5e4f29279320a2700 |
| AgreementCreated count == 2 | PASS | ids [0, 1] |
| created ids match direct reads | PASS | events [0, 1] vs direct [0, 1] |
| Funded events for both | PASS | funded [0, 1] |
| AgreementCompleted for both | PASS | completed [0, 1] |
| A direct status Completed | PASS | status 2, next 2/2 |
| A direct nextMilestone == 2 | PASS | next 2 |
| A milestones both Released | PASS | statuses [1, 1] |
| A two MilestoneReleased events | PASS | [{'index': 0, 'amount': 50000000000000000, 'fee': 500000000000000}, {'index': 1, 'amount': 50000000000000000, 'fee': 500000000000000}] |
| A released indices {0,1} | PASS | indices [0, 1] |
| A released gross == total | PASS | sum 100000000000000000 == total 100000000000000000 |
| B direct status Completed | PASS | status 2, next 1/1 |
| B direct nextMilestone == 1 | PASS | next 1 |
| B milestone Resolved | PASS | status 3 |
| B DisputeRaised by seller | PASS | raisedBy topic 0x00000000000000000000000000669c300511207767dd0556f0575c8d7bbebf8e |
| B one DisputeResolved | PASS | [{'index': 0, 'buyerBps': 6000, 'buyerAmount': 60000000000000000, 'sellerAmount': 39600000000000000, 'fee': 400000000000000}] |
| B dispute buyerAmount matches floor(bps) | PASS | event 60000000000000000 expected 60000000000000000 |
| B dispute sellerAmount matches fee math | PASS | event 39600000000000000 expected 39600000000000000 |
| B dispute fee matches fee math | PASS | event 400000000000000 expected 400000000000000 |
| accruedFees == event-derived fees | PASS | direct 1400000000000000 vs events 1400000000000000 |
| escrow balance == accrued fees (no principal left) | PASS | escrow 1400000000000000 vs fees 1400000000000000 |
| conservation: released + dispute gross == funded total | PASS | 100000000000000000 + 100000000000000000 == 200000000000000000 |

**Summary: 23/23 checks passed.**

Notes:
- The contract is **unaudited**; this is a testnet validation, not an audit or a production statement.
- Any funds used are BOT Bohr testnet funds only.
