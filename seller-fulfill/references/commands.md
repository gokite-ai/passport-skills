# Seller: Fulfill — Command Reference

Every command takes `--output json`. All flags are long-form. `--base-url`, `--output`, and `--no-interactive` are persistent root flags; `--key-file` (overriding `KAGENT_RUNTIME_KEY_FILE`) and `--config-dir` (default `~/.kagent`) are registered on every command in this file.

Colon-separated paths are aliases: `kagent agreement:funding:sign` equals `kagent agreement funding sign`.

---

## `kagent agreement list`

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--state <STATE>` | string | `""` | **Client-side filter only.** The signed request carries role, limit, and offset; the envelope reports `filtered_client_side: true`. |
| `--role <buyer\|seller>` | string | `""` | Validated locally; anything else is exit 2. |
| `--limit <n>` | int | `0` (backend default 50) | Capped at 200. |
| `--offset <n>` | int | `0` | |

```
{
  "agreements": [ { "agreement_id": "...", "state": "PROPOSED", "revision": 1, "role": "seller",
                    "buyer_agent_id": "...", "seller_agent_id": "...", "terms_hash": "...",
                    "amount": "...", "updated_at": "..." } ],
  "count": 1,
  "page_size": 1,
  "state_filter": "PROPOSED",
  "filtered_client_side": true
}
```

Because `--state` filters after the page is fetched, an empty result does not mean nothing matches — page with `--offset`.

---

## `kagent agreement status`

| Flag | Type | Default | Required |
|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** |
| `--watch` | bool | `false` | no |
| `--timeout <duration>` | duration | `10m` | no |

`--watch` backs off from 2 seconds to a 30-second cap and only polls while the state is non-terminal. A timeout yields envelope `status: "pending"` with `timed_out: true` — exit 0.

Data members include `agreement_id`, `state`, `revision`, `role`, `buyer_agent_id`, `seller_agent_id`, `terms_hash`, `amount`, `updated_at`, `arbiter_agent_id`, `buyer_runtime_key_id`, `seller_runtime_key_id`, `seller_payout`, `latest_proof_hash`, a `vault` object (`deal_id`, `nonce`, `state`, `vault_address`, `chain_id`), `contract` and `formation` (the engine's bytes **verbatim**), an `agreement_sig` object (`sig`, `key_id`, `seller_key_id`, `recorded_at`), plus `watched`, `changed`, and `timed_out` with `--watch`. `proposal_unavailable: true` appears when the proposal bytes could not be read.

Terminal states: `ACCEPTED`, `RESOLVED`, `SETTLED_MUTUAL`, `CANCELLED`, `DEFAULTED`, `EXPIRED`. An unrecognized state is reported as `State: <X>.` — engine spellings pass through untranslated.

On a chart that offers the co-signed split, four more states appear. `SETTLING_MUTUAL`, `SETTLING_MUTUAL_REJECTED`, and `SETTLING_MUTUAL_DISPUTED` are in-flight — a submitted split whose vault call has not been observed yet, returning to the origin each is named for on a `RELAY_FAILED` — and `SETTLED_MUTUAL` is terminal, carrying `seller_bps` when the read has it. `--watch` terminates on `SETTLED_MUTUAL` as it does on every other terminal state. `standard/v1` and the other templates in the catalog today never produce any of them.

---

## `kagent agreement accept`

| Flag | Type | Default | Required |
|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** |

Nothing else. This agent does not edit the buyer's contract; it verifies and countersigns it.

Preconditions: the runtime key resolves and its binding is `active` (else exit 3), and a card is pinned (else exit 2 with `next_command: "kagent card fetch --pin --output json"`; a pin with `chain_id == 0` or an empty escrow vault is exit 8).

### Local verification, in order

| # | Check | Failure |
|---|---|---|
| 1 | The agreement has a contract | Exit **1** (retriable) when the proposal is merely unavailable; exit **4** otherwise |
| 2 | The contract names **this agent** as seller | Exit **6** — `Agreement <id> names seller <did>, not this agent (<did>).` |
| 3 | The terms hash **re-derives** from the verbatim proposal bytes and matches what the runtime reports | Exit **8** — the runtime reports one hash, the stored contract derives another |
| 4 | A buyer signature entry exists for the buyer agent id | Exit **8** |
| 5 | The buyer's `keyId` is in the buyer's **published** key set | Exit **8**, `error_code: "unknown_key"`, `next_command: "kagent directory keys <ref> --output json"` — read it with `ksearch agent keys <ref> --output json` instead: it is a public read and needs no runtime key (the printed `kagent` spelling reads the same data) |
| 6 | The buyer's terms signature recovers to that key's address | Exit **8** |
| 7 | The relayed EIP-712 Agreement co-signature is present | Exit **1**, `next_command: "kagent agreement status --agreement-id <id> --watch --output json"` |
| 8 | The co-signature names **this agent's** key, not a sibling | Exit **8** |
| 9 | The co-signature recovers to the buyer's address under the escrow domain | Exit **8** |
| 10 | The contract's `registrationBasis` and `priceSchedule` match this seller's own active registration (read fresh via `GET /v1/agents/<seller>/registration`) | Exit **8** |

Every one of these refuses before any signature is produced and before the accept is sent. Check 7 is the exception worth reading twice — it means the buyer's formation relay has not landed, which only the buyer can fix by re-running `propose` (the relay is write-once, so their identical resend is a no-op).

Check 10 is new: it used to be enforced only server-side, after this agent had already signed. It reuses the same validation `propose` runs on the buyer's side, so a schedule one lane would refuse can no longer be signed by the other.

Then this agent signs the terms hash and the EIP-712 Agreement, appends its signature entry alongside the buyer's, re-validates the contract against the schema, and asserts the terms anchor did not move.

```bash
kagent agreement accept --agreement-id agr_7f2a --output json
```

```
{
  "status": "success",
  "agreement_id": "agr_7f2a",
  "state": "COMMITTED",
  "revision": 2,
  "terms_hash": "...",
  "buyer_agent_id": "did:kite:...",
  "seller_agent_id": "did:kite:...",
  "seller_key_id": "did:kite:...#k1",
  "amount_base_units": "25000000",
  "agreement_sig": "0x...",
  "buyer_verified": true,
  "receipt": { ... },
  "hint": "Committed. The funding context opens next, and both parties' Activation signatures are due before the escrow can be funded.",
  "next_command": "kagent agreement funding get --agreement-id agr_7f2a --output json"
}
```

### Automatic governance escalation

When a typed seller policy clause fails, the platform creates the decision request and `accept` exits **0** with a `human_action_required` envelope:

```json
{
  "status": "human_action_required",
  "agreement_id": "agr_7f2a",
  "escalation_id": "agent_escalation_...",
  "escalation_reason": "seller_price_below_floor",
  "action_digest": "sha256:...",
  "approval_url": "https://.../agent-escalation/decide?token=...",
  "approval_expires_at": "...",
  "next_command": "kagent escalation status --id agent_escalation_... --wait --output json"
}
```

Passport already created this request. Surface its URL and poll its id; **do not run `kagent escalate` for the same action**. After approval, retry the identical accept. Multiple independent failed clauses may require sequential decisions, all consumed atomically when acceptance commits.

Exit **6**, `error_code: "acceptance_policy_violation"`, is retained as the rollout/debug fallback when automatic creation is unavailable or the policy failure is an untyped legacy condition. Its `next_command` uses the manual recovery:

```bash
kagent escalate --kind acceptance-override --agreement-id <id> --summary "<why this deal>" --wait --output json
```

---

## `kagent escalate` (manual recovery/debug)

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--kind <kind>` | string | `""` | **yes** | `acceptance-override` is the manual reserved seller kind. `funding-override` is also reserved but platform-created only; passing it manually is exit 2. Other strings are advisory with `enforced: false`. |
| `--summary <text>` | string | `""` | **yes** | This agent's own description of the decision, for the owner. |
| `--agreement-id <id>` | string | `""` | conditional | **Required** for `acceptance-override`. |
| `--payload <json>` | string | `""` | no | The machine-readable content the decision binds to. Mutually exclusive with `--payload-file`. |
| `--payload-file <path>` | string | `""` | no | Read the payload from a JSON file instead. |
| `--wait` | bool | `false` | no | Poll with backoff until the owner decides or the window closes. |
| `--timeout <duration>` | duration | `10m` | no | |

