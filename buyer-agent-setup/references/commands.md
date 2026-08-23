# Buyer Agent Setup — Command Reference

Every command takes `--output json`. All flags are long-form; there are no single-letter shorthands anywhere in the `kpass agent` tree.

## Shared Flags

Present on every command in this skill:

| Flag | Type | Default | Notes |
|---|---|---|---|
| `--output json` | string | (human text) | Required. JSON mode is exactly `--output json`; `--output=json` also works. |
| `--base-url <url>` | string | `https://passport.prod.gokite.ai` | Persistent root flag. Overridden by `KITE_PASSPORT_BASE_URL`. Only pass it when the owner names a backend. |
| `--no-interactive` | bool | `false` | Never prompt; fail if a required flag is missing. Pass it in unattended runs. |
| `--key-file <path>` | string | `<state-dir>/runtime.key` | Overrides `KPASS_RUNTIME_KEY_FILE`. Relocates the key alone — `agent-state.json` stays in the role directory. |

`--config-dir` is **not registered on the buyer surface**. Buyer state resolves by searching upward from the working directory for `.kite-passport/`; when none exists, `init` creates one at the git root, or at the working directory if there is no git root.

---

## `kpass agent init`

Generate (or import) the secp256k1 runtime key.

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--import-key <file\|->` | string | `""` | no | Import instead of generating. A PATH to a file holding the key, or `-` for stdin. Inline key material is REFUSED: argv reaches shell history, the process table and agent transcripts. |
| `--force` | bool | `false` | no | Overwrite an existing runtime key. Destructive — see below. |

```bash
kpass agent init --output json
```

Success envelope (`status: "success"`):

```
{
  "_version": "1",
  "status": "success",
  "role": "buyer",
  "state_dir": "/path/to/project/.kite-passport",
  "key_file": "/path/to/project/.kite-passport/runtime.key",
  "imported": false,
  "address": "0x...",
  "thumbprint": "...",
  "key_id_fragment": "...",
  "pubkey": "...",
  "key_file_override": false,
  "hint": "Runtime key ready. Bind it to an agent so Passport recognizes this runtime.",
  "next_command": "kpass agent bind --agent <did-or-agt-id> --output json"
}
```

Field notes:

- `key_file_override` is `true` when the path came from `--key-file` or `KPASS_RUNTIME_KEY_FILE` rather than from the discovered state directory.
- `imported` distinguishes a generated key from an `--import-key` one.
- No private key material appears in the envelope, by design.

**Existing key, no `--force`** — exit 2, with the hint that replacing a bound key orphans every agreement pinned to it, and `next_command: "kpass agent key show --output json"`. Treat this as "check `status` first", not as an obstacle to force through.

**File mechanics:** the key file is created 0600 (permissions applied before any bytes are written), in a 0700 directory, via an exclusive temp file plus rename — so a pre-placed file or symlink at the target is never reused. `agent-state.json` (the card pin, and later the stream cursor) is written the same way and stays in the role directory even when `--key-file` moves the key.

---

## `kpass agent key show`

Report the public half of the runtime key. Offline — it does not reach the backend.

No flags beyond the shared ones.

```bash
kpass agent key show --output json
```

```
{
  "_version": "1",
  "status": "success",
  "address": "0x...",
  "key_id": "",
  "key_id_fragment": "...",
  "thumbprint": "...",
  "pubkey": "...",
  "key_file": "/path/to/.kite-passport/runtime.key",
  "role": "buyer",
  "hint": "keyId is <agent DID>#<fragment>; the DID is filled in once this key is bound to an agent.",
  "next_command": "kpass agent status --output json"
}
```

`key_id` is **always the empty string here** — this verb is offline and the DID half of the `keyId` is only known once the key is bound. Read the bound `key_id` from `bind` or `status` instead. The private key is never printed.

---

## `kpass agent bind`

Register the runtime public key against an agent record.

| Flag | Type | Default | Required | Notes |
|---|---|---|---|---|
| `--agent <ref>` | string | `""` | **yes** | DID, `agt_...` id, or uid. Empty is exit 2. |
| `--token <art_...>` | string | `""` | no | Owner-minted bind token. Its presence selects the token path. |
| `--wait` | bool | `false` | no | Poll until the binding becomes active. |
| `--env <label>` | string | `""` | no | Environment label recorded on the binding (e.g. `prod`, `staging`). |
| `--software <id>` | string | this binary and version | no | Software identifier recorded on the binding. |
| `--device <text>` | string | `""` | no | Device description recorded on the binding. |
| `--poll-interval <seconds>` | **int** | `3` | no | Seconds between polls when `--wait` is set. Values below 1 are coerced to the default. |
| `--timeout <seconds>` | **int** | `300` | no | Seconds before `--wait` gives up. Values below 1 are coerced to the default. |

`--poll-interval` and `--timeout` on `bind` are bare integers in seconds. Every other `--timeout` in the `kpass agent` tree is a Go duration (`10m`, `30s`) — this one command is the exception.

`--agent` is required on both paths; `--token` does not replace it.

### The two paths

| Path | Trigger | Mechanism | Resulting `binding` |
|---|---|---|---|
| **Direct** | `--token` omitted | The CLI takes a bind nonce from Passport, proves possession of the key against it, and registers | Always `pending` until the owner approves |
| **Token** | `--token art_...` | The owner pre-authorized by minting a token; the CLI proves possession against the token | Can be `active` immediately |

The agent reference is resolved to its storage id before the proof is built, because the direct path's proof commits to the agent id the server reads from the request path.

```bash
kpass agent bind --agent did:kite:example-agent --wait --output json
```

Envelope (same data map on every outcome):

```
{
  "_version": "1",
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
  "next_command": "kpass agent status --output json"
}
```

| `binding` | Envelope `status` | Exit | Meaning |
|---|---|---|---|
| `active` | `success` | 0 | The key can sign for the agent now. |
| `pending` | `human_action_required` | 0 | Awaiting the owner's passkey approval. `approval_url` is present when Passport issued one. |
| anything else (e.g. `revoked`) | `error` | **3** | `Runtime <id> is "<status>", which cannot sign for agent <id>.` |

`approval_url` appears only when Passport issued one, and is also appended to the hint. **Nothing in this CLI can approve a binding.**

`--wait` polls at a **fixed** interval (no backoff) until the deadline, treating a not-yet-visible runtime as "keep polling" rather than an error. A timeout is **not** an error: the command returns the last observation, so a still-pending binding exits 0 with `human_action_required`.

---

## `kpass agent status`

The diagnostic. **Always exits 0** — the verdict is in the envelope `status` and `next_command`, never in the exit code.

No flags beyond the shared ones. No selector: it reports on the locally resolved key.

```bash
kpass agent status --output json
```

```
{
  "_version": "1",
  "status": "success",
  "role": "buyer",
  "backend": {
    "url": "https://passport.prod.gokite.ai",
    "reachable": true,
    "status": null,
    "error": null,
    "env": "prod"
  },
  "key": {
    "present": true,
    "key_file": "/path/to/.kite-passport/runtime.key",
    "override": false,
    "thumbprint": "...",
    "address": "0x...",
    "key_id_fragment": "...",
    "pubkey": "..."
  },
  "binding": {
    "bound": true,
    "status": "active",
    "agent_id": "agt_...",
    "agent_did": "did:kite:...",
    "agent_name": "...",
    "verified_tier": "...",
    "agent_address": "0x...",
    "runtime_id": "...",
    "bind_method": "direct",
    "key_id": "did:kite:...#<fragment>"
  },
  "state_dir": "/path/to/project/.kite-passport",
  "hint": "...",
  "next_command": ""
}
```

`binding.status` is the server's runtime status (`active`, `pending`, `revoked`) or the literal `unbound` when Passport knows no runtime for this key. Sub-objects carry an `error` member instead of the detail fields when that half could not be read.

Verdict mapping — the condition is checked in this order, so an unreachable backend masks the binding state:

| Condition | Envelope `status` | `next_command` |
|---|---|---|
| No key present | `pending` | `kpass agent init --output json` |
| Backend unreachable | `pending` | `kpass agent status --output json` |
| `binding.status: "active"` | `success` | `""` |
| `binding.status: "pending"` | `human_action_required` | `kpass agent status --output json` |
| `binding.status: "revoked"` | `pending` | `kpass agent init --force --output json` |
| Otherwise (unbound) | `pending` | `kpass agent bind --agent <did-or-agt-id> --output json` |

Because `status` never fails, it is the right command to run first in any recovery: it distinguishes "no key" from "unreachable backend" from "the owner has not approved yet" without risking a second side effect.

---

## Error Envelope

Errors print to stdout in JSON mode, with this shape:

```
{
  "_version": "1",
  "status": "error",
  "error": "<the raw message>",
  "hint": "<recovery guidance>",
  "next_command": "<the command that advances this>",
  "error_code": "runtime_revoked",
  "details": { },
  "retriable": false
}
```

- `error_code` is omitted when the CLI has no machine-readable classification. Prefer it over message matching when it is present.
- `details` is omitted when empty.
- `retriable` is a three-state field: `true` (the server said retry), `false` (the server said no), or **absent** (nobody ruled — every local refusal and every transport failure). Absence is not `false`.
- In non-JSON mode the message goes to stderr with `Hint: ...` on a second line. Always pass `--output json`.

Exit codes relevant to setup: 0 success or human action required, 1 network, 2 usage, 3 auth (the whole `runtime_*` family), 4 not found, 5 rate limited, 6 forbidden, 7 conflict, 8 local protocol refusal (nothing was sent — do not retry the same bytes).
