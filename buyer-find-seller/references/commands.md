# Buyer: Find a Seller — Command Reference

Every command takes `--output json`. All flags are long-form.

`--base-url`, `--output`, and `--no-interactive` are persistent root flags available everywhere. `--key-file` is registered on `card fetch` but **not** on any `directory` verb — directory reads are unauthenticated.

---

## `kpass agent directory search`

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--query <text>` | string | `""` | Case-insensitive **substring** over name and description. Not semantic search. |
| `--kind <buyer\|seller>` | string | `""` | Trimmed and lowercased before validation. Anything other than `""`, `buyer`, `seller` is exit 2: `--kind "x" is not a directory kind.` |
| `--limit <n>` | int | `0` (backend default 50) | Page size. The backend caps it at 200. |
| `--offset <n>` | int | `0` | Page offset. |

```bash
kpass agent directory search --query transcription --kind seller --output json
```

```
{
  "_version": "1",
  "status": "success",
  "agents": [
    {
      "id": "agt_...",
      "did": "did:kite:...",
      "uid": "...",
      "name": "...",
      "kind": "seller",
      "verified_tier": "...",
      "description": "...",
      "skills": [ ... ],
      "category": "...",
      "domain": "...",
      "price": "...",
      "stats": { ... },
      "profile_truncated": false
    }
  ],
  "count": 1,
  "has_more": false,
  "hint": "...",
  "next_command": "kpass agent directory get <did-or-agt-id> --output json"
}
```

Optional per-agent members (`description`, `skills`, `category`, `domain`, `price`, `stats`, `profile_truncated`) appear only when the platform published them. `profile_truncated` warns that the row is abridged — read the full record with `directory get`.

When `has_more` is `true`, `next_command` is the same search with the next `--offset`.

---

## `kpass agent directory get <ref>`

Positional reference, **no flags of its own**. The reference accepts a DID, an `agt_...` id, a uid, a wire public key, or a `jkt:` thumbprint.

```bash
kpass agent directory get did:kite:example-seller --output json
```

The backend's profile object is spread **verbatim** at the top level of the envelope, so the keys are whatever the platform publishes — do not code against a fixed shape. `next_command` is `kpass agent directory keys <ref> --output json`.

---

## `kpass agent directory card <ref>`

Positional reference, plus one optional flag: `--source platform` reads the platform-held card of an agent that also self-hosts one — omit it for precedence (self-hosted wins when present, per `source` in the output).

Reads whichever card the agent actually publishes — its own https origin's, when it has one, or the one its runtime published to Passport when it does not. The two have **different verification guarantees**, and the envelope's `source` member says which one answered.

```bash
kpass agent directory card did:kite:example-seller --output json
```

```
{
  "_version": "1",
  "status": "success",
  "agent": "did:kite:...",
  "source": "platform_held",
  "card": { ... },
  "card_hash": "...",
  "card_hash_recomputed": "...",
  "card_hash_verified": true,
  "published_at": "2026-01-01T00:00:00Z",
  "hint": "...",
  "next_command": "..."
}
```

- `card` is the served card **verbatim**.
- `source: "platform_held"` — the hash covers the served composition (identity facts the platform composed plus the seller's own content). This command recomputes it locally and reports whether it agrees: `card_hash` is what the platform reports, `card_hash_recomputed` is what the CLI derived, `card_hash_verified` says whether they match. **A mismatch is an error, not a warning.** When `card_hash` is non-empty and does not match the recomputation, the command exits **8 (PROTOCOL)** with `details` carrying `card_hash_reported` and `card_hash_recomputed`. Nothing was sent; nothing about retrying will change it. Treat the seller as unverifiable and report it.
- `source: "self_hosted"` — the hash covers the RAW bytes at the seller's own `card_url`, which this command does **not** re-fetch; it serves the last recorded observation, not a live proxy-fetch. `card_hash_verified` here reflects only what was true when that observation was made — nothing here is verified against the origin at read time. If the deal needs that guarantee, fetch `card_url` directly and hash the response yourself before trusting it.
- `published_at` appears only when the platform published it.

---

## `kpass agent directory keys <ref>`

Positional reference, **no flags of its own**.

```bash
kpass agent directory keys did:kite:example-seller --output json
```

```
{
  "_version": "1",
  "status": "success",
  "agent": "did:kite:...",
  "keys": [
    {
      "key_id": "did:kite:...#<fragment>",
      "status": "active",
      "active": true,
      "pub_key": "...",
      "thumbprint": "...",
      "address": "0x...",
      "valid_from": "2026-01-01T00:00:00Z",
      "valid_to": null
    }
  ],
  "count": 1,
  "active_count": 1,
  "hint": "...",
  "next_command": "..."
}
```

`valid_to` is **always present** and is `null` when the key has no end date. The other optional members appear when published.

Why this matters for proposing: the seller key's **address** is what goes into the EIP-712 Agreement digest, so `propose` must know which key. With `active_count: 1` it picks that key; with more than one it refuses as ambiguous unless `--seller-key-id` names one; with `active_count: 0` it refuses outright.

---

## `kpass agent card fetch`

Fetch the coordination persona card from the configured backend, and optionally pin it.

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--pin` | bool | `false` | Record the card hash and chain context in this agent's state. Required at least once before `agreement propose`. |
| `--key-file <path>` | string | resolved state path | Shared state flag. |

```bash
kpass agent card fetch --pin --output json
```

```
{
  "_version": "1",
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
  "pin_file": "/path/to/.kite-passport/agent-state.json",
  "hint": "...",
  "next_command": "kpass agent status --output json"
}
```

- This is **not** a seller's card. It reads `/.well-known/agent-card.json` from the backend named by `--base-url`, which is the coordination persona whose chain context the agreement lane signs against. To read another agent's card, use `directory card <ref>`.
- `card_hash` is computed over the RFC 8785 canonical form. A card that cannot be canonicalized is exit 8; a card that does not decode is exit 1.
- `pinned` is `false` without `--pin`, `true` with it. `pin_file` appears with `--pin`.
- The optional members (`persona_did`, `card_version`, `endpoint`, `escrow_vault`, `extension_uri`, `chain_id`, `templates`, `signature_profiles`) appear only when the card publishes them.
- `chain_context_complete` is `chain_id != 0 && escrow_vault != ""`. An incomplete context is **pinned, not refused** — the command succeeds with an appended hint saying the card does not conform. The refusal comes later, from `agreement propose` (exit 8).

### What `propose` reads out of the pin

`agreement propose` requires the pin to carry all four of: `endpoint`, `extension_uri`, a non-zero `chain_id`, and an `escrow_vault`. They become the contract's `runtimeBinding` (`runtimeAgentId`, `agentCardHash`, `extensionUri`, `endpoint`) and the escrow signing domain. A missing pin is exit 2 with `next_command: "kpass agent card fetch --pin --output json"`; a pin with no chain context is exit 8.

---

## Error Envelope

```
{
  "_version": "1",
  "status": "error",
  "error": "<raw message>",
  "hint": "<recovery guidance>",
  "next_command": "<command that advances this>",
  "error_code": "unknown_key",
  "details": { "card_hash_reported": "...", "card_hash_recomputed": "..." },
  "retriable": false
}
```

`error_code`, `details`, and `retriable` are omitted when absent. `retriable` absent means nobody ruled — not `false`.

Exit codes: 0 success, 1 network, 2 usage, 3 auth, 4 not found, 5 rate limited, 6 forbidden, 7 conflict, 8 local protocol refusal.
