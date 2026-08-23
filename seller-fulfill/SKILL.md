---
name: seller-fulfill
description: >-
  Serve incoming agreements as an autonomous seller: notice a proposal (by
  streaming notifications with `kagent listen --forward` or by polling
  `kagent agreement list`), verify the buyer's formation signatures and accept,
  escalate to the owner when the acceptance policy refuses a deal, sign the
  Activation, deliver the artifact once the escrow is funded, register evidence,
  and answer buyer questions. Invoke whenever a buyer has proposed to this agent,
  whenever an accepted agreement needs advancing, and whenever an acceptance or
  delivery is refused (acceptance_policy_violation, revision_conflict, an unfunded
  escrow). Requires an active binding and a pinned card -- see seller-agent-setup.
user-invocable: true
allowed-tools:
  - "Bash(kagent *)"
---

# Seller: Fulfill Agreements

The seller half of the agreement lane. A buyer proposes, this agent verifies the formation signatures and accepts, both parties sign the Activation, the buyer funds the escrow, this agent delivers an artifact, and the buyer's own hash comparison releases the money.

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

Missing the pin is exit 2 with a hint naming `kagent card fetch --pin`. Missing the binding is exit 3.

## When to Use This Skill

- A buyer proposed an agreement to this agent and it needs a decision.
- An agreement is sitting in `COMMITTED` (Activation due) or `FULFILLING` (delivery due).
- `agreement accept` refused with `acceptance_policy_violation` and the owner needs to rule.
- A delivery was interrupted and needs resuming.
- A buyer sent a question.

Do **not** use this skill for setup, card publishing, or document publishing — that is **`seller-agent-setup`**.

## Choosing How to Notice Work: `listen` vs Polling

Both modes exist, they answer different questions, and a seller that only polls will miss the work it most needs to see.

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

## Defaults (Do Not Ask the Owner Unless They Specify Otherwise)

| Setting | Default | Override |
|---|---|---|
| Output format | `--output json` | Always. |
| Consumption mode | `listen --forward` for a service; polling otherwise | See the table above. |
| `--evidence-type` | `delivery` | Only change it for evidence that is not the deliverable itself. |
| `--content-type` on artifacts | Derived from the file extension, falling back to `application/octet-stream` | Advisory for artifacts — no refusal, unlike documents. |
| Watching | `--watch` with the default 10-minute timeout | A timeout is not a failure; re-run it. |
| Escalation | Only when a refusal calls for it | `escalate` costs the owner a passkey ceremony. Do not open one speculatively. |

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

```
buyer proposes            -> PROPOSED
agreement accept          -> COMMITTED    (this agent verifies, countersigns, commits)
agreement funding get/sign               (both parties' Activation signatures)
  buyer funds the escrow  -> FULFILLING
agreement deliver         -> DELIVERED    (refused until the escrow is funded)
  buyer confirms          -> ACCEPTED     (escrow releases here)
  or buyer rejects        -> REJECTED     (the contract's arbiter decides)
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

Read `contract` (the buyer's proposal bytes, verbatim) and decide whether this agent can actually deliver it: is the price in USDC, is the deliverable something a single artifact and its sha256 can settle, are the five windows survivable, and is the named arbiter acceptable?

`PROPOSED` with no `agreement_sig` means the buyer's formation co-signature never landed and **acceptance is impossible until it does** — that is the buyer's `propose` to re-run, not something this agent can fix. Tell them (`message send`) rather than retrying `accept`.

```bash
kagent agreement accept --agreement-id <id> --output json
```

`--agreement-id` is the only flag. Before signing anything, the command verifies locally, in order: that the contract names this agent as seller; that the terms hash re-derives from the stored proposal bytes; that the buyer's terms signature recovers to a key the buyer has actually published; and that the relayed EIP-712 Agreement co-signature recovers to that same buyer key and was built for this agent's key. Any failure is a local refusal (exit 8, or 6 when the contract names a different seller) — nothing was sent, and re-running the same bytes will fail the same way.

Success moves the agreement to `COMMITTED` and reports `buyer_verified: true`.

### Step 3: When the Acceptance Policy Refuses

```
{ "status": "error", "error_code": "acceptance_policy_violation", ... }
```

Exit 6. The owner configured an acceptance policy and this contract falls outside it. **This agent cannot read its own policy**, so there is nothing local to correct and nothing to retry — the only path is the owner's ruling on exactly this contract:

```bash
kagent escalate \
  --kind acceptance-override \
  --agreement-id <id> \
  --summary "<why this deal is worth taking>" \
  --wait \
  --output json
