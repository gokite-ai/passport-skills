# Seller: Fulfill — Worked Examples

Two walkthroughs. The first is a clean fulfilment driven by polling. The second hits the acceptance policy and an interrupted delivery — the two situations where a seller agent most easily makes things worse.

Both assume `seller-agent-setup` left an active binding, a pinned card with a complete chain context, and a published card and terms.

---

## Example 1: A Clean Fulfilment

### 1. Notice the proposal

```bash
kseller agreement list --role seller --output json
```

```
{
  "agreements": [
    { "agreement_id": "agr_7f2a", "state": "PROPOSED", "revision": 1, "role": "seller",
      "buyer_agent_id": "did:kite:example-buyer", "amount": "25", "updated_at": "2026-08-22T09:02:00Z" }
  ],
  "count": 1,
  "page_size": 1
}
```

A service seller would have learned this from `kseller listen --forward ...` as an `agreement.proposed` notification instead — polling only finds it here because something already told this agent to look.

### 2. Read the contract before deciding

```bash
kseller agreement status --agreement-id agr_7f2a --output json
```

```
{
  "status": "success",
  "state": "PROPOSED",
  "revision": 1,
  "role": "seller",
  "buyer_agent_id": "did:kite:example-buyer",
  "terms_hash": "0xab...",
  "amount": "25",
  "arbiter_agent_id": "did:kite:arbiter",
  "contract": {
    "template": "fixed_outcome/v1",
    "price": { "amount": "25", "asset": "USDC" },
    "deliverable": { "summary": "Market research report ... PDF", "acceptanceCriteria": "..." }
  },
  "agreement_sig": { "sig": "0x...", "key_id": "did:kite:example-buyer#k1", "seller_key_id": "did:kite:me#k1" }
}
```

Four things to check before accepting:

- **`price.asset` is `USDC`.** Anything else cannot be funded on this lane — the refusal comes at `funding sign`, after acceptance, which is a worse place to find out.
- **The deliverable is settlable by one artifact's sha256.** That is literally how the buyer accepts.
- **`agreement_sig` is present.** Without the buyer's relayed co-signature, `accept` refuses with exit 1 and there is nothing this agent can do about it.
- **`arbiter_agent_id` is acceptable.** A dispute goes to that arbiter, not to Passport.

### 3. Accept

```bash
kseller agreement accept --agreement-id agr_7f2a --output json
```

```
{
  "status": "success",
  "agreement_id": "agr_7f2a",
  "state": "COMMITTED",
  "revision": 2,
  "terms_hash": "0xab...",
  "seller_key_id": "did:kite:me#k1",
  "amount_base_units": "25000000",
  "buyer_verified": true,
  "hint": "Committed. The funding context opens next, and both parties' Activation signatures are due before the escrow can be funded.",
  "next_command": "kseller agreement funding get --agreement-id agr_7f2a --output json"
}
```

`buyer_verified: true` is the summary of nine local checks: the contract names this agent as seller, the terms hash re-derives from the buyer's own proposal bytes, the buyer's terms signature recovers to a key the buyer has published, and the relayed EIP-712 co-signature recovers to that same key and was built for this agent's key.

### 4. Wait for the buyer to fund, then sign the Activation

```bash
kseller agreement funding get --agreement-id agr_7f2a --output json
```

```
{
  "have_buyer_wallet": false,
  "have_buyer_activation_sig": false,
  "have_seller_activation_sig": false,
  "have_auth_3009": false,
  "activation": { "buyer": "", "amount": "25000000", ... },
  "activation_signable": false
}
```

`activation_signable: false` because the buyer's wallet has not arrived. Signing now returns exit 8 with a hint saying it is a normal stage rather than a fault. Wait:

```bash
kseller agreement status --agreement-id agr_7f2a --watch --output json
kseller agreement funding get --agreement-id agr_7f2a --output json
```

```
{
  "have_buyer_wallet": true,
  "have_buyer_activation_sig": true,
  "have_seller_activation_sig": false,
  "have_auth_3009": true,
  "activation": { "buyer": "0x9c...", ... },
  "activation_signable": true,
  "next_command": "kseller agreement funding sign --agreement-id agr_7f2a --output json"
}
```

```bash
kseller agreement funding sign --agreement-id agr_7f2a --output json
```

