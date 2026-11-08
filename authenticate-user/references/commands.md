# Authenticate User — Command Reference

Full command reference for the `authenticate-user` skill. SKILL.md carries the trigger logic, the sign-in order (browser first, email code second, the older-kpass flow last), the security note on passing codes via environment variables, and the mandatory display cards; this file has the command-level detail (flags, validation, full JSON output shapes, and the exhaustive error-scenario list). Worked end-to-end examples live in `examples.md`.

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

## `login` -- Start the Browser Sign-In

The first command of every sign-in, for a new user and a returning user alike. kpass opens the browser on this machine and registers the approval request with the backend.

```
kpass login --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

No other flags. `--client` and `--no-interactive` belong to `login init`, not here.

### Success Output (exit code 0)

```json
{
  "request_id": "req_abc123",
  "approve_url": "https://passport.gokite.ai/approve/req_abc123",
  "login_status": "pending",
  "browser_opened": true,
  "expires_at": "2026-03-17T12:10:00Z",
  "_version": "1",
  "status": "pending",
  "hint": "Approve the sign-in in your browser.",
  "next_command": "kpass login status --wait 50 --output json"
}
```

**Key fields:**
- `status` is `"pending"` -- NOT an error. Exit code is 0.
- `approve_url` -- put this in your reply to the user, in full. They see your message, not this JSON.
- `request_id` -- the backend's handle for this attempt. `login status` finds it on its own; you do not pass it back.
- `login_status` -- `"pending"` here, the same field `login status` answers with.
- `browser_opened` -- whether kpass opened the browser itself. Put `approve_url` in your reply either way, so the user can open it when nothing opened for them.
- `expires_at` -- when this attempt stops being approvable. After it, `login status` answers `expired`.

### No Browser on This Machine (exit code 9)

```json
{
  "_version": "1",
  "status": "error",
  "error": "No browser can be opened here (…).",
  "hint": "Run 'kpass login init --email <EMAIL>' to sign in with an emailed code instead.",
  "next_command": ""
}
```

Containers, SSH sessions and CI machines land here. **Detect this by the exit code 9.** There is no `error_code` field on this response and `next_command` is empty, so the exit code is the only thing that tells you to switch. The parenthetical inside `error` names the reason and varies, so match the start of the string at most, never the whole of it. Switch to `login init` below. This is not a failure to report to the user.

### Older kpass

A kpass from before browser sign-in answers `kpass login` with the login group's help text or an unknown-command error rather than JSON. Treat that as "no browser sign-in on this install" and run the older flow in SKILL.md ("Older kpass: Login vs Signup").

### What to Do After This Command

1. Put the `approve_url` in your reply: "Approve the sign-in in your browser: {approve_url}".
2. Run `login status` below. Do not wait for the user to tell you they approved.

---

## `login status` -- Read the Browser Sign-In

Blocks server-side for up to `--wait` seconds, then reports where the sign-in got to.

```
kpass login status --wait 50 --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Wait seconds | `--wait` | Yes (for agent use) | Always pass `50` | Positive integer |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

Run it exactly as written; you do not pass the `request_id` back. The approval itself lives on the backend, so this command still answers in a later agent run, after the one that started the sign-in has ended.

### Output

The sign-in state is the `login_status` field. If a response carries no `login_status`, read the envelope's `status` instead and map it: `success` means `signed_in`, `pending` means `pending`, `expired` means `expired`, and `error` means `failed`.

```json
{
  "login_status": "signed_in",
  "email": "user@example.com",
  "user_id": "user_789xyz",
  "_version": "1",
  "status": "success",
  "hint": "Signed in as user@example.com.",
  "next_command": ""
}
```

| State | Meaning | Next step |
|---|---|---|
| `pending` | Not approved yet | Run the same command again. Repeat the `approve_url` in your reply every few rounds. |
| `signed_in` | Done; `email` and `user_id` are in the response | Display the Welcome Back card. No email was sent and no code is needed. |
| `expired` | Nobody approved in time | Run `kpass login --output json` again. The browser is usually signed in by then, so it is one click. |
| `failed` | The sign-in did not complete | Run `kpass login --output json` again. If that also fails, ask the user whether to send a code by email instead of switching to `login init` yourself. |

### What to Do After This Command

The approval lands server-side whether or not you are waiting. If your run stops between `login` and `login status`, run `login status` again when you come back rather than starting a new `kpass login` — the earlier attempt is very likely already approved, and a fresh one would make the user click twice.

---

## `signup init` -- Start Signup (Older kpass Only)

