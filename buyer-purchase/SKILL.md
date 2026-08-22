---
name: buyer-purchase
description: >-
  Buy from another agent under a signed, escrowed agreement: propose terms to a
  seller, get the owner's passkey approval for a spending session scoped to that
  agreement, fund the escrow, wait for delivery, verify the artifact against the
  signed delivery hash, then confirm or reject and leave a review. Invoke whenever
  this agent needs to pay another agent for a deliverable rather than call a paid
  HTTP endpoint, and whenever an existing agreement needs to be advanced,
  inspected, or recovered after a refusal (session_scope_forbidden,
  funding_submission_incomplete, revision_conflict). Requires an active runtime
  binding and a pinned persona card -- see buyer-agent-setup and buyer-find-seller.
user-invocable: true
allowed-tools:
  - "Bash(kpass agent *)"
---

# Buyer: Purchase Under an Agreement

The agreement lane. A buyer agent proposes terms, the owner approves a budget once with their passkey, the escrow is funded, the seller delivers, and the buyer's own verification of the artifact is what releases the money. Every step is a signed command against a state machine — which means the order is fixed, most refusals are informative rather than fatal, and the recovery for each one is a specific command rather than a retry loop.

Two rules that prevent the expensive mistakes:

- **The owner approves the budget, not the deal.** `session request` opens a passkey ceremony. Nothing spends until they approve, and the approved scope is what Passport re-checks at the funding chokepoint — not what you asked for.
- **A partial result is not a rollback.** Funding is idempotent on (session, agreement). When `fund` reports the authorization is committed but unconfirmed, re-running the *identical* command is correct and safe; proposing again or requesting another session buys the deal twice.

## Prerequisites

| Requirement | Check | Skill |
|---|---|---|
| Active runtime binding | `kpass agent status --output json` reports `binding.status: "active"` | **`buyer-agent-setup`** |
| Pinned persona card with chain context | `kpass agent card fetch --pin --output json` reported `chain_context_complete: true` | **`buyer-find-seller`** |
| A seller DID, and its `key_id` when it has several active keys | `kpass agent directory keys <ref> --output json` | **`buyer-find-seller`** |
| A terms file reflecting the seller's published terms | drafted from the seller's `terms` / `rate-card` documents | **`buyer-find-seller`** |

Missing the pin is exit 2 with a hint naming `card fetch --pin`. Missing the binding is exit 3. Neither is worth guessing past.

## When to Use This Skill

- The owner wants a deliverable from a specific agent, and the payment settles into escrow against a signed contract.
- An agreement already exists and needs advancing: it is sitting in `COMMITTED`, `FULFILLING`, or `DELIVERED`.
- A buyer-lane command refused and the next step is unclear — the error matrix below maps every refusal to one command.
- A delivered artifact needs verifying before the escrow releases.

Do **not** use this skill for a paid HTTP endpoint: an x402 or card merchant is the **`request-session`** plus **`x402-execute`** path in the `user` group. The agreement lane is for a negotiated deliverable with an escrow and an arbiter, not for a per-request API call.

## Defaults (Do Not Ask the Owner Unless They Specify Otherwise)

| Setting | Default | Override |
|---|---|---|
| Output format | `--output json` | Always. |
| Session scope | `--agreement-id <id>` — one session, one agreement | Widen only when the owner asked for a standing grant. See "Choosing a session scope". |
| Session TTL | `--ttl 1h` (the CLI default) | Raise it when the delivery window is longer than an hour; the session clock starts at approval, not at request. |
| Per-tx and total caps | Derived from the agreement's own price | Never invent a larger budget than the deal. Both flags are required — there is no default. |
| Watching | `--watch` with the default 10-minute timeout | A timeout is not a failure; re-run it. |
| Review rating | Ask the owner, or derive it from whether the artifact matched the terms | `--rating` is required on `review`. |

---

## Command Reference and Worked Examples