Validation, all exit 2: `--kind and --summary are both required.`; `funding-override is platform-created only.`; `--agreement-id is required for acceptance-override.`; `--payload and --payload-file cannot both be given.`; `The escalation payload is not valid JSON.`

**For `acceptance-override` with no payload, the verb fetches the contract and uses its verbatim bytes.** That is what binds the owner's decision to *this* contract rather than to a category. An agreement with no contract is exit 4.

Create envelope — always `human_action_required`:

```
{
  "status": "human_action_required",
  "escalation_id": "esc_...",
  "escalation_status": "pending",
  "kind": "acceptance-override",
  "enforced": true,
  "approval_url": "https://.../approve/esc_...",
  "approval_expires_at": "...",
  "summary": "...",
  "agreement_id": "agr_7f2a",
  "next_command": "kagent escalation status --id esc_... --wait --output json"
}
```

`enforced` is `true` only for `acceptance-override`. An advisory escalation records the owner's opinion; it does not unlock an acceptance gate.

---

## `kagent escalation status`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--id <id>` | string | `""` | **yes** | Not `--escalation-id`. |
| `--wait` | bool | `false` | no | Backoff 2 seconds to a 15-second cap. |
| `--timeout <duration>` | duration | `10m` | no | |

```
{
  "escalation_id": "esc_...",
  "escalation_status": "decided",
  "kind": "acceptance-override",
  "enforced": true,
  "agreement_id": "agr_7f2a",
  "decision": { "decision": "approved", "decided_at": "...", "payload_hash": "...", "terms_hash": "..." },
  "decided": "approved"
}
```

`escalation_status` values: `pending`, `decided`, `expired`.

| Condition | Envelope `status` | `next_command` |
|---|---|---|
| decided, approved, enforced, with an agreement id | `success` | **`kagent agreement accept --agreement-id <id> --output json`** |
| decided, approved, otherwise | `success` | `""` |
| decided, **declined** | `expired` | `""` |
| `expired` | `expired` | `""` |
| pending, or a timed-out wait | `human_action_required` | the same poll |

On approval, **re-run `agreement accept`**. The approved hint says it plainly: the decision is bound to this agreement's terms hash, and the acceptance gate admits exactly this contract **once** — a second acceptance of the same deal finds the override spent.

A declined escalation is envelope status `expired`. The owner said no.

---

## `kagent agreement funding get`

Flags: `--agreement-id` (required).

```
{
  "agreement_id": "...",
  "phase": "...",
  "chain_id": 8453,
  "vault_address": "0x...",
  "have_buyer_wallet": true,
  "have_buyer_activation_sig": false,
  "have_seller_activation_sig": false,
  "have_auth_3009": true,
  "have_expected_deal_id": true,
  "vault_deal_id": "...",
  "rejected_fields": [ ],
  "activation": {
    "terms_hash": "...", "buyer": "0x...", "buyer_agent": "0x...", "seller_agent": "0x...",
    "seller_payout": "0x...", "arbiter": "0x...", "amount": "...",
    "funding_deadline": "...", "delivery_window": "...", "delivery_confirmation_window": "...",
    "appeal_response_window": "...", "arbitration_window": "..."
  },
  "activation_signable": true
}
```

`activation_signable` is `activation != nil && activation.buyer != ""`. The buyer's wallet arrives with their funding authorization, so this is `false` until the buyer has funded. `next_command` becomes the `funding sign` command exactly when this agent's signature is outstanding.

`rejected_fields` appears only when non-empty and lists write-once values the engine refused to change — retrying cannot change them.

---

## `kagent agreement funding sign`

Flags: `--agreement-id` (required). **No amount flag** — the amount comes from the signed contract, converted once, never from a flag and never twice.

Signs the EIP-712 `Activation` (terms hash, buyer, buyer agent, seller agent, seller payout, arbiter, amount, and the five windows) under the vault domain, and submits `sellerActivationSig`.

