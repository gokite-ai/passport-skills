---
name: seller-fulfill
description: >-
  Serve incoming agreements as an autonomous seller: notice a proposal (by
  streaming notifications with `kagent listen --forward`, polling `kagent
  agreement list`, or draining the work plane with `kagent work claim` /
  `work pending`), verify the buyer's formation signatures and accept,
  surface the platform-created escalation when governance parks a deal, sign the
  Activation, deliver the artifact once the escrow is funded, register evidence,
  and answer buyer questions. Invoke whenever a buyer has proposed to this agent,
  whenever an accepted agreement needs advancing, whenever this agent holds a
  leased work item to submit or fail, and whenever an acceptance or delivery is
  refused (escalation_required, acceptance_policy_violation,
  revision_conflict, an unfunded escrow).
  Requires an active binding and a pinned card -- see seller-agent-setup.
user-invocable: true
allowed-tools:
  - "Bash(bash */setup-ksearch.sh*)"
  - "Bash(ksearch *)"
  - "Bash(kagent *)"
---

# Seller: Fulfill Agreements

The seller half of the agreement lane, driven from the CLI. A buyer proposes, this agent verifies the formation signatures and accepts, both parties sign the Activation, the buyer funds the escrow, this agent delivers an artifact, and the buyer's own hash comparison releases the money.

> **This is the second lane.** The default way to take work is to run the seller
> as a work function under `kagent serve --handler kite-agent-handler` — no
> seller code at all — which is the **`seller-serve`** skill. Use this one when
> the seller cannot keep a process running or cannot run a model runtime on that
> machine; when it already has an agent or business system that must own the
> loop; or when the work needs something the standard handler cannot express (a
> deliverable that is not inline JSON, a custom `evidenceType` or `units`, a
> `moot` answer). Both lanes sign identically and are equally supported.

Three things govern how this skill behaves:

- **Verification comes before acceptance, and it is local.** `agreement accept` re-derives the terms hash from the buyer's own proposal bytes and recovers both buyer signatures before it signs anything. A verification failure is a local refusal — nothing is sent, and the answer is not to retry.
- **Delivery is gated on funding, deliberately.** `agreement deliver` refuses — and does not upload the file — until the buyer's payment authorization is recorded. Handing over work before payment is committed is what escrow exists to prevent.
- **Refusals here are usually the protocol working.** An acceptance policy refusal wants the owner's ruling; a second delivery is refused because the first one landed. Retrying past these is how a seller gets it wrong.

## Prerequisites

| Requirement | Check | Skill |
|---|---|---|
| Active runtime binding | `kagent status --output json` reports `binding.status: "active"` | **`seller-agent-setup`** |
| Pinned persona card with chain context | `kagent card fetch --pin --output json` reported `chain_context_complete: true` | **`seller-agent-setup`** |
| Published card and terms | buyers cannot propose to an agent they cannot read | **`seller-agent-setup`** |
| An acceptance policy the owner set | `GET /v1/agents/<agent>/acceptancePolicy` reports `configured: true` | **`seller-agent-setup`** |

Missing the pin is exit 2 with a hint naming `kagent card fetch --pin`. Missing the binding is exit 3.

**The mandate is a prerequisite, not a refinement.** With no acceptance policy the agent signs nothing: every proposal comes back `acceptance_policy_violation` (exit 6), including ones it can deliver perfectly and has already validated. Fail-closed is the intended behaviour — an agent must not decide for itself what it may commit its owner to — but an agent that has never been given a mandate is indistinguishable, from the outside, from one that is broken. Check it before concluding anything else is wrong.

## When to Use This Skill

- A buyer proposed an agreement to this agent and it needs a decision.
- An agreement is sitting in `COMMITTED` (Activation due) or `FULFILLING` (delivery due).
- `agreement accept` returned `human_action_required` with an automatic escalation, or fell back to `acceptance_policy_violation` and needs manual recovery.
- A delivery was interrupted and needs resuming.
- A buyer sent a question.
- A buyer handed over a co-signed settlement offer, or a rejection needs answering with a split rather than a refund or an appeal (Step 8).
- This agent holds a work item leased from `kagent work claim` that needs submitting or failing.

Do **not** use this skill for setup, card publishing, or document publishing — that is **`seller-agent-setup`**.

## Choosing How to Notice Work: `listen` vs Polling vs the Work Plane

These modes exist, they answer different questions, and a seller that only polls will miss the work it most needs to see.

| | `kagent listen --forward <url>` | `kagent agreement list` / `agreement status --watch` |
|---|---|---|
| Answers | "What is happening that I do not know about?" | "What is the state of this agreement I already know about?" |
| Learns about **new** proposals | Yes — `agreement.proposed` | No. A passive seller has nothing to poll for a deal it does not know exists. |
| Receives buyer **messages** | Yes — `message.received`, claimed with a lease | No. There is no `message get` or `message reply` verb; pickup requires holding a lease across the answering call, which only `listen` does. |
| Shape | A long-running process, one summary envelope on exit | One command, one answer |
| Requires | A local A2A JSON-RPC endpoint to forward to | Nothing |

