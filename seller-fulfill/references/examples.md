# Seller: Fulfill — Worked Examples

Two walkthroughs. The first is a clean fulfilment driven by polling. The second hits the acceptance policy and an interrupted delivery — the two situations where a seller agent most easily makes things worse.

Both assume `seller-agent-setup` left an active binding, a pinned card with a complete chain context, and a published card and terms.

---

## Example 1: A Clean Fulfilment

### 1. Notice the proposal

```bash
kagent agreement list --role seller --output json
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

A service seller would have learned this from `kagent listen --forward ...` as an `agreement.proposed` notification instead — polling only finds it here because something already told this agent to look.

### 2. Read the contract before deciding

```bash
kagent agreement status --agreement-id agr_7f2a --output json
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
  "arbiter_agent_id": "did:kite:corp-kite:demo-arbiter",
  "contract": {
    "workflow": { "templateId": "standard/v1", "workflowHash": "sha256:…", "chartHash": "sha256:…", "config": {}, "configHash": "sha256:…" },
    "registrationBasis": {
      "registrationHash": "sha256:abababababababababababababababababababababababababababababababab",
      "offeringId": "market-report"
    },
    "price": { "amount": "25", "asset": "USDC" },
    "priceSchedule": {},
    "deliverable": "Market research report ... PDF",
    "acceptanceCriteria": "A PDF whose sha256 matches the deliveryHash"
  },
  "agreement_sig": { "sig": "0x...", "key_id": "did:kite:example-buyer#k1", "seller_key_id": "did:kite:me#k1" }
}
```

Five things to check before accepting:

- **`registrationBasis` and `price` match the intended active offering.** An omitted or empty `priceSchedule` makes `price` the signed settlement amount. If the schedule is non-empty, inspect its concrete request quantities, every override, resolved lines and required escrow; `price.amount` must be the decimal form of that escrow.
- **`price.asset` is `USDC`.** Anything else cannot be funded on this lane — the refusal comes at `funding sign`, after acceptance, which is a worse place to find out.
- **The deliverable is settlable by one artifact's sha256.** That is literally how the buyer accepts.
- **`agreement_sig` is present.** Without the buyer's relayed co-signature, `accept` refuses with exit 1 and there is nothing this agent can do about it.
- **`arbiter_agent_id` is acceptable.** A dispute goes to that arbiter, not to Passport.

### 3. Accept

```bash
kagent agreement accept --agreement-id agr_7f2a --output json
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
  "next_command": "kagent agreement funding get --agreement-id agr_7f2a --output json"
}
```

`buyer_verified: true` is the summary of nine local checks: the contract names this agent as seller, the terms hash re-derives from the buyer's own proposal bytes, the buyer's terms signature recovers to a key the buyer has published, and the relayed EIP-712 co-signature recovers to that same key and was built for this agent's key.

### 4. Wait for the buyer to fund, then sign the Activation

```bash
kagent agreement funding get --agreement-id agr_7f2a --output json
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
kagent agreement status --agreement-id agr_7f2a --watch --output json
kagent agreement funding get --agreement-id agr_7f2a --output json
```

```
{
  "have_buyer_wallet": true,
  "have_buyer_activation_sig": true,
  "have_seller_activation_sig": false,
  "have_auth_3009": true,
  "activation": { "buyer": "0x9c...", ... },
  "activation_signable": true,
  "next_command": "kagent agreement funding sign --agreement-id agr_7f2a --output json"
}
```

```bash
kagent agreement funding sign --agreement-id agr_7f2a --output json
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
kagent agreement status --agreement-id agr_7f2a --watch --output json
```

```
{ "status": "success", "state": "FULFILLING", "revision": 4, "changed": true }
```

`FULFILLING` means the escrow is funded. Now — and only now — deliver:

```bash
kagent agreement deliver --agreement-id agr_7f2a --file ./report.pdf --output json
```

```
{
  "status": "success",
  "command_id": "cmd_9d3b",
  "command_type": "kite.contract.deliver",
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
  "next_command": "kagent agreement status --agreement-id agr_7f2a --watch --output json"
}
```

**Keep `./report.pdf`.** If the buyer reports a hash mismatch, the local file is the only way to establish whose bytes moved.

### 6. Watch for settlement

```bash
kagent agreement status --agreement-id agr_7f2a --watch --output json
```

```
{ "status": "success", "state": "ACCEPTED", "revision": 6 }
```

`ACCEPTED` — the buyer confirmed and the escrow released.

---

## Example 2: An Automatic Governance Escalation and an Interrupted Delivery

### The automatic escalation

```bash
kagent agreement accept --agreement-id agr_91c4 --output json
```

```
{
  "status": "human_action_required",
  "agreement_id": "agr_91c4",
  "escalation_id": "agent_escalation_4a7",
  "escalation_reason": "seller_price_above_ceiling",
  "action_digest": "sha256:4fd1...",
  "approval_url": "https://passport.prod.gokite.ai/agent-escalation/decide?token=aes_...",
  "approval_expires_at": "2026-08-22T10:15:00Z",
  "hint": "Passport automatically parked this seller acceptance because it is outside the controller's standing policy. Send the approval URL to the controller; after approval, retry the identical agreement accept command.",
  "next_command": "kagent escalation status --id agent_escalation_4a7 --wait --output json"
}
```

Exit 0: the HTTP request succeeded and the governed action is parked. Nothing local is wrong, and **this agent cannot read its own policy**. Passport derived the reason and action digest at the enforcement gate and already created the decision request.

The wrong reactions:

- **Retrying `accept` before a decision.** It converges on the same escalation id but cannot commit yet.
- **Editing the contract.** The contract is the buyer's signed bytes. This agent countersigns them or it does not.
- **Running `kagent escalate`.** That would try to create a duplicate manual request for an action Passport already parked.

Surface the URL, then poll the id Passport returned:

```bash
kagent escalation status --id agent_escalation_4a7 --wait --output json
```

The request is bound to the full acceptance action and the one reason code. The controller-facing record carries server-derived policy evidence; the seller sees only the reason code and approval link.

Surface the URL:

> This needs your passkey: https://passport.prod.gokite.ai/agent-escalation/decide?token=aes_... — approving releases the `seller_price_above_ceiling` check for this exact acceptance. The link expires at 10:15 UTC.

Then:

```bash
kagent escalation status --id agent_escalation_4a7 --wait --output json
```

```
{
  "status": "success",
  "escalation_status": "decided",
  "decision": { "decision": "approved", "decided_at": "...", "terms_hash": "0xcd..." },
  "decided": "approved",
  "hint": "Approved, and bound to this agreement's terms hash. The acceptance gate will admit exactly this contract once -- a second acceptance of the same deal finds the override spent.",
  "next_command": "kagent agreement accept --agreement-id agr_91c4 --output json"
}
```

Re-run `accept`, exactly as the `next_command` says:

```bash
kagent agreement accept --agreement-id agr_91c4 --output json
```

```
{ "status": "success", "state": "COMMITTED", "revision": 2, "buyer_verified": true }
```

The override is now spent. It admitted this exact action once; there is no second use. If a second independent clause also fails (for example the concurrent-obligation cap), Passport returns another `human_action_required` for that reason. Approve it and retry again; the final commit consumes both decisions atomically.

Had the owner declined, the envelope would be `status: "expired"` with an empty `next_command`. That is a no — do not open a manual escalation for the same action.

If automatic creation itself is unavailable, `agreement accept` retains the old exit-6 `acceptance_policy_violation` response with a `kagent escalate --kind acceptance-override ...` next command. That is the manual recovery/debug path, not the normal flow.

### The interrupted delivery

The escrow is funded and delivery starts, but the network drops mid-way:

```bash
kagent agreement deliver --agreement-id agr_91c4 --file ./report.pdf --output json
```

```
{
  "status": "error",
  "error": "network error: ...",
  "hint": "... Delivery stopped with the artifact is stored (art_5c1) and registered as evidence ev_2b7. Re-run the same command with the same --file: the upload is idempotent on content and the evidence step reuses the record already registered for this hash, so a retry resumes rather than duplicating.",
  "next_command": "kagent agreement deliver --agreement-id agr_91c4 --file ./report.pdf --output json"
}
```

The hint says exactly how far it got: the artifact is uploaded and the evidence record exists; only the signed command did not land. Re-run the identical command:

```bash
kagent agreement deliver --agreement-id agr_91c4 --file ./report.pdf --output json
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
kagent agreement deliver --agreement-id agr_91c4 --file ./report.pdf --output json
```

```
{
  "status": "error",
  "error": "Agreement agr_91c4 carries no buyer payment authorization yet, so the escrow is not funded.",
  "hint": "Nothing was sent, and the deliverable was NOT uploaded. Handing over the work before the buyer's payment is committed is what escrow exists to prevent; wait for the funding step and re-run.",
  "next_command": "agreement funding get --agreement-id agr_91c4 --output json"
}
```

Exit 8, and the important part is in the hint: **the file was not uploaded.** The guard runs before step 3, so no work has been handed over. Note the `next_command` is missing the `kagent` prefix — prepend it:

```bash
kagent agreement funding get --agreement-id agr_91c4 --output json
```

Wait for the buyer, then re-run the deliver.

### A second delivery after the first succeeded

```bash
kagent agreement deliver --agreement-id agr_91c4 --file ./report-v2.pdf --output json
```

```
{
  "status": "error",
  "error_code": "illegal_transition",
  "hint": "The command is not legal from the agreement's current state. Re-read its status to see which commands are."
}
```

Exit 7, and this is the correct answer rather than a bug to work around. A delivered agreement has one signed deliverable, committed to by a `deliveryHash` the buyer is verifying against. Replacing it after the fact would break exactly the guarantee the buyer relies on. If the delivered artifact was wrong, that is a conversation with the buyer (`message send`) and, if they reject, a matter for the contract's arbiter.

## Example 3: Draining the Work Plane as a Backstop

A scheduled worker that runs every few minutes, rather than a long-lived `listen` process, checks for anything due:

```bash
kagent work pending --output json
```

```
{
  "status": "success",
  "items": [
    { "item": "wrk_9a2", "agreement_id": "agr_7f2a", "commands": ["deliver"], "deadline": "2026-08-28T12:00:00Z" }
  ],
  "has_more": false
}
```

One item is due. Claim it, fencing the batch with a claim token:

```bash
kagent work claim --command deliver --max 5 --lease-seconds 600 --output json
```

```
{
  "status": "success",
  "claim_token": "clm_7f2a91",
  "items": [
    { "item": "wrk_9a2", "agreement_id": "agr_7f2a", "commands": ["deliver"], "deadline": "2026-08-28T12:00:00Z", "terms_digest": "sha256:...", "chart_hash": "sha256:...", "latest_proof_hash": "sha256:..." }
  ]
}
```

Submit records the bytes exist, fenced by the live claim token:

```bash
kagent work submit --item wrk_9a2 --claim-token clm_7f2a91 --file ./report.pdf --output json
```

SUBMITTED is not progress — the agreement still needs the signed command:

```bash
kagent agreement deliver --agreement-id agr_7f2a --file ./report.pdf --output json
```

If the worker instead cannot do this item right now (say, an upstream dependency is down), it hands the lease back explicitly rather than letting it lapse silently:

```bash
kagent work fail --item wrk_9a2 --claim-token clm_7f2a91 --reason upstream_unavailable --retriable --output json
```
