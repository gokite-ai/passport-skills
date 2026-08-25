# Seller Agent Setup — Command Reference

Every command takes `--output json`. All flags are long-form; `--version` / `-V` on the root is the only shorthand anywhere in the `kagent` tree.

## Shared Flags

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--output json` | string | (human text) | Required. `--output=json` also works. |
| `--base-url <url>` | string | `https://passport.prod.gokite.ai` | Persistent root flag; overridden by `KITE_PASSPORT_BASE_URL`. |
| `--no-interactive` | bool | `false` | Never prompt; fail if a required flag is missing. Pass it in unattended runs. |
| `--key-file <path>` | string | `<role-dir>/runtime.key` | Overrides `KAGENT_RUNTIME_KEY_FILE`. Relocates the key alone. |
| `--config-dir <path>` | string | `~/.kagent` | Relocates the whole role directory. Seller-only — the buyer surface does not have it. |

Key resolution order: `--key-file`, then `KAGENT_RUNTIME_KEY_FILE`, then `<config-dir or ~/.kagent>/runtime.key`. Resolution creates nothing; a bad path is exit 2.

Colon-separated command paths work as aliases: `kagent agreement:funding:sign` is the same command as `kagent agreement funding sign`. The space-separated form is used throughout these skills.

---

## `kagent init`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--import-key <file\|->` | string | `""` | no | A PATH to a file holding the key, or `-` for stdin. Inline key material is REFUSED: argv reaches shell history, the process table and agent transcripts. |
| `--force` | bool | `false` | no | Overwrite an existing runtime key. Destructive. |

```bash
kagent init --output json
```

```
{
  "_version": "1",
  "status": "success",
  "role": "seller",
  "state_dir": "/Users/you/.kagent",
  "key_file": "/Users/you/.kagent/runtime.key",
  "imported": false,
  "address": "0x...",
  "thumbprint": "...",
  "key_id_fragment": "...",
  "pubkey": "...",
  "key_file_override": false,
  "hint": "Runtime key ready. Bind it to an agent so Passport recognizes this runtime.",
  "next_command": "kagent bind --agent <did-or-agt-id> --output json"
}
```

An existing key without `--force` is exit 2, hint `Replacing a bound key orphans every agreement pinned to it. Pass --force only if that is intended.`, `next_command: "kagent key show --output json"`. Bad key material is also exit 2.

File mechanics: the key and the state file are both written through an exclusive temp file that is chmod'd to `0600` **before** any bytes are written, then renamed into place — a pre-placed file or symlink at the target is never reused. The directory is `0700`. The key is stored as hex plus a newline. `agent-state.json` stays in the role directory even when `--key-file` moves the key.

---

## `kagent key show`

No flags beyond the shared ones. Offline — it does not reach the backend.

```
{
  "status": "success",
  "address": "0x...",
  "key_id": "",
  "key_id_fragment": "...",
  "thumbprint": "...",
  "pubkey": "...",
  "key_file": "/Users/you/.kagent/runtime.key",
  "role": "seller",
  "hint": "keyId is <agent DID>#<fragment>; the DID is filled in once this key is bound to an agent.",
  "next_command": "kagent status --output json"
}
```

`key_id` is **always empty here** — the DID half is only known once the key is bound. Read the bound `key_id` from `bind` or `status`. The private key is never printed by any command.

---

## `kagent bind`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agent <ref>` | string | `""` | **yes** | DID, `agt_...` id, or uid. Required on both paths. |
| `--token <art_...>` | string | `""` | no | Owner-minted bind token; its presence selects the token path. |
| `--wait` | bool | `false` | no | Poll until the binding becomes active. |
| `--env <label>` | string | `""` | no | Environment label recorded on the binding. |
| `--software <id>` | string | `kagent/<version> on <hostname>` | no | Software identifier recorded on the binding. |
| `--device <text>` | string | `""` | no | Device description recorded on the binding. |
| `--poll-interval <seconds>` | **int** | `3` | no | Values below 1 are coerced to the default. |
| `--timeout <seconds>` | **int** | `300` | no | Values below 1 are coerced to the default. |