Refuses first with exit **8** (nothing sent) on any of: the funding context's chain id or vault not matching the pinned card; the Activation's terms hash not matching the agreement's; a served contract that will not canonicalize or re-derives a different hash; `price.asset` not `USDC`; a price that will not convert to base units; an amount that is not exactly the derived base units; `seller_payout` not matching the contract's escrow payout address; this role's agent address not being this agent's own runtime key address; a blank buyer agent, seller agent, or arbiter; an arbiter that disagrees with the contract's dispute policy; a contract card hash that is not the one this agent pinned; a blank buyer wallet; any of the five windows being zero; or non-empty `rejected_fields`.

The blank-buyer-wallet refusal comes with a hint saying it is a normal stage rather than a fault — the wallet arrives with the buyer's funding authorization.

```
{
  "agreement_id": "...",
  "role": "seller",
  "activation_sig": "0x...",
  "submitted_member": "sellerActivationSig",
  "terms_hash": "...",
  "amount_base_units": "25000000",
  "chain_id": 8453,
  "escrow_vault": "0x...",
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
  ],
  "hint": "Activation validated against the signed terms and signed. The escrow can be funded once both parties' signatures and the buyer's authorization are recorded.",
  "next_command": "kagent agreement funding get --agreement-id <id> --output json"
}
```

The submission is schema-gated per role, so a seller cannot write buyer fields even by accident.

---

## `kagent agreement deliver`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** | |
| `--file <path>` | string | `""` | **yes** | The deliverable. Its sha256 becomes the `deliveryHash`. |
| `--content-type <type>` | string | derived from the extension | no | Advisory for artifacts, falling back to `application/octet-stream`. No refusal, unlike documents. |
| `--evidence-type <type>` | string | `delivery` | no | The evidence record's type; free-form. Can never be blank — an empty value is re-defaulted. |

There is no `--force`, no `--yes`, and no `--evidence-id`.

### The forced order — five steps, one verb

1. **Read the anchors** — the agreement and the funding context.
2. **Hash locally** — sha256 of the file on this disk, **before** anything is uploaded.
3. **Upload** content-addressed, idempotent on (agreement, sha256).
4. **Register as evidence**, reading existing records before writing.
5. **Sign** the EIP-712 Delivery and submit the `kite.contract.deliver` command.

### The guards

**Role.** `view.Role != "seller"` is exit 8: only the seller delivers, and the artifact store refuses a buyer's upload for the same reason — a buyer able to write there could manufacture the backing for the other side's delivery claim.

**Funding — the constraint that must pass before delivery.** When the buyer's payment authorization is not recorded, exit 8:

> Agreement `<id>` carries no buyer payment authorization yet, so the escrow is not funded.
> Hint: Nothing was sent, and the deliverable was NOT uploaded. Handing over the work before the buyer's payment is committed is what escrow exists to prevent; wait for the funding step and re-run.
> Next: `agreement funding get --agreement-id <id> --output json` (prepend `kagent`)

**Domain and anchors.** Exit 8 when the funding context's chain id or vault address disagrees with the pinned card, or when the vault deal id, the terms hash, or the latest proof hash is missing from the agreement.

**The file.** All exit 2: `--file is required.` (hint: `The file IS the delivery: its sha256 is the deliveryHash both the vault signature and the command commit to.`); unreadable; empty; larger than **64 MiB**.

### Content-derived resume

The digest is derived once, in two spellings: bare lowercase hex for the signed artifact upload, and `sha256:<hex>` for the evidence record's `hash` and the command's `deliveryHash`.

| Step | Idempotency |
|---|---|
| Upload | Idempotent on (agreement, sha256). The reply's `Duplicate` says whether the bytes were already stored. A reply whose sha256 disagrees with the local digest is exit 8 — it is not a reply about this artifact. |
| Evidence | The existing records are **read first** and matched on the digest; a match is reused and reported as `evidence_reused: true`. The evidence schema admits no idempotency key, so this read *is* the idempotency. Both `evidenceId`/`evidence_id` and `sizeBytes`/`size_bytes` spellings are accepted when matching, because a one-spelling matcher would register a duplicate. |
| Command | A fresh command id per invocation. A `revision_conflict` (exit 7) is re-runnable: the artifact and evidence are reused and the command is rebuilt against the current revision with a new id, because its bytes changed. |

Any failed step annotates the error **in place** rather than re-classifying it, appending how far it got — either `nothing was stored yet` or `the artifact is stored (<id>) and registered as evidence <id>` — and setting `next_command` to the identical deliver command with the same `--file`. Re-running resumes rather than duplicating.

**After the deliver command lands, a second is refused as `illegal_transition` (exit 7)** — the correct answer, not a bug to work around.

```bash
kagent agreement deliver --agreement-id agr_7f2a --file ./report.pdf --output json
```

```
{
  "status": "success",
  "agreement_id": "agr_7f2a",
  "command_id": "cmd_...",
  "command_type": "kite.contract.deliver",
  "state": "DELIVERED",
  "revision": 5,
  "expected_revision": 4,
  "evidence_id": "ev_2b7",
  "evidence_reused": false,
  "artifact_id": "art_...",
  "artifact_url": "https://...",
  "artifact_duplicate": false,
  "delivery_hash": "sha256:4f1e...",
  "delivery_sig": "0x...",
  "size_bytes": 482113,
  "content_type": "application/pdf",
  "content_file": "./report.pdf",
  "vault_deal_id": "...",
  "vault_nonce": "...",
  "receipt_hash": "...",
  "expiry": "...",
  "terms_hash": "...",
  "receipt": { ... },
  "hint": "Delivered. The buyer's own check is what settles this: it downloads the artifact, recomputes sha256, and compares it against the deliveryHash inside this signed command -- so keep the local file until the escrow releases.",
  "next_command": "kagent agreement status --agreement-id agr_7f2a --watch --output json"
}
```

The signed command's payload carries `evidenceId`, `deliveryHash`, `sellerDeliverySig`, and `expiry`.

---

## `kagent agreement refund-consent`

| Flag | Type | Default | Required |
|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** |

Nothing else. Signs the EIP-712 RefundConsent the EscrowVault recovers, wraps it in a signed `kite.contract.consent_refund` command, and submits it. The anchors it commits to — the revision, the vault's current nonce, and the newest transition proof as `receiptHash` — are read back immediately before signing.

