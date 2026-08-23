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