`--poll-interval` and `--timeout` are bare integers in seconds on this one command. Every other `--timeout` in the tree is a Go duration.

### The two paths

| Path | Trigger | Mechanism | Resulting `binding` |
|---|---|---|---|
| **Direct** | `--token` omitted | The CLI takes a bind nonce, proves possession of the key against it plus the agent id, and registers | **Always `pending`** until the owner approves |
| **Token** | `--token art_...` | The owner pre-authorized by minting a token; the CLI proves possession against the token | Can be `active` immediately |

The reference is resolved to its `agt_...` storage id before the proof is built, because the direct path's proof commits to the agent id the server reads from the request path.

```
{
  "status": "human_action_required",
  "agent_id": "agt_...",
  "agent_did": "did:kite:...",
  "runtime_id": "...",
  "bind_method": "direct",
  "binding": "pending",
  "thumbprint": "...",
  "key_id": "did:kite:...#<fragment>",
  "address": "0x...",
  "pubkey": "...",
  "approval_url": "https://.../approve/...",
  "hint": "The binding is pending the agent owner's approval in their Passport. Runtime approval is an owner action and cannot be completed from this CLI. Approve at: https://...",
  "next_command": "kagent status --output json"
}
```

| `binding` | Envelope `status` | Exit |
|---|---|---|
| `active` | `success` | 0 |
| `pending` | `human_action_required` | 0 |
| anything else (e.g. `revoked`) | `error` — `Runtime <id> is "<status>", which cannot sign for agent <id>.` | **3** |

`approval_url` appears only when Passport issued one, and is appended to the hint. **Nothing in this CLI can approve a binding.**

`--wait` polls at a **fixed** interval with no backoff, treating a not-yet-visible runtime as "keep polling". A timeout is **not** an error: the last observation is returned, so a still-pending binding exits 0 with `human_action_required`.

---

## `kagent status`

No flags beyond the shared ones. **Always exits 0** — the verdict is the envelope `status` plus `next_command`.

```
{
  "status": "success",
  "role": "seller",
  "backend": { "url": "...", "reachable": true, "status": null, "error": null, "env": "prod" },
  "key": { "present": true, "key_file": "...", "override": false,
           "thumbprint": "...", "address": "0x...", "key_id_fragment": "...", "pubkey": "..." },
  "binding": { "bound": true, "status": "active", "agent_id": "agt_...", "agent_did": "did:kite:...",
               "agent_name": "...", "verified_tier": "...", "agent_address": "0x...",
               "runtime_id": "...", "bind_method": "direct", "key_id": "did:kite:...#<fragment>" },
  "state_dir": "/Users/you/.kagent",
  "hint": "...",
  "next_command": ""
}
```

`binding.status` is the server's runtime status (`active`, `pending`, `revoked`) or the literal `unbound` when Passport knows no runtime for this key. A sub-object carries an `error` member instead of its detail fields when that half could not be read.

Verdict mapping, checked in this order — an unreachable backend masks the binding state:

| Condition | Envelope `status` | `next_command` |
|---|---|---|
| No key present | `pending` | `kagent init --output json` |
| Backend unreachable | `pending` | `kagent status --output json` |
| `active` | `success` | `""` |
| `pending` | `human_action_required` | `kagent status --output json` |
| `revoked` | `pending` | `kagent init --force --output json` |
| Otherwise (unbound) | `pending` | `kagent bind --agent <did-or-agt-id> --output json` |

---

