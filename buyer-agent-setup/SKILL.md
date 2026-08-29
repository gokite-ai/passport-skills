---
name: buyer-agent-setup
description: >-
  Give this agent its own signing identity as an autonomous buyer on Kite Passport:
  generate a secp256k1 runtime key, bind it to an agent record with the owner's
  passkey approval, and confirm the binding is active. Invoke before any other
  `kpass agent ...` command, and whenever a buyer-lane command fails with exit
  code 3 (no runtime key, binding pending, binding revoked) or `kpass agent status`
  reports anything other than an active binding. This is the gateway skill for the
  buyer-agent group -- discovery (buyer-find-seller) and the agreement lane
  (buyer-purchase) both require an active binding first.
user-invocable: true
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(kpass agent *)"
  - "Bash(kpass identifier *)"
  - "Bash(kpass onboarding *)"
  - "Bash(kpass wallet balance*)"
  - "Bash(kpass wallet address*)"
---

# Buyer Agent Setup

Establish the runtime identity an autonomous buyer signs with. Every `kpass agent ...` command that reaches Passport is signed by a secp256k1 **runtime key** held on this machine, and Passport only honors a signature from a key whose **binding** to an agent record is `active`. This skill takes a machine from nothing to an active binding: `init` -> `bind` -> `status`.

The owner is a human with a Passport passkey. Binding approval is theirs, not yours -- no CLI verb can approve a binding, so the skill's job is to surface the approval URL and wait.

## Step 0: Ensure the CLI is Installed — MANDATORY

Run the setup script before any `kpass` command — the script verifies the CLI is installed and recent enough, and a missing or stale binary surfaces as a confusing exit-3 ("no runtime key") rather than a clean "CLI not installed" error if you skip it.

```bash
bash <skill-directory>/scripts/setup.sh
```

Where `<skill-directory>` is the directory containing this SKILL.md file.

**If setup succeeds** (`status: "ok"`): proceed.
**If setup fails** (`status: "error"`): **STOP.** Report the error and the installation instructions to the owner. Do not search for the binary elsewhere.

The `kpass agent ...` verb tree ships in newer bundles than the human-facing `kpass` commands. If setup reports `ok` but `kpass agent init --output json` fails with a usage error naming an unknown command, the installed bundle predates the buyer lane — report that to the owner rather than trying alternative spellings.

## When to Use This Skill

- This agent has never acted as a buyer on this machine (no runtime key yet).
- Any `kpass agent ...` command returns exit code 3 with `runtime_key_required`, `runtime_not_found`, `runtime_pending`, `runtime_revoked`, `runtime_agent_mismatch`, or `runtime_signature_mismatch`.
- `kpass agent status --output json` reports `binding.status` of `unbound`, `pending`, or `revoked`.
- The owner switched the agent record this runtime should sign for.

Do **not** use this skill to register a human-driven spending agent — that is `kpass agent register` and the **`request-session`** skill in the `user` group. The two lanes are different identities: `agent register` mints an agent record under the owner's JWT, while this skill binds a *runtime key* to an agent record and signs with it thereafter.

## Where the State Lives — Read This Before Running `init`

Buyer state is **anchored to the project directory, not the home directory**. `kpass agent` searches upward from the working directory for a `.kite-passport/` directory; if none exists, `init` creates one at the git root (or at the working directory when there is no git root).

The consequence matters for unattended runs: **the same agent invoked from a different working directory can resolve to a different runtime key, or to none.** Pin the location explicitly for anything long-running:

| Mechanism | Effect |
|---|---|
| `--key-file <path>` | Relocates the key file alone, leaving `agent-state.json` in the role directory. Deployments mount a read-only key this way. |
| `KPASS_RUNTIME_KEY_FILE` | Same as `--key-file`, as an environment variable. `--key-file` wins when both are set. |
| Consistent working directory | Cheapest option: always run from the same project root. |

`--config-dir` **does not exist on the buyer surface** and is rejected rather than ignored: buyer state is anchored to `.kite-passport/`. Use `--key-file` to relocate the key.

## Running Multiple Buyer Agents on One Machine

Because buyer state is discovered upward from the working directory, the clean way to add a second (or third) buyer identity on the same machine is a **separate project directory with its own `.kite-passport/`** — not `--force` on the existing key. Each directory's key, binding, and owner JWT stay fully independent; nothing about the first agent is touched.

