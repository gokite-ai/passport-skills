---
name: upgrade-passport
description: >-
  Detect and apply kpass CLI updates automatically. Invoke whenever a
  `kpass --output json` response carries an `update_available` field, or when
  the user asks to "update kpass", "upgrade", "is my CLI up to date?". On
  POSIX (macOS, Linux), the agent SHOULD upgrade automatically after the
  user's current task completes — no permission prompt needed. On Windows,
  the agent surfaces the manual install command for the user to run; the
  agent must NOT auto-execute PowerShell install scripts. Auto-upgrade is on
  by default; `KPASS_AUTO_UPGRADE=1` is the explicit form, `=0` disables it
  (agent surfaces the update to the user but doesn't apply it without
  confirmation). `KPASS_NO_UPDATE_CHECK=1` disables detection entirely.
user-invocable: true
allowed-tools:
  - "Bash(kpass upgrade*)"
  - "Bash(kpass --version*)"
---

# Upgrade Passport

Update the `kpass` CLI in place (POSIX) or surface the right manual-install command (Windows). Also the place to interpret the optional `update_available` field that may appear in any `kpass --output json` envelope.

> **Reference files** (read when you need exact detail):
> - `@references/commands.md` — full command reference: every flag, exit code, and JSON output shape for `upgrade --check`, `upgrade`, and `upgrade --bundle N`, plus the full Error Handling table, Behavior Knobs, and the Input Validation Checklist.
> - `@references/examples.md` — worked examples covering POSIX auto-upgrade, the manual-check flow, Windows manual upgrade, channel switching, and when to skip/defer.

## When to Use This Skill

**Automatic triggers (no user prompt needed):**

- A prior `kpass <anything> --output json` response included an `update_available` field. Auto-upgrade on POSIX; surface the install command on Windows. See **Auto-Upgrade Behavior** below for the exact rules.
- The user's current task just finished and you want to opportunistically refresh the CLI before the next command.

**User-driven triggers:**

- The user asks: "update kpass", "upgrade", "is there a newer version?", "what version am I on?"
- The user wants to switch channels (`latest` ↔ `stable`) or pin a specific bundle.

**Diagnostic triggers:**

- Before troubleshooting another command's failure, confirm the CLI is current — running an old CLI against a newer backend is a common root cause.

## When NOT to Use This Skill

- For a **first-time install**: this skill assumes `kpass` is already installed via `install.sh` / `install.ps1`. If not, point the user at the installer:
  - macOS / Linux: `curl -fsSL https://cli.gokite.ai/install.sh | bash`
  - Windows: `irm https://cli.gokite.ai/install.ps1 | iex`
- For installing or updating **passport-skills only**. Skills are upgraded together with the CLI as part of a single bundle.
- For switching environments (prod ↔ staging). That's a fresh install against the other domain, not an upgrade.

## Prerequisites

- `kpass` was installed via the install script. The skill detects this from `~/.kpass/version.json`. If that file is missing, `kpass upgrade` exits 1 with a reinstall hint and you should follow it.
- No authentication required. Upgrade is a local + CDN operation; it doesn't talk to the Kite backend.

## Defaults (Do Not Ask the User Unless They Specify Otherwise)

| Setting | Default value | Override |
|---|---|---|
| Output format | `--output json` | Always use JSON output. Never omit this flag. |
| Channel | Sticky from the install (`latest` for most users) | Only pass `--channel <c>` if the user explicitly asks to switch. |
| Bundle | Resolved from the channel pointer | Only pass `--bundle <N>` if the user explicitly pins to a number. |
| Force | Off | Only pass `--force` if the user explicitly asks to reinstall the same bundle. |
| Auto-execute on Windows | **Never** | The Windows upgrade flow returns an `install_command` string. Show it to the user; they run it themselves. |

---

## Auto-Upgrade Behavior (Read This First)

Every `kpass <command> --output json` may include this optional top-level field:

```json
"update_available": {
  "current_bundle":  21,
  "latest_bundle":   22,
  "channel":         "latest",
  "install_command": "kpass upgrade"
}
```

When you see it, follow these rules **without asking the user for permission first** (unless `KPASS_AUTO_UPGRADE=0` is set — see overrides below).

### Rule 1 — POSIX (macOS, Linux): auto-upgrade after the current task

**Detection:** `update_available.install_command` equals `"kpass upgrade"`.

**Action:** Once the user's current task completes (a payment finishes, a search returns results, etc.), invoke this skill and run `kpass upgrade --output json` immediately. After the upgrade succeeds, briefly tell the user what was upgraded:

> Upgraded kpass: bundle 21 → 22 (CLI 1.3.18, ksearch 1.0.4, skills 1.1.8).

If the upgrade fails, surface the error and continue with whatever else the user was doing — don't abandon the original task because of a failed background upgrade.

### Rule 2 — Windows: never auto-execute, surface the install command

**Detection:** `update_available.install_command` starts with `"irm "` (PowerShell `Invoke-RestMethod`).

**Action:** Do **not** run the command yourself. PowerShell's `irm | iex` executes arbitrary remote code; that's a user decision, not an agent decision. Show the command to the user verbatim:

> A newer Kite Passport bundle is available (22). To upgrade on Windows, run this in a PowerShell prompt:
>
> ```
> irm https://cli.gokite.ai/install.ps1 | iex
> ```
>
> I can't run it for you on Windows — please run it yourself, then re-run your original task in a fresh shell.

### Rule 3 — when NOT to auto-upgrade (even on POSIX)

Skip the auto-upgrade and defer to a future invocation if any of these are true:

- A payment, checkout, or x402 execute call is mid-flight (`x402-execute` or `shopping` is the active skill).
- A session-approval poll is running (`request-session` waiting for the user's passkey approval).
- The user is in a multi-step interactive flow (TUI prompts, OTP entry, etc.).
- The current command's exit code was non-zero — fix the underlying issue first, don't pile a CLI upgrade on top of an already-broken flow.

In all of these cases, just keep the field in mind and trigger the upgrade once the active flow finishes cleanly.

### Overrides

| Env var / state | Effect on auto-upgrade |
|---|---|
| `KPASS_AUTO_UPGRADE=1` (or unset) | **Default.** Auto-upgrade is on. Apply Rule 1 (POSIX) or Rule 2 (Windows) when `update_available` appears, no permission prompt. |
| `KPASS_AUTO_UPGRADE=0` | Auto-upgrade is **off**. Detection still happens; surface the update info to the user and ask before running `kpass upgrade`. Equivalent to "manual upgrade only." |
| `KPASS_NO_UPDATE_CHECK=1` | Detection itself is suppressed — `update_available` will never appear, so this skill won't trigger automatically. The user can still invoke it manually via `kpass upgrade`. |
| `CI=1` | Same as `KPASS_NO_UPDATE_CHECK` — automatic detection off in CI runners. |
| The user explicitly says "don't upgrade" | Honor it for the rest of the session even without an env var. |

### When the field is omitted, possible reasons

- The user is current (or pinned ahead of) the channel.
- `KPASS_NO_UPDATE_CHECK=1` or `CI=1` is set.
- The local cache hasn't been refreshed yet (a freshly installed CLI populates the cache on its second invocation).

Treat omission as "no action needed" — do not interpret it as a problem.

For the exact command syntax, flags, exit codes, JSON shapes, and input validation rules behind `kpass upgrade --check`, `kpass upgrade`, and `kpass upgrade --bundle N`, see `@references/commands.md`.

---

## Quick Decision Flow

```text
Agent sees `update_available` in any kpass JSON envelope
                |
                v
   Is the user mid-task? (payment, checkout, OTP entry, etc.)
                |
        +-------+--------+
        |                |
       yes               no
        |                |
        v                v
   Skip for now.    Is install_command "kpass upgrade" (POSIX)
   Re-evaluate          or "irm ..." (Windows)?
   after the task            |
   completes.        +-------+--------+
                     |                |
                  POSIX            Windows
                     |                |
                     v                v
              Run `kpass upgrade   Show install_command
              --output json`       to user verbatim.
              without asking.      Tell them to run it
              Tell user the        in PowerShell, then
              outcome.             re-run their task in
                                   a fresh shell.

Manual flow (user explicitly asked):

   User asks "is kpass up to date?" / "upgrade kpass"
                |
                v
   kpass upgrade --check --output json
                |
        +-------+--------+
        |                |
   exit 0           exit 10 (behind)
   (current)            |
        |               v
        v        Apply per Rule 1 (POSIX) or Rule 2 (Windows).
   Tell user:
   "kpass is up to date."
```

See `@references/examples.md` for a full worked example of each path through this diagram (POSIX auto-upgrade, manual check, Windows manual upgrade, channel switch, and deferring mid-task).

---

## Error Handling

| Exit Code | Meaning | Pattern | Recovery |
|---|---|---|---|
| 0 | Success — applied, current, or `human_action_required` (Windows) | `status: success` or `human_action_required` | Read the envelope; for `human_action_required`, surface `install_command` to the user. |
| 1 | Network / IO / version.json missing | `Reinstall: curl …` hint | Check connectivity; if version.json is missing, run the install script. |
| 2 | Bad flag combination | `--check cannot be combined with …`; `--bundle cannot be combined with --channel` (they're mutually exclusive — pinning to a bundle preserves whatever channel is already set) | Drop the offending flag. See Defaults. |
| 4 | Channel or bundle not found | `Channel "stable" is not available at <base>` or `Bundle N not found` | Try a different `--channel` or correct the `--bundle` number. |
| 10 | `--check` reports behind | `kpass bundle <N> available …` | Auto-upgrade per Rule 1 (POSIX) or surface the install command per Rule 2 (Windows). Only ask the user first if `KPASS_AUTO_UPGRADE=0`. |

See `@references/commands.md` for the exact error envelope of every state and the full input validation rules (argument and flag combinations).

---

## Commands That DO NOT Exist

Do NOT attempt any of the following — they will fail:

- `kpass update` — the command is `upgrade`, not `update`.
- `kpass upgrade --auto` / `--yes` — there is no auto-confirm flag.
- `kpass upgrade --version <semver>` — `--bundle` takes an integer (the bundle number), not a semver.
- `kpass upgrade --rollback` — to roll back, use `kpass upgrade --bundle <previous>` to pin to the prior bundle number.
- `kpass upgrade --uninstall` — there is no built-in uninstall; `rm -rf ~/.kpass` plus removing PATH entries does it manually.
- `kpass __check-updates` is a hidden internal subcommand for the background refresh. **Do not invoke it directly** unless explicitly debugging the cache; agents should always go through `kpass upgrade --check`.

---

## Cross-Skill References

- **For first-time install or reinstall**: not a skill — direct the user to `curl -fsSL https://cli.gokite.ai/install.sh | bash` (POSIX) or `irm https://cli.gokite.ai/install.ps1 | iex` (Windows).
- **For diagnostics**: pair with **`manage-agents`** (lists registered agents and sessions) or **`activity`** (transaction history) when troubleshooting unexpected behavior.
- **For the orchestrator**: **`kite-passport`** routes user requests for "update kpass" / "upgrade" / "is my CLI up to date" to this skill.