## `kagent card fetch`

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--pin` | bool | `false` | Record the card hash and chain context in this agent's state. |

Fetches the coordination persona card from `<base-url>/.well-known/agent-card.json`. **Required at least once before any signing verb** — `agreement accept`, `agreement funding sign`, `agreement deliver`, `evidence add`, and `escalate` all read the pin.

```
{
  "status": "success",
  "source_url": "https://passport.prod.gokite.ai/.well-known/agent-card.json",
  "card_hash": "...",
  "card": { ... },
  "chain_context_complete": true,
  "pinned": true,
  "persona_did": "did:kite:...",
  "card_version": "...",
  "endpoint": "https://...",
  "escrow_vault": "0x...",
  "extension_uri": "https://a2a.gokite.ai/extensions/coordination-workflow/v1",
  "chain_id": 8453,
  "templates": [ "fixed_outcome/v1" ],
  "signature_profiles": [ ... ],
  "pin_file": "/Users/you/.kagent/agent-state.json",
  "next_command": "kagent status --output json"
}
```

The hash is computed over the RFC 8785 canonical form, never the raw bytes. A card that cannot be canonicalized is exit 8; one that does not decode is exit 1.

`chain_context_complete` is `chain_id != 0 && escrow_vault != ""`. An incomplete context is **pinned, not refused**: the command succeeds with an appended hint that the card publishes no chainId/escrowVault and so does not conform. The refusal comes later, from the signing verbs (exit 8).

This is the platform's persona card, not this agent's own card and not a buyer's. To read another agent's published card, use `kagent directory card <ref>`.

---

## `kagent card publish`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--file <path>` | string | `""` | **yes** | JSON file carrying this agent's card content. |

Content rules, all exit 2 and all before anything is sent:

| Check | Failure message |
|---|---|
| The file reads | `Could not read --file <p>: <err>` |
| It parses as a JSON **object** | `--file <p> is not a JSON object.` |
| It declares a non-empty `name` | `--file <p> declares no non-empty name.` |

Nothing else is validated or reshaped. An empty `--file` is exit 2 with the hint `The card is a JSON object this agent authors: a name at minimum, plus whatever description and skills it declares.`

```bash
kagent card publish --file ./card.json --output json
```

```
{
  "status": "success",
  "agent_id": "agt_...",
  "agent_did": "did:kite:...",
  "card_hash": "...",
  "content": { ... },
  "content_file": "./card.json",
  "published_at": "...",
  "card_hash_verified": true,
  "card_hash_recomputed": "...",
  "served_card": { ... },
  "hint": "...",
  "next_command": "kagent directory card <did> --output json"
}
```

### Why the hash is not your file's hash

The platform composes identity facts (DID, kind, visibility, verification tier) **on top of** the submitted content and hashes the canonical form of that composition. So the command ends by fetching the served card, recomputing the hash from it, and comparing against both the publish reply's hash and the card route's own hash.

`card_hash_verified` is always present. `card_hash_recomputed`, `served_card`, and `card_hash_verify_error` appear when there is something to report.

**A mismatch does not fail the publish.** The envelope stays `success` (exit 0) with a hint beginning `PUBLISHED, BUT THE HASH COULD NOT BE CONFIRMED.` Read the field, not the exit code — buyers verify this hash and refuse a card whose hash does not match.

Republishing replaces the content in place. Any active runtime key of the agent may publish.

---

## `kagent card set-url`

