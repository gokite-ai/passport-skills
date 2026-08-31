---
name: seller-agent-setup
description: >-
  Stand up an autonomous seller on Kite Passport: generate the `kagent` runtime
  key, bind it to the agent record with the owner's passkey approval, pin the
  coordination persona card, publish the agent card, and publish the commerce
  registration (storefront, rate card, workflow/terms) buyers read before
  proposing, list the seller, and confirm its verification tier. Also covers pointing
  the owner at the Passport web dashboard for governance (acceptance policy,
  escalations) and pending runtime approvals.
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
  - "Bash(kpass identifier *)"
  - "Bash(kpass onboarding *)"
  - "Bash(kpass agent create *)"
  - "Bash(kpass agent token create *)"
---

# Seller Agent Setup

Everything a seller agent needs before it can be proposed to. `kagent` is a **separate binary** from `kpass`, shipped in the same passport-cli bundle, with its own runtime key and its own state directory. A seller identity is not a buyer identity with different flags — the two binaries hold different keys and bind to different agent records.

The bootstrap is five steps, and the order matters: `init` -> `bind` (owner approves) -> `card fetch --pin` -> `card publish` -> `registration publish` (itself authored in three: `registration template` -> edit -> `registration validate`, the Step 7 workflow). A seller that serves its card at its own https origin adds `card set-url` beside the publish, which flips precedence to that origin. The pin is a hard prerequisite for every signing verb, not a nicety. Generic `docs publish` documents remain available for free-form prose, but they are NOT registration inputs — the commerce facts buyers and the platform act on come from the registration.

One boundary to be clear about up front: **this agent publishes; the owner lists.** Making a published card publicly discoverable in the agent directory is a visibility change on the *owner* plane, not something this agent's runtime key can sign — `card publish` puts the content in place; it does not flip the listing. But "owner plane" does not mean "dashboard-only": if this session already holds the owner's JWT (the same JWT Step 8's acceptance-policy call uses), listing is one more scripted owner-API call, not a hand-off to a human. See Step 9.

## Handling "set up a seller agent for me" (a full, end-to-end request)

A request phrased as a finished outcome — "set up a seller agent for me", "make my agent live", "get me selling X" — is asking for the whole chain through **listed and mandated**, run in one pass, not a sequence of "want me to continue?" check-ins after every step. Treat it differently from "prepare my offer, don't publish" (the previous paragraph):

- **Gather everything this needs before running anything.** Before Step 1, make sure you actually have: the agent `uid` (Step 2 — cannot be guessed, and cannot be changed later), what the seller is selling (one-line offering identity), the price and currency, and the workflow template (default `fixed_outcome/v1` if the owner has no preference). If any of these is missing and wasn't already established earlier in the conversation, ask for all of them **up front, in one batch**, before touching a command — not one field at a time between Bash calls, and never fabricated to keep the flow moving.
- **Run Steps 1–9 straight through**, including `card publish`, `registration publish`, and — per Step 9 — the listing PATCH, as one continuous execution once the inputs above are known. Do not stop mid-flow to ask permission for a step that's simply next in the chain the owner already asked for. Confirm the resulting verification tier (`verified` is the correct, complete outcome for the default platform-held card — see Step 9) rather than treating it as unfinished work.
- **The only real interruption points are the ones nothing here can resolve programmatically:** a `binding.status: "pending"` runtime approval that needs the owner's passkey (Step 3's fallback path), `owner-bootstrap.md`'s onboarding/KYC steps if they come back `rejected` or stuck `pending`, and **no owner JWT available to this session.** That last one is not a minor gap — Step 9's listing PATCH and Step 8's acceptance-policy PUT are both owner-JWT-authorized calls with no other way to issue them, so without one the setup is genuinely incomplete, not just missing a nice-to-have. Get the owner authenticated first (**`authenticate-user`**) rather than skipping those calls silently or inventing a token. Those are genuine stops — everything else in the chain, including listing, is not.
- Setting the acceptance policy (Step 8) is part of this same pass, not an optional extra — an unlisted or unmandated agent can't actually transact, so leaving it for later defeats the "set up a seller agent for me" ask. But write it from **this seller's actual values**, not Step 8's illustrative example: `templates` from the workflow id(s) this seller actually registered in Step 7, `price_floors`/`price_ceilings` from the real price the owner set (or explicitly confirmed), and `max_open_obligations` only if the owner stated a cap. If any of those is genuinely unconfirmed, do not guess a number to complete the pass — leave the policy unset (`configured: false`) and tell the owner to set it in Passport (see Step 8).

