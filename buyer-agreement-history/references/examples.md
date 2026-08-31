# Buyer Agreement History — Worked Examples

End-to-end walkthroughs for the `buyer-agreement-history` skill. Per-command syntax, arguments, and JSON shapes live in `commands.md`; the mandatory prerequisites and defaults live in SKILL.md.

---

## Complete Worked Example: "What Happened to This Agreement?"

**Context:** The owner asks "What happened to agreement `agr_7f2a`? Did the delivery go through?"

**Step 1:** Read the proof chain, verified.

```bash
kpass agent agreement proofs --agreement-id agr_7f2a --verify --output json
```

Output (abbreviated — the full verified shape, including the verbatim `proofs` array, `_version`, and `next_command`, is in `commands.md`):

```json
{
  "agreement_id": "agr_7f2a",
  "count": 3,
  "verified": true,
  "sequence": [1, 2, 3],
  "chain_linked": true,
  "proof_hashes_recomputed": true,
  "signatures_verify": true,
  "signer_attested": true,
  "receipt_hash_for_next_command": "sha256:1f9e0d...",
  "status": "success",
  "hint": "3 link(s) verified: ordered, linked, recomputed, and signed by an attested key."
}
```

**Step 2:** Read what was delivered.

```bash
kpass agent agreement evidence list --agreement-id agr_7f2a --output json
```

Output:

```json
{
  "agreement_id": "agr_7f2a",
  "evidence": [
    {
      "evidence_id": "evd_abc123",
      "type": "delivery",
      "hash": "sha256:cde456...",
      "url": "https://passport.example/artifacts/evd_abc123",
      "recorded_at": "2026-08-20T15:00:00Z"
    }
  ],
  "count": 1,
  "status": "success",
  "hint": "1 evidence record(s). The hash is the binding value..."
}
```

**Step 3:** Present to the owner:

> Agreement `agr_7f2a`: 3 verified state transitions, all signed and internally consistent. Delivery landed 2026-08-20 — one artifact registered, hash `sha256:cde456...`. Note the chain's receipt hash (`receipt_hash_for_next_command`) is the newest proof link's `proofHash`, not the artifact hash — it vouches for the transition record, not the bytes. To verify the artifact itself, download it and compare its own sha256 against the registered evidence hash, and against the `deliveryHash` in the seller's signed deliver command when that value is available; until then, artifact verification has not been established.

---

## Complete Worked Example: Listing Open Escalations

**Context:** The owner asks "Do I have anything waiting on me for this agent?"

```bash
kpass agent escalation list --status pending --output json
```

Output:

```json
{
  "escalations": [
    {
      "escalation_id": "agent_escalation_01HZY",
      "kind": "acceptance-override",
      "status": "pending",
      "agreement_id": "agr_7f2a",
      "controller_decision_deadline": "2026-08-21T10:00:00Z",
      "created_at": "2026-08-20T10:00:00Z"
    }
  ],
  "total": 1,
  "status": "success",
  "hint": "1 escalation(s) of 1 total.",
  "next_command": "kpass agent escalation status --id agent_escalation_01HZY --output json"
}
```

Present: "One pending escalation on `agr_7f2a` — an acceptance-override that needs your decision by 2026-08-21T10:00:00Z. Decide it at the approval URL from when this agent originally raised it, or on Passport web's Governance page; `escalation status --id agent_escalation_01HZY` reports the decision state but does not carry the link."

If the escalation was raised a while ago and the approval URL was lost, note that `escalation list`/`status` do not re-mint it — the URL comes from the original `escalate` response or Passport web's Governance page for this agent.

---

## Complete Worked Example: A Proof Chain That Fails to Verify

**Context:** Something looks off about a delivery, and the owner wants it checked before trusting it.

```bash
kpass agent agreement proofs --agreement-id agr_9k2p --verify --output json
```

Output (exit 8):

```json
{
  "status": "error",
  "error": "The transition-proof chain for agr_9k2p did not verify: link 2's signature does not recover to an attested key",
  "hint": "Do not settle against this chain. The newest proofHash is the receiptHash a settlement signature quotes, so signing against a chain that does not verify would commit to an anchor nobody can vouch for.",
  "details": {
    "chain_linked": true,
    "proof_hashes_recomputed": true,
    "signatures_verify": false,
    "signature_errors": ["link 2's signature does not recover to an attested key"]
  }
}
```

**Do not** treat this as a transient failure to retry — it is a local, cryptographic finding. Present it plainly:

> The proof chain for `agr_9k2p` did NOT verify: link 2's signature does not recover to a key the seller's coordination persona has published. This is not something to retry — it means the chain as served cannot be trusted. Do not treat any delivery on this agreement as confirmed until this is resolved; consider raising an escalation or contacting the seller directly.

Re-running the identical command will report the identical failure — the chain itself did not change, and nothing here has a retriable classification.

---

## Complete Worked Example: Paginating a Long Escalation History

**Context:** This agent has raised many escalations over its lifetime.

**Page 1:**

```bash
kpass agent escalation list --limit 20 --offset 0 --output json
```

Check the response: if `offset + escalations.length < total`, fetch the next page.

**Page 2:**

```bash
kpass agent escalation list --limit 20 --offset 20 --output json
```

Continue until `offset + escalations.length >= total`.
