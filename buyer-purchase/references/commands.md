# Buyer: Purchase — Command Reference

Every command takes `--output json`. All flags are long-form. `--base-url`, `--output`, and `--no-interactive` are persistent root flags; `--key-file` (overriding `KPASS_RUNTIME_KEY_FILE`) is registered on every command in this file.

`--config-dir` does not exist on the buyer surface.

---

## `kpass agent agreement propose`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--seller <ref>` | string | `""` | **yes** (unless `--resume`) | DID, `agt_` id, uid, or key thumbprint. Resolving to this same agent is exit 2. |
| `--terms-file <path>` | string | `""` | **yes** (unless `--resume`) | JSON file carrying the contract's business members. |
| `--seller-key-id <key_id>` | string | `""` | conditional | Which of the seller's active keys the Agreement digest names. Required when the seller has more than one active key with an address. |
| `--resume <proposalId>` | string | `""` | no | Resend a journaled proposal's exact bytes. Short-circuits every other flag. |

Preconditions, in the order they are checked:

1. The runtime key resolves and its binding is `active` — otherwise exit 3.
2. A persona card is pinned — otherwise exit 2 with `next_command: "kpass agent card fetch --pin --output json"`. The pin must carry `endpoint` and `extension_uri`, and a non-zero `chain_id` and `escrow_vault` — a pin without chain context is exit 8.
3. The seller reference resolves, and is not this agent.
4. The terms file reads, parses, contains none of the six CLI-owned members, and carries required matching `registrationBasis`, `priceSchedule`, and `price` members.
5. The seller key selection is unambiguous.

**CLI-owned terms members** — each is exit 2 if present in the terms file: `schema`, `buyerAgentId`, `sellerAgentId`, `runtimeBinding`, `signatures`, `termsHash`.

The CLI has no price override flag. `priceSchedule` is signed business data derived from the selected offering's pinned rate card, and `price.amount` is its resolved escrow expressed as decimal USDC. Changing only one would create an internally inconsistent contract, so both must be complete in the terms file.

What the command does, in order: derives the contract (pinning the template, the schema, both agent ids, and a `runtimeBinding` of `{runtimeAgentId, agentCardHash, extensionUri, endpoint}` from the pin), validates it against the vendored schema, canonicalizes it, signs the terms hash, re-validates, re-derives the hash and asserts it did not move, journals the proposal **before sending**, sends it, and then relays the formation co-signature.

```bash
kpass agent agreement propose --seller did:kite:example-seller --terms-file ./terms.json --output json
```

```
{
  "_version": "1",
  "status": "success",
  "agreement_id": "...",
  "state": "PROPOSED",
  "revision": 1,
  "terms_hash": "...",
  "proposal_id": "prop_...",
  "seller_agent_id": "did:kite:...",
  "seller_key_id": "did:kite:...#<fragment>",
  "amount_base_units": "25000000",
  "agreement_sig": "0x...",
  "formation_relayed": true,
  "receipt": { ... },
  "hint": "...",
  "next_command": "kpass agent agreement status --agreement-id <id> --watch --output json"
}
```

### The formation relay

After the contract is accepted, the same invocation signs an EIP-712 Agreement (agreement id, terms hash, amount, buyer agent address, seller key address) under the escrow domain and submits it as a `formation-signatures` party envelope carrying `agreementSig` and `sellerKeyId`. **The seller cannot accept without it.** `formation_relayed: true` confirms it landed.

Two post-proposal partial failures are reported as errors that still name the agreement:

| Failure | Shape | Recovery |
|---|---|---|
| The co-signature could not be built | Local protocol error, `details.agreement_id` | The agreement exists but has no relay. Report; nothing local can sign it. |
| The relay was rejected or lost | Classified API error, `details.agreement_id` and `details.agreement_sig` | Re-run `propose`. The relay is write-once and an identical resend is a no-op. |

### `--resume`

