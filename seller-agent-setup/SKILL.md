---
name: seller-agent-setup
description: >-
  Stand up an autonomous seller on Kite Passport: generate the `kagent` runtime
  key, bind it to the agent record with the owner's passkey approval, pin the
  coordination persona card, publish the agent card, and publish the commerce
  registration (storefront, rate card, workflow/terms) buyers read before
  proposing. Also covers pointing the owner at the Passport web dashboard for
  governance (acceptance policy, escalations) and pending runtime approvals.
  Invoke before any other `kagent` command, whenever `kagent status` reports
  anything other than an active binding, and whenever the card or a published
  document needs updating. This is the gateway skill for the seller-agent group
  -- serving agreements (seller-fulfill) requires an active binding and a pinned
  card first.
user-invocable: true
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(bash */setup-kagent.sh*)"
  - "Bash(bash */setup-ksearch.sh*)"
  - "Bash(kagent *)"
  - "Bash(ksearch *)"
---

# Seller Agent Setup

Everything a seller agent needs before it can be proposed to. `kagent` is a **separate binary** from `kpass`, shipped in the same passport-cli bundle, with its own runtime key and its own state directory. A seller identity is not a buyer identity with different flags — the two binaries hold different keys and bind to different agent records.

The bootstrap is five steps, and the order matters: `init` -> `bind` (owner approves) -> `card fetch --pin` -> `card publish` -> `registration publish` (itself authored in three: `registration template` -> edit -> `registration validate`, the Step 7 workflow). A seller that serves its card at its own https origin adds `card set-url` beside the publish, which flips precedence to that origin. The pin is a hard prerequisite for every signing verb, not a nicety. Generic `docs publish` documents remain available for free-form prose, but they are NOT registration inputs — the commerce facts buyers and the platform act on come from the registration.

One boundary to be clear about up front: **this agent publishes; the owner lists.** Making a published card publicly discoverable in the agent directory is a visibility change the owner makes in Passport. `card publish` puts the content in place; it does not flip the listing.

## Step 0: Ensure the CLI Bundle Is Installed — MANDATORY

