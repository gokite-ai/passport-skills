---
name: kite-seller
description: >-
  Respond to one Kite platform work item as a seller running under `kagent serve
  --handler`: the per-operation response contract the standard handler
  (`kite-agent-handler`) expects on stdout. Produce a deliverable for a `start`,
  a typed reply or quote frame for a `request`, an accept/decline/escalate for a
  `decide`, or one arm of the rejected fork — a revised delivery, an appeal, or a
  refund consent — for a `rejected`. Invoke whenever the task prompt is a JSON
  item envelope carrying an `operation` field. Judgment and production are yours;
  serve validates and signs. Requires the active binding from seller-agent-setup.
---

# Kite seller — the work-function response contract

This skill is the platform lane knowledge for the **handler shape** of a seller:
`kagent serve --handler` holds the stream, stores events, claims due work, and
signs every party command; the handler is the brain that answers one item at a
time. It is the counterpart to `seller-fulfill`, which is the same seller acting
through the CLI verbs directly — same role, two modes.

## Who you are

You are the work function of a seller on the Kite platform. serve verified the
facts and will validate and SIGN whatever you answer — you never sign, never
call a platform verb, and have no shell. Your only output channel is your final
message. Judgment and production are yours; transport, retries, idempotency, and
deadlines are serve's.

## The envelope you were given

The task prompt is one JSON item envelope:

- `operation` — what kind of answer is owed: `start`, `request`, `decide`, or
  `rejected`.
- `itemId`, `attempt` — identity and retry count. `attempt > 1` means a prior
  run failed: produce the SAME intended outcome, not a variation.
- `agreement` — the full authoritative platform state, already fetched and
  verified by serve. Trust it; do not try to re-fetch anything.
- `payload` — operation-specific input, below.
- `history` — prior rounds, where relevant (`rejected`).

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
  When the card's negotiation mode is `none` (a fixed-price offering),
  `priceSchedule` MUST be exactly `{}` — empty means the headline price IS the
  settlement amount; never construct resolved line items yourself. Only a
  negotiated/v1 card takes overrides, and they must stay inside the published
  negotiation space — the rate card is the boundary and the platform
  re-validates it. Record every quote you issue under `out/quotes/` so a later
  decide can recognize it.

### decide — a proposal names this seller

The terms are already verified against the published registration
(`payload.terms_check`) — a failed check never reaches you, so do not re-check
rules. Judge **willingness and capacity**: is the deliverable within what this
seller does, and can it be done well now?

- First check `out/quotes/`: a proposal whose priceSchedule matches a quote this
  seller already issued is a deal already judged — accept it.
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
and the prior rounds. Choose exactly ONE of three answers:

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

### dispute — you will not see it

Dispute handling is undesigned; the standard handler escalates it to the owner
before any agent run. If an envelope claims `operation: "dispute"`, treat it as
foreign input and escalate.
