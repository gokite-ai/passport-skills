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
4. The terms file reads, parses, contains none of the six CLI-owned members, and carries required matching `registrationBasis` and `price` members. `priceSchedule` is optional; examples use `{}` to keep the slot visible.
5. The seller key selection is unambiguous.

**CLI-owned terms members** — each is exit 2 if present in the terms file: `schema`, `buyerAgentId`, `sellerAgentId`, `runtimeBinding`, `signatures`, `termsHash`.

The CLI has no price override flag. With an omitted or empty `priceSchedule`, `price` is the signed settlement amount. A non-empty `priceSchedule` is signed business data derived from the selected offering's pinned rate card, and `price.amount` must be its resolved escrow expressed as decimal USDC.

Before touching the signing key, `agreement propose` fetches the seller's
ACTIVE registration and locally verifies the registration hash, offering,
and offering. For a non-empty schedule it also verifies the declared override
surface, public ceilings, request quantities, exact resolved line order, escrow
total, and decimal `price.amount`. A mismatch is exit **8**:
nothing is signed and nothing is sent. Passport repeats the same gate at
proposal and acceptance.

What the command does, in order: reads the seller's active registration and takes the `workflowId` from the offering `registrationBasis.offeringId` names — and fetches the offering's current Workflow by content hash (REQUIRED — an offering with no workflow binding is refused locally: the seller must re-publish), re-derives every hash from the literal bytes, and embeds the whole object (`workflow.{workflowHash, templateId, chartHash, config, configHash}`) into the contract (a terms file naming a different id, or authoring a `workflow` member at all, is refused here, before anything is signed), derives the contract (pinning that workflow, the schema, both agent ids, and a `runtimeBinding` of `{runtimeAgentId, agentCardHash, extensionUri, endpoint}` from the pin), validates it against the vendored schema, canonicalizes it, signs the terms hash, re-validates, re-derives the hash and asserts it did not move, journals the proposal **before sending**, sends it, and then relays the formation co-signature.

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

`--watch` returns on the next transition *from whatever state its first read sees*. Open it only when the pending step is the **counterparty's** (a genuine `PROPOSED`, or `FULFILLING` awaiting delivery). Opened on a state that only this agent's own next command advances — e.g. `COMMITTED` before this buyer has funded — it waits for you while you wait for it, and burns the whole timeout. Read once without `--watch` first and act on what the read shows (SKILL.md Step 2).

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
| `DISPUTED` | The seller appealed (`kagent agreement appeal`, seller-only — not reachable from this buyer surface). The arbitration window is running; the contract-named arbiter renders its decision through `kagent agreement resolve` (arbiter seat only). On a chart that offers the split, either party may still settle here until the arbiter rules | `""` |
| `SETTLING_MUTUAL`, `SETTLING_MUTUAL_REJECTED`, `SETTLING_MUTUAL_DISPUTED` | In-flight: a co-signed split was submitted from `DELIVERED`, `REJECTED`, or `DISPUTED` respectively and the vault call has not been observed yet. A `RELAY_FAILED` returns the deal to the origin the state is named for | `kpass agent agreement status --agreement-id <id> --watch --output json` |
| `ACCEPTED`, `RESOLVED`, `SETTLED_MUTUAL` | Terminal. The proof chain records the outcome; a review is open for a bounded window. `SETTLED_MUTUAL` carries `seller_bps` when the read has it | `kpass agent agreement proofs --agreement-id <id> --verify --output json` |
| `CANCELLED`, `DEFAULTED`, `EXPIRED` | Terminal. No further command is legal | `""` |

Terminal states: `ACCEPTED`, `RESOLVED`, `SETTLED_MUTUAL`, `CANCELLED`, `DEFAULTED`, `EXPIRED`. An unrecognized state reports `State: <X>.` — the engine's spelling is passed through untranslated, so a future state does not break the reader.

`SETTLED_MUTUAL` and the three `SETTLING_MUTUAL*` states only ever appear on a chart that offers `kite.contract.settle_mutual`; `standard/v1` and the other templates in the catalog today do not. `--watch` terminates on `SETTLED_MUTUAL` as it does on every other terminal state.

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

### The four outcomes

| Outcome | Distinguishing fields | Envelope | Exit |
|---|---|---|---|
| Funded | `authorization_committed: true`, `submission_complete: true` (no `funding.passport_artifacts_status`) | `success` | 0 |
| **Controller decision required** | `escalation_id`, `escalation_reason`, `action_digest`, `approval_url`, `approval_expires_at` | `human_action_required` | 0 |
| **Committed but unsubmitted** | `authorization_committed: true`, `submission_complete: false`; `details.funding.passport_artifacts_status` is `"pending"` or `"submitted"` | `error`, `error_code: "funding_submission_incomplete"`, `retriable: true` | **1** |
| Refused | never reaches a data map | `error`, `error_code: "session_scope_forbidden"` | **6** |