The local journal is the idempotency key. On a **4xx** (the server ruled) the journal is cleared. On a **5xx or transport failure** it is kept, and the error carries `details.proposal_id` plus `next_command: "kpass agent agreement propose --resume <proposalId> --output json"`. Resume resends the exact journaled bytes; a fresh `propose` mints new bytes and can create a second agreement for one intent.

Exit 4 on `--resume` means no journaled proposal by that id.

---

## `kpass agent agreement status`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** | |
| `--watch` | bool | `false` | no | Poll until the state or revision changes, a terminal state is reached, or the timeout. |
| `--timeout <duration>` | duration | `10m` | no | Go duration (`10m`, `30s`). |

`--watch` backs off from 2 seconds to a 30-second cap, and only polls while the state is non-terminal. A timeout yields envelope `status: "pending"` with `timed_out: true` — exit 0, nothing failed.

```
{
  "_version": "1",
  "status": "success",
  "agreement_id": "...",
  "state": "DELIVERED",
  "revision": 4,
  "role": "buyer",
  "buyer_agent_id": "did:kite:...",
  "seller_agent_id": "did:kite:...",
  "terms_hash": "...",
  "amount": "...",
  "updated_at": "...",
  "arbiter_agent_id": "did:kite:...",
  "buyer_runtime_key_id": "...",
  "seller_runtime_key_id": "...",
  "seller_payout": "0x...",
  "latest_proof_hash": "...",
  "vault": { "deal_id": "...", "nonce": "...", "state": "...", "vault_address": "0x...", "chain_id": 8453 },
  "contract": { ... },
  "formation": { ... },
  "agreement_sig": { "sig": "0x...", "key_id": "...", "seller_key_id": "...", "recorded_at": "..." },
  "watched": true,
  "changed": true,
  "hint": "...",
  "next_command": "..."
}
```

`contract` and `formation` are the engine's bytes **verbatim**. `proposal_unavailable: true` appears when the proposal bytes could not be read. Optional members are omitted when the engine has not filled them.

### State machine and what each state means for a buyer

| State | Meaning | `next_command` the CLI gives |
|---|---|---|
| `PROPOSED`, no `agreement_sig` | The formation co-signature never landed; the seller cannot accept | `""` — re-run `propose` |
| `PROPOSED`, `agreement_sig` present | Awaiting the seller's acceptance | `""` |
| `COMMITTED` | The seller accepted. Funding context is open; both Activation signatures are due | `kpass agent agreement funding get --agreement-id <id> --output json` |
| `FULFILLING` | Escrow funded; the seller's delivery is next | `""` |
| `DELIVERED` | Verify the artifact against the `deliveryHash` in the signed command, then confirm or reject | `kpass agent agreement proofs --agreement-id <id> --verify --output json` |
| `REJECTED` | Rejected by the buyer; the dispute branch is open | `""` |
| `DISPUTED` | Under arbitration; the contract-named arbiter decides | `""` |
| `ACCEPTED`, `RESOLVED` | Terminal. The proof chain records the outcome; a review is open for a bounded window | `kpass agent agreement proofs --agreement-id <id> --verify --output json` |
| `CANCELLED`, `DEFAULTED`, `EXPIRED` | Terminal. No further command is legal | `""` |

Terminal states: `ACCEPTED`, `RESOLVED`, `CANCELLED`, `DEFAULTED`, `EXPIRED`. An unrecognized state reports `State: <X>.` — the engine's spelling is passed through untranslated, so a future state does not break the reader.

---

