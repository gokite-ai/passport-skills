# Authenticate User — Command Reference

Full command reference for the `authenticate-user` skill. SKILL.md carries the trigger logic, the login-vs-signup decision, the security note on passing codes via environment variables, and the mandatory display cards; this file has the command-level detail (flags, validation, full JSON output shapes, and the exhaustive error-scenario list). Worked end-to-end examples live in `examples.md`.

**Common envelope.** All commands return this envelope structure when `--output json` is used:

```json
{
  "...": "command-specific fields",
  "_version": "1",
  "status": "success | human_action_required | pending | expired | error",
  "error": "Raw backend error message (present only when status is error)",
  "error_code": "Machine-readable error classification (present only when status is error)",
  "hint": "Human-readable recovery guidance",
  "next_command": "The exact CLI command to run next (may contain <PLACEHOLDER> tokens)"
}
```

**Status values:**
- `"success"` -- Operation completed. Proceed with whatever the user needs next.
- `"human_action_required"` -- NOT an error. The user needs to do something (click link, provide code). Follow `hint` and `next_command`.
- `"pending"` -- Still in progress. Run again with `--wait`, or retry after a delay.
- `"expired"` -- The flow timed out. Restart from the beginning.
- `"error"` -- Something went wrong. Check `error_code` for programmatic classification, `hint` for recovery instructions, and `error` for the raw backend message.

---

## `signup init` -- Start Signup

Sends a verification link and a sign-up code to the user's email address.

```
kpass signup init --email <EMAIL> --client agent --output json --no-interactive
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Email address | `--email` | Yes | Ask the user | Must be a valid email address |
| Caller surface | `--client agent` | Yes | Always pass | Literal value `agent` |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |
| Non-interactive | `--no-interactive` | Yes | Always pass | Boolean flag, no value |

### Success Output (exit code 0)

```json
{
  "action": "check_email_for_code",
  "signup_id": "signup_abc123",
  "poll_interval_seconds": 3,
  "expires_at": "2026-03-17T12:00:00Z",
  "_version": "1",
  "status": "human_action_required",
  "hint": "A verification link and sign-up code were sent to user@example.com. Enter the code to complete signup.",
  "next_command": "KPASS_SIGNUP_CODE=<CODE> kpass signup exchange --signup-id signup_abc123 --output json"
}
```

**Key fields:**
- `status` is `"human_action_required"` -- this is NOT an error. Exit code is 0.
- `signup_id` -- needed for `signup exchange`. Extract it from this response.
- `next_command` -- contains the exact `signup exchange` command (with the real signup_id filled in, but `<CODE>` as a placeholder you must get from the user).

### What to Do After This Command

1. Tell the user: "Two emails were sent to **{email}**: a **verification link** and a **sign-up code**. Please click the verification link first, then share the 8-character code with me."
2. **Wait for the user to provide the 8-character code** from the "Your Kite Passport sign-up code" email.
3. Run `signup exchange` with the `signup_id` from this response and the code the user provided.

**CRITICAL:** You MUST ask the user for the code and wait. Do NOT try to guess or fabricate the code. The user reads it from their email.

---

## `signup poll` -- Wait for Email Verification (Optional)

Polls the backend until the user clicks the verification link. This command is optional — the primary signup flow uses `signup exchange` with the code directly.

```
kpass signup poll --signup-id <signup_id> --wait --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Signup ID | `--signup-id` | Yes | From `signup init` output: `signup_id` field | String starting with `signup_` |
| Wait mode | `--wait` | Yes (for agent use) | Always pass | Boolean flag, no value |
| Poll interval | `--poll-interval` | No | Default: 3 seconds | Positive integer |
| Timeout | `--timeout` | No | Default: 600 seconds | Positive integer |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output -- Verified (exit code 0)

```json
{
  "signup_id": "signup_abc123",
  "verification_status": "verified",
  "_version": "1",
  "status": "success",
  "hint": "Email verified. Proceed to signup exchange.",
  "next_command": "KPASS_SIGNUP_CODE=<CODE> kpass signup exchange --signup-id signup_abc123 --output json"
}
```

**Important:** The `next_command` contains `<CODE>` as a placeholder. You must get the 8-character code from the user (they read it from the "Your Kite Passport sign-up code" email).

### Expired Output (exit code 3)