**Create the directory before authenticating, not after.** `authenticate-user`'s `login`/`signup` writes `config.json` (the owner JWT) to the nearest `.kite-passport/` too, using the same upward search. Authenticate first in a directory with no local `.kite-passport/` and the JWT lands wherever the search resolves instead — often the home directory — leaving you to move `config.json` into the new directory by hand afterward. Avoid that by ordering it this way:

1. `mkdir -p <project-dir>/.kite-passport` — this directory now wins upward discovery for everything run from inside it.
2. From inside `<project-dir>`, run **`authenticate-user`** for the owning account this new buyer belongs to (a new email, or an existing one not already bound to a runtime here).
3. Still from inside `<project-dir>`, run this skill's Steps 1–6 as normal. `kpass agent init` creates its own `runtime.key` here — it never touches the key in any other directory.

Every later command for this agent — `bind`, `status`, `buyer-find-seller`, `buyer-purchase` — must also run from inside `<project-dir>` (or with `--key-file`/`KPASS_RUNTIME_KEY_FILE` pointed at its key), or upward discovery resolves to a different `.kite-passport/` than the one you intended.

## Key Custody Rules

- **The private key is never printed by any command.** `init`, `key show`, and `status` report the EVM address, the JWK thumbprint, the `keyId` fragment, and the public key. If you find yourself about to echo key material into a log, a message, or a chat reply, you have the wrong field — report `address` and `thumbprint` instead.
- The key file is written with mode **0600** inside a **0700** directory, permissions applied before any bytes are written. Do not `chmod` it looser to make a container work; mount it with the right ownership instead.
- **`init --force` on a bound key is destructive.** Replacing a bound key orphans every agreement pinned to it — the old key can no longer sign for agreements that named it. The CLI refuses an overwrite without `--force` for exactly that reason. Only pass `--force` when the owner has said the existing identity is being abandoned. Wanting to run a second buyer agent alongside the first is **not** that case — see "Running Multiple Buyer Agents on One Machine" above instead.
- One key, one agent. If `bind` reports `runtime_agent_mismatch`, the owner pointed you at a different agent record; ask rather than re-initializing.

## Defaults (Do Not Ask the Owner Unless They Specify Otherwise)

| Setting | Default | Override |
|---|---|---|
| Output format | `--output json` | Always. Every command in this skill takes `--output json`; there is no human-readable fallback worth parsing. |
| Key location | Discovered `.kite-passport/runtime.key` | Only pass `--key-file` when the deployment mounts a key elsewhere. |
| Key material | Freshly generated | Only pass `--import-key` when the owner supplies an existing key to reuse. |
| Bind path | Mint-then-bind (`agent token create` → `bind --token`) | Falls back to direct (no `--token`) only if token mint ever requires step-up. |
| `--wait` on bind | Not used on the default mint-then-bind path (lands `active` immediately) | On the fallback direct path, for unattended runs — omit it if you would rather report the approval URL immediately and poll `status` later. |
| Bind poll interval / timeout | `3` seconds / `300` seconds | Raise `--timeout` when the owner will be slow to reach their passkey. Both are **integers in seconds** here. |

---

## Command Reference

Full argument tables, JSON envelopes, and the per-command error envelopes for `init`, `key show`, `bind`, `status`, and the owner-bootstrap commands (`kpass identifier claim`, `kpass onboarding submit`, `kpass onboarding status`, `kpass agent token create`) live in:

-> **`@references/commands.md`**

Read that file before running `bind` — the two bind paths behave differently and the difference is not visible in the flag names.

---

## The Bootstrap Flow

### Step 1: Create the Runtime Key

```bash
kpass agent init --output json
```

`status: "success"` carries `state_dir`, `key_file`, `address`, `thumbprint`, `key_id_fragment`, and `pubkey`. Record the `address` and `thumbprint` — the owner needs one of them to identify this runtime, and `thumbprint` is how Passport looks the runtime up.

Exit code 2 with a hint about orphaning means a key already exists at that path. Run `kpass agent status --output json` and compare the bound agent to the one you're setting up:

- **Same agent** — idempotent good news. Skip to Step 4; nothing left to do.
- **A different agent (or a different owner entirely)** — this is not a "force or leave it" choice. It usually means the owner wants a *second*, independent buyer identity, not to retire the first one. Default to setting up an isolated project directory for the new agent instead — see "Running Multiple Buyer Agents on One Machine" below — and only offer `--force` if the owner tells you the old identity is being abandoned.

