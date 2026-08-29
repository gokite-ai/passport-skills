# Authenticate User — Worked Examples

End-to-end walkthroughs for the `authenticate-user` skill. Per-command syntax, flags, and JSON shapes live in `commands.md`; the login-vs-signup decision, the mandatory signup messaging, the security note on passing codes via environment variables, and the mandatory display cards live in `SKILL.md`.

---

## Complete Worked Example: New User Signup

```
Agent                                  CLI                              User
  |                                     |                                |
  |-- signup init --email user@ex.com ->|                                |
  |<- {status:"human_action_required",  |                                |
  |    signup_id:"signup_abc123",       |                                |
  |    next_command:"...exchange..."}   |                                |
  |                                     |                                |
  |-- "Click the link in email #1;   ---------------------------------->|
  |    share the code from email #2"    |                                |
  |                                     |                     [clicks    |
  |                                     |                      link,     |
  |                                     |                      reads     |
  |                                     |                      code]     |
  |<- "A1B2C3D4" ----------------------------------------------------- |
  |                                     |                                |
  |-- KPASS_SIGNUP_CODE=A1B2C3D4        |                                |
  |   signup exchange --signup-id      |                                |
  |   signup_abc123 ------------------>|                                |
  |<- {status:"success",               |                                |
  |    user_id:"user_789xyz",           |                                |
  |    email:"user@example.com"}        |                                |
  |                                     |                                |
  |-- "Account created & logged in" ----------------------------------->|
```

### Step-by-step commands:

**Step 1:** Start signup.
```bash
kpass signup init --email user@example.com --client agent --output json --no-interactive
```
Output:
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
Use the mandatory ordered wording from `SKILL.md`'s "Messaging After `signup init`" section — click the link (and, for a new account, create the passkey it leads to), then share the 8-character code. Do not phrase these as two alternative ways to finish.

Right after sending that message, also start `kpass signup poll --signup-id signup_abc123 --wait --output json` **in the background** — do not wait for the user to say "verified" first. It runs in parallel with waiting for the code below and reports the link click on its own; see `signup poll` in `commands.md`.

**Step 2:** User provides the code (e.g., "A1B2C3D4"). Only run exchange once **both** conditions hold: the background poll from Step 1 has reported `verification_status: "verified"`, and the code is in hand. If the code arrives first and the poll hasn't resolved yet, hold it and wait for `verified` — do not exchange early on the strength of the code alone.
```bash
KPASS_SIGNUP_CODE=A1B2C3D4 kpass signup exchange --signup-id signup_abc123 --output json
```
Output:
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

Done. The user is authenticated. Display the account-created card.

---

## Complete Worked Example: Returning User Login

**Step 1:** Start login.
```bash
kpass login init --email user@example.com --client agent --output json --no-interactive
```
Output:
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
Ask the user: "An 8-character login code was sent to your email. Please share it with me."

**Step 2:** User provides code (e.g., "A1B2C3D4"). Verify it.
```bash
KPASS_LOGIN_CODE=A1B2C3D4 kpass login verify --login-id login_xyz789 --output json
```
Output:
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

Done. The user is authenticated.

---

## Complete Worked Example: Login Fallback to Signup (New User Says "Sign In")

**Context:** The user says "sign me in" but does not have an account yet. Per the Decision section, try login first, then fall back to signup.

**Step 1:** Try login first.
```bash
kpass login init --email user@example.com --client agent --output json --no-interactive
```
Output (exit code 4):
```json
{
  "_version": "1",
  "status": "error",
  "error": "email not registered",
  "hint": "No account found for user@example.com. Try signup instead.",
  "next_command": "kpass signup init --email user@example.com --output json --no-interactive"
}
```
Email not registered. Fall back to signup.

**Step 2:** Start signup.
```bash
kpass signup init --email user@example.com --client agent --output json --no-interactive
```
Output:
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
Tell the user to click the verification link in the "Sign in to Kite Passport" email, then share the 8-character code from the separate "Your Kite Passport sign-up code" email — two emails, not one.

Right after sending that message, also start `kpass signup poll --signup-id signup_abc123 --wait --output json` **in the background** — same as the new-signup example above, do not wait for the user to say "verified" first.

**Step 3:** User provides the code (e.g., "A1B2C3D4"). Only run exchange once the background poll has reported `verification_status: "verified"` **and** the code is in hand — if the code arrives before the poll resolves, wait for `verified` rather than exchanging on the code alone.
```bash
KPASS_SIGNUP_CODE=A1B2C3D4 kpass signup exchange --signup-id signup_abc123 --output json
```
Output:
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

Done. The user is authenticated. Display the account-created card.

---

## Complete Worked Example: Signup Blocked by Existing Account (User Explicitly Asked to Register)

**Context:** The user says "create a new account for me" / "sign me up" / "register me" — an explicit signup request, not an ambiguous "sign in". The email they give you already has an account.

**Step 1:** Go straight to signup, per the Decision section — an explicit signup request skips the login-first check.
```bash
kpass signup init --email user@example.com --client agent --output json --no-interactive
```
Output (exit code 3):
```json
{
  "_version": "1",
  "status": "error",
  "error": "email already registered",
  "hint": "Agent is already registered. Run 'kpass status --output json' to see current agent details.",
  "next_command": ""
}
```

**Step 2:** Do NOT fall back to `login init` on your own here — the user asked for a *new* account, and quietly logging them into the old one overrides that without asking. Ask:

> "An account already exists for user@example.com. Do you want me to log you into that account, or would you rather use a different email to create a new one?"

**Step 3a — user says "log me in":** proceed with `login init` for that email (see the Returning User Login example above).

**Step 3b — user gives a different email:** retry `signup init` with the new email (see the New User Signup example above).

Either way, wait for the user's answer before running the next command — do not guess which one they'd prefer.
