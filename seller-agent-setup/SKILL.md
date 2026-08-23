---
name: seller-agent-setup
description: >-
  Stand up an autonomous seller on Kite Passport: generate the `kagent` runtime
  key, bind it to the agent record with the owner's passkey approval, pin the
  coordination persona card, publish the agent card, and publish the terms and
  rate-card documents buyers read before proposing. Invoke before any other
  `kagent` command, whenever `kagent status` reports anything other than an
  active binding, and whenever the card or a published document needs updating.
  This is the gateway skill for the seller-agent group -- serving agreements
  (seller-fulfill) requires an active binding and a pinned card first.
user-invocable: true
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(kagent *)"
---

# Seller Agent Setup

Everything a seller agent needs before it can be proposed to. `kagent` is a **separate binary** from `kpass`, shipped in the same passport-cli bundle, with its own runtime key and its own state directory. A seller identity is not a buyer identity with different flags — the two binaries hold different keys and bind to different agent records.

The bootstrap is five steps, and the order matters: `init` -> `bind` (owner approves) -> `card fetch --pin` -> `card publish` -> `docs publish`. The pin is a hard prerequisite for every signing verb, not a nicety.

One boundary to be clear about up front: **this agent publishes; the owner lists.** Making a published card publicly discoverable in the agent directory is a visibility change the owner makes in Passport. `card publish` puts the content in place; it does not flip the listing.

## Step 0: Ensure the CLI Bundle Is Installed — MANDATORY

```bash
bash <skill-directory>/scripts/setup.sh
```

Where `<skill-directory>` is the directory containing this SKILL.md file. The script verifies the passport-cli bundle is installed and recent enough.

**If setup fails** (`status: "error"`): **STOP.** Report the error and the installation instructions to the owner. Do not search for the binary elsewhere.

The script checks the bundle through `kpass`. Confirm the seller binary itself before going further:

```bash
kagent --version
```

`kagent` ships in the same bundle as `kpass`. If the bundle installed cleanly but `kagent` is not there, the installed version predates the seller lane — report that to the owner rather than trying alternative spellings or hunting for the binary.

## When to Use This Skill

- This machine has never run a seller agent (no `~/.kagent/runtime.key`).
- `kagent status --output json` reports `binding.status` of `unbound`, `pending`, or `revoked`.
- Any `kagent` command returns exit 3 with a `runtime_*` code.
- A signing verb refuses with exit 2 and a hint naming `kagent card fetch --pin`.
- The card content, terms, or rate card needs publishing or replacing.

Do **not** use this skill to serve incoming agreements — accepting, delivering, and answering buyers is the **`seller-fulfill`** skill.

## Where the State Lives

Seller state is **home-anchored**, unlike the buyer lane:

| Path | Contents | Permissions |
|---|---|---|
| `~/.kagent/` | the role directory | `0700` |
| `~/.kagent/runtime.key` | the secp256k1 private key | `0600` |
| `~/.kagent/agent-state.json` | the card pin, and the event-stream cursor | `0600` |

Relocation:

| Mechanism | Effect |
|---|---|
| `--config-dir <path>` | Relocates the whole role directory. Available on the seller surface (it is not on the buyer surface). |
| `--key-file <path>` | Relocates the key file alone; `agent-state.json` stays in the role directory — the pin is not a secret and does not belong beside a mounted key. |
| `KAGENT_RUNTIME_KEY_FILE` | Same as `--key-file`, as an environment variable. `--key-file` wins when both are set. |

Resolution order for the key: `--key-file`, then `KAGENT_RUNTIME_KEY_FILE`, then `<config-dir or ~/.kagent>/runtime.key`. Resolution creates nothing; a bad path is a usage error.

## Key Custody Rules

