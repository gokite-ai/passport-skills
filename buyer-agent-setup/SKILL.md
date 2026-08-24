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

## Key Custody Rules

- **The private key is never printed by any command.** `init`, `key show`, and `status` report the EVM address, the JWK thumbprint, the `keyId` fragment, and the public key. If you find yourself about to echo key material into a log, a message, or a chat reply, you have the wrong field — report `address` and `thumbprint` instead.
- The key file is written with mode **0600** inside a **0700** directory, permissions applied before any bytes are written. Do not `chmod` it looser to make a container work; mount it with the right ownership instead.
- **`init --force` on a bound key is destructive.** Replacing a bound key orphans every agreement pinned to it — the old key can no longer sign for agreements that named it. The CLI refuses an overwrite without `--force` for exactly that reason. Only pass `--force` when the owner has said the existing identity is being abandoned.
- One key, one agent. If `bind` reports `runtime_agent_mismatch`, the owner pointed you at a different agent record; ask rather than re-initializing.

## Defaults (Do Not Ask the Owner Unless They Specify Otherwise)

| Setting | Default | Override |
|---|---|---|
| Output format | `--output json` | Always. Every command in this skill takes `--output json`; there is no human-readable fallback worth parsing. |
| Key location | Discovered `.kite-passport/runtime.key` | Only pass `--key-file` when the deployment mounts a key elsewhere. |
| Key material | Freshly generated | Only pass `--import-key` when the owner supplies an existing key to reuse. |
| Bind path | Direct (no `--token`) | Only pass `--token` when the owner minted an `art_...` bind token. |
| `--wait` on bind | On, for unattended runs | Omit it if you would rather report the approval URL immediately and poll `status` later. |
| Bind poll interval / timeout | `3` seconds / `300` seconds | Raise `--timeout` when the owner will be slow to reach their passkey. Both are **integers in seconds** here. |

---

## Command Reference

Full argument tables, JSON envelopes, and the per-command error envelopes for `init`, `key show`, `bind`, and `status` live in:

-> **`@references/commands.md`**

Read that file before running `bind` — the two bind paths behave differently and the difference is not visible in the flag names.

---

## The Bootstrap Flow

### Step 1: Create the Runtime Key

```bash
kpass agent init --output json
```

`status: "success"` carries `state_dir`, `key_file`, `address`, `thumbprint`, `key_id_fragment`, and `pubkey`. Record the `address` and `thumbprint` — the owner needs one of them to identify this runtime, and `thumbprint` is how Passport looks the runtime up.

Exit code 2 with a hint about orphaning means a key already exists at that path. That is usually good news: skip to Step 3 and check whether it is already bound. Only re-run with `--force` if the owner has explicitly abandoned the old identity.

### Step 2: Ask the Owner Which Agent to Bind To

You cannot discover this. The owner creates the agent record and tells you which one this runtime represents. Accept any of: a `did:kite:...` DID, an `agt_...` id, or a uid.

If the owner has not created an agent record yet, stop and say so — `bind` against a nonexistent agent is exit code 4, not a retriable condition. What they run is either the Passport dashboard or, with their own login:

```bash
kpass agent create --uid <slug> --kind buyer --output json
```

That is the owner's command, not yours: it authenticates with their JWT, and the `uid` becomes the tail of the DID permanently — neither can be changed afterwards, only replaced by a new agent. (The display name IS editable later; the uid is not.) Do not offer to run it against a token you happen to hold.

### Step 3: Bind the Key, and Surface the Approval

```bash
kpass agent bind --agent <did-or-agt-id> --wait --output json
```

Two outcomes, and the difference is the whole ceremony:

- **`status: "human_action_required"`, `binding: "pending"`** — the normal direct path. The envelope carries `approval_url`. **Surface that URL to the owner verbatim and tell them it needs their passkey.** Nothing this agent can do advances the binding; `--wait` polls every 3 seconds up to the timeout and returns the last observation.
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
| `binding.status: "pending"` | `human_action_required` | Surface `approval_url` from the earlier `bind` output again and wait |
| `binding.status: "revoked"` | `pending` | The owner revoked this runtime. Ask before running `init --force`. |
| `binding.status: "unbound"` | `pending` | `kpass agent bind --agent <did-or-agt-id> --output json` (Step 3) |

### Step 5: Hand Off

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

**`runtime key already exists` (exit 2):** A key is present at the resolved path. Run `kpass agent status --output json` first — if it is already bound and active, setup is complete and nothing needs doing. Only `--force` if the owner is abandoning that identity.

**Binding stuck at `pending`:** Expected, and not an error. The owner has not opened the approval URL, or has not finished the passkey ceremony. Re-surface the URL. Do not re-run `bind` in a loop — each direct bind mints a fresh nonce and a fresh approval, which makes it harder for the owner to know which link is live.

**`runtime_revoked` (exit 3):** The owner revoked this runtime in Passport, deliberately. The key is dead for signing. Ask before running `init --force`: a new key orphans agreements pinned to the old one.

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
2. **`--token`**: only when the owner minted one; it starts with `art_`. Do not pass an empty `--token` — omit the flag to take the direct path.
3. **`--import-key`**: a PATH to a file holding the key, or `-` to read it from stdin. Never the key itself — a key passed on the command line reaches shell history, the process table and this transcript, and cannot be un-leaked. The CLI refuses inline material.
4. **`--force`**: only with explicit owner agreement, on the record, that the existing identity is being abandoned.
5. **`--poll-interval` / `--timeout`**: bare integers (seconds), not durations.

---

## Cross-Skill References

- **Next, to find a counterparty and pin the persona card:** the **`buyer-find-seller`** skill.
- **Then, to run an agreement end to end:** the **`buyer-purchase`** skill.
- **The seller side of the same protocol:** the **`seller-agent-setup`** skill (`kagent`), a separate binary and a separate identity.
- **Human-driven spending sessions (not this lane):** the **`request-session`** skill in the `user` group.
- **Group contract (permission glob, envelope, exit codes):** [`buyer-agent/README.md`](../buyer-agent/README.md).