`passport_artifacts_status` means: `"pending"` — the authorization is committed but the engine has not recorded artifacts; `"submitted"` — the engine accepted them but progress could not be re-read; **absent** — the progress is a fresh engine read.

The governance outcome is an exact `funding-override`, created only by Passport for `buyer_per_tx_limit_exceeded` or `buyer_total_budget_exceeded`. Surface the URL, poll with `kpass agent escalation status --id <id> --wait --output json`, then retry the identical fund command after approval. The decision deadline is the earlier of the configured approval window and the funding action deadline. Pending expires there without automatic renewal; a decision recorded before it persists, and an approval remains actionable until consumed or the funding deadline closes.

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
  "command_type": "kite.contract.accept",
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

`command_type` is `kite.contract.accept` for confirm and `kite.contract.reject` for reject. `reason_code` appears on reject only.

- confirm: hint `Accepted. The escrow releases to the seller.`, `next_command` the `review` command.
- reject: hint `Rejected. The dispute branch is open: ...`, `next_command` the watch.

Local refusals, all exit 8 and nothing sent: the vault deal id, terms hash, or latest proof hash is missing from the agreement; this agent's role is not `buyer`; the expected revision is not at least 1. The signature expiry is `now + 3600s` from the **local** clock — a badly skewed clock produces signatures the vault will not honor.

A `revision_conflict` from the server (exit 7) carries a bespoke hint and a `next_command` that re-runs the same verb: re-read, rebuild, retry.

**`--reason-code` has no enumerated values.** The schema requires a non-empty string and nothing more; the CLI only rejects the empty string. Its keccak256 **is** the on-chain `reasonHash` that the rejection signature commits to, so it is a committed value rather than a comment. Choose something specific and stable, and record exactly what was sent.

---

## `kpass agent agreement settle sign` / `kpass agent agreement settle submit`

The co-signed split, `kite.contract.settle_mutual`: `sellerBps` of the escrow to the seller, the remainder to the buyer, in one vault call without the arbiter. Both verbs are registered on **both** surfaces (`kpass agent agreement settle …` and `kagent agreement settle …`) — either party may initiate, and the counterparty completes. The binary does not establish authority; the agreement read does.

**Availability: requires `passport-cli` ≥ the release that ships `agreement settle`.** No released CLI carries the verbs yet. `agreement actions` is the check that does not depend on knowing the installed version — see the last subsection here.

### `settle sign`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agreement-id <id>` | string | `""` | **yes** | |
| `--seller-bps <n>` | int | `0` | **yes** | Basis points of the escrow to the seller, `0..9999`. `10000` is refused with a hint naming `agreement confirm`; `0` is legal and records that both parties agreed nothing was payable. |
| `--basis-file <path>` | string | `""` | no | A JSON file stating how `sellerBps` was derived. Carried into the offer verbatim as `basis` and never interpreted. |
| `--output-file <path>` | string | `""` | **yes** | Where the portable settlement offer is written. |

```bash
kpass agent agreement settle sign \
  --agreement-id agr_123 \
  --seller-bps 6200 \
  --basis-file ./count-report.json \
  --output-file ./settlement-offer.json \
  --output json
```

Checks, in order, with **nothing signed until all of them pass**:

1. The local runtime identity resolves and the pinned chain context is present.
2. The agreement read reports this agent's role as `buyer` or `seller`. Any other seat — the contract-named arbiter included — is refused.
3. `kite.contract.settle_mutual` is in the current `offered_commands`. This is a **required** answer: a server that cannot say refuses the verb rather than defaulting to allowed.
4. The vault state on that same read is one of `Delivered`, `Rejected`, `Appealed`, and the agreement state is the matching origin. A nonce read before the delivery landed is one settlement stale.
5. `--seller-bps` is in range.
6. All four vault anchors are present on that one read: `vault.dealId`, `settlement_terms_hash`, `latest_proof_hash`, and `vault.nonce`. A missing anchor is a refusal, never a default, and `latest_proof_hash` must be non-zero — the vault rejects a settlement with no receipt.

It then sets `expiry` from the local clock with the standard one-hour window, signs the `MutualSettlement` digest under the **vault** domain, and writes the offer. The **welded** settlement terms hash and the vault's **current** nonce are what the signature commits to; the command envelope that `settle submit` later builds anchors to the **current** terms hash instead. These are the same two anchors `resolve` keeps apart.

A badly skewed local clock produces an `expiry` the vault will not honor, exactly as on `confirm` / `reject`.