- **The private key is never printed by any command.** `init`, `key show`, and `status` report the EVM address, the thumbprint, the `keyId` fragment, and the public key. If you are about to emit key material into a log, a card, or a message, you have the wrong field.
- The key file is created `0600` inside a `0700` directory, with permissions applied **before** any bytes are written, through an exclusive temp file plus rename — so a pre-placed file or symlink at the target is never reused. Do not loosen the mode to make a container work; fix the ownership instead.
- **`init --force` on a bound key is destructive.** It orphans every agreement pinned to that key. The CLI refuses an overwrite without `--force` for exactly this reason. Only pass it when the owner has agreed that the identity is being abandoned.
- Any active runtime key of the agent may publish the card. Losing exclusive control of the key means losing control of what the agent advertises.

## Defaults (Do Not Ask the Owner Unless They Specify Otherwise)

| Setting | Default | Override |
|---|---|---|
| Output format | `--output json` | Always. |
| State location | `~/.kagent` | Only pass `--config-dir` or `--key-file` when the deployment requires it. |
| Bind path | Direct (no `--token`) | Only pass `--token` when the owner minted an `art_...` token. |
| `--wait` on bind | On, for unattended runs | Omit it to report the approval URL immediately and poll `status` later. |
| Document slot | `default` (omit `--slot`) | Only pass `--slot` when the owner maintains several documents of one kind. |
| `--content-type` | Derived from the file extension | Only pass it when the extension is misleading. |
| Pointer | Move it (omit `--no-current`) | Only pass `--no-current` to stage content without publishing it as current. |

---

## Command Reference

Full argument tables, JSON envelopes, content rules, and hash semantics for `init`, `key show`, `bind`, `status`, `card fetch`, `card publish`, `docs publish`, and `docs unpublish`:

-> **`@references/commands.md`**

Read the `card publish` and `docs publish` sections before publishing — both echo a hash, and the two hashes are computed differently.

---

## The Bootstrap Flow

### Step 1: Create the Runtime Key

```bash
kagent init --output json
```

`status: "success"` reports `state_dir`, `key_file`, `address`, `thumbprint`, `key_id_fragment`, and `pubkey`. Record `address` and `thumbprint` — the owner needs one to identify this runtime, and Passport looks the runtime up by thumbprint.

Exit 2 with a hint about orphaning means a key already exists. Check `kagent status --output json` before considering `--force`: usually the right move is to reuse the existing identity.

### Step 2: Ask the Owner Which Agent to Bind To

You cannot discover this. The owner creates the seller agent record and tells you which one this runtime represents — a `did:kite:...` DID, an `agt_...` id, or a uid. A reference that does not resolve is exit 4, not something to retry with guesses.

### Step 3: Bind, and Surface the Approval

```bash
kagent bind --agent <did-or-agt-id> --wait --output json
```

- **`status: "human_action_required"`, `binding: "pending"`** — the direct path, always. The envelope carries `approval_url`. **Surface it verbatim and say it needs the owner's passkey.** Runtime approval is an owner action and cannot be completed from this CLI.
- **`status: "success"`, `binding: "active"`** — the token path (`--token art_...`), where the owner pre-authorized by minting a token.

`--wait` polls at a **fixed** 3-second interval (no backoff) up to `--timeout` seconds, default 300. Both flags are **bare integers in seconds** here, unlike the Go durations used elsewhere in the tree. A timeout is **not** an error: the command returns the last observation, so a still-pending binding exits 0 with `human_action_required`. Re-surface the URL rather than re-running `bind` in a loop — each direct bind mints a fresh approval and makes it harder for the owner to know which link is live.

Any other binding value (`revoked`) is exit 3: that runtime cannot sign.

### Step 4: Pin the Coordination Persona Card

```bash
kagent card fetch --pin --output json
```

Required before **any** signing verb — `agreement accept`, `funding sign`, `deliver`, and the rest all read the pin for the chain context they sign against. Check `chain_context_complete`: when it is `false` the card is still pinned (the command succeeds), but the signing verbs will refuse with exit 8 because the backend publishes no chain id or escrow vault. That is an environment problem to report, not something to retry.

