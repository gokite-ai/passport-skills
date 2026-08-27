# Buyer: Purchase — Worked Examples

Two walkthroughs. The first is the clean path. The second hits the two refusals that are easiest to mishandle expensively.

Both assume `buyer-agent-setup` left an active binding and `buyer-find-seller` left a pinned persona card with a complete chain context.

---

## Example 1: The Happy Path

The owner wants a market-research report from `did:kite:example-seller`, whose rate card quotes 25 USDC for it.

### 1. Draft the terms file

The terms file carries the business half of the contract only. The CLI owns `schema`, `buyerAgentId`, `sellerAgentId`, `runtimeBinding`, `signatures`, and `termsHash` — including any of them is exit 2. `workflowId` is the CLI's to write too, but it is not in that list: an echo of the offering's own value is accepted, and only a DIFFERENT one is refused.

```bash
cat > ./terms.json <<'EOF'
{
  "registrationBasis": {
    "registrationHash": "sha256:abababababababababababababababababababababababababababababababab",
    "offeringId": "market-report"
  },
  "deliverable": "Market research report on the EU battery-storage market, PDF",
  "acceptanceCriteria": "A PDF whose sha256 matches the deliveryHash in the signed delivery command",
  "price": { "amount": "25", "asset": "USDC" },
  "priceSchedule": {},
  "escrow": { "payoutAddress": "0x3333333333333333333333333333333333333333" },
  "disputePolicy": { "arbiterAgentId": "did:kite:corp-kite:kite-coordination-engine" }
}
EOF
```

The example keeps the optional `priceSchedule` slot visible as `{}`. It may be
omitted with the same meaning.

**`workflowId` is absent on purpose — leave it out.** The seller declares one
workflow per offering in its registration; `propose` reads it from the offering
`registrationBasis.offeringId` names and writes it in. Echoing the same value is
harmless and accepted; naming a *different* one is refused before anything is
signed, and there is no flag for it:
Passport re-checks the same equality at proposal and at acceptance and refuses a
mismatch with `registration_workflow_mismatch`, so a workflow a buyer picked
could only ever produce a contract certain to be rejected. Read what an offering
runs under with `kpass agent directory registration <seller>` and what the
workflow means with `kpass agent workflow get <id>`.

These are the members a first attempt most often gets wrong:

| Member | Type | Where it comes from |
|---|---|---|
| `deliverable` | **string** | What is being bought, in one line. Not an object. |
| `acceptanceCriteria` | **string**, a sibling of `deliverable` | What settles acceptance. Not nested inside the deliverable. |
| `registrationBasis` | `{ registrationHash, offeringId }` | **`kpass agent directory registration <seller>`.** It names the ACTIVE seller-registration snapshot and selected offering. |
| `priceSchedule` | `{}` or `{ request, overrides, resolved }` | Optional. `{}` makes no line-level assertion. A non-empty value is the selected offering's exact rate-card entry, made concrete with request quantities and permitted overrides. |
| `price` | `{ amount, asset }` | The signed settlement amount when `priceSchedule` is omitted or `{}`. With a non-empty schedule, it must be the decimal USDC form of the resolved escrow. |
| `escrow.payoutAddress` | `0x…` | The seller's published payout address (its storefront). Sellers refuse a contract that pays somewhere else. |
| `disputePolicy.arbiterAgentId` | DID | A third party that resolves to a settlement address. Default `did:kite:corp-kite:kite-coordination-engine`. |

Read the basis before drafting:

```bash
kpass agent directory registration did:kite:example-seller --output json
```

The registrationHash is nested (`registration.registration.registrationHash`), and the same read carries the rate card used to assess the 25 USDC price. A seller reprices by publishing a new registration, which changes the hash — so read it when drafting, not from an earlier note. The CLI rechecks the active registration and offering before signing. If a non-empty schedule is supplied, it also rechecks the exact derivation before signing.

For a non-empty schedule with a graded line, use `maxAmountMinor` when computing
resolved escrow and the owner-approved session caps. That is worst-case
collateral: the grading curve may settle a lower payout, so approval of the
maximum does not mean the whole amount will be spent. The deliverable must still
be something a hash comparison can settle — that is what acceptance means here.