### Step 2: Ask the Owner Which Agent to Bind To

You cannot discover the `uid` on your own — ask the owner. Before creating the agent, work through **`@references/owner-bootstrap.md`** steps 1–4: check onboarding status, claim the controller identifier, submit KYC/KYB, and poll briefly. Every account needs this before `agent create` will succeed — it refuses with `ErrRequiresIdentifier` / `ErrRequiresOnboarding` otherwise.

Once that resolves (`verified`, or already was), create the agent — either the owner does this through the Passport dashboard, or you run it directly on their already-authenticated `kpass` session (see `authenticate-user`):

```bash
kpass agent create --uid <slug> --kind buyer --output json
```

The `uid` becomes the tail of the DID permanently — neither can be changed afterwards, only replaced by a new agent. (The display name IS editable later; the uid is not.) A reference that does not resolve later, in Step 3, is exit code 4, not a retriable condition.

If `owner-bootstrap.md` Step 4 reports onboarding still `pending` past its poll budget, or Step 1/3 hit a `rejected` record, stop there and follow that file's guidance — do not attempt `agent create` early.

### Step 3: Bind the Key, and Surface the Approval

**Default path — mint then bind (`@references/owner-bootstrap.md` Step 6):**

```bash
kpass agent token create --agent <did-or-agt-id> --output json
kpass agent bind --agent <did-or-agt-id> --token <art_...> --output json
```

Token minting needs only the owner's plain JWT — no passkey step-up — so this lands `active` immediately in practice: no `--wait`, no `approval_url` to surface. Do this first.

**Fallback path — if token mint ever comes back requiring step-up** (defensive, not expected):

```bash
kpass agent bind --agent <did-or-agt-id> --wait --output json
```

Two outcomes, and the difference is the whole ceremony:

- **`status: "human_action_required"`, `binding: "pending"`** — the direct path. **The owner must approve it with their passkey; no CLI verb can.** How to tell them depends on what the envelope carries, and both cases happen:
  - **`approval_url` present** — surface it verbatim and say it needs their passkey. It is written only when the backend supplied one, so its absence is normal, not an error.
  - **`approval_url` absent** — give the navigation path and the identifying fields instead, because a bare "go approve it" is not actionable and an agent can carry **several** pending runtimes at once:

    > Approve this runtime in Passport: **the Passport web app → Agents → `<agent_did>` → Runtimes**, and approve the row shown as PENDING with thumbprint `<thumbprint>` (address `<address>`, runtime `<runtime_id>`).

    All four values are in the bind envelope. Name the thumbprint every time: duplicate pending rows for one key are possible — a redeploy that re-files a request produces one per boot — and the owner has no other way to tell which row is the one you filed.

    When the owner has several agents, or several pending runtimes to sort through, **Passport web app → Overview → "Awaiting runtime approval"** lists every pending runtime across every agent in one place — thumbprint, bind method, and key-verified state, with Approve/Reject inline — which is faster than opening this agent's own Runtimes tab.

  Re-surface the same message rather than re-running `bind`: each direct bind files a fresh request, which adds a row for the owner to disambiguate and does not speed anything up.

  Nothing this agent can do advances the binding; `--wait` polls every 3 seconds up to the timeout and returns the last observation.
- **`status: "success"`, `binding: "active"`** — the token path (`--token art_...`), where the owner pre-authorized the binding by minting a token. No approval URL, nothing to wait for.

A `--wait` that times out is **not a failure**: it exits 0 with `human_action_required` and the binding is still pending. Report the approval URL again and poll `status` later rather than re-running `bind`.

Any other `binding` value — `revoked`, for instance — is exit code 3. A revoked runtime cannot sign, and the recovery is a new key (`init --force`) plus a fresh binding, which the owner must agree to.

### Step 4: Confirm

```bash
kpass agent status --output json
```

`status` is a diagnostic and **always exits 0** — read the envelope, not the exit code. Setup is done when `status: "success"` and `binding.status: "active"`. Every other verdict comes with the `next_command` that advances it:

