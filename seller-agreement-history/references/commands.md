# Seller Agreement History — Command Reference

Full command reference for the `seller-agreement-history` skill. SKILL.md carries the trigger logic, prerequisites, defaults, and a condensed error table; this file has the command-level detail. Worked end-to-end examples live in `examples.md`.

All commands here are `kagent ...` — signed with this agent's runtime key, exactly like `seller-fulfill`'s writes, but none of these mutate anything.

---

## `agreement proofs` — Read the Transition-Proof Chain

```
kagent agreement proofs --agreement-id <id> --output json
```

With verification:

```
kagent agreement proofs --agreement-id <id> --verify [--signer-agent <ref>] --output json
```

### Arguments

| Argument | Flag | Required | Notes |
|---|---|---|---|
| Agreement id | `--agreement-id` | Yes | From `agreement list` or a prior step. |
| Verify | `--verify` | No | Recomputes and checks the chain locally instead of trusting the server. |
| Signer attestation source | `--signer-agent` | No | Which agent's published signing keys attest the chain. Default: read from the contract's `runtimeBinding.runtimeAgentId`, falling back to this agent's own pinned coordination persona. Only override when auditing a chain whose Runtime is not the pinned one. |

### What `--verify` Actually Checks

Three independent claims, all local:

1. **Linkage** — each link's `previousProofHash` equals its predecessor's `proofHash`. Proves internal consistency only; on its own, a malicious server could still serve a self-consistent fake chain.
2. **Recomputation** — each link's `proofHash` is exactly what its own members hash to. This is what binds content to attestation: a link edited after the fact stops producing the hash it claims.
3. **Signatures** — each link's `signedBy` address recovers a valid signature over the link's content, and that address was one of the attesting agent's published signing keys **at the time the link was created** (revoked keys still validate against their now-closed validity window — a key revoked yesterday can validly sign a link from last week).

An **unsigned** link fails the check too: an engine deployed without a proof-signer key serves the record unsigned, and an unsigned record is not a proof no matter how consistent it looks.

### Success Output — Unverified Read (exit 0)

```json
{
  "agreement_id": "agr_7f2a",
  "count": 3,
  "proofs": [
    {
      "sequence": 1,
      "fromState": "",
      "toState": "COMMITTED",
      "event": "agreement.accepted",
      "actorId": "did:kite:this-seller",
      "signedBy": "0xabc123...",
      "proofHash": "sha256:...",
      "previousProofHash": ""
    }
    /* ...sequences 2 and 3 elided; all served links appear here... */
  ],
  "verified": false,
  "_version": "1",
  "status": "success",
  "hint": "3 proof link(s), as served and unverified.",
  "next_command": "kagent agreement proofs --agreement-id agr_7f2a --verify --output json"
}
```

`proofs` is passed through **verbatim** from what the engine served — a member this CLI does not name is still present in the JSON.

### Success Output — No Links Yet (exit 0)

```json
{
  "agreement_id": "agr_7f2a",
  "count": 0,
  "proofs": [],
  "verified": false,
  "_version": "1",
  "status": "success",
  "hint": "No transition proofs yet: nothing has moved this agreement.",
  "next_command": "kagent agreement proofs --agreement-id agr_7f2a --verify --output json"
}
```

Note the `next_command` still offers `--verify` here, but running it against zero links is refused (see Error Output below) — offering it is a template, not a guarantee it will succeed.

### Success Output — Verified (exit 0)

```json
{
  "agreement_id": "agr_7f2a",
  "count": 3,
  "proofs": [ /* ... */ ],
  "verified": true,
  "receipt_hash_for_next_command": "sha256:...",
  "sequence": [1, 2, 3],
  "chain_linked": true,
  "proof_hashes_recomputed": true,
  "signatures_verify": true,
  "signer_attested": true,
  "signer_agent": "did:kite:this-seller",
  "_version": "1",
  "status": "success",
  "hint": "3 link(s) verified: ordered, linked, recomputed, and signed by an attested key.",
  "next_command": ""
}
```

`receipt_hash_for_next_command` is the newest link's `proofHash` — the value a settlement signature would quote next. `signer_attested` reports whether every link's `signedBy` was found in the attesting agent's published key set. An unreadable key set (the signer agent's keys cannot be resolved) fails the verification like any other check: exit 8 (`PROTOCOL`), `status: "error"`, `verified: false`, with `attestation_notes` in `details` naming the resolution failure. The note distinguishes this from a bad signature — the signatures themselves may have verified — but a chain whose signer cannot be attested is never reported as verified.

