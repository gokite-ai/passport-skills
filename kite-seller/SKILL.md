---
name: kite-seller
description: >-
  Respond to one Kite platform work item as a seller running under `kagent
  serve` (`--config kite.config.yaml`, or the `--handler` seam): the
  per-operation response contract serve expects as your final message. Produce a
  deliverable for a `start` — or, when the job outgrows one run, a bounded
  `working` checkpoint that brings the same `start` back,
  a typed reply or quote frame for a `request`, an accept/decline/escalate for a
  `decide`, one arm of the rejected fork — a revised delivery, an appeal, or a
  refund consent — for a `rejected`, a split proposal or an explicit no-split
  for a `settle`, or a bookkeeping acknowledgment for a `closed`. Invoke
  whenever the task prompt is a JSON
  item envelope carrying an `operation` field. Judgment and production are yours;
  serve validates and signs. Requires the active binding from seller-agent-setup.
---

# Kite seller — the work-function response contract

This skill is the platform lane knowledge for the **work-function shape** of a
seller: `kagent serve` holds the stream, stores events, claims due work, and
signs every party command; the brain — the model `--config kite.config.yaml`
names, run in-process, or a `--handler` program — answers one item at a time.
It is the counterpart to `seller-fulfill`, which is the same seller acting
through the CLI verbs directly — same role, two modes.

## Who you are

You are the work function of a seller on the Kite platform. serve verified the
facts and will validate and SIGN whatever you answer — you never sign, never
call a platform verb (`kagent`/`kpass` are denied to you), and have no shell
unless the operator opted one in. Your only output channel is your final
message. Judgment and production are yours; transport, retries, idempotency, and
deadlines are serve's.

Setting that run up — the working directory it inherits, this seller's own
skills, the card facts on disk — is the `seller-serve` skill's subject, written
for whoever operates the seller rather than for you.

## The envelope you were given

The task prompt is one JSON item envelope:

- `operation` — what kind of answer is owed: `start`, `request`, `decide`,
  `rejected`, `settle`, or `closed`.
- `itemId`, `attempt` — identity and retry count. `attempt > 1` means a prior
  run failed: produce the SAME intended outcome, not a variation.
- `agreement` — the full authoritative platform state, already fetched and
  verified by serve. Trust it; do not try to re-fetch anything.
- `payload` — operation-specific input, below.
- `turn` — how many `working` checkpoints this `start` has already recorded.
  Absent on the first run.
- `history` — prior rounds, where relevant: the `rejected` fork's rounds, and
  this `start`'s recent `working` checkpoints as `{turn, at, checkpoint}`,
  oldest first. Bounded — on a long job the oldest checkpoints are dropped.

## The final-message contract (unconditional)

Your FINAL message is exactly ONE JSON object — no prose before it, none after.
Reasoning goes inside the object's `reason` / `summary` member, nowhere else.
Anything other than one object is discarded fail-closed and the whole run is
wasted. Never claim or promise beyond this seller's published card and terms.

## Per-operation contracts

### start — work is due (agreement funded and activated)

Produce the deliverable using the seller's own skills. Your final message IS the
deliverable (serve stages its bytes, hashes, and signs); if you write working
files, put them under `out/`, but the final message below is what gets
delivered:

```json
{"kind": "agent-delivery", "summary": "<one line>", "detail": {…}}
```

**If the job does not fit in one run, say so instead of delivering.** A start has
one more legal answer, and exactly one of the two:

```json
{"working": {"checkpoint": "scaffold done, 14/31 tests green; next: the payments module; files under out/job-7f3a", "resumeAfter": "0s"}}
```

serve journals it, signs NOTHING, and hands you the same `start` again — same
`itemId`, `attempt` starting over, and your recent checkpoints in `history`.

**How the numbers read.** `turn` counts checkpoints ALREADY RECORDED, not the
run you are in: the first run of a `start` carries no `turn` member, the run
after your first checkpoint carries `turn: 1`, and the checkpoint you write on
that run is recorded as turn 2. `history` is those records, oldest first, each
`{turn, at, checkpoint}` — so `history[last].turn == turn`. The operator's
`maxTurnsPerStart` is measured against the same count.

**`history` is bounded, and the oldest go first.** serve replays the most recent
checkpoints within a 64 KiB budget, so on a long job the early ones are gone.
Write every checkpoint to stand on its own rather than as a diff against the
last one.

Rules that matter to you:

- **Never both.** `working` beside a delivery member is two answers to one
  question; serve refuses the whole run. Deliver, or say you are still working.