```
{
  "status": "success",
  "role": "seller",
  "submitted_member": "sellerActivationSig",
  "amount_base_units": "25000000",
  "validated": [
    "vault domain matches the pinned card",
    "termsHash matches the agreement",
    "the served contract re-derives the agreement's termsHash",
    "amount 25 USDC converts to exactly the Activation's 25000000 base units",
    "sellerPayout matches the contract's escrow.payoutAddress",
    "sellerAgent is this agent's own runtime-key address",
    "buyerAgent, sellerAgent and arbiter are present, and the arbiter matches the contract",
    "the contract's pinned Runtime card is the one this agent pinned",
    "buyer wallet and all five deadline windows are present"
  ]
}
```

### 5. Wait for the escrow, then deliver

```bash
kseller agreement status --agreement-id agr_7f2a --watch --output json
```

```
{ "status": "success", "state": "FULFILLING", "revision": 4, "changed": true }
```

`FULFILLING` means the escrow is funded. Now — and only now — deliver:

```bash
kseller agreement deliver --agreement-id agr_7f2a --file ./report.pdf --output json
```

```
{
  "status": "success",
  "command_id": "cmd_9d3b",
  "command_type": "kite.contract.delivered",
  "state": "DELIVERED",
  "revision": 5,
  "evidence_id": "ev_2b7",
  "evidence_reused": false,
  "artifact_id": "art_5c1",
  "artifact_url": "https://artifacts.../ev_2b7",
  "artifact_duplicate": false,
  "delivery_hash": "sha256:4f1e...",
  "size_bytes": 482113,
  "content_type": "application/pdf",
  "content_file": "./report.pdf",
  "hint": "Delivered. The buyer's own check is what settles this: it downloads the artifact, recomputes sha256, and compares it against the deliveryHash inside this signed command -- so keep the local file until the escrow releases.",
  "next_command": "kseller agreement status --agreement-id agr_7f2a --watch --output json"
}
```

**Keep `./report.pdf`.** If the buyer reports a hash mismatch, the local file is the only way to establish whose bytes moved.

### 6. Watch for settlement

```bash
kseller agreement status --agreement-id agr_7f2a --watch --output json
```

```
{ "status": "success", "state": "ACCEPTED", "revision": 6 }
```

`ACCEPTED` — the buyer confirmed and the escrow released.

---

## Example 2: An Acceptance Policy Refusal and an Interrupted Delivery

### The policy refusal

```bash
kseller agreement accept --agreement-id agr_91c4 --output json
```

```
{
  "status": "error",
  "error_code": "acceptance_policy_violation",
  "error": "...",
  "hint": "The contract falls outside the owner's acceptance policy. Obtain the owner's approval for exactly this contract through the escalation flow, then retry.",
  "next_command": "kseller escalate --kind acceptance-override --agreement-id agr_91c4 --summary <why this deal> --wait --output json"
}
```

Exit 6. The owner configured an acceptance policy and this contract falls outside it. Nothing local is wrong, and **this agent cannot read its own policy** — there is no way to inspect what the boundary is, only to ask the owner to rule on this contract.

The wrong reactions:

- **Retrying `accept`.** The policy is server-side and will refuse identically.
- **Editing the contract.** The contract is the buyer's signed bytes. This agent countersigns them or it does not.
- **Escalating with a vague summary.** The summary is the entire basis for a human's decision.

Escalate, with a summary written for the person who will read it:

```bash
kseller escalate \
  --kind acceptance-override \
  --agreement-id agr_91c4 \
  --summary "Buyer did:kite:example-buyer proposes 25 USDC for a battery-storage market report, due in 48h. Above the usual per-deal ceiling but the buyer has two prior ACCEPTED agreements with us and the deliverable is a standard PDF report." \
  --wait \
  --output json
```

```
{
  "status": "human_action_required",
  "escalation_id": "esc_4a7",
  "escalation_status": "pending",
  "kind": "acceptance-override",
  "enforced": true,
  "approval_url": "https://passport.prod.gokite.ai/approve/esc_4a7",
  "approval_expires_at": "2026-08-22T10:15:00Z",
  "agreement_id": "agr_91c4",
  "next_command": "kseller escalation status --id esc_4a7 --wait --output json"
}
```

`enforced: true` because `acceptance-override` is the reserved kind — an advisory escalation (any other `--kind` string) would record an opinion without unlocking the acceptance gate.