**Reached only from SKILL.md's "Older kpass: Login vs Signup".** A current kpass signs up new users through `login` or `login init`, so it never runs any `signup` sub-command.

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

See the **"Messaging After `signup init` (Older kpass Only) — MANDATORY"** section in `SKILL.md` for the exact, ordered wording to use — clicking the link and sharing the code are sequential steps, not alternatives ("whichever is easier"), because `signup exchange` will fail with "not verified" if the link hasn't been opened yet regardless of whether the code is correct. That wording also covers the "Create a passkey" page a brand-new signup lands on after clicking the link — mention it proactively, not as a surprise afterward.

1. Tell the user to click the verification link first, then share the 8-character code.
2. **In the background** (`run_in_background`), start `signup poll --signup-id <signup_id> --wait --output json` right away — do not wait for the user to say "verified" first. It detects the link click on its own; see `signup poll` below.
3. **Also wait for the user to provide the 8-character code** from the "Your Kite Passport sign-up code" email — the two waits happen in parallel, not one gating the other.
4. Run `signup exchange` with the `signup_id` from this response and the code the user provided, once both the background poll has confirmed `verified` and the code is in hand.

**CRITICAL:** You MUST ask the user for the code — do NOT try to guess or fabricate it, the user reads it from their email. But do NOT make the user manually confirm the link click in words either; the background poll exists precisely so you don't have to ask.

---

## `signup poll` -- Detect Email Verification (Older kpass Only)

Polls the backend until the user clicks the verification link. **Start this immediately after `signup init`, in the background** (`run_in_background: true`), rather than waiting for the user to type something like "verified" or "done" — that keyword is not a real signal (the backend is), and requiring it just adds a manual step the poll makes unnecessary. Do not run it inline/foreground: with `--wait` it blocks server-side for up to `--timeout` (default 600s), which would stall the whole conversation for up to ten minutes if not backgrounded.

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

When the backgrounded poll notifies you `verification_status` is `"verified"`:
1. Tell the user proactively — "✅ email confirmed" — rather than staying silent. Don't wait for them to ask.
2. If the 8-character code hasn't arrived yet, say you're still waiting on it; if it already has, run `signup exchange` with the `signup_id` and that code right away.

---

## `signup exchange` -- Complete Signup and Authenticate (Older kpass Only)

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

## `login init` -- Start the Email Code Sign-In

The fallback when `kpass login` exits 9 (`browser_unavailable`), and the first command of the older-kpass flow.

Sends an 8-character one-time code to the user's email address. **One email, one code, and it works for an address that has never signed up as much as for a known one** — a current kpass registers the new user on `login verify`. There is no second email and no `signup` step.

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
  "error_code": "not_authenticated",
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

**No browser on this machine (exit code 9 from `kpass login`, the `browser_unavailable` case):**
- Expected on containers, SSH sessions and CI machines, not a failure.
- The exit code is the signal. The body carries `status: "error"` and an `error` starting "No browser can be opened here", with no `error_code` field and an empty `next_command`.
- Run `login init` with the user's email, then `login verify` with the code they read back. One email, one code.
- Do not report exit 9 to the user as an error, and do not retry `kpass login`.

**Browser sign-in came back `expired` or `failed` (from `login status`):**
- Run `kpass login --output json` once more and give the user the new `approve_url`.
- The browser is usually signed in by this point, so the second attempt is one click.
- If the second attempt also ends `failed`, switch to `login init`.

**Email not registered during login (exit code 4):**
- Only an older kpass returns this; a current one registers the address instead.
- On an older kpass, fall back to `signup init` with the same email.
- Tell the user: "It looks like you don't have an account yet. I'll create one for you."

**Signup blocked — email already registered (exit code 3 from `signup init`):**
- This only matters when the user explicitly asked to sign up / create an account / register — not when you chose `signup init` yourself as the login-not-found fallback above.
- Do NOT silently fall back to `login init`. The user's stated intent was a new account; defaulting to logging them into an existing one overrides that intent without asking.
- Ask the user to choose: "An account already exists for {email}. Do you want me to log you into that account, or would you rather use a different email to create a new one?"
- If they choose to log in: proceed with `login init` for that email.
- If they give a different email: retry `signup init` with the new one.
- Do not proceed with either path until the user has answered.

---

## Input Validation Checklist

Before running any command, verify:

1. **Email format:** Contains `@` and a domain. Do not pass obviously invalid strings.
2. **OTP / signup code:** Should be exactly 8 characters (alphanumeric). If the user provides something shorter or longer, ask them to double-check.
3. **signup_id:** Must come from a `signup init` response. Do not fabricate values.
4. **login_id:** Must come from a `login init` response. Do not fabricate values.
