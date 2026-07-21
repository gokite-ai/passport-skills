# Authenticate User — Worked Examples

End-to-end walkthroughs for the `authenticate-user` skill. Per-command syntax, flags, and JSON shapes live in `commands.md`; the login-vs-signup decision, the security note on passing codes via environment variables, and the mandatory display cards live in `SKILL.md`.

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
  |-- "Click the link & share the    ---------------------------------->|
  |    8-char code from your email"     |                                |
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
Tell the user to click the verification link, then share the 8-character code.

**Step 2:** User provides the code (e.g., "A1B2C3D4"). Complete signup.
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
Tell the user to click the verification link, then share the 8-character code.

**Step 3:** User provides the code (e.g., "A1B2C3D4"). Complete signup.
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