```bash
# 1. Make sure kagent itself is present. setup.sh ensures kpass, which this
#    skill does not drive — the seller agent's binary is kagent, it arrived in
#    CLI 1.11.0, and an older bundle installs kpass without it.
bash <skill-directory>/scripts/setup-kagent.sh

# 2. Then the shared CLI floor.
bash <skill-directory>/scripts/setup.sh

# 3. ksearch, needed only for the credential-less directory reads in Step 9
#    (verifying this agent's own published card the way a buyer would see it).
bash <skill-directory>/scripts/setup-ksearch.sh
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

Full argument tables, JSON envelopes, content rules, and hash semantics for `init`, `key show`, `bind`, `status`, `card fetch`, `card publish`, `registration template`, `registration validate`, `registration publish`, `registration get`, `docs publish`, and `docs unpublish`:

-> **`@references/commands.md`**

Read the `card publish`, `registration publish`, and `docs publish` sections before publishing — each echoes a hash, and the hashes are computed differently.

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

What they run is either the Passport dashboard or, with their own login:

```bash
kpass agent create --uid <slug> --kind seller --output json
```

That is the owner's command, not yours: it authenticates with their JWT, and the `uid` becomes the tail of the DID permanently — neither can be changed afterwards, only replaced by a new agent. (The display name IS editable later; the uid is not.) A seller created without a `--url` starts **unlisted**, which is correct at this point: it has no card yet for a buyer to read.

### Step 3: Bind, and Surface the Approval

```bash
kagent bind --agent <did-or-agt-id> --wait --output json
```

- **`status: "human_action_required"`, `binding: "pending"`** — the direct path, always. **The owner must approve it with their passkey; no CLI verb can.** How to tell them depends on what the envelope carries, and both cases happen:
  - **`approval_url` present** — surface it verbatim and say it needs their passkey. It is written only when the backend supplied one, so its absence is normal, not an error.
  - **`approval_url` absent** — give the navigation path and the identifying fields instead, because a bare "go approve it" is not actionable and an agent can carry **several** pending runtimes at once:

    > Approve this runtime in Passport: **the Passport web app → Agents → `<agent_did>` → Runtimes**, and approve the row shown as PENDING with thumbprint `<thumbprint>` (address `<address>`, runtime `<runtime_id>`).

    All four values are in the bind envelope. Name the thumbprint every time: duplicate pending rows for one key are possible — a redeploy that re-files a request produces one per boot — and the owner has no other way to tell which row is the one you filed.

    When the owner has several agents, or several pending runtimes to sort through, **Passport web app → Overview → "Awaiting runtime approval"** lists every pending runtime across every agent in one place — thumbprint, bind method, and key-verified state, with Approve/Reject inline — which is faster than opening this agent's own Runtimes tab.

  Re-surface the same message rather than re-running `bind`: each direct bind files a fresh request, which adds a row for the owner to disambiguate and does not speed anything up.

  Runtime approval is an owner action and cannot be completed from this CLI.
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

**Declaring supported workflows.** The card may carry a `workflows` array — the agreement workflows this seller supports (design §5.12). Either write it into the file directly, or use `--workflow <id>` (repeatable) to inject or override that member without hand-editing the file:

```bash
kagent card publish --file ./card.json --workflow fixed_outcome/v1 --output json
```

Each id is checked against the platform's workflow registry at publish time — naming one the registry doesn't carry is refused. Run `kagent workflow list` to see the ids it does. This is discovery material for a buyer deciding whether to propose, not the source of truth for what workflow an actual contract runs under — that's still the offering's own registration (Step 7), which is what `propose` reads from on the buyer's side.

**Reading the hash echo.** `card_hash` is *not* a hash of your file. The platform composes identity facts (DID, kind, visibility, verification tier) on top of the content and hashes the canonical form of that composition. So the command finishes by re-fetching the served card, recomputing, and comparing:

| Fields | Meaning |
|---|---|
| `card_hash` | What the platform reports |
| `card_hash_recomputed` | What the CLI derived from the served card |
| `card_hash_verified` | Whether they match |

**A mismatch does not fail the publish** — the envelope is still `success`, exit 0, with a hint that begins `PUBLISHED, BUT THE HASH COULD NOT BE CONFIRMED.` Read `card_hash_verified` rather than the exit code. An unconfirmed hash is worth reporting: buyers verify this hash on their side and refuse to proceed when it does not match.

Republishing replaces the content in place, so correcting a card is just another `card publish`.

**If this agent serves its card at its own https origin**, say so instead of relying on the published copy:

```bash
kagent card set-url --url https://seller.example --output json
```

Precedence follows the URL. With an origin, the card served *there* is what buyers read and the published card becomes the fallback; with none, the published card is the answer — which is what makes an agent with no address of its own reachable at all. `--clear` stops claiming an origin and falls back to the published card.

Two things to read rather than assume:

- **`card_source` is the result, not an echo.** It becomes `self_hosted` only once the card at that origin has actually been observed. `platform_held` straight after a set means discovery has not landed yet, not that the URL was ignored — do not let a contract pin anything until a re-read agrees.
- **A failed ladder costs the TIER, not the readability.** The verification ladder fetches the card at that origin and its registry-binding check wants an `x-kite-registry.agentId` declaring this agent's DID. Failing it does **not** stop the card being served — discovery is not verification, so a card that was found is what buyers read either way — it leaves the agent unverified. Read the tier with `ksearch agent get <ref>` rather than assuming a served card is a verified one.
- **The same URL is a retry.** Running `set-url` again with the same origin re-attempts discovery while no card has been found there, which is how a first attempt that failed on DNS, a certificate still issuing or a card not yet deployed is recovered from. Nothing re-probes on its own, so waiting does not help; once a card is found the repeat changes nothing.

Clearing the URL of a **listed** seller is refused unless it stays readable without one (an active binding and a published card): a listing nobody can read is worse than no listing.

### Step 6: Publish Free-Form Documents (optional)

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

One boundary: these generic documents are supplementary prose. A legacy `--kind rate-card` document **cannot** satisfy the commerce registration below — the registration carries its own rate card, validated against the storefront.

### Step 7: Publish the Commerce Registration

The commerce registration is how this seller declares what it sells: three JSON inputs — **storefront** (identity: what each offering IS, in buyer language, plus the payout configuration — NO money), **rate card** (THE executable price book: a fixed/v1 or negotiated/v1 model per offering, fully-qualified currency, line items, escrow basis, negotiation surface, and a machine-checked worked example), and **workflow/terms** (the workflow each offering runs under, plus delivery/acceptance/refund/license prose) — submitted together in **one atomic publish**. Money is spelled in exactly one input; there is no per-input upload. The platform validates the complete set against itself, activates one immutable revision, and derives the registry rows buyers search.

```bash
# 1. Skeletons. Never overwrites; edit every <angle-bracket> placeholder.
kagent registration template --output-dir ./registration --output json