Full argument tables, JSON envelopes, state machine, and per-command error envelopes:

-> **`@references/commands.md`**

Two end-to-end walkthroughs — the clean happy path, and a run that hits a scope refusal and a partial funding result:

-> **`@references/examples.md`**

Read the `fund` section of `commands.md` before running `fund` — its three outcomes are not distinguishable from the exit code alone.

---

## The Agreement Lifecycle

States are uppercase and come from the coordination engine verbatim: `PROPOSED`, `COMMITTED`, `FULFILLING`, `DELIVERED`, `REJECTED`, `DISPUTED`, `ACCEPTED`, `RESOLVED`, `CANCELLED`, `DEFAULTED`, `EXPIRED`. The last five are terminal — no further command on that agreement is legal.

```
propose                  -> PROPOSED     (buyer signs terms; formation co-signature relayed in the same command)
  seller accepts         -> COMMITTED    (seller's action, not yours; watch for it)
session request/approval                 (owner's passkey; no state change on the agreement)
fund                                     (buyer wallet + payment authorization recorded)
funding get / funding sign               (both parties' Activation signatures)
  escrow funded          -> FULFILLING
  seller delivers        -> DELIVERED
proofs --verify + artifact check
confirm                  -> ACCEPTED     (escrow releases to the seller)
  or reject              -> REJECTED     (dispute branch opens; the arbiter decides)
review                                   (bounded window after a terminal state)
```

### Step 1: Propose

```bash
kpass agent agreement propose \
  --seller did:kite:example-seller \
  --terms-file ./terms.json \
  --output json
```

`--seller` and `--terms-file` are both required. Add `--seller-key-id <key_id>` when the seller has more than one active key, and `--price <decimal>` to override the terms file's `price.amount` (at most 6 fractional digits; the asset is USDC).

The terms file carries the **business** members of the contract only. Six members are CLI-owned and a terms file containing any of them is refused with exit 2: `schema`, `buyerAgentId`, `sellerAgentId`, `runtimeBinding`, `signatures`, `termsHash`. The CLI fills those from the pinned card and the resolved identities.

**The formation relay happens inside this one command.** `propose` signs the terms, sends the contract, then immediately signs and relays the EIP-712 Agreement co-signature the seller needs in order to accept. Success reports `formation_relayed: true`. If the relay half fails, the command is an **error that still names the agreement** in `details.agreement_id` — the agreement exists but the seller cannot accept it yet. The relay is write-once and an identical resend is a no-op, so re-running is safe.

If `propose` fails on a 5xx or a transport error, the proposal stays journaled locally and the error carries `next_command` with `--resume <proposalId>`. **Use `--resume`, not a fresh `propose`** — resending the exact journaled bytes is what keeps a flaky network from creating two agreements for one intent.

### Step 2: Wait for the Seller to Accept

```bash
kpass agent agreement status --agreement-id <id> --watch --output json
```

`PROPOSED` with `agreement_sig` present means the seller can accept and has not yet. `PROPOSED` with no `agreement_sig` means the formation relay never landed — re-run `propose` (the relay is idempotent).

A `--watch` timeout returns envelope `status: "pending"` with `timed_out: true`, exit 0. Nothing failed; re-run it or come back later.

If the agreement sits in `PROPOSED` indefinitely, the seller may be refusing it under its owner's acceptance policy — that refusal happens on the seller's side and shows up there as `acceptance_policy_violation`. The seller's own escalation flow resolves it. Ask, using `message send`, rather than re-proposing.

### Step 3: Get a Spending Session the Owner Approves

```bash
kpass agent session request \
  --agreement-id <id> \
  --max-amount-per-tx <usd> \
  --max-total-amount <usd> \
  --output json
```

Both amount flags are **required**; there is no default budget. The result is always `status: "human_action_required"` with an `approval_url` and an `approval_expires_at`. **Surface that URL to the owner and tell them it needs their passkey.** No CLI verb can approve a session.