No `--payload` was passed, so the verb attached the contract's verbatim bytes. That is what binds the owner's decision to *this* contract rather than to a category of deals.

Surface the URL:

> This needs your passkey: https://passport.prod.gokite.ai/approve/esc_4a7 — approving lets me accept agreement agr_91c4 (25 USDC report for did:kite:example-buyer), which is outside the current acceptance policy. The link expires at 10:15 UTC.

Then:

```bash
kseller escalation status --id esc_4a7 --wait --output json
```

```
{
  "status": "success",
  "escalation_status": "decided",
  "decision": { "decision": "approved", "decided_at": "...", "terms_hash": "0xcd..." },
  "decided": "approved",
  "hint": "Approved, and bound to this agreement's terms hash. The acceptance gate will admit exactly this contract once -- a second acceptance of the same deal finds the override spent.",
  "next_command": "kseller agreement accept --agreement-id agr_91c4 --output json"
}
```

Re-run `accept`, exactly as the `next_command` says:

```bash
kseller agreement accept --agreement-id agr_91c4 --output json
```

```
{ "status": "success", "state": "COMMITTED", "revision": 2, "buyer_verified": true }
```

The override is now spent. It admitted this contract once; there is no second use.

Had the owner declined, the envelope would be `status: "expired"` with an empty `next_command`. That is a no — do not open a second escalation for the same deal unless the owner asks for one.

### The interrupted delivery

The escrow is funded and delivery starts, but the network drops mid-way:

```bash
kseller agreement deliver --agreement-id agr_91c4 --file ./report.pdf --output json
```

```
{
  "status": "error",
  "error": "network error: ...",
  "hint": "... Delivery stopped with the artifact is stored (art_5c1) and registered as evidence ev_2b7. Re-run the same command with the same --file: the upload is idempotent on content and the evidence step reuses the record already registered for this hash, so a retry resumes rather than duplicating.",
  "next_command": "kseller agreement deliver --agreement-id agr_91c4 --file ./report.pdf --output json"
}
```

The hint says exactly how far it got: the artifact is uploaded and the evidence record exists; only the signed command did not land. Re-run the identical command:

```bash
kseller agreement deliver --agreement-id agr_91c4 --file ./report.pdf --output json
```

```
{
  "status": "success",
  "state": "DELIVERED",
  "evidence_id": "ev_2b7",
  "evidence_reused": true,
  "artifact_id": "art_5c1",
  "artifact_duplicate": true,
  "delivery_hash": "sha256:4f1e..."
}
```

`evidence_reused: true` and `artifact_duplicate: true` confirm the first two steps were reused rather than repeated — same evidence id, same artifact id. This works because the file's sha256 is the identity of the delivery: the upload is idempotent on (agreement, digest), and the evidence step reads the existing records and matches on the digest before writing.

**Re-run with the same `--file`.** A different file is a different digest, which is a different delivery, not a resume.

### And if the escrow was not funded

```bash
kseller agreement deliver --agreement-id agr_91c4 --file ./report.pdf --output json
```

```
{
  "status": "error",
  "error": "Agreement agr_91c4 carries no buyer payment authorization yet, so the escrow is not funded.",
  "hint": "Nothing was sent, and the deliverable was NOT uploaded. Handing over the work before the buyer's payment is committed is what escrow exists to prevent; wait for the funding step and re-run.",
  "next_command": "agreement funding get --agreement-id agr_91c4 --output json"
}
```

Exit 8, and the important part is in the hint: **the file was not uploaded.** The guard runs before step 3, so no work has been handed over. Note the `next_command` is missing the `kseller` prefix — prepend it:

```bash
kseller agreement funding get --agreement-id agr_91c4 --output json
```

Wait for the buyer, then re-run the deliver.

### A second delivery after the first succeeded

```bash
kseller agreement deliver --agreement-id agr_91c4 --file ./report-v2.pdf --output json
```

```
{
  "status": "error",
  "error_code": "illegal_transition",
  "hint": "The command is not legal from the agreement's current state. Re-read its status to see which commands are."
}
```

Exit 7, and this is the correct answer rather than a bug to work around. A delivered agreement has one signed deliverable, committed to by a `deliveryHash` the buyer is verifying against. Replacing it after the fact would break exactly the guarantee the buyer relies on. If the delivered artifact was wrong, that is a conversation with the buyer (`message send`) and, if they reject, a matter for the contract's arbiter.
