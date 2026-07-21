---
name: authenticate-user
description: >-
  Sign up or log in to Kite Passport. Invoke when the user needs an account, wants
  to sign in, or when any other Kite Passport skill returns an auth error (exit
  code 3). This is the gateway skill -- required before payments, shopping checkout,
  wallet operations, or session creation. Invoke proactively if the user has not
  authenticated yet and a Passport capability is needed.
user-invocable: true
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(kpass signup *)"
  - "Bash(kpass login *)"
  - "Bash(kpass logout*)"
  - "Bash(kpass me*)"
  - "Bash(KPASS_SIGNUP_CODE=* kpass signup *)"
  - "Bash(KPASS_LOGIN_CODE=* kpass login *)"
---

# Authenticate User

Sign up a new user or log in a returning user to Kite Passport. This skill is a prerequisite for all other Passport skills (`request-session`, `x402-execute`, `wallet-send`).

> **Reference files** (read when you need exact detail):
> - `@references/commands.md` — full command reference: every flag, validation rule, and JSON output shape for `signup init`, `signup poll`, `signup exchange`, `login init`, `login verify`, `logout`, and `me`, plus the exhaustive Error Handling reference and Input Validation Checklist.
> - `@references/examples.md` — complete worked examples (new user signup, returning user login, login fallback to signup).

## Step 0: Ensure CLI is Installed — MANDATORY

**CRITICAL: Before running ANY kpass command, you MUST run the setup script first. This is NOT optional. Do not skip this step. Do not run any kpass command before setup completes successfully.**

```bash
bash <skill-directory>/scripts/setup.sh
```

Where `<skill-directory>` is the directory containing this SKILL.md file (e.g., the directory this skill is installed in).

This script ensures `kpass` is installed and available on PATH. It will attempt to install it automatically if not found.

**If setup succeeds** (`status: "ok"` in JSON output): proceed to the next step.

**If setup fails** (`status: "error"`): **STOP immediately.** Show the user the error message and the installation instructions from the setup output. Do NOT search for the binary elsewhere. Do NOT try to build from source. Do NOT look in other directories. Just show the error and ask the user to install the CLI manually.

## When to Use This Skill

- The user says "sign up", "create an account", "register", or similar.
- The user says "sign in", "log in", "authenticate", or similar.
- The user says "log out", "sign out", or similar.
- Any other skill returns exit code `3` (auth error) with a message like "Not logged in" or "JWT is expired".
- You need to check who is currently logged in.

## Defaults (Do Not Ask the User Unless They Specify Otherwise)

| Setting | Default value | Override |
|---------|--------------|---------|
| Output format | `--output json` | Always use JSON output. Never omit this flag. |
| Interactive mode | `--no-interactive` | Always pass this flag. Never rely on TTY detection. |
| Caller surface | `--client agent` | Always pass this flag on `signup init` and `login init`. It tells the backend an agent is acting on the user's behalf so the email copy reads "Share this code with your agent" instead of "Enter this code in your terminal". Never omit this flag. |
| Base URL | Omit (uses built-in default) | Only pass `--base-url` if the user explicitly provides a custom backend URL. |

**Note on `next_command`:** The CLI's `next_command` field may show `kpass signup init` or `kpass login init` *without* `--client agent`. You must still add `--client agent` when running it. The Defaults table above is authoritative; CLI hints are starting points, not literal commands.

## Display Cards — MANDATORY

**CRITICAL: You MUST display the formatted status cards shown in this skill after every major step. This is NOT optional. Never skip, summarize, or replace these cards with plain text. The exact horizontal-rule format must be used every time — no exceptions.**

If a command succeeds and has a display card template below, you MUST output that card before doing anything else. Do not proceed to the next step until the card is displayed.

## Decision: Login vs Signup

If the user says "sign in" or "authenticate" without specifying whether they have an existing account:

1. **Try login first** with `login init`.
2. If the command fails with **exit code 4** (not found / "email not registered"), fall back to `signup init`.
3. If the user explicitly says "sign up" or "create account", go directly to signup.

**After signup exchange succeeds, the user is fully authenticated.** The `signup exchange` command returns a JWT and saves it to local config. Do NOT run `login init` after signup — it is unnecessary and will generate a conflicting OTP code.

---

## Security: Codes Are Passed via Environment Variable, Not a Flag

**CRITICAL — do not paraphrase or weaken this.** `signup exchange` and `login verify` both accept the one-time code via an environment variable rather than a CLI flag:

```
KPASS_SIGNUP_CODE=<CODE> kpass signup exchange --signup-id <signup_id> --output json
KPASS_LOGIN_CODE=<OTP_CODE> kpass login verify --login-id <login_id> --output json
```