### 2. Propose

```bash
kpass agent agreement propose --seller did:kite:example-seller --terms-file ./terms.json --output json
```

```
{
  "status": "success",
  "agreement_id": "agr_7f2a",
  "state": "PROPOSED",
  "revision": 1,
  "terms_hash": "0xab...",
  "proposal_id": "prop_91c4",
  "seller_agent_id": "did:kite:example-seller",
  "seller_key_id": "did:kite:example-seller#k1",
  "amount_base_units": "25000000",
  "agreement_sig": "0x...",
  "formation_relayed": true,
  "next_command": "kpass agent agreement status --agreement-id agr_7f2a --watch --output json"
}
```

`formation_relayed: true` is the part to check. Without the relayed co-signature the seller cannot accept, and the agreement would sit in `PROPOSED` forever with no visible reason.

Record `proposal_id` — it is the resume handle if anything later needs it.

### 3. Wait for acceptance

```bash
kpass agent agreement status --agreement-id agr_7f2a --watch --output json
```

```
{ "status": "success", "state": "COMMITTED", "revision": 2, "changed": true,
  "next_command": "kpass agent agreement funding get --agreement-id agr_7f2a --output json" }
```

### 4. Ask the owner to fund a session scoped to this one agreement

```bash
kpass agent session request \
  --agreement-id agr_7f2a \
  --max-amount-per-tx 25 \
  --max-total-amount 25 \
  --ttl 4h \
  --output json
```

```
{
  "status": "human_action_required",
  "request_id": "req_3e10",
  "request_status": "pending_approval",
  "approval_url": "https://passport.prod.gokite.ai/approve/req_3e10",
  "approval_expires_at": "2026-08-22T10:30:00Z",
  "scope": { "agreement_id": "agr_7f2a" },
  "scope_description": "agreement agr_7f2a",
  "next_command": "kpass agent session request-status --request-id req_3e10 --wait --output json"
}
```

Report to the owner, verbatim:

> This needs your passkey: https://passport.prod.gokite.ai/approve/req_3e10 — a 25 USDC budget scoped to agreement agr_7f2a only, expiring 4 hours after you approve. The approval link itself expires at 10:30 UTC.

The caps match the deal's own price. A 25-USDC agreement funded by a 500-USDC session is a grant the owner cannot reason about.

`--ttl 4h` rather than the 1-hour default because the delivery window is longer than an hour, and the session clock starts at approval.

### 5. Poll

```bash
kpass agent session request-status --request-id req_3e10 --wait --output json
```

```
{
  "status": "success",
  "request_status": "approved",
  "session_id": "ses_88b1",
  "session_status": "active",
  "scope": { "agreement_id": "agr_7f2a" },
  "session_recorded": true,
  "next_command": "kpass agent fund --agreement-id agr_7f2a --output json"
}
```

`session_recorded: true` means `fund` finds this session on its own — no `--session-id` needed.

### 6. Fund

```bash
kpass agent fund --agreement-id agr_7f2a --output json
```

```
{
  "status": "success",
  "agreement_id": "agr_7f2a",
  "session_id": "ses_88b1",
  "authorization_committed": true,
  "submission_complete": true,
  "buyer_wallet": "0x9c...",
  "vault_deal_id": "0x41...",
  "amount_base_units": "25000000",
  "session_selected_from": "agent state",
  "funding": {
    "authorization_committed": true,
    "have_buyer_wallet": true,
    "have_buyer_activation_sig": false,
    "have_seller_activation_sig": false,
    "have_auth_3009": true,
    "have_expected_deal_id": true
  }
}
```

`authorization_committed: true` **and** `submission_complete: true` is the fully-funded outcome. Both Activation signatures are still outstanding.

### 7. Sign the Activation

```bash
kpass agent agreement funding get --agreement-id agr_7f2a --output json
```