## `kpass agent agreement list`

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--state <STATE>` | string | `""` | **Client-side filter only** — the signed request carries role, limit, and offset. The envelope reports `filtered_client_side: true`. |
| `--role <buyer\|seller>` | string | `""` | Validated locally; anything else is exit 2. |
| `--limit <n>` | int | `0` (backend default 50) | Capped at 200. |
| `--offset <n>` | int | `0` | |

```
{
  "agreements": [ { "agreement_id": "...", "state": "...", "revision": 2, "role": "buyer",
                    "buyer_agent_id": "...", "seller_agent_id": "...", "terms_hash": "...",
                    "amount": "...", "updated_at": "..." } ],
  "count": 1,
  "page_size": 1,
  "state_filter": "COMMITTED",
  "filtered_client_side": true
}
```

Because `--state` filters after the page is fetched, a `--state` that matches nothing on the current page does not mean nothing matches — page through with `--offset`.

---

## `kpass agent session request`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agreement-id <id>` | string | `""` | see below | Scope to one agreement — the narrow default. |
| `--seller <did>` | string array | none | see below | Repeatable. Scope to a seller agent DID. |
| `--template <name>` | string array | none | see below | Repeatable. Scope to a workflow template. |
| `--all-agreements` | bool | `false` | see below | The explicit general grant. |
| `--max-amount-per-tx <usd>` | string | `""` | **yes** | Per-payment USD cap. |
| `--max-total-amount <usd>` | string | `""` | **yes** | Total USD budget for the session. |
| `--ttl <duration>` | duration | `1h` | no | How long the session lasts **once approved**. Zero or negative is exit 2. |
| `--task-summary <text>` | string | derived | no | What the owner is asked to fund. Defaults to a description of the scope. |

### Scope rules (exit 2 on violation, message `The requested scope is invalid: ...`)

- At least one of `--agreement-id`, `--seller`, `--template`, `--all-agreements` is required.
- `--all-agreements` **cannot** be combined with any of the other three: it is the general grant.
- `--agreement-id`, `--seller`, and `--template` **narrow together** (AND), they do not widen.
- An explicitly empty seller or template list is refused — no agreement could satisfy it.

Scope descriptions the CLI produces (they appear in `scope_description` and in hints): `any agreement with any seller (the general grant)`, or `agreement <id>` / `seller(s) a, b` / `template(s) x, y` joined with ` AND `.

```bash
kpass agent session request --agreement-id agr_123 --max-amount-per-tx 25 --max-total-amount 25 --output json
```

Always `status: "human_action_required"`, exit 0:

```
{
  "_version": "1",
  "status": "human_action_required",
  "request_id": "req_...",
  "request_status": "pending_approval",
  "approval_url": "https://.../approve/...",
  "approval_expires_at": "...",
  "scope": { "agreement_id": "agr_123" },
  "scope_description": "agreement agr_123",
  "max_amount_per_tx": "25",
  "max_total_amount": "25",
  "ttl_seconds": 3600,
  "task_summary": "Fund agreement agr_123",
  "hint": "...",
  "next_command": "kpass agent session request-status --request-id <id> --wait --output json"
}
```

`approval_expires_at` is the **approval window**, not the session TTL — the session clock starts when the owner approves.