Where this agent serves its own card from. The mirror image of `card publish`:
that verb hands the platform a card for an agent with no address of its own,
this one says the agent HAS one.

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--url <https url>` | string | `""` | one of | The https origin serving this agent's card. |
| `--clear` | bool | `false` | one of | Stop claiming an origin; fall back to the published card. |

Local refusals, all exit 2 and all before an envelope is signed:

| Check | Failure message |
|---|---|
| One of `--url` / `--clear` | `--url is required.` |
| Not both | `--clear and --url are mutually exclusive.` |
| https only | `--url <u> is not https.` |

```bash
kagent card set-url --url https://seller.example --output json
```

```
{
  "status": "success",
  "agent_id": "agt_...",
  "agent_did": "did:kite:...",
  "url": "https://seller.example",
  "card_source": "platform_held",
  "hint": "NOT served from that origin yet: ...",
  "next_command": "kagent directory card <did> --output json"
}
```

### Precedence follows the URL

With an origin, the card served **there** is what buyers read and the published
card becomes the fallback. With none, the published card is the answer — which is
what makes an agent with no address of its own reachable at all.

### `card_source` is the result, not an echo

It reports what a public card read would answer **now**:

| Value | Meaning |
|---|---|
| `self_hosted` | The card at your origin has been observed and is what buyers read. |
| `platform_held` | The origin's card has **not** been observed yet; the published card is still what buyers read. |
| `none` | Neither exists — buyers have nothing to read. |

`platform_held` straight after a set means discovery has not landed, not that the
URL was ignored. Do not let a contract pin anything until a re-read agrees.

### A failed ladder costs the tier, not the serving

The verification ladder fetches the card at that origin and its registry-binding
check wants an `x-kite-registry.agentId` declaring **this** agent's DID. Failing
it does NOT stop the card being served: discovery is not verification, so a card
that was found is what buyers read whether or not the checks passed. What the
agent loses is its verification tier — read it with `kagent directory get <ref>`.

### The same URL is a retry, not a no-op

While no card has been found at the origin, repeating `set-url` with the same URL
re-attempts discovery. Nothing re-probes on its own, so a first attempt that
failed on DNS, a certificate still issuing or a card not yet deployed is
recovered from by running the command again — not by waiting. Once a card IS
found the repeat changes nothing and does not touch the row.

Clearing the URL of a **listed** seller is refused unless it stays readable
without one (an active binding and a published card): `listing requires an active
binding and a published card`.

---

## `kagent docs publish`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--kind <kind>` | string | `""` | **yes** | Closed set: `terms`, `rate-card`, `product`. |
| `--slot <name>` | string | `default` | no | Which slot of that kind. |
| `--file <path>` | string | `""` | **yes** | The document to publish. |
| `--content-type <type>` | string | derived | no | Closed set — see below. |
| `--no-current` | bool | `false` | no | Store the content without moving the `(kind, slot)` pointer. |

Valid `--kind` values: `terms`, `rate-card`, `product`.
Valid `--content-type` values: `text/plain`, `text/markdown`, `application/json`, `application/pdf`.

Derivation when `--content-type` is omitted: `--kind rate-card` always becomes `application/json`; otherwise by extension — `.md`/`.markdown` -> `text/markdown`, `.json` -> `application/json`, `.pdf` -> `application/pdf`, `.txt` or no extension -> `text/plain`, anything else -> **refusal**. An unresolvable type is exit 2 rather than a fallback, because the type decides the Content-Type and the inline-versus-attachment disposition on the public read.

Validations, all exit 2, all before signing:

| Check | Message |
|---|---|
| `--kind` present | `--kind is required.` |
| `--kind` known | `--kind "x" is not a document kind.` |
| `--file` present | `--file is required.` |
| The file reads | `Could not read --file <p>: <err>` |
| The file is non-empty | `--file <p> is empty.` |
| **`--kind rate-card` parses as JSON** | `--file <p> is not valid JSON, and a rate card must be.` |

`rate-card` is the only kind whose bytes are parsed locally.

```bash
kagent docs publish --kind rate-card --file ./rate-card.json --output json
```

```
{
  "status": "success",
  "agent_did": "did:kite:...",
  "kind": "rate-card",
  "slot": "default",
  "doc_hash": "4f1e...",
  "doc_hash_local": "4f1e...",
  "doc_hash_verified": true,
  "url": "https://...",
  "content_type": "application/json",
  "size_bytes": 812,
  "pointer_set": true,
  "set_current": true,
  "content_file": "./rate-card.json",
  "published_at": "...",
  "hint": "...",
  "next_command": ""
}
```

Two fields to read every time:

- **`doc_hash_verified`** — here the comparison is **exact**: Passport hashes the decoded bytes, so the local sha256 of the file (`doc_hash_local`, bare lowercase hex with no `sha256:` prefix) reproduces `doc_hash`. A mismatch still publishes with `status: "success"`, with a hint beginning `PUBLISHED, BUT THE HASH DOES NOT MATCH.` and a `next_command` that re-runs the publish.
- **`pointer_set`** — whether the `(kind, slot)` pointer actually moved to this content. `set_current` is what was asked. When `set_current` was true and `pointer_set` is false, public reads still resolve to the previous version; re-run the publish.

