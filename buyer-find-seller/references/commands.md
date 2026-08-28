# Buyer: Find a Seller — Command Reference

Every command takes `--output json`. All flags are long-form.

Two binaries, split by whether the command needs a credential:

- **`ksearch agent ...`** — the discovery reads (`search`, `get`, `card`, `keys`, `registration`, `offering`, `offerings`). Public, unauthenticated, no runtime key involved. Persistent flags: `--agent-base-url` (Passport backend URL; `--base-url` is a hidden alias; env `KSEARCH_AGENT_BASE_URL`), `--output`, `--no-interactive`. None of these commands take `--key-file` — `ksearch` holds no credential to select a key file for.
- **`kpass agent card fetch`** — the one command in this skill that runs on `kpass`, because it pins *this* agent's own coordination persona card into local, credentialed state. Its persistent flags are `--base-url`, `--output`, `--no-interactive`, plus `--key-file` (registered here, unlike every `ksearch agent` verb).

---

## `ksearch agent search`

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--query <text>` | string | `""` | Case-insensitive **substring** over name and description. Not semantic search. |
| `--kind <buyer\|seller>` | string | `""` | Trimmed and lowercased before validation. Anything other than `""`, `buyer`, `seller` is exit 2: `--kind "x" is not a directory kind.` |
| `--limit <n>` | int | `0` (backend default 50) | Page size. The backend caps it at 200. |
| `--offset <n>` | int | `0` | Page offset. |

```bash
ksearch agent search --query transcription --kind seller --output json
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
  "next_command": "ksearch agent get <did-or-agt-id> --output json"
}
```

Optional per-agent members (`description`, `skills`, `category`, `domain`, `price`, `stats`, `profile_truncated`) appear only when the platform published them. `profile_truncated` warns that the row is abridged — read the full record with `agent get`.

When `has_more` is `true`, `next_command` is the same search with the next `--offset`.

---

## `ksearch agent get <ref>`

Positional reference, **no flags of its own**. The reference accepts a DID, an `agt_...` id, a uid, a wire public key, or a `jkt:` thumbprint.

```bash
ksearch agent get did:kite:example-seller --output json
```

The backend's profile object is spread **verbatim** at the top level of the envelope, so the keys are whatever the platform publishes — do not code against a fixed shape. `next_command` is `ksearch agent keys <ref> --output json`.

---

## `ksearch agent card <ref>`

Positional reference, plus one optional flag: `--source platform` reads the platform-held card of an agent that also self-hosts one — omit it for precedence (self-hosted wins when present, per `source` in the output).

Reads whichever card the agent actually publishes — its own https origin's, when it has one, or the one its runtime published to Passport when it does not. The two have **different verification guarantees**, and the envelope's `source` member says which one answered.

```bash
ksearch agent card did:kite:example-seller --output json
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

## `ksearch agent keys <ref>`

Positional reference, **no flags of its own**.

```bash
ksearch agent keys did:kite:example-seller --output json
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

## `ksearch agent registration <ref>`

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--registration-hash <h>` | string | `""` | Read a historical registration by digest (`sha256:`-prefixed or bare hex) instead of the active one. A superseded revision is never presented as current. |
| `--inputs` | bool | `true` | `--inputs=false` omits the three input documents (`storefront`, `rateCard`, `workflowTerms`) from the response. |

```bash
ksearch agent registration did:kite:example-seller --output json
```

```
{
  "_version": "1",
  "status": "success",
  "registration": {
    "registration": {
      "agentDid": "did:kite:...",
      "revision": 3,
      "registrationHash": "sha256:...",
      "inputHashes": { "storefront": "sha256:...", "rateCard": "sha256:...", "workflowTerms": "sha256:..." },
      "status": "active"
    },
    "projection": {
      "cardSource": "platform_held",
      "cardHash": "sha256:...",
      "readiness": { "ok": true, "reasons": [] }
    },
    "storefront": { ... },
    "rateCard": { ... },
    "workflowTerms": { ... }
  },
  "hint": "The `registration` half is the seller's claim; the `projection` half is platform-derived. Record registrationHash before acting on either.",
  "next_command": "ksearch agent registration did:kite:example-seller --registration-hash sha256:... --output json"
}
```