```json
{
  "signup_id": "signup_abc123",
  "verification_status": "expired",
  "_version": "1",
  "status": "expired",
  "hint": "Verification link expired. Restart signup.",
  "next_command": "kpass signup init --email <EMAIL> --output json"
}
```

If expired, tell the user the link expired and re-run `signup init` with their email.

### Pending Output -- Without `--wait` (exit code 0)

If you omit `--wait`, a single check is performed:

```json
{
  "signup_id": "signup_abc123",
  "verification_status": "pending",
  "_version": "1",
  "status": "pending",
  "hint": "Not yet verified. Run with --wait to poll automatically.",
  "next_command": ""
}
```

### What to Do After This Command

When `verification_status` is `"verified"`:
1. Ask the user for the 8-character code from the "Your Kite Passport sign-up code" email.
2. Run `signup exchange` with the `signup_id` and the code the user provided.

---

## `signup exchange` -- Complete Signup and Authenticate

Completes the signup flow: creates the user account, obtains a JWT, and saves credentials to local config. After this command succeeds, the user is fully authenticated — do NOT run `login init`.

```
KPASS_SIGNUP_CODE=<CODE> kpass signup exchange --signup-id <signup_id> --output json
```

**Security:** Pass the signup code via the `KPASS_SIGNUP_CODE` environment variable (shown above) instead of the `--code` flag. Environment variables are not visible in process listings (`ps`, `/proc/<pid>/cmdline`), while flags are. The `--code` flag still works for backward compatibility but is discouraged.

### Arguments

| Argument | Env Var / Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Signup ID | `--signup-id` | Yes | From `signup init` output: `signup_id` field | String starting with `signup_` |
| Code | `KPASS_SIGNUP_CODE` env var (preferred) or `--code` flag | Yes | From the user (they read it from the "Your Kite Passport sign-up code" email) | 8-character alphanumeric string |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "user_id": "user_789xyz",
  "email": "user@example.com",
  "_version": "1",
  "status": "success",
  "hint": "Account created and logged in as user@example.com.",
  "next_command": ""
}
```

### What to Do After This Command

The user is now authenticated. Do NOT run `login init` — the JWT was already obtained and saved.

Display the Account Created & Logged In card (SKILL.md). Fill in all placeholders from the JSON output.

---

## `login init` -- Start OTP Login

Sends an 8-character one-time code to the user's email address.

```
kpass login init --email <EMAIL> --client agent --output json --no-interactive
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Email address | `--email` | Yes | Ask the user (or reuse from prior signup) | Must be a valid email address |
| Caller surface | `--client agent` | Yes | Always pass | Literal value `agent` |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |
| Non-interactive | `--no-interactive` | Yes | Always pass | Boolean flag, no value |

**Note:** If `--email` is omitted, the CLI will attempt to read the email from the saved config. However, always pass `--email` explicitly for reliability.

### Success Output (exit code 0)

```json
{
  "action": "enter_otp",
  "login_id": "login_xyz789",
  "expires_at": "2026-03-17T12:10:00Z",
  "_version": "1",
  "status": "human_action_required",
  "hint": "An 8-character code was sent to user@example.com. Ask the user to share it.",
  "next_command": "KPASS_LOGIN_CODE=<OTP_CODE> kpass login verify --login-id login_xyz789 --output json"
}
```

**Key fields:**
- `status` is `"human_action_required"` -- NOT an error. Exit code is 0.
- `login_id` -- needed for the verify command. Already filled in `next_command`.
- `next_command` -- contains the exact `login verify` command, but `<OTP_CODE>` is a placeholder you must get from the user.

### What to Do After This Command

1. **Ask the user for the code.** Say: "An 8-character login code was sent to **{email}**. Please check your email and share the code with me."
2. **Wait for the user to provide the code** in the conversation.
3. Run `login verify` with the `login_id` from this response and the code the user provided.

**CRITICAL:** Unlike signup (which uses a link and polls automatically), login requires the user to type the OTP code back to you. You MUST ask the user and wait. Do NOT try to poll or guess the code.

---

## `login verify` -- Verify OTP and Get JWT

Verifies the OTP code and saves the JWT to local config.

```
KPASS_LOGIN_CODE=<OTP_CODE> kpass login verify --login-id <login_id> --output json
```

**Security:** Pass the OTP code via the `KPASS_LOGIN_CODE` environment variable (shown above) instead of the `--code` flag. Environment variables are not visible in process listings (`ps`, `/proc/<pid>/cmdline`), while flags are. The `--code` flag still works for backward compatibility but is discouraged.