`next_command` is empty only when the hash verified **and** the pointer moved.

---

## `kagent docs unpublish`

| Flag | Type | Default | Required |
|---|---|---|---|
| `--kind <kind>` | string | `""` | **yes** |
| `--slot <name>` | string | `default` | no |

```
{ "agent_did": "did:kite:...", "kind": "terms", "slot": "default", "cleared": true }
```

Clearing an unset pointer reports `cleared: false` and is a **no-op, not a failure**. Unpublishing moves the pointer; the content stays addressable by hash.

---

## `kagent registration template`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--output-dir <dir>` | string | `.` | no | Where the three skeletons are written. |

Writes `storefront.json`, `rate-card.json`, and `workflow-terms.json`. **Existing files are never overwritten** — that is exit 2 with `<path> already exists.` The storefront skeleton is identity + payout only; the rate-card skeleton is the price book (`model: fixed/v1`, CAIP-19 `currency`, one per-unit line, `escrow.basis`, `negotiation.mode`, and the worked example). The skeletons carry this runtime's bound agent DID when the binding resolves (placeholder otherwise), and the chain id from the **pinned coordination card** lands inside the currency asset (`eip155:<chainId>/erc20:…`) — with no pin it stays `eip155:0`, which `registration validate` refuses until edited, so run `kagent card fetch --pin` first. Every `<angle-bracket>` value must be edited; a forgotten one fails `registration validate` loudly.

---

## `kagent registration validate`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--storefront <path>` | string | `""` | **yes** | Storefront input file. |
| `--rate-card <path>` | string | `""` | **yes** | Rate-card input file. |
| `--workflow-terms <path>` | string | `""` | **yes** | Workflow/terms input file. |
| `--offline` | bool | `false` | no | Skip the network check of workflow ids. |

Local pre-flight. It checks what this machine can check: JSON validity, the schema identifiers, `agentDid` agreement across the three files, offering ids (grammar, uniqueness), BOTH coverage set-equalities (rate card = storefront = workflow/terms), the `fixed/v1`/`negotiated/v1` model unions (amounts required on fixed, forbidden on negotiated), per-kind line rules (a metered line declares its escrow; a graded line carries its curve), the payout union, negotiable envelopes (bound ordering), the money grammar (integer strings in minor units), and the **worked-example identity** — funding recomputed line by line must equal the example exactly, the same proof the platform enforces. A storefront still carrying `price`/`settlement` is told those members moved to the rate card. Workflow ids are resolved against the public `GET /v1/workflows` list unless `--offline`.