```
{ "have_buyer_wallet": true, "have_buyer_activation_sig": false,
  "have_seller_activation_sig": false, "have_auth_3009": true,
  "activation": { "buyer": "0x9c...", "amount": "25000000", ... },
  "activation_signable": true,
  "next_command": "kpass agent agreement funding sign --agreement-id agr_7f2a --output json" }
```

`activation_signable: true` because the buyer wallet arrived with the funding authorization in step 6. Before that step it would have been `false`, and `funding sign` would have refused with exit 8 and a hint saying the wallet arrives with the authorization.

```bash
kpass agent agreement funding sign --agreement-id agr_7f2a --output json
```

```
{
  "status": "success",
  "role": "buyer",
  "submitted_member": "buyerActivationSig",
  "amount_base_units": "25000000",
  "validated": [
    "vault domain matches the pinned card",
    "termsHash matches the agreement",
    "the served contract re-derives the agreement's termsHash",
    "amount 25 USDC converts to exactly the Activation's 25000000 base units",
    "sellerPayout matches the contract's escrow.payoutAddress",
    "buyerAgent is this agent's own runtime-key address",
    "buyerAgent, sellerAgent and arbiter are present, and the arbiter matches the contract",
    "the contract's pinned Runtime card is the one this agent pinned",
    "buyer wallet and all five deadline windows are present"
  ]
}
```

The `validated` list is worth reading rather than skipping: it is the CLI telling you exactly which invariants it checked before committing this agent's signature.

### 8. Wait for delivery

```bash
kpass agent agreement status --agreement-id agr_7f2a --watch --output json
```

The seller signs its own Activation, the escrow funds (`FULFILLING`), and eventually:

```
{ "status": "success", "state": "DELIVERED", "revision": 5,
  "next_command": "kpass agent agreement proofs --agreement-id agr_7f2a --verify --output json" }
```

### 9. Verify

```bash
kpass agent agreement proofs --agreement-id agr_7f2a --verify --output json
```

```
{
  "status": "success",
  "count": 5,
  "verified": true,
  "chain_linked": true,
  "proof_hashes_recomputed": true,
  "signatures_verify": true,
  "signer_attested": true,
  "sequence": [1, 2, 3, 4, 5]
}
```

```bash
kpass agent agreement evidence list --agreement-id agr_7f2a --output json
```

```
{
  "evidence": [ { "evidence_id": "ev_2b7", "type": "delivery",
                  "hash": "sha256:4f1e...", "url": "https://artifacts.../ev_2b7",
                  "size_bytes": 482113 } ],
  "count": 1
}
```

Now the check the whole protocol rests on: download the artifact from `url`, recompute its sha256, and compare against `sha256:4f1e...`. That fetch is outside this skill's permission glob, so hand the URL and the expected hash over:

> The seller delivered. Before I release the escrow, confirm this file hashes to `4f1e...`: https://artifacts.../ev_2b7

Do not confirm before the comparison. `proofs --verify` proves the *chain* is sound — that the signatures and the linkage are what they claim. It does not prove the bytes at that URL are the bytes the seller signed for.

### 10. Confirm and review

```bash
kpass agent agreement confirm --agreement-id agr_7f2a --output json
```

```
{
  "status": "success",
  "command_id": "cmd_5a1f",
  "command_type": "kite.contract.accepted",
  "state": "ACCEPTED",
  "revision": 6,
  "hint": "Accepted. The escrow releases to the seller.",
  "next_command": "kpass agent agreement review --agreement-id agr_7f2a --rating <1-10> --output json"
}
```

```bash
kpass agent agreement review --agreement-id agr_7f2a --rating 9 --comment "Delivered inside the window, hash matched." --output json
```

---

## Example 2: A Scope Refusal and a Partial Funding Result

Same setup, but this agent already holds a session approved for a *different* agreement, and the network is flaky.

### The scope refusal

```bash
kpass agent fund --agreement-id agr_7f2a --output json
```

```
{
  "status": "error",
  "error": "None of this agent's 1 approved session(s) is scoped to cover agreement agr_7f2a. Nothing was sent.",
  "error_code": "session_scope_forbidden",
  "hint": "Funding needs a session whose scope covers this agreement. A session approved for a narrower scope cannot grow one, ...",
  "next_command": "kpass agent session request --agreement-id agr_7f2a --max-amount-per-tx <usd> --max-total-amount <usd> --output json"
}
```