| `status` reports | Envelope `status` | What to do |
|---|---|---|
| no key present | `pending` | `kpass agent init --output json` (Step 1) |
| backend unreachable | `pending` | Retry `status`; this is a network condition, not an identity problem |
| `binding.status: "active"` | `success` | Done. Proceed to **`buyer-find-seller`**. |
| `binding.status: "pending"` | `human_action_required` | Re-surface the approval message from Step 3 — the URL when there was one, otherwise the navigation path plus the thumbprint — and wait |
| `binding.status: "revoked"` | `pending` | The owner revoked this runtime. Ask before running `init --force`. |
| `binding.status: "unbound"` | `pending` | `kpass agent bind --agent <did-or-agt-id> --output json` (Step 3) |

### Step 5: Check Testnet Funding

```bash
kpass wallet balance --output json
```

This environment settles escrow on **Arc testnet** (`arc`) — the only chain a dev backend serves. Find the `USDC` entry in `assets[]`, then find its `arc` row inside `chains[]`. If that row is missing or its `amount` is `0`, this agent cannot fund any purchase yet. Tell the owner:

> This buyer agent is active, but its wallet has no test USDC on Arc yet — funding a purchase later will fail without it. Kite's own `faucet drop` cannot fund Arc, so get free test USDC directly from Circle:
> 1. Open https://faucet.circle.com/
> 2. Select token **USDC**
> 3. Select the **Arc** testnet network
> 4. Paste this wallet address: `<address from kpass wallet address --chain arc --output json>`
> 5. Submit — Circle's faucet typically drops **~20 USDC** per request, not a fixed amount to promise precisely — then re-run `kpass wallet balance --output json` to confirm it arrived.

This is informational, not a blocker — funding only matters once the owner actually proposes a purchase. **`buyer-purchase`** Step 4 checks again, and blocks, right before funding.

### Step 6: Hand Off

An active binding is the prerequisite, not the whole preparation. Before this agent can propose an agreement it must also pin the coordination persona card — that is `kpass agent card fetch --pin`, covered by the **`buyer-find-seller`** skill. Go there next.

---

## Minimal Example

```bash
bash <skill-directory>/scripts/setup.sh
kpass agent init --output json
kpass agent bind --agent did:kite:example-seller-owner-agent --wait --output json
kpass agent status --output json
```

Between the second and third commands, the owner opens the `approval_url` from the `bind` envelope and approves with their passkey.

---

## Error Handling

The buyer lane uses the standard table extended with two agent-plane codes (7 and 8). Codes 7 and 8 do not appear on the human-facing `kpass` surface.

| Exit | Meaning | What it looks like here | Recovery |
|---|---|---|---|
| 0 | Success, or human action required | `status: "success"` / `"human_action_required"` / `"pending"` | Read the envelope `status`, not the exit code. |
| 1 | Network / general error | `network error: ...`; backend unreachable in `status` | Retry after a pause. `status` still exits 0 and reports `backend.reachable: false`. |
| 2 | Usage error | `--agent is required.`; a key already exists without `--force` | Fix the flag. An existing key is usually a reason to check `status`, not to force. |
| 3 | Auth error | `runtime_key_required`, `runtime_not_found`, `runtime_pending`, `runtime_revoked`, `runtime_agent_mismatch`, `runtime_signature_mismatch`; a binding that is neither active nor pending | Work back through this skill: no key -> Step 1; unbound -> Step 3; pending -> wait for the owner; revoked or mismatched -> ask the owner before re-keying. |
| 4 | Not found | The `--agent` reference does not resolve | Ask the owner for the correct DID or `agt_` id. Do not retry with guesses. |
| 5 | Rate limited | `rate_limited` | Wait 30 seconds, then retry. |
| 6 | Forbidden | Authenticated but not entitled | Not expected during setup. If it appears, report it — the identity exists but is not allowed to do what was asked. |
| 7 | Conflict | Agreement-plane state moved under you | Not expected during setup. |
| 8 | Protocol | A **local** refusal: signing or canonicalization failed on this machine and nothing was sent | Do not retry the same bytes. Report it; this is a bug or a corrupt key file, not a transient fault. |

**Error envelope fields:** `error` (the raw message), `hint` (recovery guidance), `next_command` (the command that advances the situation), plus optional `error_code` (prefer this for programmatic matching), `details`, and `retriable`. `retriable` is **absent** rather than `false` when no server ruled on the request — treat absence as "nobody said", not as "no".

### Specific Scenarios