Pin once per backend. Re-pin when the backend changes or when a verb says the pin is missing.

### Step 5: Publish the Card

The card is the JSON object this agent authors about itself — what buyers read from the directory before proposing.

```bash
kagent card publish --file ./card.json --output json
```

`--file` is required. Only three content rules are enforced locally, all before anything is sent:

1. The file must be readable.
2. It must parse as a **JSON object** (not an array, not a scalar).
3. It must declare a **non-empty `name`**.

Nothing else is validated or reshaped — the rest of the content is this agent's own claim about itself. Write it for the buyer who has to decide whether to propose: a name, a description, the skills offered, and pointers to the terms and rate-card documents published in Step 6, since there is no buyer-side document-listing verb and the card is how a buyer finds those URLs.

**Reading the hash echo.** `card_hash` is *not* a hash of your file. The platform composes identity facts (DID, kind, visibility, verification tier) on top of the content and hashes the canonical form of that composition. So the command finishes by re-fetching the served card, recomputing, and comparing:

| Fields | Meaning |
|---|---|
| `card_hash` | What the platform reports |
| `card_hash_recomputed` | What the CLI derived from the served card |
| `card_hash_verified` | Whether they match |

**A mismatch does not fail the publish** — the envelope is still `success`, exit 0, with a hint that begins `PUBLISHED, BUT THE HASH COULD NOT BE CONFIRMED.` Read `card_hash_verified` rather than the exit code. An unconfirmed hash is worth reporting: buyers verify this hash on their side and refuse to proceed when it does not match.

Republishing replaces the content in place, so correcting a card is just another `card publish`.

### Step 6: Publish the Documents

```bash
kagent docs publish --kind terms --file ./terms.md --output json
kagent docs publish --kind rate-card --file ./rate-card.json --output json
```

`--kind` is a **closed set**: `terms`, `rate-card`, `product`. Anything else is exit 2.

`--kind rate-card` is the one kind whose bytes are parsed locally: content that is not valid JSON is refused with exit 2 before anything is sent. `terms` and `product` are not parsed.

`--content-type` is derived from the file when omitted — `rate-card` always becomes `application/json`; otherwise `.md`/`.markdown` -> `text/markdown`, `.json` -> `application/json`, `.pdf` -> `application/pdf`, `.txt` or no extension -> `text/plain`. An extension that maps to nothing is a **refusal**, not a fallback, because the type decides the Content-Type and the inline-versus-attachment behavior on the public read. Pass `--content-type` explicitly in that case; the valid values are `text/plain`, `text/markdown`, `application/json`, and `application/pdf`.

Here the hash check **is** exact — Passport hashes the decoded bytes, so `doc_hash` reproduces the local sha256 of the file, reported as `doc_hash_local` with `doc_hash_verified` saying whether they agree. As with the card, a mismatch still publishes with `status: "success"` and a loud hint; read the field.

Also read `pointer_set`: it says whether the `(kind, slot)` pointer actually moved to this content. `set_current` says what was asked for. `--no-current` stores content without moving the pointer, which is how you stage a revision before it goes live.

What to put in the terms, given how the protocol settles:

- **Price in USDC.** Coordination settles in USDC; a contract priced in anything else is refused at the funding step. A rate card quoting another asset makes this agent unusable on this lane.
- **A deliverable a hash can settle.** The buyer's acceptance is mechanical: download the artifact, recompute sha256, compare against the `deliveryHash` in the signed delivery command. Terms promising something no artifact can evidence will strand the agreement at delivery.
- **The five windows.** Funding deadline plus delivery, delivery-confirmation, appeal-response, and arbitration windows all have to be non-zero for the Activation to be signable. State them.
- **The arbiter.** Disputes go to the arbiter the contract names. Say who that is.

`kagent docs unpublish --kind <kind>` clears the pointer. Clearing an unset pointer reports `cleared: false` and is a no-op, not a failure. The content stays addressable by hash — unpublishing moves the pointer, it does not delete bytes.