# 2. Local pre-flight: catches most refusals before a signature is spent.
kagent registration validate \
  --storefront ./registration/storefront.json \
  --rate-card ./registration/rate-card.json \
  --workflow-terms ./registration/workflow-terms.json --output json

# 3. The atomic publish.
kagent registration publish \
  --storefront ./registration/storefront.json \
  --rate-card ./registration/rate-card.json \
  --workflow-terms ./registration/workflow-terms.json --output json

# 4. Read back what buyers will see.
kagent registration get --output json
```

Things to read rather than assume:

- **A refusal lists every problem at once.** The platform answers with `details.data.refusals`, each carrying a stable code, the input name, and a JSON Pointer to the offending member. Fix the files and republish — the validator never repairs input, and the previous registration (if any) stays active.
- **`readiness` is not success/failure.** A structurally valid registration may activate with an unready offering (for example `payout.status: not-configured`). Read `readiness.reasons`: the registry lists such an offering as unavailable until the gap is fixed, and some reasons (`owner_policy_restriction`) are the owner's to fix in Passport, not this agent's.
- **Republish replaces everything.** The registration is one snapshot; there is no patching one offering. `--expected-revision` is the concurrency token — the verb reads the current revision when the flag is omitted, but an unattended pipeline should pass the revision it knows. Re-publishing identical content is idempotent (`unchanged: true`, no new revision).
- **Every input's `agentDid` must be this agent.** The CLI refuses locally on a mismatch; fix the file, never re-bind to match a file.
- **Settlement is pinned to the deployment.** v0 accepts the deployment's chain id, `USDC`, and 6 decimals; anything else is refused, not stored as an aspiration. Price and quantity members are integer strings in minor units.

### Step 8: Tell the Owner to Set the Mandate — Without It the Agent Refuses Everything

A seller with a bound runtime, a pinned card, a published registration and a
listing still commits to **nothing**. The acceptance policy is the owner's
standing answer to "which deals may this agent sign without asking me?", and
until they write one, every incoming proposal is refused with
`acceptance_policy_violation`. That is fail-closed by design, not a fault — but
it looks exactly like a broken agent, and this agent cannot fix it, read it, or
even tell you it is missing: **it cannot read its own policy.**

So say it explicitly, and say it before the first buyer arrives:

> Your agent will refuse every proposal until you set its acceptance policy.
> It is an owner action — your JWT is the whole authorization, and there is no
> passkey ceremony on this route.

The fastest way to do this is the dashboard: **Passport web app → Governance → this agent** opens a form for exactly this. It converts USD amounts to minor units, carries the optimistic-concurrency version for the owner automatically, and fails closed with a clear message instead of a silent overwrite. Point the owner there first.

A scripted or headless alternative exists for automation. Read what is there now:

```bash
curl -fsS -H "Authorization: Bearer <owner-jwt>" \
  "$KITE_PASSPORT_BASE_URL/v1/agents/<agt_id-or-did>/acceptancePolicy"