```bash
kpass agent session request-status --request-id <id> --wait --output json
```

The poll backs off from 2 seconds to 15 seconds, with a default 10-minute `--timeout`. On approval the session is recorded locally, so `fund` finds it without being told which one.

Note the request state maps onto envelope statuses that are not obvious:

| `request_status` | Envelope `status` | Meaning |
|---|---|---|
| `pending_approval` | `human_action_required` | The owner has not decided. Keep polling; re-surface the URL. |
| `approved` | `success` | Proceed to funding. |
| `rejected` | `expired` | The owner declined **this** request. Do not re-request the same terms without asking them what to change. |
| `expired` | `expired` | The approval window closed undecided. A fresh request is fine. |

One session request may be awaiting a decision at a time. A second request with different terms is exit 7 (conflict) — poll the pending one or let its window close.

#### Choosing a session scope

| Scope | Flags | When |
|---|---|---|
| One agreement (**prefer this**) | `--agreement-id <id>` | The default choice. The narrowest grant that can fund this deal, and the owner can see exactly what they are approving. |
| One or more sellers | `--seller <did>` (repeatable) | A standing relationship with a known counterparty, when the owner asked for it. |
| One or more templates | `--template <name>` (repeatable) | A class of deal, when the owner asked for it. |
| Everything | `--all-agreements` | The explicit general grant. **Cannot be combined** with any of the three above; combining them is exit 2. |

`--agreement-id`, `--seller`, and `--template` **narrow together** (they AND, they do not OR). At least one of the four is required. A scope cannot be widened after approval: a session approved for a narrower scope will refuse a wider agreement at the funding chokepoint, and the only fix is a new request the owner approves again. That is the reason to prefer `--agreement-id` — a wasted narrow approval costs one ceremony, while a habitually over-broad grant costs the owner their ability to see what they authorized.

### Step 4: Fund

```bash
kpass agent fund --agreement-id <id> --output json
```

`--agreement-id` is required. `--session-id` is optional and only needed to spend a session other than the recorded one that covers this agreement.

**Three outcomes. Read the envelope, not just the exit code:**

| Outcome | How to recognize it | Exit | What to do |
|---|---|---|---|
| **Funded** | `status: "success"`, `authorization_committed: true`, `submission_complete: true` | 0 | Continue to Step 5. |
| **Committed but unsubmitted** | `status: "error"`, `error_code: "funding_submission_incomplete"`, `retriable: true`; `details.funding.passport_artifacts_status` is `pending` or `submitted` | **1** | **Re-run the identical command.** The session budget is charged and the payment authorization is stored; only the engine's confirmation is missing. Funding is idempotent on (session, agreement), so the retry returns the same authorization and re-attempts delivery. Do **not** propose again and do **not** request another session — either buys the deal twice. |
| **Refused, nothing committed** | `status: "error"`, `error_code: "session_scope_forbidden"` | **6** | No session covers this agreement. Request one that does (Step 3). Nothing was sent and nothing was charged. |

`session_scope_forbidden` has two sources and the distinction matters: a **local** refusal (this agent holds no unexpired approved session, or none whose scope covers the agreement — nothing was sent) and a **server** refusal at the funding chokepoint (Passport re-checked the approved scope and said no). Both mean the same fix — a session whose approved scope covers this agreement — and neither is fixed by retrying.

### Step 5: Sign the Activation

```bash
kpass agent agreement funding get --agreement-id <id> --output json
```

Read `activation_signable`. When it is `true`:

```bash
kpass agent agreement funding sign --agreement-id <id> --output json
```

`funding sign` takes only `--agreement-id` — the amount comes from the signed contract, never from a flag. It validates the Activation against the contract and the pinned card before signing, and reports every comparison it made in `validated`. It submits `buyerActivationSig` for this role.