**Always use the env-var form (`KPASS_SIGNUP_CODE`, `KPASS_LOGIN_CODE`) — never the `--code` flag.** Environment variables are not visible in process listings (`ps`, `/proc/<pid>/cmdline`), while flags are. The `--code` flag still works for backward compatibility but is discouraged; do not default to it. This applies every time you re-run `signup exchange` or `login verify` (e.g., after a wrong-code retry), not just the first attempt. See `@references/commands.md` for the full argument tables for both commands.

---

## Display Cards: Account Created / Welcome Back

**MANDATORY — After `signup exchange` succeeds, you MUST display this card. Do not skip this. Do not summarize. Do not replace with plain text:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 Account Created & Logged In!

📧 Email:    {email}
🆔 User ID:  {user_id}
🔓 Session active
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{email}` | From JSON response field `email` |
| `{user_id}` | From JSON response field `user_id` |

**MANDATORY — After `login verify` succeeds, you MUST display this card. Do not skip this. Do not summarize. Do not replace with plain text:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
👋 Welcome back!

📧 {email}
🆔 {user_id}
🔓 Session active
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{email}` | From JSON response field `email` |
| `{user_id}` | From JSON response field `user_id` |

**You MUST always display the matching card after a successful response. No exceptions.** Fill in all placeholders from the JSON output. See `@references/commands.md` for the full success JSON shape these placeholders are pulled from, and `@references/examples.md` for both cards shown in context.

---

## Error Handling

| Exit Code | Meaning | Error Message Pattern | Recovery Action |
|-----------|---------|----------------------|-----------------|
| 0 | Success or human action required | `status: "human_action_required"` | Follow the `next_command` field. This is NOT an error. |
| 1 | Network error | `network error: ...` | Check connectivity. Retry after a brief pause. |
| 2 | Usage error | `--email is required`, `unknown option` | Fix the command syntax. Check required flags. |
| 3 | Auth error | `invalid OTP`, `verification expired`, `already consumed` | For invalid OTP: ask user to re-check email and provide code again. For expired: restart the flow. |
| 4 | Not found | `email not registered`, `not found` | If trying login: fall back to signup. If unexpected: inform user. |
| 5 | Rate limited | `rate limit` | Wait 30 seconds, then retry. |
| 6 | Session policy violation | N/A for authenticate-user | This exit code is not expected from authentication commands. If encountered, it indicates a session delegation issue — use **`request-session`** to create a new session. |

See `@references/commands.md` for the exact JSON error envelope of every command and the full Specific Error Scenarios reference (wrong OTP, expired verification link, already-consumed signup session, email not registered).

---

## Commands That DO NOT Exist

Do NOT attempt any of the following. They will fail:

- `kpass signup` (without a sub-command) -- must use `signup init`, `signup poll`, or `signup exchange`
- `kpass login` (without a sub-command) -- must use `login init` or `login verify`
- `kpass signup verify` -- does not exist; signup uses `exchange` with `KPASS_SIGNUP_CODE` env var (or `--code` flag)
- `kpass login poll` -- does not exist; login uses `verify` with `KPASS_LOGIN_CODE` env var (or `--code` flag), not polling
- `kpass login exchange` -- does not exist
- `kpass register` -- does not exist; use `signup init` for user registration
- `kpass auth` -- does not exist
- `kpass signin` -- does not exist; use `login init`
- Any command with `--json` -- the correct flag is `--output json` (two separate tokens)
- Any command with `--interactive` -- the correct flag is `--no-interactive`
- Any command with `--exchange-token` -- this flag was removed; use `KPASS_SIGNUP_CODE` env var (or `--code` flag) instead

---

## Cross-Skill References

### After Successful Authentication (what to do next)

Once the user is logged in, immediately resume the task that required authentication:

- **If the original task involves shopping or buying products:** Invoke the **`shopping`** skill.
- **If the original task involves a paid API or service:** Invoke the **`request-session`** skill to create a spending session, then **`x402-execute`**.
- **If the original task involves sending tokens or checking balance:** Invoke the **`wallet-send`** skill.
- **If the user just wanted to log in:** Confirm success and mention available capabilities: "You're logged in. I can now shop for products, make payments, transfer tokens, or check your account activity."

### Related Skills

- To register the agent and create a spending session, use the **`request-session`** skill.
- To make direct wallet transfers (no session needed) or request test tokens from the faucet, use the **`wallet-send`** skill.
- To execute x402 paid API requests through a session, use the **`x402-execute`** skill.
- To inspect registered agents and session history, use the **`manage-agents`** skill.