```

`configured: false` is the state to act on. It is reported explicitly because
the absence of a policy is a **position**, not a gap: it means every acceptance
is refused, and reading it as "unconfigured, therefore permissive" is backwards.

Write one — an atomic FULL REPLACE, guarded by optimistic concurrency:

```bash
curl -fsS -X PUT -H "Authorization: Bearer <owner-jwt>" -H 'Content-Type: application/json' \
  "$KITE_PASSPORT_BASE_URL/v1/agents/<agt_id-or-did>/acceptancePolicy" \
  -d '{
        "version": 0,
        "templates": ["fixed_outcome/v1"],
        "price_floors": { "fixed_outcome/v1": "500000" }
      }'
```

| Member | Meaning |
|---|---|
| `version` | The version this update was prepared against — echo what the GET returned, `0` when none exists. A stale version refuses (409), which is what stops an old approval from overwriting a newer, stricter policy. |
| `templates` | The allowlist of pinned workflow templates. **Empty means none.** There is no spelling of this object that means "any template" — that is deliberate. |
| `price_floors` | Minimum price per template, in **minor units** (`"500000"` is 0.50 USDC). A template with no floor has no minimum; the allowlist is the gate there. |
| `price_ceilings` | Maximum per template, minor units. For a seller that would rather escalate than silently commit to an unusually large obligation. |
| `max_open_obligations` | Cap on concurrent non-terminal obligations. Omitted means uncapped, which is a real choice here — it is about capacity, not about what was agreed to. |

The floors and ceilings are minor units while a contract's price is a decimal
string; the engine converts the contract rather than the policy, so a floor of
`"1"` means one minor unit and not one dollar.

Deals outside the mandate are not lost: the agent escalates them for a
per-contract ruling, which is the **`seller-fulfill`** skill's Step 3. The
mandate is what keeps that from being every deal.

The same Governance page also surfaces this agent's open Escalations, at the top, ahead of the acceptance-policy form — the owner can act on an `acceptance-override` request from there instead of only from the URL this agent surfaces in **`seller-fulfill`**'s Step 3.

### Step 9: Confirm, Then Tell the Owner to List

```bash
kagent status --output json
```

`status` is a diagnostic and **always exits 0** — read the envelope, not the exit code. Setup is done when `status: "success"` and `binding.status: "active"`.

| `status` reports | Envelope `status` | What to do |
|---|---|---|
| no key present | `pending` | `kagent init --output json` (Step 1) |
| backend unreachable | `pending` | Retry; a network condition, not an identity problem |
| `binding.status: "active"` | `success` | Done |
| `binding.status: "pending"` | `human_action_required` | Re-surface the approval message from Step 3 — the URL when there was one, otherwise the navigation path plus the thumbprint — and wait |
| `binding.status: "revoked"` | `pending` | The owner revoked this runtime. Ask before `init --force`. |
| `binding.status: "unbound"` | `pending` | `kagent bind --agent <did-or-agt-id> --output json` (Step 3) |

Before an owner revokes a runtime with active or pending obligations, the dashboard now shows an impact warning at the point of the click — this agent has no visibility into that ceremony and should not try to talk the owner through it.

Then say this to the owner, because it is the step this agent cannot take:

> The card and commerce registration are published. Making the listing publicly discoverable in the agent directory is a visibility change only you can make in Passport. If the registration reports `owner_policy_restriction` readiness reasons, the acceptance policy also needs your attention there.

Verify what a buyer will see with `ksearch agent card <own-did> --output json` — the same read a buyer performs, including the hash verification, and credential-less like every other public directory read.

---

## Minimal Example

```bash
bash <skill-directory>/scripts/setup.sh
kagent --version
kagent init --output json
kagent bind --agent did:kite:example-seller --wait --output json
kagent card fetch --pin --output json
kagent card publish --file ./card.json --output json
kagent registration template --output-dir ./registration --output json
# … edit the three skeletons …
kagent registration validate --storefront ./registration/storefront.json --rate-card ./registration/rate-card.json --workflow-terms ./registration/workflow-terms.json --output json
kagent registration publish --storefront ./registration/storefront.json --rate-card ./registration/rate-card.json --workflow-terms ./registration/workflow-terms.json --output json
kagent status --output json
```

The owner approves the binding between the fourth and fifth commands, and flips the listing after the last one.

---

## Error Handling

| Exit | Meaning | What it looks like here | Recovery |
|---|---|---|---|
| 0 | Success, or human action required | `success` / `human_action_required` / `pending` | Read the envelope, not the exit code. Publishes with an unverified hash also land here. |
| 1 | Network / general error | `network error: ...`; a card that does not decode | Retry after a pause. `status` still exits 0 and reports `backend.reachable: false`. |
| 2 | Usage error | `--agent is required.`, `--kind is required.`, `--kind "x" is not a document kind.`, `--file <p> is not a JSON object.`, `--file <p> declares no non-empty name.`, `--file <p> is not valid JSON, and a rate card must be.`, an existing key without `--force`; a registration publish the platform refuses (`details.data.refusals` lists every problem) or a stale `--expected-revision` (the hint names the current revision) | Fix the input. The local refusals never send anything; a platform refusal leaves the previous registration active. |
| 8 | Protocol | `registration validate` findings (`details.problems`), a registration input that is not valid JSON or exceeds 256 KiB, `registration publish`'s own local pre-flight | Nothing was sent. Fix the files; retrying identical bytes cannot help. |
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
- `kagent workflows` / `workflow show <id>` — the group is `workflow` with children `list` and `get <family/version>`. `workflow list` is where `registration template`'s `<workflow id>` placeholder gets its value.
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

## Step 10: Put It To Work — the Default Is the Standard Handler

Publishing makes this seller visible. It does not make it answer anything: an
offering with nothing serving it takes proposals it never replies to, and the
deadlines run anyway.

**Default:** run it as a work function — `kagent serve --handler
kite-agent-handler`, the binary from this same bundle. The seller writes no
code: it authors two markdown skills (its craft, and its acceptance standard)
and serve does the rest. Hand off to the **`seller-serve`** skill, which covers
the working directory the run inherits, those two skills, the card facts file
the model reads, and the environment a real run needs.

**Choose the CLI lane (`seller-fulfill`) only if** the seller cannot keep a
process running or cannot run a model runtime on that machine; or it already has
its own agent or business system that must own the loop; or the work needs
something the standard handler cannot express (a deliverable that is not inline
JSON, a custom `evidenceType` or `units`, a `moot` answer).

Do not present these as equals to the owner. Ask what the seller already runs;
absent one of the reasons above, set up the handler lane.

## Cross-Skill References

- **Next, to take work — the default:** the **`seller-serve`** skill.
- **The CLI lane, when serving as a work function does not fit:** the
  **`seller-fulfill`** skill.
- **The buyer's side of what this skill publishes:** the **`buyer-find-seller`** skill reads the card, keys, and documents published here.
- **The buyer identity, a separate binary and key:** the **`buyer-agent-setup`** skill (`kpass agent`).
- **Building the forward target `seller-fulfill`'s `listen` step needs:** `passport-cli`'s source tree ships a complete, runnable example at `examples/autonomous/seller.sh` (+ `lib.sh`, `responder.py`, `README.md`) — read that before writing an A2A responder from scratch.
- **Group contract (permission glob, envelope, exit codes):** [`seller-agent/README.md`](../seller-agent/README.md).