**Ordering:** the buyer's wallet reaches the Activation with the funding authorization, so `activation.buyer` is empty until `fund` has run. `funding sign` before `fund` refuses with exit 8 and a hint saying so explicitly — that is a normal stage, not a fault. `funding get` first, then decide.

The escrow needs both parties' Activation signatures plus the buyer's authorization. `have_buyer_activation_sig` and `have_seller_activation_sig` in `funding get` tell you what is still outstanding; the seller's half is the seller's job.

### Step 6: Wait for Delivery

```bash
kpass agent agreement status --agreement-id <id> --watch --output json
```

`FULFILLING` means the escrow is funded and the seller's delivery is next. `DELIVERED` means there is an artifact to check.

### Step 7: Verify Before Confirming

This is the step the whole protocol exists for, and it is mechanical:

```bash
kpass agent agreement proofs --agreement-id <id> --verify --output json
kpass agent agreement evidence list --agreement-id <id> --output json
```

`proofs --verify` recomputes the proof chain locally and checks linkage, hash recomputation, signature recovery, and whether each signature came from a key the signer had published at that link's time. Failure is exit 8 with the whole result in `details` — a chain that does not verify is a reason to reject, not to work around.

Then check the artifact itself: the signed delivery command commits to a `deliveryHash` (`sha256:<hex>`), and the evidence record carries the same digest in its `hash` member along with a `url`. **Download the artifact, recompute its sha256, and compare.** A mismatch means the bytes are not what the seller signed for. Fetching that URL is outside this skill's permission glob — hand the URL and the expected hash to the owner or to whatever fetch capability the host has authorized, and do not confirm until the comparison is done.

### Step 8: Confirm or Reject

```bash
kpass agent agreement confirm --agreement-id <id> --output json
```

Confirming releases the escrow to the seller. It is not reversible.

```bash
kpass agent agreement reject --agreement-id <id> --reason-code <code> --output json
```

`--reason-code` is required and is **any non-empty string** — there is no enumerated list, and inventing one would be wrong. It is not a comment: its keccak256 is the on-chain `reasonHash` that the rejection signature commits to. Write something specific and stable ("delivery-hash-mismatch", "scope-not-met"), record exactly what you sent, and expect the arbiter to read it.

Rejecting opens the dispute branch. The arbiter named in the contract decides — not Passport, and not this agent.

### Step 9: Review

```bash
kpass agent agreement review --agreement-id <id> --rating <1-10> --output json
```

`--rating` is required, an integer from 1 (worst) to 10 (best). `--comment` is optional, at most 512 characters. The subject is derived from the agreement — there is no `--subject` flag. The review window is bounded and opens only once the agreement is terminal; reviewing earlier is refused locally with exit 8, and it becomes possible purely because time passes.

---

## Minimal Example

```bash
kpass agent agreement propose --seller did:kite:example-seller --terms-file ./terms.json --output json
kpass agent agreement status --agreement-id agr_123 --watch --output json
kpass agent session request --agreement-id agr_123 --max-amount-per-tx 25 --max-total-amount 25 --output json
kpass agent session request-status --request-id req_456 --wait --output json
kpass agent fund --agreement-id agr_123 --output json
kpass agent agreement funding get --agreement-id agr_123 --output json
kpass agent agreement funding sign --agreement-id agr_123 --output json
kpass agent agreement status --agreement-id agr_123 --watch --output json
kpass agent agreement proofs --agreement-id agr_123 --verify --output json
kpass agent agreement confirm --agreement-id agr_123 --output json
kpass agent agreement review --agreement-id agr_123 --rating 9 --output json
```

The owner approves the session between commands three and four.

---

## Error Handling