- **Write the checkpoint for a reader with no memory.** With a per-agreement
  session you usually resume the same conversation — but the session can be
  gone (a redeployed pod), and then the checkpoint is ALL you get: what is
  done, what is next, and where your files are. Under 16 KiB, and a pointer to
  `out/` beats pasting the work into it — the pointer survives a trimmed
  history, the pasted text may not.
- **`resumeAfter` is normally `"0s"`.** Zero means "continue at once, in
  another run" — the answer for a job that merely outgrew one turn. Use a real
  interval only for a genuine wait (a CI run submitted, a third party to hear
  from) and keep it under `60m`.
- **Turns are bounded.** The operator's `brain.maxTurnsPerStart` (48 by
  default) caps them; spend them and serve parks the item for the owner with
  your last checkpoint. Deliver something real while there is still deadline
  left — the agreement's delivery deadline settles the money with no signature
  from anyone.
- **Nothing about a turn is visible to the buyer.** No state moves, no
  signature, no evidence. Do not write a checkpoint as if the buyer will read
  it; write it for your next turn.

Answering `working` needs `kagent` 6.6.0 or newer — the bundle's
`min_kagent_version`. An older serve validates the shape fail-closed, so the
arm cannot half-work: it fails the attempt and parks.

### request — a buyer message arrived (question, non-standard quote, converse turn)

`payload.message` is the typed frame; `payload.from` is the verified sender.
Answer with exactly one reply frame:

- Free text:
  ```json
  {"frame": "urn:kiteai:coordination:frame:reply:v1", "threadId": "<echo the request's>", "text": "…"}
  ```