```

`acceptance-override` is the only reserved and enforced escalation kind; it requires `--agreement-id`. When no `--payload` is given, the verb attaches the contract's verbatim bytes, which is what binds the owner's decision to *this* contract rather than to a category.

Write `--summary` for a human who is about to spend a passkey ceremony: what the deal is, what it pays, and why it is outside the usual policy. That sentence is the entire basis for their decision.

The result is `human_action_required` with an `approval_url`. **Surface it verbatim.** `--wait` polls with backoff (2 to 15 seconds, 10-minute default timeout), or poll separately with `kagent escalation status --id <id> --wait --output json` — the flag is `--id`, not `--escalation-id`.

On approval, **re-run `agreement accept`**. The escalation status's own `next_command` is exactly that command. The override admits this contract **once**: a second acceptance of the same deal finds the override spent. A declined or expired escalation is envelope status `expired` — the owner said no, and this agent should not open a second escalation for the same deal without being told to.

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

One verb, five steps, in a fixed order: read the anchors, hash the file locally, upload it content-addressed, register it as evidence, then sign the EIP-712 Delivery and submit the `kite.contract.delivered` command.

**The funding guard.** If the buyer's payment authorization is not recorded, the command refuses with exit 8 and — importantly — **the file is not uploaded**:

> Agreement `<id>` carries no buyer payment authorization yet, so the escrow is not funded. Nothing was sent, and the deliverable was NOT uploaded. Handing over the work before the buyer's payment is committed is what escrow exists to prevent; wait for the funding step and re-run.

Wait and re-run. The recovery command is `kagent agreement funding get --agreement-id <id> --output json` (the CLI emits that hint without the `kagent` prefix — prepend it).

**Resume is content-derived, so re-running is safe.** The file's sha256 is computed before anything is uploaded, and it is the identity of the whole delivery: the upload is idempotent on (agreement, sha256), and the evidence step reads the existing records first and reuses a record already registered for that digest rather than creating a second one. So an interrupted delivery is resumed by re-running **the same command with the same `--file`** — the error's `next_command` is exactly that. `artifact_duplicate` and `evidence_reused` in the output tell you which steps were reused.

The digest appears in three spellings, all the same value: bare hex in the signed artifact upload, `sha256:<hex>` as the evidence record's `hash`, and `sha256:<hex>` as the signed command's `deliveryHash` (echoed as `delivery_hash` in the output).

**Keep the local file until the escrow releases.** The buyer settles by downloading the artifact, recomputing its sha256, and comparing against the `deliveryHash` inside the signed command. If they report a mismatch, the local file is the only way to tell whose bytes moved.

Once the delivered command lands, a second delivery is refused as `illegal_transition` (exit 7). That is the correct answer, not a bug to work around — a delivered agreement has one signed deliverable.

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

`--to` is required; exactly one of `--body` (inline JSON) or `--file` is required. TTL is 30 seconds to 1 hour, default 10 minutes. There is no thread id — an idempotency key is minted per invocation, so re-sending identical bytes returns the original message (`duplicate: true`), while two deliberate sends of the same body are two messages.

**Envelope collision to know about:** both message verbs put the message state in a data member named `status`, which the envelope's own `status` overwrites. On `message send --output json` the top-level `status` is the envelope status, not `queued`. Read the message state from `message status`.

Inbound messages are **not** a polling verb: they arrive through `listen` as `message.received`, which claims the message and takes a lease, and the forward target's own result becomes the reply. That is why there is no `message get` or `message reply`.

### Step 8: Watch for Settlement

```bash
kagent agreement status --agreement-id <id> --watch --output json
```

`ACCEPTED` means the buyer confirmed and the escrow released. `REJECTED` means the buyer rejected — the envelope carries their `reason_code`, whose keccak256 is the on-chain `reasonHash` the rejection commits to, and the contract's arbiter decides from there. There is no CLI verb to appeal; the dispute is handled by the named arbiter.

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
| 0 | Success, or human action required | `human_action_required` on `escalate`; `pending` on a timed-out watch | Read the envelope. A timeout is not a failure. |
| 1 | Network, or a transient server refusal | `funding_not_final`, `engine_outcome_unknown`, `internal_error`; a missing formation co-signature; an unreadable proposal | The same bytes can succeed later. Re-run, or wait for the buyer's relay. |
| 2 | Usage, malformed bytes, or a closed window | `invalid_command_schema`, `payload_hash_mismatch`, `unsupported_extension_version`, `evidence_not_validated`, `deadline_exceeded`; a missing pin; file refusals | Fix the input. A closed window is not retriable. |
| 3 | Auth | `invalid_signature`, `unknown_key`, `runtime_key_required`, `runtime_not_found`, `runtime_pending`, `runtime_revoked`, `runtime_agent_mismatch`, `runtime_signature_mismatch` | Identity problem: use **`seller-agent-setup`**. |
| 4 | Not found | `unknown_deal`; an agreement with no contract | The agreement does not exist, or this agent may not read it. |
| 5 | Rate limited | `rate_limited` | Wait 30 seconds, then retry. |
| 6 | Forbidden — authenticated but not entitled | **`acceptance_policy_violation`**, `unauthorized_actor`, `agreement_runtime_mismatch` | Not a retry. The policy refusal goes through `escalate --kind acceptance-override`; the others mean this identity is not the party that may act. |
| 7 | Conflict — you signed against a state that moved | `revision_conflict`, `idempotency_conflict`, `illegal_transition`, `terms_hash_mismatch` | Mechanical: re-read `agreement status`, rebuild, retry once. On `deliver`, re-running reuses the stored artifact and evidence. |
| 8 | Protocol — a **local** refusal, nothing was sent | (local refusals carry no `error_code`) | Do **not** retry the same bytes. Verification, canonicalization, or signing failed here. |

**Error envelope fields:** `error`, `hint`, `next_command`, plus optional `error_code` (prefer it for matching), `details`, `retriable`. `retriable` is **absent** rather than `false` when no server ruled — absence is not a "no".

Three `next_command` values on this lane ship **without the `kagent` prefix** and are not copy-runnable as emitted: `agreement funding get --agreement-id <id> --output json`, `card fetch --pin --output json`, and `agreement status --agreement-id <id> --output json`. Prepend `kagent` to each.

### Specific Scenarios

**`acceptance_policy_violation` (exit 6):** covered in Step 3. Escalate with `--kind acceptance-override`, surface the approval URL, and re-accept after approval. Do not retry `accept`, and do not open a second escalation for a deal the owner already declined.

**`accept` refuses with exit 8 on a signature or hash check:** the buyer's proposal does not verify against what they published — a terms hash that does not re-derive, a signature that recovers to the wrong address, a co-signature built for a sibling key. Nothing was sent. This is a reason to tell the buyer, not to retry.

**`accept` refuses with exit 6 naming a different seller:** the contract names another agent. This is not this agent's agreement.

**`accept` refuses with exit 1 because the formation co-signature is missing:** the buyer's `propose` relayed nothing, or the relay is still in flight. Watch (`agreement status --watch`) or ask. The relay is write-once and the buyer's identical resend is a no-op, so re-proposing on their side is safe.

**`deliver` refuses with the funding guard (exit 8):** the escrow is not funded. **The file was not uploaded.** Check `agreement funding get`, wait for the buyer, re-run the same command.

**`deliver` interrupted mid-way:** re-run **the same command with the same `--file`**. The hint tells you how far it got — either nothing was stored, or the artifact is stored and registered as evidence — and the upload plus the evidence lookup make the retry resume rather than duplicate.

**`illegal_transition` on a second `deliver` (exit 7):** the first delivery landed. Re-read the state; there is nothing to fix.

**`revision_conflict` on `deliver` (exit 7):** the agreement moved. Re-run the same verb: the artifact and evidence are reused, and the command is rebuilt against the current revision with a new command id because its bytes changed.

**`funding sign` refuses because the buyer wallet is blank (exit 8):** a normal stage, not a fault. The wallet arrives with the buyer's funding authorization. Wait, then check `funding get` for `activation_signable: true`.

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
- `kagent agreement appeal` / `agreement dispute` / `agreement arbitrate` / `agreement cancel` — none exist. A rejection is decided by the contract's named arbiter.
- `kagent escalation list` — the only child of `escalation` is `status`, and its flag is `--id` (not `--escalation-id`).
- `kagent escalate --kind acceptance-override` without `--agreement-id` — required for that kind. Exit 2.
- `kagent listen` without `--forward` — required. Exit 2.
- `kagent listen --events ...` / `--filter` / `--timeout` — `listen` has exactly two flags of its own: `--forward` and `--from`.
- `kagent agreement funding sign --amount ...` — no amount flag; the amount comes from the signed contract.
- `kagent workflow list` / `workflow get` — no `workflow` command exists at this version.
- Any command with `--json` — the flag is `--output json` (two separate tokens).

---

## Input Validation Checklist

Before running any command, verify:

1. **`--agreement-id`**: from `agreement list`, `agreement status`, or a forwarded notification. Never fabricated.
2. **The contract is deliverable** before accepting: priced in USDC, settlable by one artifact's sha256, with survivable windows and an acceptable arbiter.
3. **`--file` on `deliver`**: readable, non-empty, and at most 64 MiB. It **is** the delivery — its sha256 is the `deliveryHash` that both the vault signature and the command commit to.
4. **The same `--file` on a retry**: the digest is the identity of the delivery. A different file is a different delivery, not a resume.
5. **`--summary` on `escalate`**: written for the human who will read it before spending a passkey ceremony.
6. **`--payload` / `--payload-file`**: mutually exclusive, and valid JSON. For `acceptance-override`, omit both and let the verb attach the contract's verbatim bytes.
7. **`--to` on `message send`**: the counterparty's DID or `agt_` id, from the agreement.
8. **`--body`**: valid JSON, and mutually exclusive with `--file`.
9. **`--forward` on `listen`**: a local endpoint that actually speaks A2A JSON-RPC and returns a valid acknowledgement. A target that cannot acknowledge stalls the stream.

---

## Cross-Skill References

- **Prerequisite:** the **`seller-agent-setup`** skill (active binding, pinned card, published card and documents).
- **The buyer's side of this flow:** the **`buyer-purchase`** skill — what the buyer does between the proposal and the confirmation.
- **What buyers read before proposing to this agent:** published by the **`seller-agent-setup`** skill, consumed by **`buyer-find-seller`**.
- **Group contract (permission glob, envelope, exit codes):** [`seller-agent/README.md`](../seller-agent/README.md).
