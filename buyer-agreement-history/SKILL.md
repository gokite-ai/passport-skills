---
name: buyer-agreement-history
description: >-
  Look up what already happened on one of this buyer agent's agreements or
  escalations -- an after-the-fact read, not a workflow step. Invoke for "what
  happened to agreement X", "is my delivery verified", "show me the proof
  chain", "what's the status of my escalations", or "list the escalations
  I've raised". Wraps `agreement proofs [--verify]`, `agreement evidence
  list`, `escalation list`, and `escalation status`, all agent-signed reads on
  the `kpass agent` surface. Distinct from the `activity` skill (the human
  owner's own account history, JWT-authenticated) and from `buyer-purchase`
  (which uses these same reads internally as steps of funding and confirming
  a deal, not as a standalone lookup). Requires an active runtime binding --
  see buyer-agent-setup.
user-invocable: true
allowed-tools:
  - "Bash(kpass agent *)"
---

# Buyer: Agreement and Escalation History

A read-only lookup skill: everything here answers "what already happened", never "what happens next". Three independent trails, each with its own binding value:

- **The transition-proof chain** (`agreement proofs`) is the hash-chained record of every accepted state change on one agreement, and `--verify` recomputes it locally instead of trusting the server's word for it.
- **Evidence** (`agreement evidence list`) is the delivery artifacts registered against an agreement, keyed by content hash.
- **Escalations** (`escalation list` / `escalation status`) are the decisions this agent has asked its owner to make, and what they decided.

None of these three lanes calls the others, and none of them changes anything: every command here is a read.

> **Reference files** (read when you need exact detail):
> - `@references/commands.md` — full command reference, argument tables, and every JSON output shape.
> - `@references/examples.md` — worked examples (checking a delivery, listing open escalations, verifying a proof chain that fails).

## Prerequisites

| Requirement | Check | Skill |
|---|---|---|
| Active runtime binding | `kpass agent status --output json` reports `binding.status: "active"` | **`buyer-agent-setup`** |
| An agreement id, for the proofs/evidence reads | from `kpass agent agreement list` or a prior `buyer-purchase` step | **`buyer-purchase`** |

An escalation id is only needed for `escalation status --id`; `escalation list` needs nothing but this agent's own identity.

## When to Use This Skill

- "What happened to agreement `<id>`?" — read `agreement proofs`, optionally `--verify` it, and `agreement evidence list` for what was delivered.
- "Is my delivery legitimate / can I trust this chain?" — `agreement proofs --verify`.
- "What's the status of my escalations?" / "Did the owner decide yet?" — `escalation list`, then `escalation status --id <id>` for one in particular.
- "Show me everything I've had to ask the owner about." — `escalation list` with no filters.

## When NOT to Use This Skill

- To **advance** a deal (propose, fund, confirm, reject, review) — that is **`buyer-purchase`**.
- To **raise** a new escalation — that is `kpass agent escalate`, documented in **`buyer-purchase`**.
- For the **owner's own** account history (wallet transfers, faucet drops, shopping checkouts, session approvals) — that is the **`activity`** skill, which authenticates as the human owner via JWT, not as this agent via its runtime key.
- To find an agreement id in the first place — `kpass agent agreement list` is documented in **`buyer-purchase`**.

## Defaults (Do Not Ask the Owner Unless They Specify Otherwise)

| Setting | Default | Override |
|---|---|---|
| Output format | `--output json` | Always. |
| `agreement proofs --verify` | Pass it whenever the question is "can I trust this" or before citing a proof to the owner; omit it for a quick unverified glance | An unverified read is not an audit — say so if you show one. |
| `escalation list` filters | Omit (returns everything this agent raised) | Only pass `--status`/`--kind`/`--agreement-id` when the user asks to narrow the list. |
| `escalation list --limit` | Server default (50) | Only pass `--limit`/`--offset` for pagination. |

---

## Reading a Proof Chain

```bash
kpass agent agreement proofs --agreement-id <id> --output json
```

Returns the chain **unverified** — the newest link's `proofHash` is also the `receiptHash` a settlement signature would quote next, so this read doubles as an audit trail and as an input to signing. Each link names `fromState`, `toState`, `event`, `actorId`, `signedBy`, and `proofHash`, with `previousProofHash` pointing at its predecessor.

```bash
kpass agent agreement proofs --agreement-id <id> --verify --output json
```

Recomputes the chain locally rather than trusting the server: linkage (each `previousProofHash` matches its predecessor), recomputation (each `proofHash` matches its own members), and signatures (each `signedBy` recovers to a key the coordination persona actually published, valid at the time the link was created — checked against revoked keys too, since a key revoked yesterday can still have validly signed a link from last week). A chain that fails any of those exits 8 (`PROTOCOL`) with `details` naming which check failed, and the hint is explicit: **do not settle against a chain that did not verify.**

An agreement with zero links (nothing has moved it yet) is reported unverified with `count: 0`, not verified-and-empty; `--verify` on an empty chain refuses outright, since an empty chain is not something that was checked.

### Reading a `SETTLED_MUTUAL` outcome

`SETTLED_MUTUAL` is a **fourth terminal class**, and reading it as one of the other three gets the story wrong. It is not an acceptance (`ACCEPTED` — the buyer confirmed and the escrow released in full), not a cancellation or a refund (`CANCELLED` / `EXPIRED` / a consented refund), and not an arbiter's ruling (`RESOLVED`). It is a **negotiated resolution**: the two parties co-signed one split of the escrow and the vault executed it without the arbiter, from `DELIVERED`, `REJECTED`, or `DISPUTED`. `seller_bps` quantifies it — `6200` means 62 percent of the escrow went to the seller and the remainder back to the buyer. Say which of the four happened when reporting an outcome; "settled" on its own reads as an acceptance to anyone who has not seen the chain.

The link that records the command carries the detail: the event Passport maps `kite.contract.settle_mutual` to, `MUTUAL_SETTLEMENT_SUBMITTED`, with `seller_bps` and **both** parties' vault-domain settlement signatures in its metadata. Two signatures on one link is what distinguishes this from every other settlement command in the chain — nobody moved the deal alone. A `MUTUALLY_SETTLED` link follows once the vault call is observed; a `RELAY_FAILED` instead returns the deal to the origin its `SETTLING_MUTUAL*` state is named for, so an in-flight state in the middle of a chain is a retry, not a dead end.

For the money, read the `settlement` legs rather than `seller_bps` alone. The legs are the amounts that actually moved, and a deal where a fee also moved value does not sum from the basis points by themselves. `kpass agent agreement status` carries `seller_bps` and the legs once the engine has them, so quantifying the split needs no chain query.

**Availability: the `agreement settle` verbs that produce these links require `passport-cli` ≥ the release that ships `agreement settle`.** Reading them needs nothing new — a chain served by the engine reads the same on any CLI, and unrecognized state and event spellings pass through untranslated.

## Reading Evidence

```bash
kpass agent agreement evidence list --agreement-id <id> --output json
```

Every delivery artifact registered against the agreement: type, content hash (`hash`), and the URL a copy can be fetched from. The hash is the binding value — compare a downloaded artifact's own sha256 against it, and against the `deliveryHash` inside the seller's signed `deliver` command (that one's not readable from this side; it's what `agreement proofs`' `deliver` link's content commits to). A buyer can read this list; only the seller can add to it.

## Reading Escalations

```bash
kpass agent escalation list --output json
```

Every escalation this agent has raised, most recent first — its own history, never another agent's; there is no flag that widens it. Filters (`--status`, `--kind`, `--agreement-id`, `--limit`, `--offset`) narrow the same list; an empty result reports `status: success` with zero rows, not an error.

```bash
kpass agent escalation status --id <id> [--wait] [--timeout <d>]
```

Polls one escalation for its owner's decision. `--wait` blocks with backoff until it leaves `pending` or the timeout elapses; without it, one read. A denial and a lapsed decision window both land on envelope `status: expired` — nothing further will happen either way — but they are distinguishable: a denial reads `escalation_status: "decided"` with a `decision` member recording the owner's no, while a window that lapsed undecided reads `escalation_status: "expired"` with no `decision` at all. `escalation list`'s rows carry the same shape minus the escalation-id path argument, so a caller that already has the list rarely needs a second `status` poll unless watching one escalation change live.

---

## Error Handling

This skill only ever reads, so the write-specific codes (6/7) from `buyer-purchase`'s table are unreachable here.

| Exit Code | Meaning | Recovery |
|-----------|---------|----------|
| 0 | Success | Present the result. `verified: false` on an unverified `proofs` read is not a failure — say so rather than implying it was checked. |
| 1 | Network, or a transient server condition | Retry. |
| 2 | Usage error | Fix the flag (e.g. a missing `--agreement-id` or `--id`). |
| 3 | Auth error (`runtime_key_required`, `runtime_pending`, `runtime_revoked`, ...) | Identity problem — use **`buyer-agent-setup`**. |
| 4 | Not found | The agreement or escalation does not exist, or this agent may not read it — another agent's escalation reads this way too, never as forbidden. |
| 5 | Rate limited | Wait 30 seconds, retry. |
| 8 | `PROTOCOL` — a chain failed local verification | Do not settle against it; see `@references/commands.md` for what each failed check means. |

---

## Commands That DO NOT Exist

- `kpass agent agreement history` -- there is no combined verb; read `agreement proofs` and `agreement evidence list` separately.
- `kpass agent escalation list --owner` / `--all` -- there is no flag that widens the scope past this agent's own escalations.
- `kpass agent agreement evidence add` -- buyer-side is read-only here; only the seller registers evidence.
- `kpass agent agreement proofs --verify` on an empty chain -- refused (exit 8); nothing has moved the agreement yet, so there is nothing to verify.
- Any command with `--json` -- the flag is `--output json` (two separate tokens).

---

## Cross-Skill References

- **Prerequisite:** the **`buyer-agent-setup`** skill (active runtime binding).
- **To advance a deal** (propose, fund, confirm/reject, escalate): the **`buyer-purchase`** skill.
- **For the owner's own account history:** the **`activity`** skill (JWT-authenticated, human-facing, a different auth model entirely).
- **The seller's side of the same three reads:** the **`seller-agreement-history`** skill.
