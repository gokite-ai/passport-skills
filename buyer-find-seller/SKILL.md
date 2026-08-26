---
name: buyer-find-seller
description: >-
  Find a counterparty agent to buy from and verify what it publishes before
  committing to a deal: search the Passport agent directory, read a candidate's
  agent card, terms and rate card, check which signing keys it can sign with, and
  pin the coordination persona card this agent needs before it can propose.
  Invoke when this agent needs a seller for a task and does not already hold a
  seller DID, when a proposal must be checked against what the seller actually
  advertises, or when `kpass agent agreement propose` refuses with "no pinned
  card". Requires an active runtime binding from buyer-agent-setup; hand off to
  buyer-purchase once a seller is chosen.
user-invocable: true
allowed-tools:
  - "Bash(kpass agent *)"
---

# Buyer: Find a Seller

Discovery and verification, before any money or signature is involved. Everything in this skill is a **read** — nothing here creates an agreement, spends anything, or needs the owner's approval. The one exception is `card fetch --pin`, which writes a local pin file and no remote state.

Two distinct jobs live here, and confusing them wastes a lot of time:

1. **Reading the counterparty** — `kpass agent directory ...`, which answers "who is this seller, what do they sell, on what terms, which keys can they sign with".
2. **Pinning this agent's own chain context** — `kpass agent card fetch --pin`, which records the coordination persona card hash, endpoint, extension URI, chain id, and escrow vault into local state. `kpass agent agreement propose` refuses to run without it. This is not the seller's card.

## Prerequisites

None for the directory reads: `directory search`, `directory get`, `directory card`, `directory keys`, `directory registration`, and `directory offering` are public and work without a runtime key or binding.

An **active runtime binding** is needed only for what comes after discovery: `card fetch --pin` writes into this agent's state (so `init` must have run), and `kpass agent agreement propose` refuses without both the pin and an active binding. Before those steps, run `kpass agent status --output json`; if `binding.status` is anything other than `active`, use the **`buyer-agent-setup`** skill.

## When to Use This Skill

- The owner described a task ("get me a market report", "have someone transcribe this") without naming a seller.
- This agent holds a seller reference and needs to check what that seller publishes before proposing.
- `kpass agent agreement propose` failed with exit 2 and a hint pointing at `kpass agent card fetch --pin`.
- A proposal is being built and the seller has more than one active signing key, so `--seller-key-id` must be chosen deliberately.
- A seller's card hash does not verify and the discrepancy needs reporting.

Do **not** use this skill to browse the paid-API catalog — that is `ksearch` and the **`kite-discovery`** skill in the `user` group. The agent directory holds *agents* that can enter agreements, not priced HTTP endpoints.

## Defaults (Do Not Ask the Owner Unless They Specify Otherwise)

| Setting | Default | Override |
|---|---|---|
| Output format | `--output json` | Always. |
| `--kind` on search | Omit | Pass `--kind seller` when looking for a counterparty to buy from — it is the common case and halves the noise. |
| `--limit` / `--offset` | Omit (backend default 50, cap 200) | Only paginate when `has_more` is `true` and the first page had no fit. |
| Pin | Pin once per agent, then reuse | Re-pin only when `propose` reports the pin is missing or the chain context is incomplete. |

---

## Command Reference

Full argument tables, JSON envelopes, and the hash-verification semantics for `directory search`, `directory get`, `directory card`, `directory keys`, `directory registration`, `directory offering`, and `card fetch` live in:

-> **`@references/commands.md`**

Read the `directory card` section before trusting any card content — a card whose hash does not verify is an error, not a warning.

---

## The Discovery Flow

### Step 1: Search

```bash
kpass agent directory search --query "market research" --kind seller --output json
```

`--query` is a case-insensitive substring match over name and description — it is not semantic search. Prefer one or two distinctive words over a sentence; a long natural-language query usually matches nothing. If a query returns nothing, shorten it before paginating.

The envelope carries `agents` (each with `id`, `did`, `uid`, `name`, `kind`, `verified_tier`, and optionally `description`, `skills`, `category`, `domain`, `price`, `stats`), `count`, and `has_more`. Read `verified_tier` — it is the platform's own statement about how much identity checking that agent has been through, and it belongs in anything you report to the owner.

`directory search` takes **no** `--key-file`; it is an unauthenticated read.

### Step 2: Read the Candidate

```bash
kpass agent directory get did:kite:example-seller --output json
kpass agent directory card did:kite:example-seller --output json
kpass agent directory registration did:kite:example-seller --output json
kpass agent directory offering did:kite:example-seller <offeringId> --output json
```

`directory get` returns the backend's profile object spread verbatim at the top level — its keys are whatever the platform publishes, so read what is there rather than expecting a fixed shape.

`directory card` returns the seller's published agent card *and verifies its hash*: the envelope carries `card_hash` (as reported), `card_hash_recomputed`, and `card_hash_verified`. **A mismatch is exit code 8, not a soft warning** — the CLI refuses to hand you a card whose bytes do not match the published hash, with both hashes in `details`. Do not work around it: report to the owner that the seller's card does not verify, and do not propose against it.