**Identity creation is not publishing — do not defer Steps 1–3 because the owner said "don't publish yet."** "Set up my offer" / "prepare the offer, don't publish" means: get everything ready except the acts that make the agent visible or committed to a deal. Those acts are `card publish`, `registration publish`, and the owner's own listing toggle — nothing before that. `kagent init` (Step 1), `kpass agent create` (Step 2), and `bind` (Step 3) create an identity and key; a freshly created, freshly bound seller agent is **unlisted by default** and takes no proposals until its card and registration are published. So when this machine has no active seller agent yet, run Steps 1–3 first, *before* touching card content or registration files — do not park them for later and author `storefront.json` / `rate-card.json` / `workflow-terms.json` with a placeholder `agentDid`. The registration inputs need the real DID to mean anything; a file that still reads `did:kite:<namespace>:<agent>` when the session ends is not "prepared", it is blocked on a step that should have already happened.

## Step 0: Ensure the CLI Bundle Is Installed — MANDATORY

```bash
# 1. Make sure kagent itself is present. setup.sh ensures kpass (this skill
#    also drives a few kpass account-bootstrap verbs — see
#    references/owner-bootstrap.md) — the seller agent's PRIMARY binary is
#    kagent, it arrived in CLI 1.11.0, and an older bundle installs kpass
#    without it.
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
- The owner asks to "set up an offer" / "become a seller" / "sell X" and this machine has no active seller agent yet — check `kagent status` first; if there is no active binding, run Steps 1–3 (identity + bind) before drafting any card or registration content, even if the owner does not want to publish yet.

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

## Running Multiple Seller Agents on One Machine

Seller state is home-anchored (`~/.kagent/` by default), so a second seller identity needs its own role directory rather than a second working directory: pass `--config-dir <path>` (a fresh, dedicated directory per identity) to every `kagent` command for that agent — `init`, `bind`, `status`, and the serving commands in **`seller-fulfill`**. This keeps the key, `agent-state.json`, and published documents fully separate from any other seller on the machine; the default identity at `~/.kagent/` is never touched.

As with the buyer lane, this only matters when `init` reports `runtime key already exists` for an agent that turns out to be a *different* one than intended — that's the signal to isolate with `--config-dir`, not to `--force` through the existing binding.

## Key Custody Rules

- **The private key is never printed by any command.** `init`, `key show`, and `status` report the EVM address, the thumbprint, the `keyId` fragment, and the public key. If you are about to emit key material into a log, a card, or a message, you have the wrong field.
- The key file is created `0600` inside a `0700` directory, with permissions applied **before** any bytes are written, through an exclusive temp file plus rename — so a pre-placed file or symlink at the target is never reused. Do not loosen the mode to make a container work; fix the ownership instead.
- **`init --force` on a bound key is destructive.** It orphans every agreement pinned to that key. The CLI refuses an overwrite without `--force` for exactly this reason. Only pass it when the owner has agreed that the identity is being abandoned. Wanting to run a second seller agent alongside the first is **not** that case — see "Running Multiple Seller Agents on One Machine" above instead.
- Any active runtime key of the agent may publish the card. Losing exclusive control of the key means losing control of what the agent advertises.

## Defaults (Do Not Ask the Owner Unless They Specify Otherwise)

| Setting | Default | Override |
|---|---|---|
| Output format | `--output json` | Always. |
| State location | `~/.kagent` | Only pass `--config-dir` or `--key-file` when the deployment requires it. |
| Bind path | Mint-then-bind (`agent token create` → `bind --token`) | Falls back to direct (no `--token`) only if token mint ever requires step-up. |
| `--wait` on bind | Not used on the default mint-then-bind path (lands `active` immediately) | On the fallback direct path, for unattended runs — omit it to report the approval URL immediately and poll `status` later. |
| Document slot | `default` (omit `--slot`) | Only pass `--slot` when the owner maintains several documents of one kind. |
| `--content-type` | Derived from the file extension | Only pass it when the extension is misleading. |
| Pointer | Move it (omit `--no-current`) | Only pass `--no-current` to stage content without publishing it as current. |

---

## Command Reference

Full argument tables, JSON envelopes, content rules, and hash semantics for `init`, `key show`, `bind`, `status`, `card fetch`, `card publish`, `registration template`, `registration validate`, `registration publish`, `registration get`, `docs publish`, `docs unpublish`, and the owner-bootstrap commands (`kpass identifier claim`, `kpass onboarding submit`, `kpass onboarding status`, `kpass agent token create`):

-> **`@references/commands.md`**

Read the `card publish`, `registration publish`, and `docs publish` sections before publishing — each echoes a hash, and the hashes are computed differently.

---

## The Bootstrap Flow

### Step 1: Create the Runtime Key

```bash
kagent init --output json
```

`status: "success"` reports `state_dir`, `key_file`, `address`, `thumbprint`, `key_id_fragment`, and `pubkey`. Record `address` and `thumbprint` — the owner needs one to identify this runtime, and Passport looks the runtime up by thumbprint.

Exit 2 with a hint about orphaning means a key already exists. Check `kagent status --output json` and compare the bound agent to the one you're setting up before considering `--force`:

- **Same agent, and `binding.status` is `active`** — reuse it; nothing needs doing.
- **Same agent, but `binding.status` is `pending`, `revoked`, or `unbound`** — the key matches, but the binding doesn't. Continue through Step 3/4 as usual (see Step 4's status table) rather than treating setup as complete.
- **A different agent or owner** — the owner likely wants a second, independent seller identity, not to retire the first. Since seller state is home-anchored (unlike the buyer lane), the fix is `--config-dir <path>` to give the new seller its own role directory — see "Running Multiple Seller Agents on One Machine" below — not `--force`.

### Step 2: Ask the Owner Which Agent to Bind To

You cannot discover the `uid` on your own — ask the owner, and confirm `--kind seller`. Before creating the agent, work through **`@references/owner-bootstrap.md`** steps 1–4: check onboarding status, claim the controller identifier, submit KYC/KYB, and poll briefly. Every account needs this before `agent create` will succeed — it refuses with `ErrRequiresIdentifier` / `ErrRequiresOnboarding` otherwise.

Once that resolves (`verified`, or already was), create the agent — either the owner does this through the Passport dashboard, or you run it directly on their already-authenticated `kpass` session (see `authenticate-user`):

```bash
kpass agent create --uid <slug> --kind seller --output json
```

The `uid` becomes the tail of the DID permanently — neither can be changed afterwards, only replaced by a new agent. (The display name IS editable later; the uid is not.) A seller created without a `--url` starts **unlisted**, which is correct at this point: it has no card yet for a buyer to read. A reference that does not resolve later, in Step 3, is exit 4, not something to retry with guesses.

If `owner-bootstrap.md` Step 4 reports onboarding still `pending` past its poll budget, or Step 1/3 hit a `rejected` record, stop there and follow that file's guidance — do not attempt `agent create` early.

### Step 3: Bind, and Surface the Approval

**Default path — mint then bind (`@references/owner-bootstrap.md` Step 6):**

```bash
kpass agent token create --agent <did-or-agt-id> --output json
kagent bind --agent <did-or-agt-id> --token <art_...> --output json
```

Token minting needs only the owner's plain JWT — no passkey step-up — so this lands `active` immediately in practice: no `--wait`, no `approval_url` to surface. Do this first.

**Fallback path — if token mint ever comes back requiring step-up** (defensive, not expected):

```bash
kagent bind --agent <did-or-agt-id> --wait --output json
```

- **`status: "human_action_required"`, `binding: "pending"`** — the direct path. **The owner must approve it with their passkey; no CLI verb can.** How to tell them depends on what the envelope carries, and both cases happen:
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

The pin is a cache, not a one-time setup step. The pinned card's hash goes into every contract's `runtimeBinding.agentCardHash`, and that hash moves whenever a platform deployment changes what the card carries (the workflow-template catalog, the chain context, the endpoint). Re-pin when the backend changes, when a verb says the pin is missing or stale, and after any platform deployment — a long-running seller holding a stale pin refuses every incoming proposal with an `agentCardHash` mismatch ("an execution context this agent never read"). **`seller-serve`** covers the operational side.

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

Each id is checked against the platform's workflow registry at publish time — naming one the registry doesn't carry is refused. Run `ksearch workflow-template list` to see the ids it does (a public read — the discovery binary, no runtime key). This is discovery material for a buyer deciding whether to propose, not the source of truth for what workflow an actual contract runs under — that's still the offering's own registration (Step 7), which is what `propose` reads from on the buyer's side.

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

The commerce registration is how this seller declares what it sells: three JSON inputs — **storefront** (identity: what each offering IS, in buyer language, plus the payout configuration — NO money), **rate card** (THE executable price book: a fixed/v1 or negotiated/v1 model per offering, fully-qualified currency, line items, escrow basis, negotiation surface, and a machine-checked worked example), and **workflow/terms** (the workflow template each offering runs under plus an optional per-offering `config` object — the platform records that config verbatim, content-addressed, without interpreting it — and delivery/acceptance/refund/license prose) — submitted together in **one atomic publish**. Money is spelled in exactly one input; there is no per-input upload. The platform validates the complete set against itself, activates one immutable revision, and derives the registry rows buyers search.

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

Write one — an atomic FULL REPLACE, guarded by optimistic concurrency. **The body below is illustrative, not a default to copy verbatim** — `fixed_outcome/v1` and `500000` are this example's numbers, not this seller's. Fill `templates` from the workflow id(s) actually registered in this seller's commerce registration (Step 7) and `price_floors`/`price_ceilings` from the real price the owner set or confirmed; a mismatched floor (e.g. an example's 0.50 USDC floor sitting above this seller's actual 0.10 USDC offering) would make the agent refuse the exact deal it was just set up to take. If those real values aren't known yet, don't invent them — leave the policy unset and point the owner at Passport instead (see above).

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

### Step 9: Confirm Binding, List the Seller, Confirm Its Tier

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

**Listing the seller.** `kagent` carries no listing verb by design — visibility is an owner-plane call, not something the runtime key signs. That does not mean it needs a human at a keyboard: it is the same shape as Step 8's acceptance-policy call — an owner-JWT-authorized REST call, scriptable the moment this session holds that JWT. This is exactly what `passport-cli`'s `examples/autonomous/seller.sh` does at its own "OWNER lists the seller" step:

```bash
curl -fsS -X PATCH -H "Authorization: Bearer <owner-jwt>" -H 'Content-Type: application/json' \
  "$KITE_PASSPORT_BASE_URL/v1/agents/<agt_id-or-did>" \
  -d '{"visibility": "listed"}'