**`runtime key already exists` (exit 2):** A key is present at the resolved path. Run `kpass agent status --output json` first and compare the bound agent to the one you're setting up. **Same agent, already active:** setup is complete, nothing needs doing. **A different agent or owner:** that's the normal signature of wanting a second buyer identity, not a reason to `--force` — set up an isolated project directory instead (see "Running Multiple Buyer Agents on One Machine"). Only `--force` if the owner explicitly says the old identity is being abandoned.

**Binding stuck at `pending`:** Expected, and not an error. The owner has not approved it yet, or has not finished the passkey ceremony. Re-surface the approval message — including the thumbprint, so they can pick the right row. Do not re-run `bind` in a loop: each direct bind files a fresh request, and a key with several pending rows is harder to approve, not easier. It also outlives the moment — an agent that re-filed on every restart can leave a column of duplicate rows behind, and once approved they all count, which makes the key ambiguous to counterparties.

**`runtime_revoked` (exit 3):** The owner revoked this runtime in Passport, deliberately. The key is dead for signing. Ask before running `init --force`: a new key orphans agreements pinned to the old one. (The dashboard now shows an impact warning at the point of the revoke click when the runtime has active or pending obligations — this agent has no visibility into that ceremony.)

**Commands work from one directory but not another:** Buyer state is discovered from the working directory upward. Pin the key with `--key-file` or `KPASS_RUNTIME_KEY_FILE`, or always run from the same project root.

---

## Commands That DO NOT Exist

Do not attempt any of the following. They will fail:

- `kpass agent init --config-dir` — the buyer surface rejects `--config-dir`; buyer state is anchored to `.kite-passport/`. Use `--key-file`.
- `kpass agent key` (without a sub-command) — the only child is `show`.
- `kpass agent key rotate` / `kpass agent key export` / `kpass agent key delete` — none exist. Re-keying is `init --force`.
- `kpass agent unbind` / `kpass agent bind --revoke` — revocation is an owner action in Passport, not a CLI verb.
- `kpass agent bind --approve` / `kpass agent approve` — binding approval is a passkey ceremony. No CLI verb can approve one.
- `kpass agent bind --poll-interval 3s` — `--poll-interval` and `--timeout` on `bind` are **integers in seconds** (`--timeout 300`), unlike the Go durations (`10m`) used elsewhere in the tree.
- `kpass agent login` / `kpass agent signup` / `kpass agent me` — the buyer lane has no human-account verbs. Those live on the human-facing `kpass` surface, outside this group's permission glob.
- `kpass agent status --agent-id ...` — `status` takes no selector; it reports on the resolved local key.
- Any command with `--json` — the flag is `--output json` (two separate tokens).

---

## Input Validation Checklist

Before running any command, verify:

1. **`--agent`**: came from the owner, not from you. A DID (`did:kite:...`), an `agt_...` id, or a uid. Never fabricate one.
2. **`--token`**: the `art_...` value from `kpass agent token create` (this skill mints it itself on the default path) — or one the owner minted directly. It starts with `art_`. Do not pass an empty `--token` — omit the flag only to take the fallback direct path.
3. **`--import-key`**: a PATH to a file holding the key, or `-` to read it from stdin. Never the key itself — a key passed on the command line reaches shell history, the process table and this transcript, and cannot be un-leaked. The CLI refuses inline material.
4. **`--force`**: only with explicit owner agreement, on the record, that the existing identity is being abandoned.
5. **`--poll-interval` / `--timeout`**: bare integers (seconds), not durations.

---

## Cross-Skill References

- **The JWT this skill assumes throughout:** the **`authenticate-user`** skill — run it first if `owner-bootstrap.md`'s commands return exit code 3.
- **Next, to find a counterparty and pin the persona card:** the **`buyer-find-seller`** skill.
- **Then, to run an agreement end to end:** the **`buyer-purchase`** skill.
- **The seller side of the same protocol:** the **`seller-agent-setup`** skill (`kagent`), a separate binary and a separate identity.
- **Human-driven spending sessions (not this lane):** the **`request-session`** skill in the `user` group.
- **Full wallet reference (balance, address, faucet) beyond Step 5's minimal usage:** the **`wallet-send`** skill in the `user` group.
- **Group contract (permission glob, envelope, exit codes):** [`buyer-agent/README.md`](../buyer-agent/README.md).