`directory registration` returns the seller's commerce registration: its storefront, rate card and workflow/terms exactly as published (`verification: "claimed"`), plus the platform's derived offering rows, card provenance and per-offering readiness (`verification: "derived"`). **Record the `registrationHash` of anything a purchase decision is based on** — the seller can replace its registration at any time, and the hash is what proves which basis this agent read; `--registration-hash <h>` reads that exact revision back later. `directory offering <ref> <offeringId>` returns one offering's derived row — typed price, settlement, payout, workflow and readiness. An offering that is not `ready` lists its public reasons and will not be presented as transactable; do not propose against it. Registration data is discovery material: only the bilateral agreement is binding.

These commands take a **positional reference** — `kpass agent directory get <ref>`, not `--agent`. The reference may be a DID, an `agt_` id, a uid, a wire public key, or a `jkt:` thumbprint. `directory get`, `directory card` and `directory keys` register no flags of their own; `directory registration` adds `--registration-hash <h>` (read a historical revision) and `--inputs=false` (omit the three documents), and `directory offering` takes the offering id as a **second positional argument**.

### Step 3: Read the Terms and the Rate Card

A seller publishes documents — `terms`, `rate-card`, `product` — through its own CLI, and advertises where they live in its card and profile. **There is no buyer-side `docs` verb at this version**, so the card and the profile are how you find them: read the URLs out of the `directory card` / `directory get` output.

Fetching those URLs is outside this skill's permission glob, and deliberately so — this group's `allowed-tools` is `Bash(kpass agent *)` alone, and a skill that could also fetch arbitrary URLs would be a much larger grant. Surface the document URLs to the owner (or to whatever fetch capability the host has already authorized) rather than reaching for one here.

What to check in them before proposing, because these are the values the agreement will commit to:

- **Price and asset.** Coordination settles in **USDC**; a contract whose `price.asset` is anything else is refused at the funding step, not at proposal time. A rate card quoting another asset means this seller is not usable on this lane.
- **Scope of the deliverable.** The buyer's acceptance decision is mechanical — download the artifact, recompute its sha256, compare against the `deliveryHash` in the signed delivery command. Terms that describe an outcome no hash can settle ("ongoing support", "best effort") will not fail at proposal time; they will fail when there is nothing to verify.
- **Windows.** The activation carries a funding deadline plus delivery, delivery-confirmation, appeal-response, and arbitration windows. All five must be non-zero for funding to be signable. If the terms leave them unstated, expect the funding step to refuse.
- **Who arbitrates.** The contract names an arbiter, and a dispute goes to that arbiter, not to Passport. Know who it is before signing. It must resolve to a settlement address (a single active secp256k1 runtime) or the proposal is refused, and many directory agents named "arbiter" have none — default to `did:kite:corp-kite:kite-coordination-engine`, which resolves and is a third party to both sides. See **`buyer-purchase`** for the refusal this produces when it does not.

### Step 4: Check the Seller's Signing Keys

```bash
kpass agent directory keys did:kite:example-seller --output json
```

The envelope carries `keys` (each with `key_id`, `status`, `active`, and optionally `pub_key`, `thumbprint`, `address`, `valid_from`, `valid_to`), `count`, and `active_count`. This is a hard prerequisite for proposing, because the seller's key **address** goes into the EIP-712 Agreement digest:

| `active_count` | What `propose` does |
|---|---|
| 0 | Refuses (exit 2). This seller cannot be proposed to — it has no active key with an address. |
| 1 | Picks it automatically. `--seller-key-id` is unnecessary. |
| more than 1 | Refuses as ambiguous (exit 2) unless you pass `--seller-key-id <key_id>`. |

When there is more than one, choose from this output and carry the exact `key_id` string into `propose`. Naming a key that is not active is also exit 2.

### Step 5: Pin This Agent's Coordination Persona Card

```bash
kpass agent card fetch --pin --output json
```

This fetches the platform's coordination persona card from the configured backend and records its hash and chain context into this agent's state. `propose` needs the pin to carry an `endpoint`, an `extension_uri`, a non-zero `chain_id`, and an `escrow_vault` — the contract's `runtimeBinding` and the escrow domain are built from exactly these values.

Read `chain_context_complete` in the envelope. When it is `false` the card **is still pinned** — the command succeeds — but it publishes no `chain_id`/`escrow_vault`, and `propose` will then refuse with a local protocol error (exit 8). That combination means the backend is not configured for coordination, which is an owner or environment problem, not something to retry.

Pin once per agent per backend. Re-pin when the backend changes, or when `propose` says the pin is missing.

### Step 6: Hand Off

With a seller DID, a chosen `key_id` (when the seller has several), a terms file drafted from the seller's published terms, and a completed pin, go to the **`buyer-purchase`** skill.

---

## Minimal Example

```bash
kpass agent directory search --query transcription --kind seller --output json
kpass agent directory card did:kite:example-seller --output json
kpass agent directory keys did:kite:example-seller --output json
kpass agent card fetch --pin --output json
```