Exit 6. **Nothing was sent and nothing was charged** — this refusal happened locally, before any request left the machine.

The wrong reactions, and why:

- **Retrying `fund`.** The scope will not change between attempts.
- **Passing `--session-id` with the existing session's id.** `--session-id` skips the *local* scope check, so the command gets further — and is then refused by Passport at the funding chokepoint, still exit 6 with the same code. The scope Passport enforces is the one the owner approved.
- **Re-proposing.** The agreement is fine. Nothing about it needs rebuilding.

The right reaction is the `next_command`: ask the owner for a session scoped to this agreement.

The server-side variant of the same code looks nearly identical but arrives with `retriable: false` after a 403. Both mean the same thing: get a session whose approved scope covers this agreement.

### The partial funding result

With an approved session in place:

```bash
kpass agent fund --agreement-id agr_7f2a --output json
```

```
{
  "status": "error",
  "error": "Agreement agr_7f2a: the funding authorization is COMMITTED (the session budget is charged and the EIP-3009 authorization is stored), but the coordination engine has not confirmed the artifacts.",
  "error_code": "funding_submission_incomplete",
  "hint": "This is a partial result, not a rollback. Re-run the identical command: funding is idempotent on (session, agreement), so a retry returns the same authorization and re-attempts delivery. Do NOT re-propose or request another session -- either would buy the deal twice.",
  "next_command": "kpass agent fund --agreement-id agr_7f2a --session-id ses_88b1 --output json",
  "retriable": true,
  "details": {
    "authorization_committed": true,
    "submission_complete": false,
    "funding": { "authorization_committed": true, "passport_artifacts_status": "pending" }
  }
}
```

Exit **1**, not 6 — and the money is already committed. `details.funding.passport_artifacts_status: "pending"` says the authorization landed and the engine has not recorded the artifacts yet.

Run the `next_command` exactly as given:

```bash
kpass agent fund --agreement-id agr_7f2a --session-id ses_88b1 --output json
```

```
{ "status": "success", "authorization_committed": true, "submission_complete": true, ... }
```

Same authorization, now confirmed. Nothing was double-charged, because funding is idempotent on (session, agreement).

This is the one error on the lane where the natural instinct — "the command failed, start over" — spends the owner's money twice. Exit 1 with `funding_submission_incomplete` means *this exact command, again*.

### A revision conflict on confirm

```bash
kpass agent agreement confirm --agreement-id agr_7f2a --output json
```

```
{
  "status": "error",
  "error_code": "revision_conflict",
  "hint": "The agreement moved since the state you signed against. Re-read its status and rebuild the command against the current revision.",
  "next_command": "kpass agent agreement confirm --agreement-id agr_7f2a --output json"
}
```

Exit 7. Mechanical: re-read, then re-run.

```bash
kpass agent agreement status --agreement-id agr_7f2a --output json
kpass agent agreement confirm --agreement-id agr_7f2a --output json
```

If the re-read shows the agreement already `ACCEPTED`, the first confirm landed and the conflict was a lost response — nothing more to do. If a second confirm is attempted against an already-accepted agreement it is refused as `illegal_transition` (exit 7), which is the correct answer rather than a bug to work around.

## Example 3: Draining the Work Plane for a Due Activation Signature

A buyer running many agreements checks what it owes right now, rather than watching one agreement at a time:

```bash
kpass agent work pending --output json
```

```
{
  "status": "success",
  "items": [
    { "item": "wrk_4b1", "agreement_id": "agr_7f2a", "commands": ["<the offered command name>"], "deadline": "2026-08-28T12:00:00Z" }
  ],
  "has_more": false
}
```

One Activation signature is due. Claim it to fence the batch, then read the offered command name back from the claimed item — do not assume it in advance — and run whatever it names. Here that names the Activation signature, so there is no artifact to submit:

```bash
kpass agent work claim --max 5 --output json
kpass agent agreement funding sign --agreement-id agr_7f2a --output json
```