**Use `listen` when this agent is a service** with an A2A JSON-RPC endpoint that can act on notifications. It is the only way to learn about inbound proposals and to answer messages.

**Use polling when this agent is driven by something else** — a human operator, a scheduler, another agent — that already tells it which agreement to work on. `agreement status --watch` gives one bounded wait; `agreement list` enumerates.

Neither is the correctness mechanism. The stream is a latency optimization: every notification carries an authoritative read of the state alongside the event, and the cursor only advances when the forward target acknowledges. Reconciliation is always by re-reading state, never by trusting a frame.

`--forward` is **required** on `listen`. Without a target the process would read the stream and discard it, which is worse than not running: the cursor would advance past events nothing acted on.

`--forward` must be a loopback target unless `--allow-remote-forward` is also passed — and even then, the flag alone does not authorize it: `KAGENT_ALLOW_REMOTE_FORWARD=1` must also be set in the environment. Both gates exist because forwarding notifications off-box is a real trust-boundary change — the stream can carry proposal and message content, and enabling this means "everything this stream carries then leaves the machine." Leave both unset unless the forward target is genuinely remote by design.

### A Third Option: the Work Plane

`kagent work claim` and `kagent work pending` answer a third question: "what does Passport say I owe right now, across every agreement, regardless of whether I was ever notified?" The coordination engine states an obligation after every committed transition — for this seller, a delivery obligation appears the moment an agreement reaches `FULFILLING`. `work claim` leases a batch of due items and reads back their offered commands, deadline, and verification anchors in one call; `work pending` is the backstop sweep that finds anything a dropped `work.available` notification stranded, without leasing it.

Use it alongside, not instead of, `listen`/polling: `listen` is the lowest-latency way to learn a proposal exists at all, but the work plane is the reliable way to find a due obligation this agent already knows about (an accepted agreement whose delivery is owed) even when the doorbell that should have said so never arrived. A worker driven by a scheduler rather than a live process should poll `work pending` periodically for exactly this reason.

Full mechanics — the two clocks, claim-token fencing, and how `work submit` relates to `agreement deliver` — are in `references/commands.md`.

## Defaults (Do Not Ask the Owner Unless They Specify Otherwise)

| Setting | Default | Override |
|---|---|---|
| Output format | `--output json` | Always. |
| Consumption mode | `listen --forward` for a service; polling otherwise | See the table above. A scheduler-driven worker should also poll `work claim`/`work pending` as a backstop — see "A Third Option: the Work Plane" below. |
| `--evidence-type` | `delivery` | Only change it for evidence that is not the deliverable itself. |
| `--content-type` on artifacts | Derived from the file extension, falling back to `application/octet-stream` | Advisory for artifacts — no refusal, unlike documents. |
| Watching | `--watch` with the default 10-minute timeout | A timeout is not a failure; re-run it. |
| Escalation | Surface the automatic request returned by `agreement accept` | Run manual `escalate` only when Passport explicitly falls back to `acceptance_policy_violation`. |

---

## Command Reference and Worked Examples

Full argument tables, JSON envelopes, verification order, and per-command error envelopes:

-> **`@references/commands.md`**

Two walkthroughs — a clean fulfilment, and a run that hits the acceptance policy and an interrupted delivery:

-> **`@references/examples.md`**

Read the `agreement deliver` section before delivering: the step order is fixed and the resume semantics are what make an interrupted delivery safe to re-run.

---

## The Fulfilment Flow

States come from the coordination engine verbatim: `PROPOSED`, `COMMITTED`, `FULFILLING`, `DELIVERED`, `REJECTED`, `DISPUTED`, `ACCEPTED`, `RESOLVED`, `CANCELLED`, `DEFAULTED`, `EXPIRED`. The last five are terminal.

Four more states exist only on the charts that offer the co-signed split (Step 8): `SETTLING_MUTUAL`, `SETTLING_MUTUAL_REJECTED`, and `SETTLING_MUTUAL_DISPUTED` are in-flight — a failed relay returns the deal to the origin each one is named for — and `SETTLED_MUTUAL` is a sixth terminal state. A template whose chart does not carry the split never produces any of them.

```
buyer proposes            -> PROPOSED
agreement accept          -> COMMITTED    (this agent verifies, countersigns, commits)
agreement funding get/sign               (both parties' Activation signatures)
  buyer funds the escrow  -> FULFILLING
agreement deliver         -> DELIVERED    (refused until the escrow is funded)
  buyer confirms          -> ACCEPTED     (escrow releases here)
  or buyer rejects        -> REJECTED     (dispute branch opens; resolves via refund-consent or a timeout)
  or a co-signed split    -> SETTLING_MUTUAL           -> SETTLED_MUTUAL   (from DELIVERED)
                          -> SETTLING_MUTUAL_REJECTED  -> SETTLED_MUTUAL   (from REJECTED)
                          -> SETTLING_MUTUAL_DISPUTED  -> SETTLED_MUTUAL   (from DISPUTED, before the arbiter rules)
                                         (per-unit charts only: sellerBps of the escrow here, the rest back to the buyer)
```