### A Chain That Ends in `SETTLED_MUTUAL`

A deal closed by the co-signed split (`kite.contract.settle_mutual`) ends on a
fourth terminal class — a **negotiated resolution**, not an acceptance, not a
cancellation or refund, and not an arbiter's ruling. The two links that record
it are the only ones in the vocabulary carrying two party signatures for one
transition:

```json
{
  "sequence": 5,
  "fromState": "DELIVERED",
  "toState": "SETTLING_MUTUAL",
  "event": "MUTUAL_SETTLEMENT_SUBMITTED",
  "actorId": "did:kite:this-seller",
  "signedBy": "0xabc123...",
  "proofHash": "sha256:...",
  "previousProofHash": "sha256:...",
  "metadata": {
    "seller_bps": 6200,
    "buyer_sig": "0x...",
    "seller_sig": "0x..."
  }
}
```

- `seller_bps` is the committed split in basis points: `6200` sends 62 percent
  of the escrow to the seller and the remainder back to the buyer. `0` is legal
  and means both parties agreed nothing was payable; `10000` cannot appear,
  because a full release is an acceptance and the verb refuses it.
- `buyer_sig` and `seller_sig` are both vault-domain EIP-712 signatures over
  **one** `MutualSettlement` struct. Two signatures on one link is the whole
  point: neither party could move the deal alone, and the vault — not the
  engine — verified them.
- `MUTUALLY_SETTLED` follows once the vault call is observed, landing the deal
  on `SETTLED_MUTUAL`. A `RELAY_FAILED` instead returns it to the origin the
  `SETTLING_MUTUAL*` state is named for (`DELIVERED`, `REJECTED`, or
  `DISPUTED`), so an in-flight state mid-chain is a retry rather than a dead
  end.
- The origin the split came from is readable off `fromState`, which is what
  distinguishes a split of a delivered batch from one negotiated after a
  rejection or during a dispute.

`--verify` treats these links like any other: linkage, recomputation, and
signature recovery against the attesting agent's published keys. The chain's
`signedBy` is the engine's proof-signer, not either party's settlement
signature — the two party signatures are content inside the link, and what
attests them is the vault's own execution.

For the amounts that actually moved, read the `settlement` legs on
`kagent agreement status` rather than deriving them from `seller_bps`: a deal
where a fee also moved value does not sum from the basis points alone. That
read also carries `seller_bps` directly, so quantifying the split needs no
chain query.

Event and state spellings are passed through **verbatim** from the engine, so
match on them rather than reformatting, and an unfamiliar spelling is not a
reason to treat a link as malformed.

### Error Output — Verification Failed (exit 8, `PROTOCOL`)

```json
{
  "_version": "1",
  "status": "error",
  "error": "The transition-proof chain for agr_7f2a did not verify: link 2's proofHash does not match its recomputed value",
  "hint": "Do not settle against this chain. The newest proofHash is the receiptHash a settlement signature quotes, so signing against a chain that does not verify would commit to an anchor nobody can vouch for.",
  "details": {
    "agreement_id": "agr_7f2a",
    "verified": false,
    "chain_linked": true,
    "proof_hashes_recomputed": false,
    "recompute_errors": ["link 2's proofHash does not match its recomputed value"]
  },
  "next_command": ""
}
```

### Error Output — Nothing to Verify (exit 8)

```json
{
  "_version": "1",
  "status": "error",
  "error": "Agreement agr_7f2a has no transition proofs, so there is no chain to verify.",
  "hint": "An empty chain is not a verified one. Nothing has moved this agreement yet.",
  "next_command": ""
}
```

---

## `agreement evidence list` — Read Registered Evidence

```
kagent agreement evidence list --agreement-id <id> --output json
```

### Arguments

| Argument | Flag | Required |
|---|---|---|
| Agreement id | `--agreement-id` | Yes |

### Success Output — Records Found (exit 0)