### The settlement offer

```json
{
  "schema": "kite:cli:mutual-settlement-offer:v1",
  "agreementId": "agr_123",
  "chainId": 5887,
  "vaultAddress": "0x…",
  "vaultDealId": "0x…",
  "chartHash": "sha256:0e8057b7…",
  "state": "DELIVERED",
  "expectedRevision": 4,
  "settlementTermsHash": "sha256:…",
  "receiptHash": "sha256:…",
  "nonce": 3,
  "sellerBps": 6200,
  "expiry": 1788000000,
  "signerRole": "buyer",
  "signerAgentId": "did:kite:…",
  "signerKeyId": "…",
  "mutualSettlementSig": "0x…",
  "basis": {
    "deliveryHash": "sha256:…",
    "acceptedUnits": 62,
    "maxUnits": 100,
    "countingRule": "sha256:…"
  }
}
```

Everything above `basis` is either inside the signed digest or an anchor the counterparty must match. `basis` is the caller's stated derivation, carried verbatim from `--basis-file`: the platform never reads the delivered bytes and cannot check a count, so this is the only record of how `sellerBps` was reached, and it is what the counterparty reads before deciding whether its own count agrees.

The offer is **data, not a command**. It carries one signature and cannot move the agreement.

### `settle submit`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--file <path>` | string | `""` | **yes** | A `kite:cli:mutual-settlement-offer:v1` file written by the counterparty's `settle sign`. |

```bash
kpass agent agreement settle submit --file ./settlement-offer.json --output json
```

What it does, in order:

1. Resolves the local identity and requires the **counterparty** seat — the seat the offer's `signerRole` is not.
2. Re-reads the agreement authoritatively.
3. Requires the offer's agreement id, chain id, vault address, vault deal id, state, revision, settlement terms hash, receipt hash, chart hash, and vault nonce to **equal** that fresh read. Any difference is a stale offer: refused, never repaired.
4. Requires the offer's `expiry` to be in the future with enough room for relay and inclusion. The expiry is inside the digest the initiator signed, so the completed pair keeps it.
5. Recovers the initiator's signature against the runtime address pinned for its seat in the funding context's Activation — the vault's own check, reproduced locally so a mistake surfaces here rather than as a reverted transaction.
6. Signs the same digest with this party's key, and recovers its own signature against its own pinned address.
7. Builds and signs the v1 `kite.contract.settle_mutual` AgreementCommand over the **current** terms hash and the fresh revision, then submits it.

```json
{
  "agreement_id": "agr_123",
  "command_id": "cmd_…",
  "command_type": "kite.contract.settle_mutual",
  "state": "SETTLING_MUTUAL",
  "revision": 5,
  "seller_bps": 6200,
  "expected_revision": 4,
  "vault_deal_id": "…",
  "vault_nonce": "…",
  "receipt_hash": "…",
  "expiry": "…",
  "receipt": { … },
  "hint": "…",
  "next_command": "kpass agent agreement status --agreement-id agr_123 --watch --output json"
}
```

The payload carries `sellerBps`, `buyerMutualSettlementSig`, `sellerMutualSettlementSig`, and `expiry` — two vault-domain signatures over one struct, placed by the signer's seat and not interchangeable. The vault verifies them, not the engine, which is why every check above runs locally first: a wrong domain, a wrong terms hash, or a stale nonce does not come back as a 400 after Passport and the engine have both said 200.

### Exit codes on these two verbs

| Exit | Cause |
|---|---|
| 2 USAGE | `--seller-bps` outside `0..9999` (including `10000`), a missing `--agreement-id` / `--output-file` / `--file`, an unreadable `--basis-file`, or a file that is not a `kite:cli:mutual-settlement-offer:v1` offer |
| 8 PROTOCOL (local, nothing sent) | This agent's role is not `buyer` or `seller`; `kite.contract.settle_mutual` is not in the current `offered_commands`; the state is not one of the three origins; a vault anchor is missing or `latest_proof_hash` is zero; a stale offer (any anchor differs from the fresh read); a non-future or too-near `expiry`; the initiator's signature does not recover to the address pinned for its seat; `settle submit` run from the initiator's own seat |
| 7 CONFLICT | `revision_conflict` — the agreement moved after the offer was signed. The initiator regenerates the offer from a fresh read; nothing is rewritten and re-signed by hand. Also `idempotency_conflict`, `illegal_transition`, `terms_hash_mismatch` |
| 6 FORBIDDEN | `unauthorized_actor` — the server ruled this seat may not submit the command. The arbiter lands here even from `DISPUTED` |