### Arguments

| Argument | Env Var / Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Login ID | `--login-id` | Yes | From `login init` output: `login_id` field | String starting with `login_` |
| OTP code | `KPASS_LOGIN_CODE` env var (preferred) or `--code` flag | Yes | From the user (they read it from their email) | 8-character alphanumeric string |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "user_id": "user_789xyz",
  "email": "user@example.com",
  "_version": "1",
  "status": "success",
  "hint": "Logged in as user@example.com.",
  "next_command": ""
}
```

### What to Do After This Command

The user is now authenticated. Tell the user: "You are now logged in as **{email}**."

If the next step is agent registration or spending, refer to the **`request-session`** skill. If the user needs test tokens (dev/staging environments), refer to the **`wallet-send`** skill for the `faucet drop` command.

If the code was wrong (exit code 3), tell the user: "That code was not valid. Please check your email again and share the correct 8-character code." Then re-run `login verify` with the corrected code. Do NOT re-run `login init` -- the same `login_id` is still valid until it expires.

Display the Welcome Back card (SKILL.md). Fill in all placeholders from the JSON output.

---

## `logout` -- Sign Out

Revokes the current session and clears all saved auth (both user JWT and agent token).

```
kpass logout --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "_version": "1",
  "status": "success",
  "hint": "Logged out.",
  "next_command": ""
}
```

If already logged out:

```json
{
  "_version": "1",
  "status": "success",
  "hint": "Already logged out.",
  "next_command": ""
}
```

**Note:** Logout clears BOTH `config.json` (user JWT) and `agent.json` (agent token/session). After logout, the agent will need to re-authenticate AND re-register.

---

## `me` -- Check Current User

Returns the currently logged-in user, or errors if not logged in.

```
kpass me --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "user_id": "user_789xyz",
  "email": "user@example.com",
  "_version": "1",
  "status": "success",
  "hint": "Logged in as user@example.com.",
  "next_command": ""
}
```

### Error Output -- Not Logged In (exit code 3)

```json
{
  "_version": "1",
  "status": "error",
  "error": "Not logged in. Run signup or login first.",
  "hint": "Run 'kpass signup init --email <email> --output json' or 'kpass login init --email <email> --output json'.",
  "next_command": ""
}
```

Use `me` when you need to confirm the current auth state before proceeding with other skills.

---

## Error Handling — Full Reference

### Specific Error Scenarios

**Wrong OTP code (exit code 3):**
- Do NOT re-run `login init`. The `login_id` is still valid.
- Ask the user to double-check the code and provide it again.
- Re-run `login verify` with the same `login_id` and the corrected code (via `KPASS_LOGIN_CODE` env var).

**Verification link expired (exit code 3 from `signup poll`):**
- Tell the user the link expired.
- Re-run `signup init` with their email to send a new link.

**Signup exchange fails with "not verified" or "pending" (exit code 3):**
- The user likely hasn't clicked the verification link yet.
- Tell the user: "Please click the verification link in your email first, then share the code."
- After the user confirms they clicked the link, retry `signup exchange` with the same `signup_id` and code (via `KPASS_SIGNUP_CODE` env var).

**Signup session already consumed (exit code 3 from `signup poll` or `signup exchange`):**
- The user already clicked the verification link and the session was consumed (e.g., by the web tab).
- If from `signup poll`: skip polling and proceed — ask the user for the 8-character code, then run `signup exchange` with the `signup_id` and code (via `KPASS_SIGNUP_CODE` env var). The exchange endpoint accepts consumed sessions.
- If from `signup exchange`: run `kpass me --output json` to check if the user is already authenticated. If `me` succeeds, display the welcome-back card. If `me` fails, the exchange may have failed for another reason — check the error message.

**Email not registered during login (exit code 4):**
- Fall back to `signup init` with the same email.
- Tell the user: "It looks like you don't have an account yet. I'll create one for you."

---

## Input Validation Checklist

Before running any command, verify:

1. **Email format:** Contains `@` and a domain. Do not pass obviously invalid strings.
2. **OTP / signup code:** Should be exactly 8 characters (alphanumeric). If the user provides something shorter or longer, ask them to double-check.
3. **signup_id:** Must come from a `signup init` response. Do not fabricate values.
4. **login_id:** Must come from a `login init` response. Do not fabricate values.
