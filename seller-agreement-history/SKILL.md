---
name: seller-agreement-history
description: >-
  Look up what already happened on one of this seller agent's agreements or
  escalations -- an after-the-fact read, not a workflow step. Invoke for "what
  happened to agreement X", "is my delivery verified", "show me the proof
  chain", "what's the status of my escalations", or "list the escalations
  I've raised". Wraps `agreement proofs [--verify]`, `agreement evidence
  list`, `escalation list`, and `escalation status`, all agent-signed reads on
  the `kagent` surface. Distinct from `seller-fulfill` (which uses these same
  reads internally as steps of accepting and delivering a deal, not as a
  standalone lookup). Requires an active runtime binding -- see
  seller-agent-setup.
user-invocable: true
allowed-tools:
  - "Bash(kagent status *)"
  - "Bash(kagent agreement proofs *)"
  - "Bash(kagent agreement evidence list *)"
  - "Bash(kagent escalation list *)"
  - "Bash(kagent escalation status *)"
---

# Seller: Agreement and Escalation History

A read-only lookup skill: everything here answers "what already happened", never "what happens next". Three independent trails, each with its own binding value:

- **The transition-proof chain** (`agreement proofs`) is the hash-chained record of every accepted state change on one agreement, and `--verify` recomputes it locally instead of trusting the server's word for it.
- **Evidence** (`agreement evidence list`) is the delivery artifacts registered against an agreement, keyed by content hash. (Registering new evidence — `evidence add` — is a **write** and belongs to **`seller-fulfill`**, not here.)
- **Escalations** (`escalation list` / `escalation status`) are the decisions this agent has asked its owner to make, and what they decided.

None of these three lanes calls the others, and none of them changes anything: every command here is a read.

> **Reference files** (read when you need exact detail):
> - `@references/commands.md` — full command reference, argument tables, and every JSON output shape.
> - `@references/examples.md` — worked examples (checking a delivery, listing open escalations, verifying a proof chain that fails).

## Prerequisites

| Requirement | Check | Skill |
|---|---|---|
| Active runtime binding | `kagent status --output json` reports `binding.status: "active"` | **`seller-agent-setup`** |
| An agreement id, for the proofs/evidence reads | from `kagent agreement list` or a prior `seller-fulfill` step | **`seller-fulfill`** |

An escalation id is only needed for `escalation status --id`; `escalation list` needs nothing but this agent's own identity.

## When to Use This Skill

- "What happened to agreement `<id>`?" — read `agreement proofs`, optionally `--verify` it, and `agreement evidence list` for what was registered and delivered.
- "Is my delivery legitimate / can I trust this chain?" — `agreement proofs --verify`.
- "What's the status of my escalations?" / "Did the owner decide yet?" — `escalation list`, then `escalation status --id <id>` for one in particular.
- "Show me everything I've had to ask the owner about." — `escalation list` with no filters.

## When NOT to Use This Skill

- To **advance** a deal (accept, sign the Activation, deliver, register new evidence, respond to a rejection) — that is **`seller-fulfill`**.
- To **raise** a new escalation — that is `kagent escalate`, documented in **`seller-fulfill`**.
- To find an agreement id in the first place — `kagent agreement list` is documented in **`seller-fulfill`**.
- To register a **new** evidence record — `evidence add` is a write and belongs to **`seller-fulfill`**; this skill only lists what already exists.

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
kagent agreement proofs --agreement-id <id> --output json
```

Returns the chain **unverified** — the newest link's `proofHash` is also the `receiptHash` a settlement signature would quote next, so this read doubles as an audit trail and as an input to signing. Each link names `fromState`, `toState`, `event`, `actorId`, `signedBy`, and `proofHash`, with `previousProofHash` pointing at its predecessor.

```bash
kagent agreement proofs --agreement-id <id> --verify --output json
```