This is the short way out of a rejection: consenting sends the escrow back to the buyer and moves the agreement to a terminal state. It is not an admission of anything, and it is not arbitration — it ends the dispute without one. The alternative is `agreement appeal`, below, which costs both parties the arbitration window. A seller that would rather refund than argue ends it here on its own authority.

```bash
kagent agreement refund-consent --agreement-id agr_7f2a --output json
```

Only valid from `REJECTED`. Running it on an agreement in any other state is refused.

---

## `kagent agreement appeal`

| Flag | Type | Default | Required |
|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** |

Nothing else. Signs the EIP-712 Appeal the EscrowVault recovers, wraps it in a signed `kite.contract.appeal` command, and submits it. The anchors it commits to — the revision, the vault's current nonce, and the newest transition proof as `receiptHash` — are read back immediately before signing, same as every other settlement command.

The long way out of a rejection: appealing stops the appeal-response window (whose expiry refunds the buyer by default) and starts the arbitration window, in which the contract-named arbiter decides — rendered through `kagent agreement resolve --decision-id <id> --seller-bps <0-10000>`, arbiter seat only (a party's attempt is refused before anything is signed). Against `did:kite:corp-kite:demo-arbiter` (the standing service at <https://arbiter.kiteai.dev>) the ruling lands within seconds under its posted policy.

```bash
kagent agreement appeal --agreement-id agr_7f2a --output json
```

```json
{
  "agreement_id": "agr_7f2a",
  "command_id": "...",
  "command_type": "kite.contract.appeal",
  "state": "DISPUTED",
  "revision": "...",
  "settlement_sig": "...",
  "expected_revision": "...",
  "vault_deal_id": "...",
  "vault_nonce": "...",
  "receipt_hash": "...",
  "expiry": "...",
  "receipt": { ... },
  "hint": "Appealed. The arbitration window is running; the contract-named arbiter decides.",
  "next_command": "kagent agreement status --agreement-id agr_7f2a --watch --output json"
}
```

Only valid from `REJECTED`, and only for this contract's own seller — the engine authorizes `kite.contract.appeal` for that role alone, so a buyer's attempt (there is no buyer-surface `agreement appeal` command at all) would be refused locally before anything is sent.

---

## `kagent agreement settle sign` / `kagent agreement settle submit`

The co-signed split, `kite.contract.settle_mutual`: `sellerBps` of the escrow to the seller, the remainder to the buyer, in one vault call without the arbiter. It is the negotiated middle between `confirm` (release everything) and `refund-consent` (refund everything), and it exists because partial fulfilment is the normal case for per-unit products.

Both verbs are registered on **both** surfaces (`kagent agreement settle …` and `kpass agent agreement settle …`) — either party may initiate, and the counterparty completes. The binary does not establish authority; the agreement read does. The contract-named arbiter is not a seat in the pair, even from `DISPUTED`: its instrument is `agreement resolve`.

**Availability: requires `passport-cli` ≥ the release that ships `agreement settle`.** `agreement actions` is the version-independent check — see the last subsection here.

Three origins, each with its own in-flight state so a failed relay returns the deal to where it left:

| Agreement state | Vault position | In-flight | Terminal |
|---|---|---|---|
| `DELIVERED` | `Delivered` | `SETTLING_MUTUAL` | `SETTLED_MUTUAL` |
| `REJECTED` | `Rejected` | `SETTLING_MUTUAL_REJECTED` | `SETTLED_MUTUAL` |
| `DISPUTED` | `Appealed` | `SETTLING_MUTUAL_DISPUTED` | `SETTLED_MUTUAL` |

`FULFILLING` is excluded: before delivery there is nothing to apportion. A chart may offer fewer origins than the vault admits, so `agreement actions` — not this table — is the authority on what is available on a given deal.

### `settle sign`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** | |
| `--seller-bps <n>` | int | `-1` | **yes** | The seller's share of the escrow in basis points, `0..9999`. There is no default and the sentinel is negative, so omitting it is exit 2 rather than a silent `0`. `0` is legal and is not the same fact as silence: it records that both parties **agreed** nothing was payable. `10000` is refused with `next_command` naming `agreement confirm`. |
| `--basis-file <path>` | string | `""` | no | A JSON document stating how `--seller-bps` was derived. Validated as JSON and nothing more, carried into the offer verbatim, and omitted from the offer entirely when the flag is absent. |
| `--output-file <path>` | string | `settlement-offer-<agreement-id>.json` | no | Where the offer is written, mode `0600`. The default lands in the working directory. |

```bash
kagent agreement settle sign \
  --agreement-id agr_7f2a \
  --seller-bps 6200 \
  --basis-file ./count-report.json \
  --output-file ./settlement-offer.json \
  --output json
```

Checks, in this order, with **nothing signed until all of them pass**. The order is the safety property: a caller in the wrong position is told that, rather than being told an anchor is missing.

1. `--seller-bps` is present, and `--basis-file` parses as JSON if given.
2. The local runtime identity resolves and the pinned card carries chain context.
3. The agreement read reports this identity's role as `buyer` or `seller`.
4. `kite.contract.settle_mutual` is in the current `offered_commands`. The answer is **required**: a server that does not publish `offered_commands` refuses the verb rather than defaulting to allowed.
5. The agreement state is one of the three origins; the read carries a vault deal id; and when the read reports a vault position, it agrees with the agreement state. An absent vault position is tolerated, never invented.
6. `--seller-bps` is in `0..9999`.
7. The anchors: a non-zero proof head, `proof_anchors_available` true, and the **welded** settlement terms hash, falling back to the current terms hash only on a server that predates the welded member. The agreement's terms must embed a workflow `chartHash`.
8. When the funding context publishes `mutualSettlementTypeHash`, it equals the typehash this build signs. An absent value is tolerated; a mismatch is a refusal naming both values, because a struct-version skew reaches the chain as a reverted transaction.

It then signs the `MutualSettlement` digest under the **vault** domain and writes the offer. The signature commits to the welded terms hash and the vault's **current** nonce; the command envelope `settle submit` later builds anchors to the **current** terms hash instead.

The CLI never derives `sellerBps`. The counting rule, the batch format, and the unit rate belong to the parties and their signed terms.

```json
{
  "agreement_id": "agr_7f2a",
  "offer_file": "./settlement-offer.json",
  "signer_role": "seller",
  "state": "REJECTED",
  "seller_bps": 6200,
  "expected_revision": 5,
  "vault_deal_id": "0x…",
  "vault_nonce": 4,
  "settlement_terms_hash": "sha256:…",
  "receipt_hash": "sha256:…",
  "chart_hash": "sha256:…",
  "expiry": 1788000000,
  "mutual_settlement_sig": "0x…",
  "basis_included": true,
  "hint": "Split signed at 6200 bps. Hand the file to the buyer; …",
  "next_command": "kagent agreement status --agreement-id agr_7f2a --output json"
}
```

`basis_included` reports whether a derivation travelled with the offer. When it is `false` the hint says so explicitly: the offer records the number without the reasoning behind it, and the counterparty has nothing to check its own count against.

### The settlement offer

```json
{
  "schema": "kite:cli:mutual-settlement-offer:v1",
  "agreementId": "agr_7f2a",
  "chainId": 5887,
  "vaultAddress": "0x…",
  "vaultDealId": "0x…",
  "chartHash": "sha256:…",
  "state": "REJECTED",
  "expectedRevision": 5,
  "settlementTermsHash": "sha256:…",
  "receiptHash": "sha256:…",
  "nonce": 4,
  "sellerBps": 6200,
  "expiry": 1788000000,
  "signerRole": "seller",
  "signerAgentId": "did:kite:…",
  "signerKeyId": "…",
  "mutualSettlementSig": "0x…",
  "basis": { "deliveryHash": "sha256:…", "acceptedUnits": 62, "maxUnits": 100, "countingRule": "sha256:…" }
}
```

It is a **local exchange format**, not a wire object of the coordination extension, and the schema string is versioned so a future change is visible. Notes on the members that are easy to misread:

- `vaultDealId` is the vault's bytes32 deal id, the hash of the whole Activation. It is not the agreement id.
- `settlementTermsHash` is the **welded** anchor `fund()` pinned, which no amendment moves.
- `expectedRevision` is the stale-write guard for the eventual command and is **not** a member of the signed digest. `receiptHash` and `nonce` are what make a stale offer unverifiable on chain.
- `chartHash` is an anchor rather than a signed member: a counterparty reading a different chart is not reading the same rulebook.
- `signerKeyID` is omitted when empty, and `basis` is omitted entirely when no `--basis-file` was passed. An absent claim, never an empty one.

`basis` is the signer's stated derivation, carried verbatim and never interpreted: the platform never reads the delivered bytes and cannot check a count. If the two parties' numbers disagree there is no honest split to sign, and the escalation ladder is the answer.

The offer is **data, not a command**. It carries one signature and cannot move the agreement, so writing one concedes nothing.

### `settle submit`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--file <path>` | string | `""` | **yes** | The offer written by the counterparty's `settle sign`. It is the **only** flag this verb takes: the split, the anchors, and the expiry are all inside the digest the initiator signed, so a flag able to change any of them would invalidate that signature. |

```bash
kagent agreement settle submit --file ./settlement-offer.json --output json
```

What it does, in order:

1. Reads and parses the offer, requires the `kite:cli:mutual-settlement-offer:v1` schema, and requires it to be complete: `agreementId`, `mutualSettlementSig`, and all three of `vaultDealId`, `settlementTermsHash`, `receiptHash`. An offer with no signature carries no consent.
2. Requires `signerRole` to be a party seat, and derives the counterparty seat from it.
3. Requires the offer's `chainId` to equal the pinned card's chain. The chain id is inside the EIP-712 domain, so a mismatch means the two halves would be signed under different domains and the vault would recover neither.
4. Re-reads the agreement authoritatively and requires this identity to hold the **counterparty** seat. One keyholder signing twice is a pair the vault refuses.
5. Requires `kite.contract.settle_mutual` to still be offered from the current state.
6. Requires every anchor to still hold: state, revision, chain id, vault address, vault deal id, vault nonce, welded settlement terms hash, proof head, and chart hash. Any difference is a stale offer, refused and never repaired.
7. Requires the `expiry` to have at least **60 seconds** of headroom. The vault checks it against `block.timestamp` at **inclusion**, not at submission, so merely not having lapsed is not enough.
8. **Re-derives** the anchors from the fresh read rather than trusting the offer's copies, then restores the one member the initiator owns: the expiry. A submit cannot stretch a consent's bound.
9. Recovers the initiator's signature against the runtime address pinned for **its** seat in the funding context's Activation, signs the same digest with this party's key, and recovers that against its own pinned address. An absent pinned address is a refusal, not a pass.
10. Refuses an identical pair: two matching halves are one keyholder consenting twice.
11. Builds and signs the v1 `kite.contract.settle_mutual` command over the **current** terms hash and the fresh revision, then submits it.

```json
{
  "agreement_id": "agr_7f2a",
  "command_id": "cmd_…",
  "command_type": "kite.contract.settle_mutual",
  "state": "SETTLING_MUTUAL_REJECTED",
  "revision": 6,
  "seller_bps": 6200,
  "initiator_role": "seller",
  "submitter_role": "buyer",
  "buyer_mutual_settlement_sig": "0x…",
  "seller_mutual_settlement_sig": "0x…",
  "expected_revision": 5,
  "settled_from": "REJECTED",
  "vault_deal_id": "0x…",
  "vault_nonce": 4,
  "settlement_terms_hash": "sha256:…",
  "receipt_hash": "sha256:…",
  "expiry": 1788000000,
  "receipt": { "…": "…" },
  "basis": { "…": "…" }
}
```

`seller_bps` and the two signatures are **top-level siblings** of `command_type`, `state`, and `revision`, not nested in a payload object. `initiator_role` and `submitter_role` record who did which half; `settled_from` names the origin. `basis` appears only when the offer carried one, and the envelope is its only durable copy — the basis is not a member of any signed object and travels no further than the offer.

The command's own payload carries `sellerBps`, `buyerMutualSettlementSig`, `sellerMutualSettlementSig`, and `expiry` — two vault-domain signatures over one struct, placed by seat and not interchangeable. **The vault verifies them, not the engine**, which is why every check above runs locally: a wrong domain, a wrong terms hash, or a stale nonce does not come back as a 400. It comes back as `InvalidSignature` inside a reverted transaction after Passport and the engine have both answered 200.

Nothing in `settle submit` checks whether `sellerBps` is *fair*. Submitting is this party's consent to the split.

### Exit codes on these two verbs

| Exit | Cause |
|---|---|
| 2 USAGE | `--seller-bps` missing, outside `0..9999`, or exactly `10000`; `--basis-file` unreadable or not valid JSON; `--file` missing or unreadable; an offer that is not JSON, declares a foreign `schema`, is incomplete, or names a `signerRole` that is not a party seat; a failure writing the offer file |
| 7 CONFLICT | `revision_conflict`, `illegal_transition`, `terms_hash_mismatch`, `idempotency_conflict` — the server ruled against bytes built on a state that moved |
| 8 PROTOCOL | Every local refusal, and nothing was sent: this identity is not a party; the command is not offered from here, or the server does not publish `offered_commands` at all; the state is outside the three origins; no vault deal id, or a vault position that disagrees with the agreement state; a missing or zero proof head, or `proof_anchors_available` false; no welded anchor and no current terms hash; terms with no workflow `chartHash`; a typehash skew; the offer's chain id against the pinned card; the wrong seat on submit; any stale anchor; an expiry with under 60 seconds of headroom; a signature that does not recover to the address pinned for its seat; an identical pair |

Two server codes are worth keeping apart, because one is temporary and the other is not:

- **`revision_conflict`** is exit 7. The agreement moved past the offer's revision, which invalidates the offer itself: its signatures commit to the proof head and the vault nonce as they were at signing. The hint says so and names the revision it was built for. The initiating party regenerates the offer from a fresh read; re-signing those bytes is not the fix.
- **`command_not_offered`** is exit **8**, deliberately not the conflict family. The agreement's own chart has no edge for this command from any state, so no re-read and no retry makes it legal. Its hint points at `agreement actions` for the commands the chart does offer. It is the server-side twin of the local offered-command gate above, and it classifies to the same exit code as that gate for exactly that reason. `illegal_transition` is the temporary one and stays exit 7.

### `agreement actions` — is the split available right now?

```bash
kagent agreement actions --agreement-id <id> --output json
```

The chart plus the current state is the authority on which commands are available, and this read is where that answer surfaces.

```json
{
  "agreement_id": "agr_7f2a",
  "state": "REJECTED",
  "revision": 5,
  "role": "seller",
  "actions_available": true,
  "proof_anchors_available": true,
  "deadline": "…",
  "workflow_id": "standard-enrichment/v1",
  "actions": [
    {
      "command": "kite.contract.settle_mutual",
      "actor_roles": ["buyer", "seller"],
      "required_signer_roles": ["buyer", "seller"],
      "available_to_caller": true,
      "cli_supported": true,
      "cli_command": "kagent agreement settle sign --agreement-id agr_7f2a"
    }
  ]
}
```

- **`actions_available: false` means UNKNOWN, not empty.** The server could not consult the chart. Never read it as "nothing can be done"; a terminal state returns `actions_available: true` with an empty `actions` list, which is the real empty answer.
- `proof_anchors_available: false` means the same about `deadline`: its absence is only authoritative while that flag is true. A chart read that succeeded alongside a proof read that failed must not render as "no time limit".
- `available_to_caller` is `true` for the buyer and the seller and `false` for the arbiter, even from `DISPUTED`. In text mode the rows available to this identity are marked with `*`.
- `cli_supported` is local capability, not availability: an offered command this build cannot produce is rendered with `cli_supported: false` rather than hidden. This is the check to run instead of reasoning about version strings.
- `workflow_id` appears when the agreement's terms name one.

`workflow-template get` publishes the same both-party metadata from the chart. Its JSON rows carry `actor_roles` and `required_signer_roles` and omit the compatibility scalar `role`, and its text output reads **`buyer or seller submits; signed by buyer + seller`** — two statements rather than one, because "buyer or seller" alone would read as a choice of one when the command in fact needs both.

---

## `kagent agreement evidence add`

Same flags as `deliver`: `--agreement-id`, `--file`, `--content-type`, `--evidence-type`.

Runs steps 1–4 only — it stores and registers, and **signs nothing on the settlement layer**. Use it for supporting material; use `deliver` for the deliverable the escrow settles against. Role guard: a non-seller is exit 8.

```
{
  "agreement_id": "...",
  "evidence_id": "ev_...",
  "evidence_reused": false,
  "evidence_type": "supporting",
  "artifact_id": "art_...",
  "artifact_url": "https://...",
  "artifact_duplicate": false,
  "hash": "sha256:...",
  "size_bytes": 1234,
  "content_type": "text/markdown",
  "content_file": "./methodology.md",
  "terms_hash": "...",
  "next_command": "kagent agreement deliver --agreement-id <id> --file <path> --output json"
}
```

Note the field name: `hash` here, `delivery_hash` in `deliver`. Same value, two names.

---

## `kagent agreement evidence list`

Flags: `--agreement-id` (required). Available to both roles.

```
{
  "agreement_id": "...",
  "evidence": [ { "evidence_id": "...", "type": "delivery", "hash": "sha256:...",
                  "url": "https://...", "format": "...", "recorded_at": "...", "size_bytes": 1234 } ],
  "records": [ { ... } ],
  "count": 1
}
```

`records` is the engine's records verbatim; `evidence` is the decoded view with each member omitted when empty or zero.

---

## `kagent message send` / `kagent message status`

`message send`:

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--to <ref>` | string | `""` | **yes** | A `did:kite` DID or an `agt_` id. |
| `--body <json>` | string | `""` | one of | Inline JSON. Mutually exclusive with `--file`. |
| `--file <path>` | string | `""` | one of | Read the body from a JSON file. |
| `--skill <name>` | string | `""` | no | An unvalidated routing hint. |
| `--ttl <duration>` | duration | `0` (server default 10m) | no | Between `30s` and `1h` when non-zero; outside that is exit 2. |
| `--wait` | bool | `false` | no | Poll until the recipient replies or the TTL elapses. No `--timeout`. |
| `--idempotency-key <value>` | string | `""` (fresh per invocation) | no | Reuse the SAME value to resend one message: the second call returns the original with `duplicate: true`. Without it a re-run mints a new key and enqueues a second message — the default protects a transport retry, not a re-run. |

Validation, all exit 2: `--to is required.`; `--body and --file cannot both be given.`; `A message body is required: pass --body or --file.`; `The message body is not valid JSON.`

`message status`: `--id` (required), `--wait`. **No `--timeout`** — the deadline is the message's own `expires_at` plus a one-second grace, falling back to one hour when absent. Backoff 1 second to a 15-second cap.

Message states: `queued`, `claimed`, `replied`, `expired`.

| Condition | Envelope `status` |
|---|---|
| `replied` | `success` |
| `expired` | `expired` |
| `queued`, `claimed`, or a timed-out wait | `pending` |

**Two different `status` questions, two different members.** The envelope's `status` is the table above — the command's own outcome. The message's own state is `message_status`, and it is the one carrying `queued` / `claimed` / `replied` / `expired`. A reply of `status: pending` with `message_status: claimed` is normal and means "still working on it".

(They used to share the key `status`, and the envelope overwrote the mailbox state, so `queued` reported as `success`. Fixed on both verbs.)

No thread id exists. An idempotency key is minted per invocation, so identical bytes resent return the original message (`duplicate: true`), while two deliberate sends of the same body are two messages.

On this lane a 409 is exit 7 and a 410 is exit **2** (the TTL elapsed — not an auth problem). A 429 stays rate-limited with a mailbox-specific hint.

---

## `kagent listen`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--forward <url>` | string | `""` | **yes** | The local A2A JSON-RPC endpoint each notification is POSTed to. Loopback only unless `--allow-remote-forward` is also set. |
| `--from <event-id>` | uint64 | `0` | no | Resume after this event id instead of the persisted cursor. |
| `--allow-remote-forward` | bool | `false` | no | Permits a non-loopback `--forward` target. Also requires `KAGENT_ALLOW_REMOTE_FORWARD=1` in the environment — the flag alone cannot authorize it. |

Three flags of its own. **No filters, no `--events`, no `--timeout`.**

`--forward` missing is exit 2: `--forward is required.`, hint `Name the local A2A JSON-RPC endpoint notifications are handed to. Without one this process would read the stream and discard it, which is worse than not running: the cursor would advance past events nothing acted on.`

### The stream

A signed handshake mints a stream grant (stream URL, token, expiry, high-water event id), then the CLI opens an SSE connection with a bearer token and a `Last-Event-ID` cursor.

Event names:

```
stream.ready, stream.reset                              (control frames)
agreement.proposed, agreement.formation.buyer_signed,
agreement.state_changed, agreement.fulfill_started,
agreement.funding.updated, agreement.evidence.recorded,
escalation.decided,
message.received, message.replied, message.expired,
session.decided
```

Each notification carries an **authoritative read** alongside the frame: `agreement.*` events attach the agreement view, `escalation.decided` the escalation, `message.replied`/`message.expired` the message status, and `message.received` **claims** the message and takes a 60-second lease. `session.decided` and unknown event names forward with no state (the session route is buyer-only).

**Act on the attached state, not on the frame.** The stream is a latency optimization; reconciliation by authoritative read is the correctness mechanism.

### The forwarded payload

POSTed as A2A JSON-RPC `SendMessage`, with the notification JSON base64-encoded in a `raw` part (media type `application/vnd.gokite.agent-notification+json;version=1`) so the bytes survive byte-identically — a protobuf value would turn an integer revision into a float. Headers carry the coordination extension URI and `A2A-Version: 1.0`.

The decoded notification carries `type`, `event`, `eventId`, `factId` (the dedupe key), `agentDid`, `frame` (the SSE data verbatim), `state` (the authoritative read — act on this), `message` (on `message.received`: `messageId`, `fromAgentDid`, `fromAgentId`, `skill`, `body`, `expiresAt`), `readError`, and `resynced`.

### The acknowledgement contract

A forward counts as delivered only when the target answers **2xx** *and* the body is JSON-RPC 2.0 *and* it echoes the request id *and* `result` is non-empty *and* `result` decodes as A2A's `task` or `message`. Anything else — a 2xx wrapping an `error`, a foreign id, a null result — is a NACK.

Retry budget: 3 attempts, 250 ms backing off to 2 seconds, 45-second timeout per POST. Exhausting it ends the connection **with the cursor unmoved**, so the frame replays.

For a claimed message the lease is heartbeated between attempts, and the target's own `result` becomes the reply body verbatim. A stale lease token is terminal — a successor owns it — and is never retried.

### Cursor and lifecycle

The cursor lives in `agent-state.json` and advances **only on acknowledgement**, flushed on exit. A `stream.reset` rewinds and emits one resync notification carrying the current agreements and pending messages, then drains the mailbox individually. Reconnect backoff runs 1 second to 30 seconds; an expired stream token re-mints immediately with no backoff. Auth, forbidden, and protocol handshake refusals are fatal.

SIGINT/SIGTERM flushes the cursor and exits 0. Progress lines go to **stderr** prefixed `[listen]`; stdout carries only the summary envelope on exit:

```
{
  "agent_did": "did:kite:...",
  "forward_url": "http://127.0.0.1:9090/a2a",
  "cursor": 1841,
  "frames": 12, "forwarded": 12, "acknowledged": 12, "not_acknowledged": 0,
  "messages_claimed": 2, "messages_replied": 2,
  "resyncs": 0, "reconnects": 1, "stream_mints": 2,
  "hint": "Stopped cleanly at cursor 1841. A restart resumes after the last acknowledged notification, ...",
  "next_command": "kagent listen --forward <url> --output json"
}
```

A fatal error emits an error envelope with no data members and the classified exit code.

---

## `kagent work claim` / `work submit` / `work fail` / `work pending`

The work plane's queue, this agent's side: after every committed transition the coordination engine states an obligation, Passport materializes it as a work item, and these four verbs are how the obligated party drains it. It exists alongside `listen`/polling as a third, backstop-reliable way to find due work — see "A Third Option: the Work Plane" in `SKILL.md` for when to prefer it.

An item carries two clocks that never merge: `deadline` is the agreement's (past it the vault settles without anyone's signature), `lease_expires_at` is the queue's (past it another attempt starts). Pace the work by the deadline, retries by the lease.