```json
{
  "agreement_id": "agr_7f2a",
  "evidence": [
    {
      "evidence_id": "evd_abc123",
      "type": "delivery",
      "hash": "sha256:...",
      "url": "https://...",
      "format": "application/pdf",
      "recorded_at": "2026-08-20T10:00:00Z",
      "size_bytes": 48213
    }
  ],
  "records": [ /* raw records, verbatim */ ],
  "count": 1,
  "_version": "1",
  "status": "success",
  "hint": "1 evidence record(s). The hash is the binding value -- compare a downloaded artifact's sha256 against it, and against the deliveryHash in the seller's signed deliver command.",
  "next_command": ""
}
```

`evidence` is this CLI's decoded projection; `records` is the raw server response passed through untouched, so a member the projection does not name is still readable there.

### Success Output — No Evidence Yet (exit 0)

```json
{
  "agreement_id": "agr_7f2a",
  "evidence": [],
  "records": [],
  "count": 0,
  "_version": "1",
  "status": "success",
  "hint": "No evidence is registered on this agreement yet, so no deliver command can cite any.",
  "next_command": ""
}
```

Registering the first record is `evidence add` (seller-only, a write) — see `seller-fulfill/references/commands.md`.

---

## `escalation list` — This Agent's Own Escalation History

```
kagent escalation list --output json
```

Full form with all optional filters:

```
kagent escalation list \
  --status <s> \
  --kind <k> \
  --agreement-id <id> \
  --limit <n> \
  --offset <n> \
  --output json
```

### Arguments

| Argument | Flag | Required | Validation |
|---|---|---|---|
| Status filter | `--status` | No | One of `pending`, `decided`, `expired`, `approved`, `denied`, `consumed` |
| Kind filter | `--kind` | No | Any escalation kind this agent has raised (typically `acceptance-override`, or an advisory kind) |
| Agreement filter | `--agreement-id` | No | Narrows to escalations raised against one agreement |
| Limit | `--limit` | No | Server default when omitted; caps how many rows come back |
| Offset | `--offset` | No | Pagination offset; cannot be negative |

Scoped **entirely** to this agent's own identity, verified from the signed envelope — there is no flag that widens it to another agent's escalations, and none is planned. This mirrors `escalation status`'s existing posture: another agent's record reads as not-found, never as forbidden.

### Success Output — Escalations Found (exit 0)

```json
{
  "escalations": [
    {
      "escalation_id": "agent_escalation_01HZY",
      "kind": "acceptance-override",
      "status": "pending",
      "agreement_id": "agr_7f2a",
      "session_id": "",
      "principal_role": "seller",
      "action_kind": "",
      "action_digest": "",
      "reason_code": "",
      "controller_decision_deadline": "2026-08-21T10:00:00Z",
      "action_deadline": "2026-08-20T18:00:00Z",
      "decision": null,
      "created_at": "2026-08-20T10:00:00Z"
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0,
  "_version": "1",
  "status": "success",
  "hint": "1 escalation(s) of 1 total.",
  "next_command": "kagent escalation status --id agent_escalation_01HZY --output json"
}
```

A decided row carries a non-null `decision`: `{"decision": "approved", "decided_at": "...", "payload_hash": "sha256:...", "terms_hash": "sha256:..."}` (`terms_hash` present for `acceptance-override`).

### Success Output — No Escalations (exit 0)

```json
{
  "escalations": [],
  "total": 0,
  "limit": 50,
  "offset": 0,
  "_version": "1",
  "status": "success",
  "hint": "No escalations raised (with these filters, if any).",
  "next_command": ""
}
```

---

## `escalation status` — Poll One Escalation

```
kagent escalation status --id <id> [--wait] [--timeout <d>]
```

See `seller-fulfill/references/commands.md` for the full argument table and every JSON shape (pending / human_action_required, decided/approved, decided/denied, expired) — this skill uses the identical read, just as a standalone lookup rather than a step inside the fulfilment flow.

---

## Input Validation Checklist

Before running any command, verify:

1. **`--agreement-id`** on `proofs`/`evidence list`: from `agreement list` or a prior step. Never fabricated.
2. **`--id`** on `escalation status`: from `escalation list`, `escalate`, or a prior step.
3. **`--status`** on `escalation list`, if given: one of `pending`, `decided`, `expired`, `approved`, `denied`, `consumed`.
4. **`--limit`/`--offset`** on `escalation list`, if given: non-negative.
5. Before citing a proof chain to the owner as trustworthy, run it with **`--verify`** — an unverified read is a fetch, not an audit.