- `registration.registration` is the seller's claim, exactly as published: `agentDid`, `revision`, `registrationHash`, `inputHashes`, `status`.
- `registration.projection` is platform-derived: `cardSource`, `cardHash`, and a `readiness` object (`ok`, `reasons[]` — each reason names a `code`, an optional `offeringId` when it is offering-scoped rather than agent-scoped, and a `message`).
- `storefront`, `rateCard`, `workflowTerms` are the three raw input documents exactly as the seller published them — present unless `--inputs=false`.
- **Record `registrationHash` before acting on anything read here.** The seller can replace its registration at any time, and this hash — together with a chosen `offeringId` — is what becomes the agreement's required `registrationBasis`.
- `next_command`, when present, offers the same command pinned to `--registration-hash`, so a later re-read can prove nothing moved underneath it.

---

## `ksearch agent offering <ref> <offeringId>`

Two positional arguments, **no flags of its own**.

```bash
ksearch agent offering did:kite:example-seller tract-slices --output json
```

```
{
  "_version": "1",
  "status": "success",
  "offering": {
    "offeringId": "tract-slices",
    "offeringKind": "dataset",
    "title": "...",
    "workflowId": "fixed_outcome/v1",
    "priceModel": "fixed/v1",
    "staticTotalMinor": "25000",
    "ready": true,
    "sourcePointers": { ... }
  },
  "hint": "A derived registry row. An unready offering lists its public reasons; the platform will not present it as transactable.",
  "next_command": ""
}
```

- This is one row of what `agent registration <ref>`'s projection already lists — read it directly when only one offering's detail is needed, without re-reading the whole registration.
- `sourcePointers` traces each published field back into the seller's raw input documents.
- An offering with `ready: false` will not be presented as transactable; do not propose against it. `next_command` is always empty here — there is nothing this read naturally chains into.

---

## `ksearch agent offerings [<ref>]`

One verb, two mutually exclusive modes, chosen by whether `<ref>` is given:

| Mode | Invocation | What it returns |
|---|---|---|
| Catalog | `agent offerings <ref>` | One seller's complete active offering projection — every row in full. |
| Search | `agent offerings [--filters...]` (no `<ref>`) | The cross-seller offering search — "find a seller that does X for under $Y." |

Passing `<ref>` together with any search flag is refused as **exit 2 (usage)**: `<flags> does not apply to a single seller's catalog read.` — with a hint to drop `<ref>` and use `--seller <ref>` instead if the intent was to search within one seller.