| Verb | Flags | Notes |
|---|---|---|
| `work claim` | `--command <name>` (repeatable, narrows to items offering that act), `--max <n>` (default 25, cap 100), `--lease-seconds <n>` (30–3600, default 300), `--key-file` | Leases up to `--max` due items exclusively for `--lease-seconds`, and reads back what the `work.available` doorbell doesn't carry: the offered commands, the agreement deadline, and the verification anchors (`terms_digest`, `chart_hash`, `latest_proof_hash`). An EMPTY batch is success, not refusal — nothing is due right now, which is what makes polling this cheap. The claim token fences the whole batch; quote it back on `submit`/`fail`. |
| `work submit` | `--item <wrk_id>`, `--claim-token <token>`, `--agreement-id` (with `--file`; read from the queue when absent), `--file` (uploads and registers the artifact — its sha256 becomes the `deliveryHash`) or `--evidence-id` + `--content-hash` (cite a record already registered), `--evidence-type` (default `delivery`), `--content-type`, `--units`, `--key-file` | Records that the deliverable's bytes exist — deliberately nothing more. SUBMITTED never moves the agreement; the receipt's `next_action` names the signed command only this party can send (for a delivery obligation, that's `agreement deliver`). A submission under a superseded token is a conflict the worker must NOT retry — the lease lapsed, a successor claimed the item, and the successor's submission is the one that counts. An identical retry under the live token is a no-op success. |
| `work fail` | `--item`, `--claim-token`, `--reason` (closed enum: `upstream_unavailable`, `request_unpriced`, `capacity_exceeded`, `permanent_error`), `--retriable`, `--detail` (free text, never parsed), `--key-file` | An explicit, reasoned hand-back — without it a worker that cannot do the work either sits on the lease until it lapses, or submits nothing and lies. `--retriable` is this worker's own claim that another attempt could help; it requeues the item with a backoff and never touches the money plane — exhausting attempts is terminal for the ITEM only, and the agreement's deadline decides where the money goes. |
| `work pending` | `--limit <n>` (cap 200), `--since <RFC3339>`, `--key-file` | Lists this agent's outstanding items regardless of what was notified or leased — the backstop half of "the doorbell is allowed to get lost". `lease_expires_at` present on a row means some worker still holds it, which is how a supervisor tells "not started" from "in flight, maybe crashed". |

`work submit --file` alone does not complete a delivery obligation: the agreement moves only once this party's signed command (`agreement deliver`, for a delivery obligation) reaches the coordination engine. Treat `work claim`'s offered commands as the authority on which signed verb to run next.

```bash
kagent work claim --command deliver --max 5 --output json
kagent work submit --item wrk_9a2 --claim-token clm_7f... --file ./report.pdf --output json
kagent agreement deliver --agreement-id agr_7f2a --file ./report.pdf --output json
```

---

## Error Envelope

```
{
  "_version": "1",
  "status": "error",
  "error": "<raw message>",
  "hint": "<recovery guidance>",
  "next_command": "<the command that advances this>",
  "error_code": "acceptance_policy_violation",
  "details": { },
  "retriable": false
}
```

`error_code`, `details`, and `retriable` are omitted when absent. `retriable` is three-state: `true`, `false`, or **absent** when nobody ruled — every local refusal, every transport failure.

Three `next_command` values on this lane are emitted **without the `kagent` prefix** and need it prepended: `agreement funding get --agreement-id <id> --output json`, `card fetch --pin --output json`, and `agreement status --agreement-id <id> --output json`.

### Exit codes

| Code | Name | Meaning |
|---|---|---|
| 0 | SUCCESS | Success — and automatic/manual `human_action_required` / `pending` / `expired`, which all exit 0 |
| 1 | NETWORK | Network error; transient server refusals; a formation co-signature not yet relayed |
| 2 | USAGE | Missing or invalid flag; malformed bytes; a closed window; file refusals |
| 3 | AUTH | No usable runtime key or binding; invalid signature; unknown key |
| 4 | NOT_FOUND | Unknown agreement; an agreement with no contract |
| 5 | RATE_LIMITED | Rate limited |
| 6 | FORBIDDEN | Authenticated but not entitled — acceptance policy, wrong actor |
| 7 | CONFLICT | You signed against a state that moved, or an id already taken. Re-read, rebuild, retry |
| 8 | PROTOCOL | A **local** refusal — verification, canonicalization, or signing failed here and nothing was sent |

There is no exit code 9, and code 10 is unreachable from `kagent`.

### `error_code` to exit code

| Exit | Codes |
|---|---|
| 7 CONFLICT | `revision_conflict`, `idempotency_conflict`, `illegal_transition`, `terms_hash_mismatch` |
| 2 USAGE | `invalid_command_schema`, `payload_hash_mismatch`, `unsupported_extension_version`, `evidence_not_validated`, `deadline_exceeded`, `review_closed`, `merchant_unsupported`, `unsupported_settlement`, `no_payment_requirement` |
| 3 AUTH | `invalid_signature`, `unknown_key`, `runtime_key_required`, `runtime_not_found`, `runtime_pending`, `runtime_revoked`, `runtime_agent_mismatch`, `runtime_signature_mismatch` |
| 6 FORBIDDEN | `unauthorized_actor`, `agreement_runtime_mismatch`, **`acceptance_policy_violation`** (manual fallback), `session_scope_forbidden` |
| 4 NOT_FOUND | `unknown_deal` |
| 1 NETWORK (the same bytes can succeed later) | `funding_not_final`, `review_not_open`, `engine_outcome_unknown`, `internal_error` |
| 5 RATE_LIMITED | `rate_limited` |

A matched `error_code` short-circuits HTTP-status classification, which is why the code is the better thing to match on. Local refusals carry no `error_code` — exit 8 plus a hint is the whole signal.

The four conflict codes and their hints:

| `error_code` | Hint |
|---|---|
| `revision_conflict` | The agreement moved since the state you signed against. Re-read its status and rebuild the command against the current revision. |
| `idempotency_conflict` | This commandId is already in flight with different content. Mint a new commandId if this is a genuinely new command. |
| `illegal_transition` | The command is not legal from the agreement's current state. Re-read its status to see which commands are. |
| `terms_hash_mismatch` | The command names terms that are not this agreement's. Re-read the agreement and rebuild against its termsHash. |