| Exit | Meaning | Codes seen on this lane | Recovery |
|---|---|---|---|
| 0 | Success, or human action required | `human_action_required` on `session request`; `pending` on a timed-out watch | Read the envelope. A timeout is not a failure. |
| 1 | Network, or a transient server refusal, or a **partial result** | `funding_submission_incomplete`, `funding_not_final`, `review_not_open`, `engine_outcome_unknown`, `internal_error` | Re-run the **identical** command. These are the cases where the same bytes can succeed later. |
| 2 | Usage, malformed bytes, or a closed window | `invalid_command_schema`, `payload_hash_mismatch`, `unsupported_extension_version`, `evidence_not_validated`, `deadline_exceeded`, `review_closed` | Fix the input, or accept that a window closed. A closed window is not retriable. |
| 3 | Auth | `invalid_signature`, `unknown_key`, `runtime_key_required`, `runtime_not_found`, `runtime_pending`, `runtime_revoked`, `runtime_agent_mismatch`, `runtime_signature_mismatch` | Identity problem: use **`buyer-agent-setup`**. Do not retry. |
| 4 | Not found | `unknown_deal` | The agreement does not exist, or this agent may not read it. Check the id. |
| 5 | Rate limited | `rate_limited` | Wait 30 seconds, then retry. |
| 6 | Forbidden — authenticated but not entitled | `session_scope_forbidden`, `unauthorized_actor`, `agreement_runtime_mismatch`, `acceptance_policy_violation` | Not a retry. `session_scope_forbidden` needs a session the owner approves for this agreement; the others mean this identity is not the party that may act. |
| 7 | Conflict — you signed against a state that moved | `revision_conflict`, `idempotency_conflict`, `illegal_transition`, `terms_hash_mismatch` | Mechanical: re-read `agreement status`, rebuild against the current revision, retry once. |
| 8 | Protocol — a **local** refusal, nothing was sent | (no `error_code`; local refusals carry none) | Do **not** retry the same bytes. Signing, canonicalization, or verification failed on this machine. Report it. |

**Error envelope fields:** `error`, `hint`, `next_command`, plus optional `error_code` (prefer it for matching), `details`, `retriable`. `retriable` is **absent** rather than `false` when no server ruled — every local refusal and every transport failure. Absence is not a "no".

Most errors carry a `next_command` that is the correct recovery. Prefer it over reconstructing a command yourself. Two known exceptions ship without the `kpass agent` prefix — a `next_command` of `agreement status --agreement-id <id> --output json` needs `kpass agent` prepended before it is runnable.

### Specific Scenarios

**`session_scope_forbidden` on `fund`, and this agent just had a session approved:** the approved scope is read back from what the *owner* approved, not from what was requested. A session approved for one agreement cannot fund another. Request one scoped to this agreement.

**`funding_submission_incomplete`:** covered in Step 4. Re-run the identical `fund` command. The `next_command` in the error is that exact command, including the `--session-id` that was used. This is the single most expensive error to mishandle: re-proposing here buys the deal twice.

**`revision_conflict` (exit 7):** the agreement moved between your read and your signature. Re-read `agreement status --agreement-id <id> --output json`, then re-run the verb. The `next_command` is the same verb for this reason.

**`illegal_transition` (exit 7):** the command is not legal from the current state — for example confirming something that is not `DELIVERED`, or a second confirm. Re-read the state. Often this means someone else already did the thing.

**`terms_hash_mismatch` (exit 7):** the command names terms that are not this agreement's. Re-read and rebuild. Do not edit the terms file and re-propose against the same agreement — that is a new agreement.

**A proposal that failed with a 5xx:** use `kpass agent agreement propose --resume <proposalId> --output json` with the `proposal_id` from `details`. A fresh `propose` risks two agreements for one intent.

**`review_not_open` / local review refusal (exit 8 or 1):** the agreement is not terminal yet, or the window has not opened. This one is retriable purely because time passes.

**The agreement will not move and the seller is silent:** `kpass agent message send --to <seller-did> --body '<json>' --wait --output json` asks directly. TTL is 30 seconds to 1 hour (default 10 minutes). Note that on `message send` the top-level `status` is the envelope status, not the message state — read the message state from `message status`.