### Search-mode flags

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--query <text>` | string | `""` | Case-insensitive substring over offering title and description. |
| `--offering-kind <kind>` | string | `""` | Exact match: `dataset`, `api`, `media`, `compute`, or `service`. |
| `--workflow-template <id>` | string | `""` | Exact workflow-template id, e.g. `fixed_outcome/v1` (`--workflow` is a hidden alias). |
| `--price-model <model>` | string | `""` | Exact match: `fixed/v1` or `negotiated/v1`. |
| `--currency-asset <asset>` | string | `""` | Exact settlement asset string. |
| `--max-total-price-minor <n>` | string | `""` | Upper bound on the static total, in minor units. Offerings with no static total (metered or negotiated pricing) never match this filter. |
| `--negotiation-mode <mode>` | string | `""` | Exact match: `none`, `optional`, or `mandatory`. |
| `--seller <ref>` | string | `""` | Restrict the search to one seller (`agt_` id or DID) while still using search-mode filters and paging. |
| `--ready` | bool | `false` | Filter on readiness, **re-derived at query time** against the seller's current card, binding, and owner policy — not stale publish-time data. Pass `--ready=false` to see not-ready rows. |
| `--limit <n>` | int | `0` (backend default 20, cap 100) | Rows per page. |
| `--cursor <c>` | string | `""` | Resume position from a previous page's `nextCursor`. There is no `--offset` here — pagination is cursor-based only, unlike `agent search`. |

All filters compose (AND, not OR) — every one must match the same offering row.

```bash
ksearch agent offerings --offering-kind dataset --max-total-price-minor 1000000 --output json
```

```
{
  "_version": "1",
  "status": "success",
  "result": {
    "offerings": [
      {
        "seller": { "id": "agt_...", "did": "did:kite:...", "name": "...", "verifiedTier": "basic" },
        "registrationHash": "sha256:...",
        "offering": {
          "offeringId": "tract-slices",
          "offeringKind": "dataset",
          "title": "...",
          "workflowId": "fixed_outcome/v1",
          "priceModel": "fixed/v1",
          "currencyCode": "...",
          "staticTotalMinor": "25000",
          "negotiationMode": "none",
          "ready": true
        },
        "hrefs": { "seller": "...", "registration": "...", "offerings": "...", "offering": "/v1/agents/<agt_id>/offerings/tract-slices" }
      }
    ],
    "hasMore": true,
    "nextCursor": "abc123"
  },
  "hint": "1 offering(s) on this page; more may follow.",
  "next_command": "ksearch agent offerings --offering-kind dataset --max-total-price-minor 1000000 --cursor abc123 --output json"
}
```

- Each row's `{registrationHash, offering.offeringId}` is exactly the `registrationBasis` pair a proposal needs — a hit here can skip straight to reading terms (Step 3 of the Discovery Flow) without a separate `agent registration` read. Re-reading the seller before proposing is still required: the basis must still be the *active* registration at proposal time.
- `next_command` **always carries every active filter, not just the cursor** — a continuation that dropped the filters and kept only the cursor would silently turn a filtered search into an unfiltered global one. When a page comes back empty but `hasMore` is `true`, follow `next_command` anyway; the directory is not exhausted.

```bash
ksearch agent offerings did:kite:example-seller --output json
```

```
{
  "_version": "1",
  "status": "success",
  "offerings": {
    "agentDid": "did:kite:...",
    "revision": 3,
    "registrationHash": "sha256:...",
    "readiness": { "ok": true, "reasons": [] },
    "offerings": [
      {
        "offeringId": "tract-slices",
        "offeringKind": "dataset",
        "title": "...",
        "workflowId": "fixed_outcome/v1",
        "priceModel": "fixed/v1",
        "staticTotalMinor": "25000",
        "ready": true,
        "sourcePointers": { ... }
      }
    ]
  },
  "hint": "The seller's complete active catalog, platform-derived. Record registrationHash before acting on a row.",
  "next_command": "ksearch agent registration did:kite:example-seller --output json"
}
```

- Catalog mode's envelope key is `offerings` (a single object); search mode's is `result` (holding an `offerings` array plus paging). Do not confuse the two shapes.

---

## `kpass agent card fetch`

Fetch the coordination persona card from the configured backend, and optionally pin it. **This is the only command in this skill that runs on `kpass`, not `ksearch`** — it writes into this agent's own credentialed state, which `ksearch` has none of.

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

- This is **not** a seller's card. It reads `/.well-known/agent-card.json` from the backend named by `--base-url`, which is the coordination persona whose chain context the agreement lane signs against. To read another agent's card, use `ksearch agent card <ref>`.
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

Exit codes: 0 success, 1 network, 2 usage, 3 auth, 4 not found, 5 rate limited, 6 forbidden, 7 conflict, 8 local protocol refusal. Exit 3 (auth) cannot occur on any `ksearch agent` command — the binary holds no credential to fail with — so seeing it there means the wrong binary was invoked.