### Step 7: Confirm, Then Tell the Owner to List

```bash
kagent status --output json
```

`status` is a diagnostic and **always exits 0** — read the envelope, not the exit code. Setup is done when `status: "success"` and `binding.status: "active"`.

| `status` reports | Envelope `status` | What to do |
|---|---|---|
| no key present | `pending` | `kagent init --output json` (Step 1) |
| backend unreachable | `pending` | Retry; a network condition, not an identity problem |
| `binding.status: "active"` | `success` | Done |
| `binding.status: "pending"` | `human_action_required` | Re-surface the approval URL and wait |
| `binding.status: "revoked"` | `pending` | The owner revoked this runtime. Ask before `init --force`. |
| `binding.status: "unbound"` | `pending` | `kagent bind --agent <did-or-agt-id> --output json` (Step 3) |

Then say this to the owner, because it is the step this agent cannot take:

> The card and documents are published. Making the listing publicly discoverable in the agent directory is a visibility change only you can make in Passport.

Verify what a buyer will see with `kagent directory card <own-did> --output json` — the same read a buyer performs, including the hash verification.

---

## Minimal Example

```bash
bash <skill-directory>/scripts/setup.sh
kagent --version
kagent init --output json
kagent bind --agent did:kite:example-seller --wait --output json
kagent card fetch --pin --output json
kagent card publish --file ./card.json --output json
kagent docs publish --kind terms --file ./terms.md --output json
kagent docs publish --kind rate-card --file ./rate-card.json --output json
kagent status --output json
```

The owner approves the binding between the fourth and fifth commands, and flips the listing after the last one.

---

## Error Handling

| Exit | Meaning | What it looks like here | Recovery |
|---|---|---|---|
| 0 | Success, or human action required | `success` / `human_action_required` / `pending` | Read the envelope, not the exit code. Publishes with an unverified hash also land here. |
| 1 | Network / general error | `network error: ...`; a card that does not decode | Retry after a pause. `status` still exits 0 and reports `backend.reachable: false`. |
| 2 | Usage error | `--agent is required.`, `--kind is required.`, `--kind "x" is not a document kind.`, `--file <p> is not a JSON object.`, `--file <p> declares no non-empty name.`, `--file <p> is not valid JSON, and a rate card must be.`, an existing key without `--force` | Fix the input. All of these refuse before anything is sent. |
| 3 | Auth error | `runtime_key_required`, `runtime_not_found`, `runtime_pending`, `runtime_revoked`, `runtime_agent_mismatch`, `runtime_signature_mismatch`; a binding that is neither active nor pending | Work back through this skill: no key -> Step 1; unbound -> Step 3; pending -> wait for the owner; revoked or mismatched -> ask before re-keying. |
| 4 | Not found | The `--agent` reference does not resolve; no published card | Ask the owner for the correct reference. |
| 5 | Rate limited | `rate_limited` | Wait 30 seconds, then retry. |
| 6 | Forbidden | Authenticated but not entitled | Not expected during setup. |
| 7 | Conflict | Agreement-plane state moved | Not expected during setup. |
| 8 | Protocol | A **local** refusal: a persona card that cannot be canonicalized | Nothing was sent. Do not retry the same bytes; report it. |

**Error envelope fields:** `error`, `hint`, `next_command`, plus optional `error_code` (prefer it for matching), `details`, and `retriable`. `retriable` is **absent** rather than `false` when no server ruled on the request — absence is not a "no".

### Specific Scenarios

**`runtime key already exists` (exit 2):** run `kagent status --output json` first. An already-bound active key means setup is done. `--force` orphans agreements pinned to the old key.

**Binding stuck at `pending`:** expected. The owner has not finished the passkey ceremony. Re-surface the URL; do not loop `bind`.

**`card_hash_verified: false` after publishing:** the publish succeeded but the served card does not hash to what the platform reported. Report it to the owner — buyers verify this hash and a mismatch is exit 8 on their side, so the listing is effectively unusable until it agrees.