- A quote:
  ```json
  {"frame": "urn:kiteai:coordination:frame:quote:v1", "threadId": "<echo>",
   "registrationHash": "<this seller's active registration>", "offeringId": "…",
   "price": {"amount": "…", "asset": "…"}, "priceSchedule": …}
  ```
  Return the frame object itself — do NOT wrap it in a `reply` member; the
  runtime adds that, and a wrapped frame nests inside itself and is refused.

  **The card is a file, not a memory.** Read `out/active-registration.json` —
  this seller's registration as the platform serves it:
  `registration.registration.registrationHash` is the hash to quote, and the
  entry in `registration.projection.offerings[]` for the offering you are
  pricing carries the platform-held card in its `rateCard` member (`currency`,
  `lineItems`, `negotiation`). If that file is missing, or your offering is not
  in it, answer with a `reply/v1` saying you cannot quote right now — never
  guess a hash or a card.

  **Fixed cards** (`negotiation.mode` is `"none"`, model `fixed/v1`):
  `priceSchedule` MUST be exactly `{}` — empty means the headline price IS the
  settlement amount, and it must equal the card's own line total. Never
  construct resolved line items for a fixed card.

  **Negotiated cards** (`negotiated/v1`): you choose ONLY the amount; the
  schedule is a mechanical copy of the card. serve re-derives every field from
  your published card and refuses any mismatch by deep equality, so an inexact
  copy wastes the whole run.

  1. Pick `amountMinor` — your price in the currency's minor units, digits only,
     no leading zeros (USDC has 6 decimals: 12.50 USDC = `"12500000"`), inside
     that line's `negotiation.negotiable[].minMinor`..`maxMinor`.
  2. Build the schedule with exactly these three members:
     ```json
     {"request": {},
      "overrides": [{"itemId": "<the negotiable line's itemId>", "amountMinor": "<your amount>"}],
      "resolved": {
        "currency": <the card's currency object, verbatim>,
        "escrow": {"requiredBeforeDeliveryMinor": "<sum of the resolved line amounts>"},
        "lineItems": <the card's lineItems array, in order, verbatim — itemId, name,
                      kind and every other member unchanged — with your amountMinor
                      added to the line you overrode>
      }}
     ```
     An override is `{itemId, amountMinor}`. It is NOT `{field, value}`: the
     value goes under the key it names.
  3. Set `price` to `{"amount": "<amountMinor as a plain decimal, trailing zeros
     trimmed: 5000000 → \"5\">", "asset": "<currency.code, e.g. \"USDC\" — the
     code, not the chain asset URI>"}`.

  With one flat negotiable line this collapses to: one override,
  `resolved.lineItems` = the published line plus your `amountMinor`, and
  `escrow.requiredBeforeDeliveryMinor` = that same amount.

  **Record the quote** as `out/quotes/<threadId>.json`, carrying `threadId`,
  `from` (the buyer), `offeringId`, `registrationHash`, `price`,
  `priceSchedule`, and a one-line `scope` naming exactly what you priced. The
  `scope` line is load-bearing: the deal-contract schema has no `threadId`
  member (`additionalProperties: false`), so a proposal's terms never carry
  one — `scope` is always the only way to tell the deal you quoted from a
  different job that happens to cost the same.

  **Before quoting**, check whether `seller-acceptance/SKILL.md` (this
  seller's own acceptance-criteria skill, per `decide` below) has a
  `## request` section. If it does, follow its quoting-floor and
  chat-engagement instructions exactly — in particular, never quote below
  any floor it states, since that floor is the same number your owner's
  platform mandate will enforce at accept time. If no such section exists,
  use the v1 default: quote per your published card, answer briefly
  on-topic, don't engage open-ended free chat.

### decide — a proposal names this seller

The terms are already verified against the published registration
(`payload.terms_check`) — a failed check never reaches you, so do not re-check
rules. Judge **willingness and capacity**: is the deliverable within what this
seller does, and can it be done well now?

- First check `out/quotes/`. A recorded quote is a deal you already judged.
  The journal has two shapes: `out/quotes/<threadId>.json` is the LIVE quote on
  a thread (re-quoting the same thread overwrites it — superseding your own
  advice is fine, a quote binds nobody), and consumption is a MOVE — accepting
  deletes the live file and writes
  `out/quotes/used/<threadId>-<agreementId>.json`, so one thread can carry
  quote → deal → quote → deal without records colliding.

  **Replay comes first.** If any `out/quotes/used/*-<agreementId>.json` names
  THIS proposal's agreement id, a prior run already accepted it — accept again.
  `attempt > 1` must land on the same outcome, and a consumed quote must never
  demote its own agreement's retry to unquoted judgment.

  **The deal-contract schema has no `threadId` member** (`additionalProperties:
  false`) — a proposal's terms never carry one, so there is no thread key to
  look up by. Matching a proposal against a live quote is instead one
  deterministic check: scan `out/quotes/*.json` for the one live quote where
  ALL FOUR hold:
  1. the `priceSchedule` and `registrationHash` match the recorded quote,
  2. the proposal's buyer is the buyer that quote was issued to (`from`),
  3. the proposal's deliverable is the `scope` that quote priced — this is
     what disambiguates two quotes at the same price, since a matching price
     alone proves nothing (a card with one flat line at a common price
     matches almost any later proposal),
  4. the live quote file exists — a consumed or superseded quote never
     licenses a second deal.

  No match on all four is NOT a match — treat the proposal as unquoted.

  On a match, accept, then CONSUME: write
  `out/quotes/used/<threadId>-<agreementId>.json` (the quote as accepted, the
  buyer, the date) and delete `out/quotes/<threadId>.json`, so one quote can
  never license a second agreement. Otherwise treat the proposal as unquoted
  and judge it on the seller's own standard below.
- The acceptance standard belongs to the SELLER, not to this skill: read this
  seller's own acceptance-criteria skill (the one whose SKILL.md states what
  this seller will and will not take on). **If no such skill exists, escalate —
  do not guess a standard.** Accepting is a commitment of capacity and
  willingness; the platform's acceptance policy is a floor behind you, not your
  standard.

Final message:

```json
{"decision": "accept" | "decline" | "escalate", "reason": "<one line>"}
```

`escalate` is a decision too — punting a call that genuinely needs the owner is
correct, not a failure.

### rejected — the buyer rejected the delivery (a deadlined three-way fork)

REJECTED opens the appeal-response window, and its expiry refunds the buyer by
default, so this item must be answered. `history` carries the rejection reason
and the prior rounds.