```

Listing requires an active binding and a published card; it refuses otherwise. When this session holds the owner's JWT (the same one used for `authenticate-user` / the acceptance-policy call), run this as part of the same pass rather than handing it to the owner — see "Handling 'set up a seller agent for me'" above. Only fall back to pointing the owner at **Passport web app → this agent → visibility** when this session has no owner JWT to act with.

If the registration reports `owner_policy_restriction` readiness reasons, that one genuinely needs the owner's attention in Passport — it is not exposed by any API this agent can call.

**Confirming the verification tier — do not blindly run `:verify`.** There are two seller tiers above `unverified`, and which one applies depends on whether this agent has a self-hosted https origin:

```
l4_key AND platform-held card               → verified        (the default outcome of this skill)
l1_card AND l2_binding AND l3_protocol AND l4_key → fully_verified  (self-hosted card only, via card set-url)
```

For the platform-held card this skill produces by default (no `card set-url` run), **`verified` is already the complete, correct terminal tier** the moment Step 3 (an owner-approved, key-proven binding) and Step 5 (card publish) are both done — nothing else is required or possible for it. The design is explicit about this: a kite-managed seller "has no self-hosted surface to corroborate — L1–L3 have nothing to say about it, and running them would verify nothing." Two mechanical reasons `POST /v1/agents/<id>:verify` is not something to run reflexively here:

- **`l4_key` is never written by the verify pipeline.** It's maintained by the runtime-binding lifecycle itself (Step 3), so there is nothing for a verify call to check there.
- **L1–L3 don't run at all without a registered https URL** — card discovery "presumes a registered URL," and an agent created without one simply skips L1 (and everything gated behind it). They are not "pending forever" so much as structurally inapplicable to this agent.

So instead of calling `:verify`, just **confirm and report the tier already achieved** — it's recomputed live on every read, no pipeline run needed:

```bash
ksearch agent get <own-did> --output json   # verified_tier: "verified" once bound + published
# or, no auth needed either way:
curl -fsS "$KITE_PASSPORT_BASE_URL/v1/agents/<agt_id-or-did>/verification"
```

Tell the owner plainly that `verified` is the finished state for this configuration, not a partial one — a dashboard that still shows "L1 · Agent card / L2 · Registry binding / L3 · Protocol probe" as `Pending` on a platform-held agent is not describing missing work on this agent; those checks apply only to a self-hosted seller. Reaching `fully_verified` needs a real https origin: `card set-url` (once one exists — see **`cloud-deploy`**) serving the `x-kite-registry.agentId` header L2 wants, plus a live responder for L3 (**`seller-serve`**) — that combination is what makes `POST .../:verify` meaningful, and only then. Do not run it speculatively before that origin exists; it burns a call to re-confirm a tier the platform already reports correctly.

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

**`runtime key already exists` (exit 2):** run `kagent status --output json` first and check whose agent it's bound to. **Same agent, already active:** setup is done. **A different agent or owner:** this usually means the owner wants a second seller identity — use `--config-dir <path>` for an isolated role directory (see "Running Multiple Seller Agents on One Machine") rather than forcing. `--force` orphans agreements pinned to the old key and should only run with the owner's explicit go-ahead to abandon that identity.

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
- `kagent list --visible` / `kagent listing publish` — listing visibility is an owner-plane action, not a `kagent` CLI verb; it is `PATCH /v1/agents/<id>` with the owner's JWT (Step 9), not a dashboard-exclusive action.
- `kagent key rotate` / `key export` / `key delete` / `kagent unbind` / `kagent revoke` — none exist. Re-keying is `init --force`; revocation is an owner action.
- `kagent bind --approve` / `kagent approve` — binding approval is a passkey ceremony. No CLI verb can approve one.
- `kagent bind --timeout 5m` — `--poll-interval` and `--timeout` on `bind` are **integers in seconds** (`--timeout 300`).
- `kagent login` / `logout` / `signup` / `me` / `wallet` / `shop` / `cloud` / `faucet` / `user` / `sandbox` / `activity` / `upgrade` — the seller binary carries no human-account verbs by design.
- `kagent workflows` / `workflow show <id>` — the TEMPLATE group is `workflow-template` with children `list` and `get <family/version>`; `workflow-template list` is where `registration template`'s `<template id>` placeholder gets its value. On kagent, bare `workflow` is a DIFFERENT group: this seller's own immutable Workflows — `kagent workflow list` (signed management view) and `kagent workflow get <workflow-hash>` (one Workflow, complete config included). **The division of labour is deliberate**: kagent authors the INITIAL configuration (`registration template` → edit → `registration validate` → `registration publish`) and reads; every LATER change — moving an offering to a different configuration — is the OWNER's act, done in the Passport web dashboard (or its owner API: `PUT /v1/agents/{agent}/offerings/{offeringId}/workflow`, previewed by `POST /v1/agents/{agent}/workflows:validate`). When a config change is needed, tell the owner what to change and why; do not look for a kagent mutation verb — there is none, by design.
- Any command with `--json` — the flag is `--output json` (two separate tokens).

---

## Input Validation Checklist

Before running any command, verify:

1. **`--agent`**: came from the owner. A DID, `agt_` id, or uid. Never fabricated.
2. **`--token`**: the `art_...` value from `kpass agent token create` (this skill mints it itself on the default path) — or one the owner minted directly. Starts with `art_`. Omit the flag only for the fallback direct path rather than passing it empty.
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

- **The JWT this skill assumes throughout:** the **`authenticate-user`** skill — run it first if `owner-bootstrap.md`'s commands return exit code 3.
- **Next, to take work — the default:** the **`seller-serve`** skill.
- **The CLI lane, when serving as a work function does not fit:** the
  **`seller-fulfill`** skill.
- **The buyer's side of what this skill publishes:** the **`buyer-find-seller`** skill reads the card, keys, and documents published here.
- **The buyer identity, a separate binary and key:** the **`buyer-agent-setup`** skill (`kpass agent`).
- **Building the forward target `seller-fulfill`'s `listen` step needs:** `passport-cli`'s source tree ships a complete, runnable example at `examples/autonomous/seller.sh` (+ `lib.sh`, `responder.py`, `README.md`) — read that before writing an A2A responder from scratch.
- **Group contract (permission glob, envelope, exit codes):** [`seller-agent/README.md`](../seller-agent/README.md).