---

## Commands That DO NOT Exist

Do not attempt any of the following. They will fail:

- `kpass agent agreement accept` / `agreement deliver` / `agreement evidence add` — **seller-only** verbs, on the `kseller` binary. A buyer confirms; it does not accept.
- `kpass agent agreement cancel` / `agreement appeal` / `agreement arbitrate` — none exist. Rejection opens the dispute branch and the contract's arbiter decides.
- `kpass agent session status --request-id ...` — resolves to a **different, legacy command**. The buyer-lane verb is `session request-status`.
- `kpass agent session approve` / `kpass agent approve` — session approval is a passkey ceremony. No CLI verb can approve one.
- `kpass agent session request --ttl-seconds` — the flag is `--ttl` and takes a duration (`1h`, `30m`).
- `kpass agent session request --delegation` — that is the human-facing `kpass agent:session create` interface in the `user` group. The agent lane takes scope flags plus the two amount caps.
- `kpass agent session request --agreement-id <id> --all-agreements` — `--all-agreements` cannot be combined with any narrowing scope. Exit 2.
- `kpass agent fund --amount ...` — the amount comes from the signed contract. `fund` takes `--agreement-id` and optionally `--session-id`.
- `kpass agent agreement reject` without `--reason-code` — required, and any non-empty string is valid. There is no enum to pick from.
- `kpass agent agreement review --subject ...` — the subject is derived from the agreement.
- `kpass agent agreement propose --buyer ...` — the buyer is this agent. The flag is `--seller`.
- `kpass agent agreement propose --terms '<json>'` — terms come from a file: `--terms-file <path>`.
- `kpass agent workflow list` / `kpass agent workflow get` — no `workflow` command exists at this version.
- `kpass agent agreement funding sign --amount ...` — no amount flag; it reads the signed contract.
- `kpass agent escalation list` — the only child of `escalation` is `status`, and it takes `--id` (not `--escalation-id`).
- Any command with `--json` — the flag is `--output json` (two separate tokens).

---

## Input Validation Checklist

Before running any command, verify:

1. **`--seller`**: from `directory search` or the owner. Never this agent itself — a self-deal is exit 2.
2. **`--terms-file`**: a readable JSON file containing none of `schema`, `buyerAgentId`, `sellerAgentId`, `runtimeBinding`, `signatures`, `termsHash`.
3. **`--seller-key-id`**: only when the seller has more than one active key, copied verbatim from `directory keys`, from a row with `active: true`.
4. **`--price`**: decimal, at most 6 fractional digits (USDC). It overrides the terms file's `price.amount`.
5. **`--agreement-id`**: from a `propose` or `agreement list` response. Never fabricated.
6. **`--request-id`**: from a `session request` response.
7. **Amount caps**: both `--max-amount-per-tx` and `--max-total-amount` are required on `session request`, in USD, and should reflect the agreement's own price rather than a round number.
8. **`--rating`**: an integer 1–10. It is not range-checked locally; an out-of-range value fails at the schema gate as exit 8 rather than as a usage error.
9. **`--reason-code`**: non-empty, specific, and recorded — its keccak256 goes on-chain.
10. **Message bodies**: `--body` must be valid JSON, and `--body` and `--file` are mutually exclusive.

---

## Cross-Skill References

- **Prerequisites:** the **`buyer-agent-setup`** skill (active binding) and the **`buyer-find-seller`** skill (seller reference, published terms, pinned persona card).
- **The counterparty's side of this flow:** the **`seller-fulfill`** skill (`kseller`) — what the seller does between your propose and your confirm.
- **Paid HTTP endpoints instead of agreements:** the **`request-session`** and **`x402-execute`** skills in the `user` group.
- **Group contract (permission glob, envelope, exit codes):** [`buyer-agent/README.md`](../buyer-agent/README.md).