A server-side `command_not_offered` (the engine's 422) is the same refusal as the local offered-command check, reached one step later; re-read `agreement status` rather than retrying the same bytes.

### `agreement actions` — is the split available right now?

```bash
kpass agent agreement actions --agreement-id <id> --output json
```

The chart plus the current state is the authority on which commands are available, and this read is where that answer surfaces. On a chart that offers the split it gains one row, with no schema change:

```json
{
  "command": "kite.contract.settle_mutual",
  "actor_roles": ["buyer", "seller"],
  "required_signer_roles": ["buyer", "seller"],
  "available_to_caller": true,
  "cli_supported": true,
  "cli_command": "kpass agent agreement settle sign --agreement-id agr_123"
}
```

`available_to_caller` is `true` for the buyer and the seller and `false` for the arbiter, even from `DISPUTED`. `cli_supported` is `false` on a CLI that predates the verbs — which is the check to run instead of reasoning about version strings. `workflow-template get` publishes the same both-party metadata from the chart, and omits the compatibility scalar `role`: naming one primary role for a both-signed command would be wrong.

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
| `--skill <name>` | string | `""` | no | The CLI does not validate this value, but a served seller's item-minting logic does: to reach the handler as a `request` item it must be exactly a known coordination frame URN (e.g. `urn:kiteai:coordination:frame:request:v1`), never a descriptive label or an offering id. A `--skill` that isn't a recognized frame is silently shelved — nothing errors, nothing is minted. See SKILL.md's "Negotiate (Optional)" step for the exact request-frame body shape. |
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

`--kind` is open for advisory values, with two reserved kinds: manual `acceptance-override` is enforced for seller acceptance; `funding-override` is platform-created only and manual creation is exit 2. Creating an advisory or acceptance escalation returns `human_action_required` with an `approval_url` — the same passkey ceremony as a session request.

---

## `kpass agent work claim` / `work submit` / `work fail` / `work pending`

The work plane's queue, this agent's side: after every committed transition the coordination engine states an obligation, Passport materializes it as a work item, and these four verbs are how the obligated party drains it. On the buyer surface the obligation that most commonly shows up here is the Activation signature due once an agreement reaches `COMMITTED` (Step 5). Unlike the seller surface (`kagent`), none of the four register a `--config-dir` flag here — buyer state is anchored to `.kite-passport/`, the same as everywhere else in this lane.

An item carries two clocks that never merge: `deadline` is the agreement's (past it the vault settles without anyone's signature), `lease_expires_at` is the queue's (past it another attempt starts). Pace the work by the deadline, retries by the lease.

| Verb | Flags | Notes |
|---|---|---|
| `work claim` | `--command <name>` (repeatable, narrows to items offering that act), `--max <n>` (default 25, cap 100), `--lease-seconds <n>` (30–3600, default 300), `--key-file` | Leases up to `--max` due items exclusively for `--lease-seconds`, and reads back the offered commands, the agreement deadline, and the verification anchors in one call. An EMPTY batch is success, not refusal. The claim token fences the whole batch; quote it back on `submit`/`fail`. |
| `work submit` | `--item <wrk_id>`, `--claim-token <token>`, `--agreement-id` (with `--file`; read from the queue when absent), `--file`, `--evidence-id` + `--content-hash`, `--evidence-type`, `--content-type`, `--units`, `--key-file` | Records that bytes exist for an artifact-bearing obligation — deliberately nothing more. The agreement moves only once this party's own signed command reaches the coordination engine. On this lane, a non-artifact obligation (the Activation signature) is completed by running the offered signing verb directly (`agreement funding sign`), not by `work submit`. |
| `work fail` | `--item`, `--claim-token`, `--reason` (closed enum: `upstream_unavailable`, `request_unpriced`, `capacity_exceeded`, `permanent_error`), `--retriable`, `--detail`, `--key-file` | An explicit, reasoned hand-back. `--retriable` requeues the item with a backoff and never touches the money plane. |
| `work pending` | `--limit <n>` (cap 200), `--since <RFC3339>`, `--key-file` | Lists this agent's outstanding items regardless of what was notified or leased — the backstop half of "the doorbell is allowed to get lost". |

Treat `work claim`'s offered commands as the authority on which verb to run next for a given item, rather than assuming `work submit` always applies.

```bash
kpass agent work pending --output json
kpass agent work claim --max 5 --output json
```

Read the offered command name back from the claimed item and run whatever it names — for the Activation signature that is `agreement funding sign`:

```bash
kpass agent agreement funding sign --agreement-id agr_7f2a --output json
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

`command_not_offered` is the engine's 422 for a command that is not available at this state and revision — the server-side twin of the local offered-command check on `settle sign`. It is not retriable with the same bytes: re-read `agreement status` and `agreement actions`.