A 409 on this command is exit **7**: one session request may await a decision at a time. Poll the pending one (the error's `next_command` becomes that poll when the pending `request_id` is known) or let its window close.

---

## `kpass agent session request-status`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--request-id <id>` | string | `""` | **yes** | |
| `--wait` | bool | `false` | no | Poll with backoff until the owner decides or the window closes. |
| `--timeout <duration>` | duration | `10m` | no | How long `--wait` waits. |

There is no `--poll-interval`: the backoff is fixed at 2 seconds doubling to a 15-second cap.

```
{
  "_version": "1",
  "status": "success",
  "request_id": "req_...",
  "request_status": "approved",
  "approval_expires_at": "...",
  "waited": true,
  "timed_out": false,
  "session_id": "ses_...",
  "session_status": "active",
  "session_expires_at": "...",
  "delegation": { ... },
  "usage": { ... },
  "scope": { "agreement_id": "agr_123" },
  "scope_description": "agreement agr_123",
  "session_recorded": true,
  "hint": "...",
  "next_command": "kpass agent fund --agreement-id agr_123 --output json"
}
```

| `request_status` | Envelope `status` | `next_command` |
|---|---|---|
| `approved` | `success` | `kpass agent fund --agreement-id <id> --output json` |
| `pending_approval` | `human_action_required` | the same poll command |
| `rejected` | **`expired`** | a fresh `session request` |
| `expired` | `expired` | a fresh `session request` |
| anything else | `success` | `kpass agent session request-status --request-id <id> --output json` |

`waited` and `timed_out` appear only with `--wait`.

**The recorded scope is what the owner approved**, read back from the approved delegation — not what was requested. `session_recorded: true` means `fund` will find this session without being told which one; `session_recorded: false` with a `session_recorded_error` means the local record failed to write (non-fatal — pass `--session-id` to `fund` explicitly).

---

## `kpass agent fund`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** | |
| `--session-id <id>` | string | `""` | no | Spend this session rather than the recorded one that covers the agreement. Skips the local scope check. |

### Session selection

With `--session-id` the value is used verbatim. Without it, the CLI reads its recorded approved, unexpired sessions and picks one whose scope permits this agreement — spending an extra agreement read only when a scope needs the seller or template to decide. Zero approved sessions, or none whose scope covers the agreement, is a **local** refusal: exit 6, `error_code: "session_scope_forbidden"`, and nothing was sent.

The envelope reports which path was taken in `session_selected_from` (`"agent state"` or `"--session-id"`).

### The three outcomes

| Outcome | Distinguishing fields | Envelope | Exit |
|---|---|---|---|
| Funded | `authorization_committed: true`, `submission_complete: true` (no `funding.passport_artifacts_status`) | `success` | 0 |
| **Committed but unsubmitted** | `authorization_committed: true`, `submission_complete: false`; `details.funding.passport_artifacts_status` is `"pending"` or `"submitted"` | `error`, `error_code: "funding_submission_incomplete"`, `retriable: true` | **1** |
| Refused | never reaches a data map | `error`, `error_code: "session_scope_forbidden"` | **6** |

`passport_artifacts_status` means: `"pending"` — the authorization is committed but the engine has not recorded artifacts; `"submitted"` — the engine accepted them but progress could not be re-read; **absent** — the progress is a fresh engine read.

Success envelope:

```
{
  "_version": "1",
  "status": "success",
  "agreement_id": "...",
  "session_id": "ses_...",
  "authorization_committed": true,
  "submission_complete": true,
  "buyer_wallet": "0x...",
  "vault_deal_id": "...",
  "vault_address": "0x...",
  "chain_id": 8453,
  "amount_base_units": "25000000",
  "session_selected_from": "agent state",
  "session_scope": { "agreement_id": "..." },
  "session_scope_description": "agreement ...",
  "auth_3009": { ... },
  "funding": {
    "authorization_committed": true,
    "have_buyer_wallet": true,
    "have_buyer_activation_sig": false,
    "have_seller_activation_sig": false,
    "have_auth_3009": true,
    "have_expected_deal_id": true,
    "phase": "...",
    "next_step": "..."
  },
  "hint": "...",
  "next_command": "..."
}
```

`session_scope` / `session_scope_description` appear only when the session came from local state. `hint` prefers the engine's own `next_step` verbatim when the engine supplied one, and calls out `rejected_fields` — artifacts the engine refused because they would change a write-once value it already pinned. Retrying cannot change a rejected field.

### The retry contract for `funding_submission_incomplete`

The error message states plainly that the authorization **is** committed: the session budget is charged and the payment authorization is stored, and only the engine's confirmation is missing. The hint is explicit that this is a partial result, not a rollback, and that funding is idempotent on (session, agreement). The `next_command` is the identical `fund` command including the resolved `--session-id`.

Run that command. Do not propose again; do not request another session. Either buys the deal twice.

---

## `kpass agent agreement funding get`

Flags: `--agreement-id` (required) plus `--key-file`.

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

`activation_signable` is `activation != nil && activation.buyer != ""`. The buyer wallet arrives with the funding authorization, so this is `false` until `fund` has run — which is why `funding get` is the right command to check before `funding sign`.

`rejected_fields` is present only when non-empty and lists write-once values the engine refused to change.

---

## `kpass agent agreement funding sign`

Flags: `--agreement-id` (required) plus `--key-file`. **No amount flag** — the amount comes from the signed contract, converted once.

Signs the EIP-712 `Activation` (terms hash, buyer, buyer agent, seller agent, seller payout, arbiter, amount, and the five windows) under the vault domain, and submits `buyerActivationSig` for this role.

Before signing it validates, refusing with exit **8** (nothing sent) on any mismatch: the funding context's chain id and vault against the pinned card; the Activation's terms hash against the agreement's; that the served contract re-derives the same terms hash; that `price.asset` is `USDC`; that the amount converts to exactly the Activation's base units; that `seller_payout` matches the contract's escrow payout address; that this role's agent address is this agent's own runtime key address; that buyer agent, seller agent, and arbiter are present and the arbiter matches the contract; that the contract's pinned card hash is the one this agent pinned; that the buyer wallet and all five windows are present.

```
{
  "agreement_id": "...",
  "role": "buyer",
  "activation_sig": "0x...",
  "submitted_member": "buyerActivationSig",
  "terms_hash": "...",
  "amount_base_units": "25000000",
  "chain_id": 8453,
  "escrow_vault": "0x...",
  "validated": [ "vault domain matches the pinned card", "termsHash matches the agreement", "..." ],
  "hint": "Activation validated against the signed terms and signed. ...",
  "next_command": "kpass agent agreement funding get --agreement-id <id> --output json"
}
```

An empty buyer wallet is exit 8 with a hint saying it is a normal stage rather than a fault — the wallet arrives with the buyer's funding authorization. Run `fund` first.

---

## `kpass agent agreement confirm` / `kpass agent agreement reject`

`confirm` flags: `--agreement-id` (required) plus `--key-file`.
`reject` flags: `--agreement-id` (required), `--reason-code` (**required**, any non-empty string), plus `--key-file`.

Both build a signed settlement command against the vault anchors:

```
{
  "agreement_id": "...",
  "command_id": "cmd_...",
  "command_type": "kite.contract.accepted",
  "state": "ACCEPTED",
  "revision": 5,
  "settlement_sig": "0x...",
  "expected_revision": 4,
  "vault_deal_id": "...",
  "vault_nonce": "...",
  "receipt_hash": "...",
  "expiry": "...",
  "receipt": { ... },
  "reason_code": "delivery-hash-mismatch"
}
```

`command_type` is `kite.contract.accepted` for confirm and `kite.contract.rejected` for reject. `reason_code` appears on reject only.

- confirm: hint `Accepted. The escrow releases to the seller.`, `next_command` the `review` command.
- reject: hint `Rejected. The dispute branch is open: ...`, `next_command` the watch.

Local refusals, all exit 8 and nothing sent: the vault deal id, terms hash, or latest proof hash is missing from the agreement; this agent's role is not `buyer`; the expected revision is not at least 1. The signature expiry is `now + 3600s` from the **local** clock — a badly skewed clock produces signatures the vault will not honor.

A `revision_conflict` from the server (exit 7) carries a bespoke hint and a `next_command` that re-runs the same verb: re-read, rebuild, retry.

**`--reason-code` has no enumerated values.** The schema requires a non-empty string and nothing more; the CLI only rejects the empty string. Its keccak256 **is** the on-chain `reasonHash` that the rejection signature commits to, so it is a committed value rather than a comment. Choose something specific and stable, and record exactly what was sent.

---

## `kpass agent agreement proofs`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** | |
| `--verify` | bool | `false` | no | Recompute the chain locally and verify every signature. |
| `--signer-agent <ref>` | string | pinned persona | no | Which agent's signing keys attest the chain. |

Without `--verify`: `{ "agreement_id", "count", "proofs": [ ... ], "verified": false }`, and `next_command` is the same command with `--verify`.

With `--verify`, success adds `verified`, `receipt_hash_for_next_command`, `sequence`, `chain_linked`, `proof_hashes_recomputed`, `signatures_verify`, `signer_attested`, `signer_agent`, and — when there is something to report — `linkage_errors`, `recompute_errors`, `signature_errors`, `attestation_notes`, `unsigned_links`, `sequence_gaps`.

Three checks run: chain linkage, hash recomputation, and signature recovery. Each signature is then attested against the signer agent's published key set **as of that link's creation time**, so a key that was valid then and revoked since still verifies. Unsigned links fail. A verification failure is exit **8** with the whole result in `details` — nothing to retry, and a reason to reject rather than confirm. An empty chain with `--verify` is also exit 8.

---

## `kpass agent agreement evidence list`

Flags: `--agreement-id` (required) plus `--key-file`.

```
{
  "agreement_id": "...",
  "evidence": [ { "evidence_id": "...", "type": "delivery", "hash": "sha256:<hex>",
                  "url": "https://...", "format": "...", "recorded_at": "...", "size_bytes": 1234 } ],
  "records": [ { ... } ],
  "count": 1
}
```

`records` is the engine's records verbatim; `evidence` is the decoded view. The digest lives in `hash` here (`sha256:<hex>`); the same value appears as `delivery_hash` in the seller's delivery output and as `deliveryHash` inside the signed delivery command. `url` is where the artifact can be downloaded for the sha256 comparison.

`agreement evidence add` is **seller-only** and is not on this surface.

---

## `kpass agent agreement review`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** | |
| `--rating <n>` | int | `0` | **yes** | 1 (worst) to 10 (best). |
| `--comment <text>` | string | `""` | no | At most 512 characters. |

The subject is derived from the agreement — the counterparty — and there is no flag for it.

```
{ "agreement_id": "...", "subject_agent_id": "did:kite:...", "score": 9,
  "terminal_state": "ACCEPTED", "comment": "..." }
```

`--rating` is **not** range-checked locally: an out-of-range value fails at the schema gate as exit 8 rather than as a usage error. A non-terminal agreement is refused locally with exit 8 — the local half of the `review_not_open` refusal, retriable purely because time passes.

---

## `kpass agent message send` / `kpass agent message status`

For asking the counterparty a question mid-agreement.

`message send`:

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--to <ref>` | string | `""` | **yes** | A `did:kite` DID or an `agt_` id. |
| `--body <json>` | string | `""` | one of | Inline JSON. Mutually exclusive with `--file`. |
| `--file <path>` | string | `""` | one of | Read the body from a JSON file. |
| `--skill <name>` | string | `""` | no | An unvalidated routing hint for the recipient. |
| `--ttl <duration>` | duration | `0` (server default 10m) | no | Between `30s` and `1h` when non-zero; outside that is exit 2. |
| `--wait` | bool | `false` | no | Poll until the recipient replies or the TTL elapses. There is no `--timeout` — the deadline is the message's own expiry. |

`message status`: `--id` (required), `--wait`. No `--timeout`.

Message states: `queued`, `claimed`, `replied`, `expired`.

**Two different `status` questions, two different members.** The envelope's top-level `status` is the command's own outcome; the message's own state is `message_status` and carries `queued` / `claimed` / `replied` / `expired`. The envelope status maps from it: `replied` -> `success`, `expired` -> `expired`, `queued`/`claimed`/timed-out -> `pending` — so `status: pending` with `message_status: claimed` is normal.

(They used to share the key `status` and the envelope overwrote the mailbox state, so `queued` reported as `success`. Fixed on both verbs.)

**Re-running `message send` enqueues a SECOND message.** The idempotency key is minted per invocation, so pass the same `--idempotency-key <value>` on both attempts when you mean to resend one message; the second call then returns the original with `duplicate: true`.

There is no thread id. An idempotency key is minted per invocation, so re-sending identical bytes returns the original message (`duplicate: true`), but two deliberate sends of the same body are two messages.

On this lane a 409 is exit 7 and a 410 is exit **2** (the TTL elapsed — not an auth problem).

---

## `kpass agent escalate` / `kpass agent escalation status`

Available on the buyer surface, though the enforced escalation kind (`acceptance-override`) is a seller-side concern. Use it when this agent needs the owner to rule on something before it proceeds.

`escalate`: `--kind` and `--summary` are both required; `--agreement-id` is required when `--kind acceptance-override`; `--payload` and `--payload-file` are mutually exclusive and must be valid JSON; `--wait` with `--timeout` (default `10m`).

`escalation status`: `--id` (required — not `--escalation-id`), `--wait`, `--timeout`.

`--kind` has **no closed enum**: `acceptance-override` is the only reserved and enforced kind, and any other string produces an advisory escalation with `enforced: false`. Creating one returns `human_action_required` with an `approval_url` — the same passkey ceremony as a session request.

---

## Error Envelope

```
{
  "_version": "1",
  "status": "error",
  "error": "<raw message>",
  "hint": "<recovery guidance>",
  "next_command": "<the command that advances this>",
  "error_code": "funding_submission_incomplete",
  "details": { "funding": { ... } },
  "retriable": true
}
```

`error_code`, `details`, and `retriable` are omitted when absent. `retriable` is three-state: `true`, `false`, or **absent** when nobody ruled (every local refusal, every transport failure).

### Exit codes

| Code | Name | Meaning on this lane |
|---|---|---|
| 0 | SUCCESS | Success — and also `human_action_required`, `pending`, `expired`, which all exit 0 |
| 1 | NETWORK | Network error; transient server refusals; the `funding_submission_incomplete` partial result |
| 2 | USAGE | Missing or invalid flag; malformed bytes; a closed window |
| 3 | AUTH | No usable runtime key or binding; invalid signature; unknown key |
| 4 | NOT_FOUND | Unknown agreement or reference; no journaled proposal |
| 5 | RATE_LIMITED | Rate limited |
| 6 | FORBIDDEN | Authenticated but not entitled — scope, actor, or policy |
| 7 | CONFLICT | You signed against a state that moved, or an id already taken. Re-read, rebuild, retry |
| 8 | PROTOCOL | A **local** refusal — canonicalization, signing, or verification failed here and nothing was sent. Do not retry the same bytes |

There is no exit code 9. A matched `error_code` short-circuits HTTP-status classification, which is why the code is the better thing to match on.

### `error_code` to exit code

| Exit | Codes |
|---|---|
| 7 CONFLICT | `revision_conflict`, `idempotency_conflict`, `illegal_transition`, `terms_hash_mismatch` |
| 2 USAGE | `invalid_command_schema`, `payload_hash_mismatch`, `unsupported_extension_version`, `evidence_not_validated`, `deadline_exceeded`, `review_closed` |
| 3 AUTH | `invalid_signature`, `unknown_key`, `runtime_key_required`, `runtime_not_found`, `runtime_pending`, `runtime_revoked`, `runtime_agent_mismatch`, `runtime_signature_mismatch` |
| 6 FORBIDDEN | `unauthorized_actor`, `agreement_runtime_mismatch`, `acceptance_policy_violation`, `session_scope_forbidden` |
| 4 NOT_FOUND | `unknown_deal` |
| 1 NETWORK (the same bytes can succeed later) | `funding_not_final`, `review_not_open`, `engine_outcome_unknown`, `internal_error`, `funding_submission_incomplete` |
| 5 RATE_LIMITED | `rate_limited` |

Local refusals carry no `error_code` — exit 8 with a hint is the whole signal.