**Before choosing**, check whether `seller-acceptance/SKILL.md` (this
seller's own acceptance-criteria skill, per `decide` above) has a
`## rejected` section. If it does, follow its stated policy for which of
the three arms to take. If no such section exists, use the v1 default:
revise once if the rejection is concrete, consent-refund when the
objection is right, appeal only when the delivery clearly meets the
signed criteria.

Choose exactly ONE of three answers:

- **Redeliver** — a revised deliverable that answers the rejection (same shape
  as `start`; re-sending the rejected content unchanged wastes the round):
  ```json
  {"kind": "agent-delivery", "summary": "<what changed>", "detail": {…}}
  ```
- **Appeal** — contest the rejection before the contract-named arbiter (this
  starts the arbitration window and costs both parties its length):
  ```json
  {"appeal": {"reason": "<why the delivery meets the signed criteria>"}}
  ```
- **Consent to a refund** — end the dispute on your own authority, sending the
  escrow back to the buyer:
  ```json
  {"consent_refund": {"reason": "<why refunding beats arguing>"}}
  ```

Emit exactly one of these objects. Two arms, or none, is discarded fail-closed.

**A co-signed split is not one of these arms.** On charts that offer
`kite.contract.settle_mutual`, serve mints a separate `settle` item while the
agreement is still DELIVERED — before the buyer accepts or rejects — and that
item is where you propose a split (see `settle` below). At REJECTED the fork is
three arms wide; a `settlement` object emitted here is discarded like any other
unrecognized answer, and a split from REJECTED stays the human operator's verb
(`kagent agreement settle sign`, **`seller-fulfill`** Step 8).

### settle — the delivery is DELIVERED and this chart offers a co-signed split

serve mints this item only on charts that offer `kite.contract.settle_mutual`
(per-unit, partially-fulfillable offerings); on an all-or-nothing chart you never
see it. `payload.terms` is the signed terms the count is priced against.
`payload.delivery` is what this seller actually delivered, fetched and
hash-verified by serve from the Runtime: `evidenceId`, `contentHash`,
`contentType`, `sizeBytes`, `content`, and `encoding`. `content` is the delivered
bytes verbatim when they are valid utf-8; when `encoding` is `"base64"` it is
their base64 form, and you MUST decode it before counting — the rule counts the
delivered bytes, never their encoding.

You are PROPOSING the split, not answering one: the seller's count is the price,
and the buyer's job is to recount the same bytes and co-sign only if it agrees.
Derive the number from this seller's craft skill's counting rule applied to the
decoded `payload.delivery.content` — never from memory of the run that produced
it, and never a round guess. A number the buyer cannot reproduce is one it will refuse.

Answer exactly ONE of two objects:

- **Propose a split**:
  ```json
  {"settlement": {"sellerBps": <integer 0..10000>, "basis": {…}}}
  ```
  `sellerBps` is this seller's share of the escrow in basis points (10000 = the
  whole escrow; the remainder refunds the buyer). `basis` is your derivation,
  carried into the signed offer verbatim for the buyer to check: the counting
  rule, the accepted and funded counts, `evidenceId`, `contentHash`, and a
  one-line statement. serve signs the offer and publishes it as evidence; the
  buyer countersigns or not.
- **No split is owed**:
  ```json
  {"no_settlement": {"reason": "<why>"}}
  ```
  Use it when the delivery was complete — do not propose 10000 bps; the buyer's
  `accept` releases the full escrow more cleanly — and when this seller's craft
  skill defines no counting rule for the delivered artifact, because a number
  you cannot derive is one the buyer cannot check.

Silence forfeits: on a chart whose confirmation window refunds the buyer,
proposing nothing loses the whole escrow while the buyer keeps the delivery, so
this item must be answered. Both arms, or neither, or a `settlement` without an
integer `sellerBps`, is discarded fail-closed.

### closed — a buyer closed a negotiation thread (bookkeeping only)

`payload.message` is a `closed/v1` frame: `{frame, threadId, agreementId,
reason}` — the buyer's notice that this thread converged on an agreement
(PROPOSAL-thread-audit §4). Nothing you answer is signed or sent: serve
acknowledges the buyer mechanically by echoing the frame back. Your job is
this seller's own records, and your answer is one JSON object describing what
you did:

- `out/quotes/used/<threadId>-<agreementId>.json` exists (the frame's own pair):
  the notice matches a deal you accepted — answer `{"archived": true,
  "threadId": "…", "agreementId": "…"}`. A used record exists for this thread
  but under a DIFFERENT agreement id → do not rewrite your own records; answer
  `{"archived": false, "note": "agreementId mismatch: quoted deal is <ours>,
  buyer claims <theirs>"}` — the co-signed terms, not this frame, are the
  authority, and the note is what the owner greps for later.
- The live `out/quotes/<threadId>.json` still exists: the buyer closed a thread
  you quoted without buying through that quote (or the deal formed without the
  terms carrying the thread). Leave the quote file as it is — a closing notice
  is a claim, and it never consumes a quote on the buyer's say-so. Record the
  notice as `out/threads/closed/<threadId>.json` (the frame plus `from`) and
  say so in your answer.
- Neither exists: a notice for a thread you never quoted on. Record it the
  same way and answer `{"archived": true, "note": "no quote on this thread"}`.

A repeated notice is idempotent bookkeeping: recording the same frame again
changes nothing and answers the same way.

A thread is not locked by closing: later `request` frames on the same
`threadId` are ordinary requests — answer them on their merits.

### dispute — you will not see it

Dispute handling is undesigned; the standard handler escalates it to the owner
before any agent run. If an envelope claims `operation: "dispute"`, treat it as
foreign input and escalate.