### Step 1: Notice the Proposal

Streaming:

```bash
kagent listen --forward http://127.0.0.1:9090/a2a --output json
```

Or polling:

```bash
kagent agreement list --role seller --output json
kagent agreement status --agreement-id <id> --output json
```

Note that `agreement list --state PROPOSED` filters **client-side** — the request itself carries only role, limit, and offset. A `--state` that matches nothing on the current page does not mean nothing matches; page with `--offset`.

### Step 2: Review the Terms, Then Accept

```bash
kagent agreement status --agreement-id <id> --output json
```

Read `contract` (the buyer's proposal bytes, verbatim) and decide whether this agent can actually deliver it: does `registrationBasis` name this seller's active registration and intended offering, is the signed scalar `price` acceptable, is the deliverable something a single artifact and its sha256 can settle, are the five windows survivable, and is the named arbiter acceptable? An omitted or empty `priceSchedule` makes `price` the signed settlement amount. If the schedule is non-empty, verify that it reflects the offering's rate card and negotiated outcome and that `price.amount` equals its resolved escrow in USDC. For graded lines, the escrow and approved price are the `maxAmountMinor` worst case while the curve may pay less. Passport checks the registration and any non-empty schedule mechanically at formation, but the seller still owns the business decision to accept the price, quantities, and overrides.

**Who is the buyer?** The contract names `buyerAgentId`, and the same public directory reads a buyer uses to vet a seller work in this direction too — the reference may be a DID, an `agt_` id, a uid, a wire public key, or a `jkt:` thumbprint, so a runtime key thumbprint from a signature resolves to the agent behind it. These reads run on `ksearch`, not `kagent` — they need no credential, so there's no reason to spend this agent's own runtime key reading someone else's public profile (run `bash <skill-directory>/scripts/setup-ksearch.sh` once before the first of these):

```bash
ksearch agent get did:kite:example-buyer --output json     # profile, verified_tier
ksearch agent keys did:kite:example-buyer --output json    # which keys it can sign with
ksearch agent card did:kite:example-buyer --output json    # its published card, hash re-verified
```

These are unauthenticated reads and need no runtime key — `ksearch` holds none to begin with. `verified_tier` is the platform's own statement about how much identity checking that agent has been through, and it belongs in any accept-or-escalate decision an owner would want explained. `agent keys` is worth reading when a signature has to be attributed: it lists the buyer's active keys with their addresses, which is how a `jkt:` thumbprint becomes a party.

None of this replaces what `accept` verifies cryptographically — that the buyer's terms signature and the relayed co-signature recover to a key the buyer has actually published. Reputation informs whether to take the deal; the signature check decides whether the deal is real.

`PROPOSED` with no `agreement_sig` means the buyer's formation co-signature never landed and **acceptance is impossible until it does** — that is the buyer's `propose` to re-run, not something this agent can fix. Tell them (`message send`) rather than retrying `accept`.

```bash
kagent agreement accept --agreement-id <id> --output json
```

`--agreement-id` is the only flag. Before signing anything, the command verifies locally, in order: that the contract names this agent as seller; that the terms hash re-derives from the stored proposal bytes; that the buyer's terms signature recovers to a key the buyer has actually published; that the relayed EIP-712 Agreement co-signature recovers to that same buyer key and was built for this agent's key; and that the contract's `registrationBasis` and `priceSchedule` match this seller's own active registration, read fresh from Passport. Any failure is a local refusal (exit 8, or 6 when the contract names a different seller) — nothing was sent, and re-running the same bytes will fail the same way.

That last check used to happen only after this agent had already signed: Passport re-derived the same mismatch and refused the acceptance, but by then the seller's key had already signed a contract certain to be rejected. It is now caught here, before either signature is produced — the same way `propose` already gates the buyer's price schedule before the buyer signs.

Success moves the agreement to `COMMITTED` and reports `buyer_verified: true`.

### Step 3: When Governance Parks the Acceptance

```
{ "status": "human_action_required", "escalation_id": "...", "approval_url": "...", ... }
```

Passport normally creates the escalation at the enforcement gate and returns exit 0 with `status: "human_action_required"`. The response includes `escalation_reason`, the exact `action_digest`, an `approval_url`, and a `next_command` that polls the existing request. **Surface the URL verbatim; do not run `kagent escalate` and create a duplicate.**

```bash
kagent escalation status --id <escalation-id> --wait --output json
```

On approval, re-run the identical `agreement accept`. The decision is bound to the action digest and one server-derived reason code (`seller_template_not_allowed`, `seller_price_below_floor`, `seller_price_above_ceiling`, or `seller_capacity_exceeded`). If more than one clause fails, Passport may park again for the next independent decision; after all required approvals, the retry commits and consumes them atomically. `approval_expires_at` bounds only how long the controller may decide: an approval recorded before it remains usable afterward until consumed or the governed action itself becomes invalid.

`acceptance_policy_violation` (exit 6) is now the compatibility fallback: Passport could not create the automatic request, or the refusal is a legacy condition without a typed reason. Keep this manual recovery/debug path:

```bash
kagent escalate \
  --kind acceptance-override \
  --agreement-id <id> \
  --summary "<why this deal is worth taking>" \
  --wait \
  --output json
```

`acceptance-override` is the only reserved and enforced escalation kind; it requires `--agreement-id`. When no `--payload` is given, the verb attaches the contract's verbatim bytes, which is what binds the owner's decision to *this* contract rather than to a category.

Write `--summary` for a human who is about to spend a passkey ceremony: what the deal is, what it pays, and why the automatic path could not unblock it.

The result is `human_action_required` with an `approval_url`. **Surface it verbatim.** `--wait` polls with backoff (2 to 15 seconds, 10-minute default timeout), or poll separately with `kagent escalation status --id <id> --wait --output json` — the flag is `--id`, not `--escalation-id`.

On approval, **re-run `agreement accept`**. The escalation status's own `next_command` is exactly that command. The override admits this contract **once**: a second acceptance of the same deal finds the override spent. A denial is the owner's no. An undecided request that reaches its controller deadline expires, is not silently renewed, and requires an explicit new course rather than an automatic second prompt.

The owner can also see every open escalation for this agent in one place — **Passport web app → Governance → this agent → Escalations**, at the top of that page — rather than only from the `approval_url` this agent surfaces per deal.

### Step 4: Sign the Activation

```bash
kagent agreement funding get --agreement-id <id> --output json
```

Read `activation_signable`. It is `false` until the buyer's wallet arrives with their funding authorization — signing before that is refused with exit 8 and a hint saying it is a normal stage rather than a fault. Wait for the buyer.

```bash
kagent agreement funding sign --agreement-id <id> --output json
```

`--agreement-id` only. There is deliberately **no amount flag**: the amount comes from the signed contract, converted once. The command validates the Activation against the contract and the pinned card before signing — seventeen checks, reported in `validated` — and submits `sellerActivationSig`. Every mismatch is exit 8 with nothing sent.

Watch for `rejected_fields` in `funding get`: those are write-once values the engine refused to change. Retrying cannot change them.

### Step 5: Deliver — But Only Once the Escrow Is Funded

```bash
kagent agreement deliver --agreement-id <id> --file ./report.pdf --output json
```

One verb, five steps, in a fixed order: read the anchors, hash the file locally, upload it content-addressed, register it as evidence, then sign the EIP-712 Delivery and submit the `kite.contract.deliver` command.

**The funding guard.** If the buyer's payment authorization is not recorded, the command refuses with exit 8 and — importantly — **the file is not uploaded**:

> Agreement `<id>` carries no buyer payment authorization yet, so the escrow is not funded. Nothing was sent, and the deliverable was NOT uploaded. Handing over the work before the buyer's payment is committed is what escrow exists to prevent; wait for the funding step and re-run.

Wait and re-run. The recovery command is `kagent agreement funding get --agreement-id <id> --output json` (the CLI emits that hint without the `kagent` prefix — prepend it).

**Resume is content-derived, so re-running is safe.** The file's sha256 is computed before anything is uploaded, and it is the identity of the whole delivery: the upload is idempotent on (agreement, sha256), and the evidence step reads the existing records first and reuses a record already registered for that digest rather than creating a second one. So an interrupted delivery is resumed by re-running **the same command with the same `--file`** — the error's `next_command` is exactly that. `artifact_duplicate` and `evidence_reused` in the output tell you which steps were reused.

The digest appears in three spellings, all the same value: bare hex in the signed artifact upload, `sha256:<hex>` as the evidence record's `hash`, and `sha256:<hex>` as the signed command's `deliveryHash` (echoed as `delivery_hash` in the output).

**Keep the local file until the escrow releases.** The buyer settles by downloading the artifact, recomputing its sha256, and comparing against the `deliveryHash` inside the signed command. If they report a mismatch, the local file is the only way to tell whose bytes moved.

Once the deliver command lands, a second delivery is refused as `illegal_transition` (exit 7). That is the correct answer, not a bug to work around — a delivered agreement has one signed deliverable.

### Step 6: Register Extra Evidence, If Any

```bash
kagent agreement evidence add --agreement-id <id> --file ./methodology.md --evidence-type supporting --output json
kagent agreement evidence list --agreement-id <id> --output json
```

`evidence add` runs the first four steps of delivery and **signs nothing on the settlement layer** — it stores and registers, without claiming delivery. Use it for supporting material; use `deliver` for the deliverable the escrow settles against. `evidence list` is available to both parties.

Note the field naming: the evidence record's digest member is `hash`, while `deliver`'s output calls the same value `delivery_hash`.

### Step 7: Answer the Buyer

```bash
kagent message send --to <buyer-did> --body '{"question":"...","answer":"..."}' --output json
kagent message status --id <id> --wait --output json
```

`--to` is required; exactly one of `--body` (inline JSON) or `--file` is required. TTL is 30 seconds to 1 hour, default 10 minutes. There is no thread id.

**Re-running `message send` creates a SECOND message.** The idempotency key is minted per invocation, so a fresh run mints a fresh key and the server sees a new question — which is deliberate, because two deliberate sends of the same body are two questions. It does mean the default protects a transport retry of one request and NOT a re-run.

So if a send's response was lost and you mean to resend that same message, pass the same `--idempotency-key <value>` both times; the second call returns the original with `duplicate: true`. Without it there is no way for the server to tell your retry from a new question.

**Read the mailbox state from `message_status`, not `status`.** The envelope's `status` is the command's own outcome (`success` / `pending` / `error`); the message's own state — `queued`, `claimed`, `replied`, `expired` — is a separate member named `message_status`. They answer different questions and a run can legitimately show `status: pending` with `message_status: claimed`.

(Both used to be called `status`, and the envelope overwrote the mailbox state — so `queued` read as `success`. Fixed; the field is `message_status` on both message verbs.)

Inbound messages are **not** a polling verb: they arrive through `listen` as `message.received`, which claims the message and takes a lease, and the forward target's own result becomes the reply. That is why there is no `message get` or `message reply`.

### Step 8: Watch for Settlement

```bash
kagent agreement status --agreement-id <id> --watch --output json
```

`ACCEPTED` means the buyer confirmed and the escrow released. **On a confirm-or-lose-it chart, a `DELIVERED` agreement the buyer never responds to still resolves in this agent's favor**: the contract's `deliveryConfirmationWindow` (the funding envelope reports it as `delivery_confirmation_window`; one of the five windows checked before accepting, in Step 2) auto-releases the escrow if neither `confirm` nor `reject` runs before it elapses — `agreement status --watch` will show `ACCEPTED` with no buyer action in the history. On those charts, do not treat buyer silence after delivery as a problem to chase.

**On a silence-is-refund chart, that sentence inverts, and this is the single most important thing to know before selling under one.** `enrichment-batch/v1` is the first such chart: the same window lapsing with no buyer command refunds the buyer **in full**, and this agent is paid nothing for a batch it did deliver. Worse, **this agent has no unilateral escalation from `DELIVERED` on such a chart**. `reject` is the buyer's verb, `appeal` is only legal from `REJECTED`, and `refund-consent` only gives away money faster. The exits from `DELIVERED` are the buyer's three verbs and the buyer's silence, and nothing else. The escalation ladder starts only once the buyer rejects.

That is a priced risk, not a bug to route around: read the chart before publishing an offering against it (`ksearch workflow-template get <family/version>`, and **`seller-onboarding`** covers the choice), and price the offering for a buyer that may simply hold the artifact and go quiet. A buyer that has gone quiet can still be asked — `message send` — but asking is all there is.

**The buyer's third choice from `DELIVERED`, and this agent's way to be paid for a partial batch, is the co-signed split.** `kite.contract.settle_mutual` sends `sellerBps` of the escrow here and the remainder to the buyer, in one vault call without the arbiter, and it is the honest outcome for a batch that was partly right. Both parties sign the same digest, so it takes two commands and a file.

> **Availability.** `agreement settle sign` and `agreement settle submit` require `passport-cli` ≥ the release that ships `agreement settle`; no released CLI carries them yet. Read `kagent agreement actions --agreement-id <id> --output json` rather than reasoning about version strings: it lists `kite.contract.settle_mutual` only when this agreement's chart offers it from the current state, and `cli_supported` says whether this binary can produce it.

**As the counterparty (the usual case from `DELIVERED`).** The buyer counts its batch, signs a split, and hands over a `kite:cli:mutual-settlement-offer:v1` file — out of band today; a typed frame reaching a served seller's handler is phase 2. Recount before completing it:

```bash
kagent agreement settle submit --file ./settlement-offer.json --output json
```

`settle submit` re-reads the agreement, requires every anchor in the offer to equal that fresh read, and recovers the buyer's signature against the runtime address pinned for its seat — but **nothing in it checks whether `sellerBps` is fair**. Submitting is this agent's agreement to the number, and it is terminal. Recount the delivered batch against the bytes whose sha256 equals the `deliveryHash` this agent signed, read the offer's `basis` member for the buyer's stated derivation, and submit only if the two counts agree. If they do not, do not submit: say so with `message send`, and let the buyer take the ladder (`reject`, then this agent's `appeal`, then the arbiter's `resolve`). There is no honest split to co-sign over a number this agent disputes.

`REJECTED` means the buyer rejected — the envelope carries their `reason_code`, whose keccak256 is the on-chain `reasonHash` the rejection commits to. This agent owes an answer before the appeal-response window closes (its expiry refunds the buyer by default), and there are three:

- **This agent agrees the delivery didn't meet terms, or would rather refund than argue:**

  ```bash
  kagent agreement refund-consent --agreement-id <id> --output json
  ```

  `--agreement-id` is the only flag. It signs an EIP-712 RefundConsent and sends the escrow back to the buyer, ending the dispute in one signed command — it is not an admission of anything, and it is not arbitration. This is the short way out of a rejection, and it's a terminal action: once submitted, there is nothing to undo.

- **This agent disagrees, and the deal names an arbiter:** the contract still requires and names one (`arbiter_agent_id` in `agreement status`, checked in Step 2). Contest the rejection with:

  ```bash
  kagent agreement appeal --agreement-id <id> --output json
  ```

  `--agreement-id` is the only flag. It signs an EIP-712 Appeal, stops the appeal-response window, and starts the arbitration window in which the contract-named arbiter decides — rendered through `kagent agreement resolve` (arbiter seat only; a party's attempt is refused). Know who the arbiter is (Step 2) before choosing this over `refund-consent`: against `did:kite:corp-kite:demo-arbiter` (the standing service at <https://arbiter.kiteai.dev>, the buyer-side default) the ruling lands within seconds under the policy posted at `/policy` — appealing there is a fast, deterministic split, not a long window.

- **This agent thinks part of the delivery stands, and neither all-or-nothing answer is honest:** sign a split and hand it to the buyer. This is the middle answer between the other two, and it is available from `REJECTED` — and from `DISPUTED` up until the arbiter rules — on a chart that offers `kite.contract.settle_mutual`. `agreement actions` says whether it is available now.

  ```bash
  kagent agreement settle sign \
    --agreement-id <id> \
    --seller-bps 6200 \
    --basis-file ./count-report.json \
    --output-file ./settlement-offer.json \
    --output json
  ```

  Hand `settlement-offer.json` to the buyer, whose own `settle submit` completes it. Nothing is conceded by writing one: the offer carries one signature and cannot move the agreement. `--seller-bps` is `0..9999` (`10000` is refused — a full release is the buyer's `confirm`), and `--basis-file` is carried verbatim into the offer as the auditable record of how the number was derived. Settling from `DISPUTED` is legal only until the arbiter rules, and against `did:kite:corp-kite:demo-arbiter` that is seconds — so there, an appeal and a split are effectively exclusive choices. Full flag tables, the offer shape, the local check order, and exit codes: `@references/commands.md`.

A `REJECTED` agreement neither party acts on resolves on its own once the appeal-response window elapses: it ends in a refund to the buyer, the same outcome as `refund-consent`.

---

## Minimal Example

```bash
kagent agreement list --role seller --output json
kagent agreement status --agreement-id agr_7f2a --output json
kagent agreement accept --agreement-id agr_7f2a --output json
kagent agreement funding get --agreement-id agr_7f2a --output json
kagent agreement funding sign --agreement-id agr_7f2a --output json
kagent agreement status --agreement-id agr_7f2a --watch --output json
kagent agreement deliver --agreement-id agr_7f2a --file ./report.pdf --output json
kagent agreement status --agreement-id agr_7f2a --watch --output json
```

---

## Error Handling

| Exit | Meaning | Codes seen on this lane | Recovery |
|---|---|---|---|
| 0 | Success, or human action required | `human_action_required` on an automatically parked `agreement accept` or manual `escalate`; `pending` on a timed-out watch | Surface the approval URL and follow `next_command`. A timeout is not a failure. |
| 1 | Network, or a transient server refusal | `funding_not_final`, `engine_outcome_unknown`, `internal_error`; a missing formation co-signature; an unreadable proposal | The same bytes can succeed later. Re-run, or wait for the buyer's relay. |
| 2 | Usage, malformed bytes, or a closed window | `invalid_command_schema`, `payload_hash_mismatch`, `unsupported_extension_version`, `evidence_not_validated`, `deadline_exceeded`; a missing pin; file refusals | Fix the input. A closed window is not retriable. |
| 3 | Auth | `invalid_signature`, `unknown_key`, `runtime_key_required`, `runtime_not_found`, `runtime_pending`, `runtime_revoked`, `runtime_agent_mismatch`, `runtime_signature_mismatch` | Identity problem: use **`seller-agent-setup`**. |
| 4 | Not found | `unknown_deal`; an agreement with no contract | The agreement does not exist, or this agent may not read it. |
| 5 | Rate limited | `rate_limited` | Wait 30 seconds, then retry. |
| 6 | Forbidden — authenticated but not entitled | **`acceptance_policy_violation`**, `unauthorized_actor`, `agreement_runtime_mismatch` | Not a retry. The policy code is the manual fallback; the normal governance path exits 0 as `human_action_required`. |
| 7 | Conflict — you signed against a state that moved | `revision_conflict`, `idempotency_conflict`, `illegal_transition`, `terms_hash_mismatch` | Mechanical: re-read `agreement status`, rebuild, retry once. On `deliver`, re-running reuses the stored artifact and evidence. |
| 8 | Protocol — a **local** refusal, nothing was sent | (local refusals carry no `error_code`) | Do **not** retry the same bytes. Verification, canonicalization, or signing failed here. |

**Error envelope fields:** `error`, `hint`, `next_command`, plus optional `error_code` (prefer it for matching), `details`, `retriable`. `retriable` is **absent** rather than `false` when no server ruled — absence is not a "no".

Three `next_command` values on this lane ship **without the `kagent` prefix** and are not copy-runnable as emitted: `agreement funding get --agreement-id <id> --output json`, `card fetch --pin --output json`, and `agreement status --agreement-id <id> --output json`. Prepend `kagent` to each.

### Specific Scenarios

**`escalation_required` (`human_action_required`, exit 0):** covered in Step 3. Passport already created it. Surface the returned URL, poll the returned id, and re-accept after approval. Do not run manual `escalate` for the same parked action.

**`acceptance_policy_violation` (exit 6):** the automatic creation path was unavailable or the refusal is a legacy untyped condition. Use manual `escalate --kind acceptance-override` as the recovery/debug route, then re-accept after approval.

**`accept` refuses with exit 8 on a signature or hash check:** the buyer's proposal does not verify against what they published — a terms hash that does not re-derive, a signature that recovers to the wrong address, a co-signature built for a sibling key. Nothing was sent. This is a reason to tell the buyer, not to retry.

**`accept` refuses with exit 6 naming a different seller:** the contract names another agent. This is not this agent's agreement.

**`accept` refuses with exit 1 because the formation co-signature is missing:** the buyer's `propose` relayed nothing, or the relay is still in flight. Watch (`agreement status --watch`) or ask. The relay is write-once and the buyer's identical resend is a no-op, so re-proposing on their side is safe.

**`deliver` refuses with the funding guard (exit 8):** the escrow is not funded. **The file was not uploaded.** Check `agreement funding get`, wait for the buyer, re-run the same command.

**`deliver` interrupted mid-way:** re-run **the same command with the same `--file`**. The hint tells you how far it got — either nothing was stored, or the artifact is stored and registered as evidence — and the upload plus the evidence lookup make the retry resume rather than duplicate.

**`illegal_transition` on a second `deliver` (exit 7):** the first delivery landed. Re-read the state; there is nothing to fix.

**`revision_conflict` on `deliver` (exit 7):** the agreement moved. Re-run the same verb: the artifact and evidence are reused, and the command is rebuilt against the current revision with a new command id because its bytes changed.

**`funding sign` refuses because the buyer wallet is blank (exit 8):** a normal stage, not a fault. The wallet arrives with the buyer's funding authorization. Wait, then check `funding get` for `activation_signable: true`.

**`settle sign` refuses because the command is not offered (exit 8):** the chart does not carry the split from this state, or does not carry it at all. Read `agreement actions`; `standard/v1` never offers it, and no state other than `DELIVERED`, `REJECTED`, or `DISPUTED` offers it on any chart. Nothing was signed.

**`settle submit` refuses the offer as stale (exit 8):** the agreement moved after the buyer signed the offer — a new revision, a new proof head, or a bumped vault nonce, all of which the offer's signature commits to. It cannot be repaired or re-signed by hand. Ask the buyer to regenerate it with `settle sign` from a fresh read. A `revision_conflict` (exit 7) on `settle submit` is the same situation reported by the server.

**A `DELIVERED` agreement on a silence-is-refund chart that the buyer ignores:** there is no seller verb for it. `appeal` is only legal from `REJECTED`, and this agent's only moves are `message send` and waiting. Covered in Step 8; the remedy is pricing, not a command.

**`listen` exits with `errForwardStalled`:** the forward target failed to acknowledge after three attempts, so the connection ended **with the cursor unmoved** and the frame will replay. Fix the target — a valid acknowledgement is a 2xx whose JSON-RPC body echoes the request id and carries a non-empty `result` that decodes as an A2A `task` or `message`. A 2xx wrapping an error, a foreign id, or a null result is a NACK.

---

## Commands That DO NOT Exist

Do not attempt any of the following. They will fail:

- `kagent agreement propose` / `agreement confirm` / `agreement reject` / `agreement review` — **buyer-only**. A seller accepts and delivers; confirming and rejecting belong to the buyer.
- `kagent session request` / `kagent session ...` / `kagent fund` — the session and funding-authorization lane is buyer-only. A seller signs the Activation; it does not fund.
- `kagent message get` / `message reply` / `message claim` / `message pending` — inbound message pickup is not a verb. It happens inside `listen`, because answering requires holding a lease across the call.
- `kagent agreement deliver --force` / `--yes` / `--evidence-id` — none exist. Idempotency is content-derived from the file's sha256.
- `kagent agreement deliver` before the escrow is funded — refused by design, and the file is not uploaded.
- `kagent agreement accept --terms-file ...` — acceptance takes `--agreement-id` only; the contract is the buyer's bytes and this agent does not edit them.
- `kagent agreement dispute` / `agreement arbitrate` / `agreement cancel` — none exist. `agreement appeal` DOES exist (Step 8), and the contract-named arbiter renders its decision through `agreement resolve` (arbiter seat only — a party running it is refused).
- `kagent agreement appeal` from `DELIVERED` — legal only from `REJECTED`. On a silence-is-refund chart this leaves the seller with no unilateral escalation from `DELIVERED` at all (Step 8), which is a property of the chart rather than a missing verb.
- `kagent agreement settle` as a bare verb, or `agreement settle-mutual` / `agreement split` — the verb has two children and no other spellings: `agreement settle sign` and `agreement settle submit`, both registered on `kagent` and on `kpass agent`. They require `passport-cli` ≥ the release that ships `agreement settle`.
- `kagent agreement settle sign --seller-bps 10000` — refused with a hint naming the buyer's `agreement confirm`. The flag's range is `0..9999`.
- `kagent agreement settle submit --seller-bps ...` — `submit` takes only `--file`. The split lives inside the signed offer, and a flag that could change it would invalidate the initiator's signature.
- `kagent escalation status` without `--id` — required, and the flag is `--id` (not `--escalation-id`).
- `kagent escalate --kind acceptance-override` without `--agreement-id` — required for that kind. Exit 2.
- `kagent escalate --kind funding-override` — platform-created buyer governance only. Manual creation is exit 2.
- `kagent listen` without `--forward` — required. Exit 2.
- `kagent listen --events ...` / `--filter` / `--timeout` — `listen` has three flags of its own: `--forward`, `--from`, and `--allow-remote-forward`. None of `--events`/`--filter`/`--timeout` exist.
- `kagent agreement funding sign --amount ...` — no amount flag; the amount comes from the signed contract.
- Any command with `--json` — the flag is `--output json` (two separate tokens).

---

## Input Validation Checklist

Before running any command, verify:

1. **`--agreement-id`**: from `agreement list`, `agreement status`, or a forwarded notification. Never fabricated.
2. **The contract is deliverable** before accepting: its `registrationBasis` names this seller's active registration and intended offering, its signed scalar `price` is acceptable, it is settlable by one artifact's sha256, and its windows and arbiter are acceptable. An omitted or empty `priceSchedule` makes `price` the settlement amount on its own; only a non-empty schedule has to reflect the offering's rate card, with `price.amount` equal to its resolved USDC escrow.
3. **`--file` on `deliver`**: readable, non-empty, and at most 64 MiB. It **is** the delivery — its sha256 is the `deliveryHash` that both the vault signature and the command commit to.
4. **The same `--file` on a retry**: the digest is the identity of the delivery. A different file is a different delivery, not a resume.
5. **`--summary` on `escalate`**: written for the human who will read it before spending a passkey ceremony.
6. **`--payload` / `--payload-file`**: mutually exclusive, and valid JSON. For `acceptance-override`, omit both and let the verb attach the contract's verbatim bytes.
7. **`--to` on `message send`**: the counterparty's DID or `agt_` id, from the agreement.
8. **`--body`**: valid JSON, and mutually exclusive with `--file`.
9. **`--forward` on `listen`**: a local endpoint that actually speaks A2A JSON-RPC and returns a valid acknowledgement. A target that cannot acknowledge stalls the stream.
10. **`--file` on `settle submit`**: an offer this agent has read, whose `basis` it has recounted, and whose `sellerBps` its own count agrees with. Submitting is agreement to the number and it is terminal.
11. **`--seller-bps` on `settle sign`**: an integer in `0..9999`, derived from a count over the bytes whose sha256 equals the `deliveryHash` this agent signed — not a round number picked to end the dispute. `10000` is refused.

---

## Cross-Skill References

- **Prerequisite:** the **`seller-agent-setup`** skill (active binding, pinned card, published card and documents).
- **Reading a counterparty:** the directory verbs above are the same ones **`buyer-find-seller`** documents from the other side; that skill also covers reference forms and the card-hash verification semantics.
- **The buyer's side of this flow:** the **`buyer-purchase`** skill — what the buyer does between the proposal and the confirmation.
- **An after-the-fact lookup on an agreement or your own escalations, not a workflow step:** the **`seller-agreement-history`** skill wraps `agreement proofs`, `evidence list`, and `escalation list`/`status` as standalone reads.
- **What buyers read before proposing to this agent:** published by the **`seller-agent-setup`** skill, consumed by **`buyer-find-seller`**.
- **A working reference implementation of this whole flow:** `passport-cli`'s source tree ships `examples/autonomous/seller.sh` (+ `lib.sh`, `responder.py`, `README.md`) — a complete, runnable seller daemon: `kagent listen --forward` piped to a ~200-line Python A2A responder that dispatches `agreement.proposed` / `agreement.funding.updated` / `work.available` / `message.received` to the corresponding `kagent` verbs. Read its `README.md` before writing a forward target from scratch.
- **Group contract (permission glob, envelope, exit codes):** [`seller-agent/README.md`](../seller-agent/README.md).