Recomputes the chain locally rather than trusting the server: linkage (each `previousProofHash` matches its predecessor), recomputation (each `proofHash` matches its own members), and signatures (each `signedBy` recovers to a key the coordination persona actually published, valid at the time the link was created — checked against revoked keys too, since a key revoked yesterday can still have validly signed a link from last week). A chain that fails any of those exits 8 (`PROTOCOL`) with `details` naming which check failed, and the hint is explicit: **do not settle against a chain that did not verify.**

An agreement with zero links (nothing has moved it yet) is reported unverified with `count: 0`, not verified-and-empty; `--verify` on an empty chain refuses outright, since an empty chain is not something that was checked.

## Reading Evidence

```bash
kagent agreement evidence list --agreement-id <id> --output json
```

Every delivery artifact registered against the agreement: type, content hash (`hash`), and the URL a copy can be fetched from. The hash is the binding value — it is what a buyer's downloaded-artifact sha256 gets compared against, and against the `deliveryHash` inside this seller's own signed `deliver` command. Registering a **new** record is `evidence add`, seller-only and a write — that verb belongs to **`seller-fulfill`**, not this skill.

## Reading Escalations

```bash
kagent escalation list --output json
```

Every escalation this agent has raised, most recent first — its own history, never another agent's; there is no flag that widens it. Filters (`--status`, `--kind`, `--agreement-id`, `--limit`, `--offset`) narrow the same list; an empty result reports `status: success` with zero rows, not an error.

```bash
kagent escalation status --id <id> [--wait] [--timeout <d>]
```

Polls one escalation for its owner's decision. `--wait` blocks with backoff until it leaves `pending` or the timeout elapses; without it, one read. A denial and a lapsed decision window both land on envelope `status: expired` — nothing further will happen either way — but they are distinguishable: a denial reads `escalation_status: "decided"` with a `decision` member recording the owner's no, while a window that lapsed undecided reads `escalation_status: "expired"` with no `decision` at all. `escalation list`'s rows carry the same shape minus the escalation-id path argument, so a caller that already has the list rarely needs a second `status` poll unless watching one escalation change live.

---

## Error Handling

This skill only ever reads, so the write-specific codes (6/7) from `seller-fulfill`'s table are unreachable here.

| Exit Code | Meaning | Recovery |
|-----------|---------|----------|
| 0 | Success | Present the result. `verified: false` on an unverified `proofs` read is not a failure — say so rather than implying it was checked. |
| 1 | Network, or a transient server condition | Retry. |
| 2 | Usage error | Fix the flag (e.g. a missing `--agreement-id` or `--id`). |
| 3 | Auth error (`runtime_key_required`, `runtime_pending`, `runtime_revoked`, ...) | Identity problem — use **`seller-agent-setup`**. |
| 4 | Not found | The agreement or escalation does not exist, or this agent may not read it — another agent's escalation reads this way too, never as forbidden. |
| 5 | Rate limited | Wait 30 seconds, retry. |
| 8 | `PROTOCOL` — a chain failed local verification | Do not settle against it; see `@references/commands.md` for what each failed check means. |

---

## Commands That DO NOT Exist

- `kagent agreement history` -- there is no combined verb; read `agreement proofs` and `agreement evidence list` separately.
- `kagent escalation list --owner` / `--all` -- there is no flag that widens the scope past this agent's own escalations.
- `kagent agreement evidence add` -- that verb exists, but it is a **write** and belongs to **`seller-fulfill`**, not this read-only skill.
- `kagent agreement proofs --verify` on an empty chain -- refused (exit 8); nothing has moved the agreement yet, so there is nothing to verify.
- Any command with `--json` -- the flag is `--output json` (two separate tokens).

---

## Cross-Skill References

- **Prerequisite:** the **`seller-agent-setup`** skill (active runtime binding).
- **To advance a deal** (accept, sign, deliver, register new evidence, respond to a rejection): the **`seller-fulfill`** skill.
- **The buyer's side of the same three reads:** the **`buyer-agreement-history`** skill.
