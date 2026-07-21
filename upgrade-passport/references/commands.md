# Upgrade Passport — Command Reference

Full per-command reference for the `upgrade-passport` skill. SKILL.md carries the trigger logic, the Auto-Upgrade Behavior rules, the Quick Decision Flow, the condensed Error Handling table, and the Commands That DO NOT Exist list; this file has the command-level detail (flags, exit codes, and every JSON shape), the full Error Handling table, the Behavior Knobs table, and the Input Validation Checklist. Worked end-to-end examples live in `examples.md`.

---

## `upgrade --check` — is the CLI up to date?

Read-only. No filesystem mutation, minimal network: just fetches the channel pointer and compares.

```bash
kpass upgrade --check --output json
```

Optional flags:

| Flag | Purpose |
|---|---|
| `--channel <c>` | Peek at a different channel (`latest` or `stable`) without committing |
| `--output json` | Always pass |

### Exit codes

| Exit code | Meaning |
|---|---|
| 0 | Up to date (or pinned ahead) |
| 10 | Behind — a newer bundle is available |
| 1 | Network error or unreadable `version.json` |
| 4 | Channel not deployed in this environment (e.g. `--channel stable` against prod where stable doesn't exist yet) |

The exit code is the most reliable signal. Shell consumers can do `if ! kpass upgrade --check; then …`.

### Output — current (exit 0)

```json
{
  "_version": "1",
  "status": "success",
  "current_bundle": 22,
  "latest_bundle": 22,
  "channel": "latest",
  "behind": false,
  "hint": "kpass is up to date (bundle 22, channel latest).",
  "next_command": ""
}
```

### Output — behind (exit 10)

```json
{
  "_version": "1",
  "status": "success",
  "current_bundle": 21,
  "latest_bundle": 22,
  "channel": "latest",
  "behind": true,
  "hint": "kpass bundle 22 available (current: 21, channel latest). Run: kpass upgrade",
  "next_command": "kpass upgrade"
}
```

Note `status: "success"` even when behind — the *check* succeeded; the `behind` boolean and exit code 10 carry the world-state signal.

`next_command` is platform-aware: on Windows it reads `"irm https://cli.gokite.ai/install.ps1 | iex"`. Use it verbatim when prompting the user.

---

## `upgrade` — apply the latest bundle on the install's channel

```bash
kpass upgrade --output json
```

Optional flags:

| Flag | Purpose |
|---|---|
| `--channel <c>` | Switch sticky channel (`latest` or `stable`) and upgrade |
| `--force` | Reinstall even if already on the latest bundle |
| `--output json` | Always pass |

### Output — POSIX success (exit 0)

```json
{
  "_version": "1",
  "status": "success",
  "from_bundle": 21,
  "to_bundle": 22,
  "channel": "latest",
  "cli_version": "1.3.18",
  "ksearch_version": "1.0.4",
  "skills_version": "1.1.8",
  "hint": "Upgraded to bundle 22.",
  "next_command": ""
}
```

The CLI atomically swaps `~/.kpass/` to the new bundle. The next time the user runs `kpass <anything>`, they get the new binary.

### Output — already current (exit 0)

```json
{
  "_version": "1",
  "status": "success",
  "current_bundle": 22,
  "target_bundle": 22,
  "channel": "latest",
  "behind": false,
  "hint": "kpass is up to date (bundle 22, channel latest).",
  "next_command": ""
}
```

### Output — Windows manual upgrade required (exit 0)

```json
{
  "_version": "1",
  "status": "human_action_required",
  "action": "manual_upgrade",
  "current_bundle": 21,
  "target_bundle": 22,
  "channel": "latest",
  "install_command": "irm https://cli.gokite.ai/install.ps1 | iex",
  "hint": "kpass upgrade is not supported on Windows yet. Run: irm https://cli.gokite.ai/install.ps1 | iex",
  "next_command": "irm https://cli.gokite.ai/install.ps1 | iex"
}
```

**Critical Windows handling:**

- `status: "human_action_required"` means the user must take an action. Exit code is 0 — *not* an error.
- **Show `install_command` to the user verbatim. Do not auto-execute it.** PowerShell's `irm | iex` runs arbitrary code; the user must consent and run it themselves from their terminal.
- After the user runs the install command, they should re-run their original task in a fresh shell.

### Output — not installed via install.sh (exit 1)

```json
{
  "_version": "1",
  "status": "error",
  "error": "kpass was not installed via install.sh.",
  "hint": "Reinstall: curl -fsSL https://cli.gokite.ai/install.sh | bash",
  "next_command": ""
}
```

Direct the user to the install script (POSIX) or PowerShell installer (Windows). After install, they can run `kpass upgrade` going forward.

---

## `upgrade --bundle N` — pin to a specific bundle

```bash
kpass upgrade --bundle 22 --output json
```

| Behavior | Detail |
|---|---|
| Channel | Preserved from `version.json`; pinning never silently changes channels |
| Mutually exclusive | `--bundle` cannot be combined with `--channel` (exit 2) |
| Downgrade allowed | Pinning to a bundle lower than current works without prompts; the atomic swap rolls back if the target binary fails to run |
| Manifest 404 | Exit 4: `Bundle N not found at <base>` |

Use cases:
- Reproducing a known-good environment for debugging.
- Reverting a flaky upgrade without waiting for a new release.
- CI: pin to a specific bundle for deterministic builds.

---

## Error Handling

| Exit Code | Meaning | Pattern | Recovery |
|---|---|---|---|
| 0 | Success — applied, current, or `human_action_required` (Windows) | `status: success` or `human_action_required` | Read the envelope; for `human_action_required`, surface `install_command` to the user. |
| 1 | Network / IO / version.json missing | `Reinstall: curl …` hint | Check connectivity; if version.json is missing, run the install script. |
| 2 | Bad flag combination | `--check cannot be combined with …` etc. | Drop the offending flag. See Defaults. |
| 4 | Channel or bundle not found | `Channel "stable" is not available at <base>` or `Bundle N not found` | Try a different `--channel` or correct the `--bundle` number. |
| 10 | `--check` reports behind | `kpass bundle <N> available …` | Auto-upgrade per Rule 1 (POSIX) or surface the install command per Rule 2 (Windows). Only ask the user first if `KPASS_AUTO_UPGRADE=0`. |

Common pitfalls:
- Treating exit 10 as a failure. It's a *signal*, not an error. The check itself succeeded.
- Calling `kpass upgrade` on Windows expecting the swap to happen. It won't — surface `install_command` instead.
- Looping `kpass upgrade --check` in a tight cycle. The cache only refreshes once per 24h; rapid polling won't see new data.
- Asking the user "want me to upgrade?" when `KPASS_AUTO_UPGRADE=0` is NOT set. The default is auto-upgrade on POSIX after the current task; asking for permission first is itself a deviation from the spec.
- Auto-upgrading mid-task (mid-payment, mid-checkout, mid-OTP). Apply Rule 3 — defer until the active flow finishes cleanly.

---

## Behavior Knobs

| Env var | Value | Effect |
|---|---|---|
| `KPASS_AUTO_UPGRADE` | `1` (or unset) | **Default.** Auto-upgrade enabled. Agent applies Rule 1 (POSIX) or Rule 2 (Windows) when `update_available` appears, no permission prompt. |
| `KPASS_AUTO_UPGRADE` | `0` | Auto-upgrade disabled. Detection still happens; agent surfaces the update info and asks the user before running `kpass upgrade`. The auto-apply step is gated. |
| `KPASS_NO_UPDATE_CHECK` | `1` | All update awareness suppressed: `update_available` field omitted, stderr notice silenced, background cache refresh skipped. The auto-upgrade rules become moot because the field never appears. |
| `CI` | `1` (any non-empty) | Same suppression as `KPASS_NO_UPDATE_CHECK`. Set automatically by most CI runners; the CLI defers to that convention. |

If the user complains the `update_available` field "stopped appearing," check whether `KPASS_NO_UPDATE_CHECK` or `CI` is set in their shell.

If the user complains "kpass keeps upgrading without asking," set `KPASS_AUTO_UPGRADE=0` to require confirmation, or `KPASS_NO_UPDATE_CHECK=1` to silence detection entirely.

---

## Input Validation Checklist

Before running any command, verify:

1. **Platform context**: if running on Windows, plan to surface `install_command` to the user — never auto-execute it.
2. **`--bundle <N>`**: must be a positive integer, not a semver. `kpass upgrade --bundle 1.3.18` will fail (use the bundle number instead, e.g. 22).
3. **`--channel <c>`**: must be `latest` or `stable`. `staging` is an environment, not a channel.
4. **`--check` + `--bundle` / `--force`**: rejected (exit 2). `--check` is read-only.
5. **`--bundle` + `--channel`**: rejected (exit 2). They are mutually exclusive.