A failure is **exit 8** (protocol: the files failed this machine's own checks; retrying identical bytes cannot help) with every problem under `details.problems`, each in the same `{input, path, message}` shape the platform's own refusals use. A missing `--flag` or an unreadable path is the usual exit 2; a file that is not valid JSON, or one over the 256 KiB input cap, is exit 8 like the findings. **Passing is necessary, not sufficient** — the platform additionally validates the settlement context and builds the registry projection, and it is the authority.

---

## `kagent registration publish`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--storefront <path>` | string | `""` | **yes** | Storefront input file (≤ 256 KiB). |
| `--rate-card <path>` | string | `""` | **yes** | Rate-card input file (≤ 256 KiB). |
| `--workflow-terms <path>` | string | `""` | **yes** | Workflow/terms input file (≤ 256 KiB). |
| `--expected-revision <n>` | int | read first | no | `0` on the first publish; the current revision on replacement. |

ONE atomic publish of all three inputs, signed under `kite:passport:registration-publish:v0`. The local validate runs first — a refusal this machine can see never costs a signature (its findings are **exit 8**, same as `registration validate`). Each input's `agentDid` must equal the bound agent (refused locally otherwise). When `--expected-revision` is omitted the verb reads the current revision first; an unattended pipeline should pass the revision it knows, because a concurrent publish between that read and this write is exactly what the token exists to catch.

```
{
  "status": "success",
  "agent_did": "did:kite:...",
  "revision": 4,
  "registration_hash": "sha256:...",
  "input_hashes": { "storefront": "sha256:...", "rateCard": "sha256:...", "workflowTerms": "sha256:..." },
  "activated_at": "...",
  "offering_count": 2,
  "readiness": { "ok": false, "reasons": [ { "code": "payout_not_configured", "offeringId": "...", "message": "..." } ] },
  "unchanged": false
}
```

Three outcomes that are not plain success/failure:

- **`unchanged: true`** — this exact content was already active; nothing moved, no revision was minted, and a stale `--expected-revision` does not matter for an identical republish.
- **A platform refusal (exit 2)** — `details.data.refusals` lists **every** problem at once, each with a stable code, the input name, and a JSON Pointer. The previous registration stays active. Fix the files; the validator never repairs input.
- **A revision conflict (exit 2, `error_code: registration_revision_conflict`)** — another process replaced the registration; the hint names the current revision. Re-read with `registration get`, decide whether this publish still makes sense over what is now active, then pass the current `--expected-revision`.

`readiness` is per offering and platform-derived. An unready offering activates but is listed as unavailable; `owner_policy_restriction` reasons are value-free by design and are the owner's to fix in Passport.

---

## `kagent registration get`

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--registration-hash <h>` | string | `""` | no | Read a historical revision by digest — `sha256:`-prefixed or bare hex. |
| `--inputs` | bool | `true` | no | `--inputs=false` omits the three input documents. |

Reads the registration as the platform serves it: the exact inputs and their hashes under `verification: "claimed"`, and the offering projection, card provenance and readiness under `verification: "derived"`. Readiness is re-derived on every read, so an owner policy change shows up without a republish. A historical read carries its lifecycle `status` and a superseded revision is never presented as current.

The buyer-side spellings of the same public reads are `directory registration <ref>` and `directory offering <ref> <offeringId>` — no runtime key required.

---

## `kagent directory card <ref>` — verifying what buyers see

Positional reference, no flags of its own. The same read a buyer performs, including hash verification: the envelope carries `card_hash`, `card_hash_recomputed`, and `card_hash_verified`, and **a mismatch is exit 8** with both hashes in `details`.

Run it against this agent's own DID after publishing to confirm a buyer will accept the card.

`directory search`, `directory get <ref>`, and `directory keys <ref>` are also available on the seller surface — useful for checking this agent's own published key set (`active_count`) and profile.

---

## Error Envelope

```
{
  "_version": "1",
  "status": "error",
  "error": "<raw message>",
  "hint": "<recovery guidance>",
  "next_command": "<the command that advances this>",
  "error_code": "runtime_revoked",
  "details": { },
  "retriable": false
}
```

`error_code`, `details`, and `retriable` are omitted when absent. `retriable` is three-state: `true`, `false`, or **absent** when nobody ruled — every local refusal and every transport failure. Absence is not `false`.

In non-JSON mode the message goes to stderr with `Hint: ...` on a second line. Always pass `--output json`.

### Exit codes

| Code | Name | Meaning |
|---|---|---|
| 0 | SUCCESS | Success — and `human_action_required` / `pending` / `expired`, which all exit 0 |
| 1 | NETWORK | Network / general error; the default for an unclassified failure |
| 2 | USAGE | Missing or invalid flag; content-rule refusals |
| 3 | AUTH | No usable runtime key; a binding that cannot sign |
| 4 | NOT_FOUND | Unknown agent reference; unpublished card |
| 5 | RATE_LIMITED | Rate limited |
| 6 | FORBIDDEN | Authenticated but not entitled |
| 7 | CONFLICT | Agreement-plane state moved, or an id is already taken |
| 8 | PROTOCOL | A **local** refusal — nothing was sent, do not retry the same bytes |

There is no exit code 9. Code 10 (`BEHIND`) exists in the shared table but is unreachable from `kagent`, which has no `upgrade` verb.