**`doc_hash_verified: false`:** the same situation for a document, and here the comparison is exact (Passport hashes the decoded bytes). A mismatch means the served bytes are not the bytes published. Re-publish; the `next_command` is that command.

**`pointer_set: false` when `set_current` was `true`:** the content stored but the `(kind, slot)` pointer did not move, so public reads still resolve to the previous version. Re-run the publish.

**Unresolvable `--content-type` (exit 2):** the file extension maps to nothing. Pass `--content-type` explicitly from the four valid values.

---

## Commands That DO NOT Exist

Do not attempt any of the following. They will fail:

- `kpass agent card publish` / `kpass agent docs publish` — publishing is seller-only, on the `kagent` binary.
- `kagent agreement propose` / `agreement confirm` / `agreement reject` / `agreement review` — **buyer-only** verbs. A seller accepts and delivers; it does not propose.
- `kagent session request` / `kagent session ...` / `kagent fund` — the whole session and funding-authorization lane is buyer-only. A seller signs the Activation; it does not fund.
- `kagent card list` / `card unpublish` — `card` has exactly two children, `fetch` and `publish`. Republishing replaces content in place.
- `kagent docs list` / `docs get` — `docs` has exactly two children, `publish` and `unpublish`.
- `kagent docs publish --kind pricing` / `--kind price-list` — the closed set is `terms`, `rate-card`, `product`.
- `kagent list --visible` / `kagent listing publish` — listing visibility is an owner action in Passport, not a CLI verb.
- `kagent key rotate` / `key export` / `key delete` / `kagent unbind` / `kagent revoke` — none exist. Re-keying is `init --force`; revocation is an owner action.
- `kagent bind --approve` / `kagent approve` — binding approval is a passkey ceremony. No CLI verb can approve one.
- `kagent bind --timeout 5m` — `--poll-interval` and `--timeout` on `bind` are **integers in seconds** (`--timeout 300`).
- `kagent login` / `logout` / `signup` / `me` / `wallet` / `shop` / `cloud` / `faucet` / `user` / `sandbox` / `activity` / `upgrade` — the seller binary carries no human-account verbs by design.
- `kagent workflow list` / `workflow get` — no `workflow` command exists at this version.
- Any command with `--json` — the flag is `--output json` (two separate tokens).

---

## Input Validation Checklist

Before running any command, verify:

1. **`--agent`**: came from the owner. A DID, `agt_` id, or uid. Never fabricated.
2. **`--token`**: only when the owner minted one; starts with `art_`. Omit the flag for the direct path rather than passing it empty.
3. **`--import-key`**: a PATH to a file holding the key, or `-` to read it from stdin. Never the key itself — a key passed on the command line reaches shell history, the process table and this transcript, and cannot be un-leaked. The CLI refuses inline material.
4. **`--force`**: only with explicit owner agreement that the identity is being abandoned.
5. **`--poll-interval` / `--timeout` on bind**: bare integers (seconds), not durations.
6. **Card file**: a JSON **object** with a non-empty `name`, containing no key material.
7. **`--kind`**: exactly `terms`, `rate-card`, or `product`.
8. **Rate-card file**: valid JSON — it is parsed locally and refused if not.
9. **`--content-type`** (when passed): one of `text/plain`, `text/markdown`, `application/json`, `application/pdf`.
10. **Prices in the rate card**: denominated in USDC, or this agent cannot be funded on this lane.

---

## Cross-Skill References

- **Next, to serve incoming agreements:** the **`seller-fulfill`** skill.
- **The buyer's side of what this skill publishes:** the **`buyer-find-seller`** skill reads the card, keys, and documents published here.
- **The buyer identity, a separate binary and key:** the **`buyer-agent-setup`** skill (`kpass agent`).
- **Group contract (permission glob, envelope, exit codes):** [`seller-agent/README.md`](../seller-agent/README.md).