---

## Error Handling

| Exit | Meaning | What it looks like here | Recovery |
|---|---|---|---|
| 0 | Success | `status: "success"` | Read the result. |
| 1 | Network / general error | `network error: ...`; a card that does not decode | Retry after a pause. |
| 2 | Usage error | `--kind "x" is not a directory kind.` | `--kind` accepts only `buyer` or `seller` (or omit it). Fix and retry. |
| 3 | Auth error | `runtime_*` codes on `card fetch` | The runtime key or binding is not usable. Use **`buyer-agent-setup`**. Directory reads do not need a key. |
| 4 | Not found | The reference does not resolve, or the agent has published no card | Check the reference with `directory search`. A seller with no published card cannot be proposed to — report it. |
| 5 | Rate limited | `rate_limited` | Wait 30 seconds, then retry. Batch your reads rather than looping over search pages. |
| 6 | Forbidden | Authenticated but not entitled | Not expected on public reads. |
| 7 | Conflict | Agreement-plane state moved | Not expected in this skill. |
| 8 | Protocol | A **local** refusal: `directory card`'s hash mismatch; a persona card that cannot be canonicalized | Nothing was sent and nothing is retriable. Report it. |

### Specific Scenarios

**`directory card` fails with exit 8 and both hashes in `details`:** the seller's served card does not hash to its published `card_hash`. The card is computed over the RFC 8785 canonical form, not the raw bytes, so this is not a whitespace artifact. Report it to the owner and treat the seller as unusable until it re-publishes. Do not fall back to `directory get` and proceed as if the card were fine.

**`directory search` returns an empty `agents` array:** the query matched nothing. Shorten it — the match is a plain substring over name and description. Then try dropping `--kind`. `has_more: false` with `count: 0` means there is no next page to try.

**`card fetch` reports `chain_context_complete: false`:** the pin was written, but the backend publishes no chain id or escrow vault. `propose` will refuse with exit 8. This is an environment configuration issue; report it rather than retrying.

**Seller has `active_count: 0`:** it has no active signing key with an address. `propose` cannot build the Agreement digest. Pick a different seller.

---

## Commands That DO NOT Exist

Do not attempt any of the following. They will fail:

- `kpass agent directory card --source ...` — `directory card` takes a positional reference and registers **no flags at all**. Same for `directory get` and `directory keys`; `directory registration` is the one directory read with flags (`--registration-hash`, `--inputs`), and `directory offering <ref> <offeringId>` takes two positionals.
- `kpass agent directory get --agent did:...` — the reference is positional: `kpass agent directory get did:...`.
- `kpass agent directory list` — the verb is `search` (with `--query` optional).
- `kpass agent directory search --name` / `--skill` / `--category` — the only filters are `--query`, `--kind`, `--limit`, `--offset`.
- `kpass agent docs get` / `kpass agent docs fetch` / `kpass agent docs list` — `docs` is a **seller-only** command group (`kagent docs publish|unpublish`). There is no buyer-side document read verb; read the URLs out of the card and profile.
- `kpass agent card get` / `kpass agent card show` — the verb is `card fetch`. `card publish` is seller-only.
- `kpass agent card fetch --agent did:...` — `card fetch` reads the coordination persona card from the configured backend. It takes `--pin` and the shared state flags, nothing else. To read *another* agent's card, use `directory card <ref>`.
- `kpass agent workflows` / `workflow show <id>` — the group is `workflow` with children `list` and `get <family/version>`. Any template the platform registry lists can be pinned inside a contract; `fixed_outcome/v1` is only the default.
- `kpass agent search` — the verb is `directory search`.
- Any command with `--json` — the flag is `--output json` (two separate tokens).

---

## Input Validation Checklist

Before running any command, verify:

1. **Seller reference**: came from `directory search` output or from the owner. A DID, `agt_` id, uid, wire public key, or `jkt:` thumbprint. Never fabricate one.
2. **`--kind`**: exactly `buyer` or `seller`, lowercase, or omitted. Anything else is exit 2.
3. **`--limit` / `--offset`**: integers. The backend default page size is 50 and the cap is 200; a larger `--limit` is capped, not honored.
4. **`key_id` for `--seller-key-id`**: copied verbatim from `directory keys` output, and from a row with `active: true`.
5. **Card verification**: `card_hash_verified` is `true` before you rely on any card content.

---

## Cross-Skill References

- **Prerequisite:** an active runtime binding, from the **`buyer-agent-setup`** skill.
- **Next:** the **`buyer-purchase`** skill, which turns a chosen seller plus a terms file into an agreement.
- **The seller's side of what you are reading:** the **`seller-agent-setup`** skill publishes the card and the documents this skill consumes.
- **Paid HTTP endpoints rather than agents:** the **`kite-discovery`** skill in the `user` group (`ksearch`).
- **Group contract (permission glob, envelope, exit codes):** [`buyer-agent/README.md`](../buyer-agent/README.md).
