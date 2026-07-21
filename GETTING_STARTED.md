# Getting Started with Agent Passport

Agent Passport gives an AI agent a limited, user-approved budget to move funds on your behalf. The agent handles all CLI commands — you only interact through conversation and a browser.

---

## Prerequisites

### Install the CLI

```bash
curl -fsSL https://cli.gokite.ai/install.sh | bash
```

> Windows (PowerShell): `irm https://cli.gokite.ai/install.ps1 | iex`

```bash
kpass --version  # should print kpass v1.5.0 or higher
```

### Clone the skills

```bash
git clone https://github.com/gokite-ai/passport-skills
```

---

## Step 1: Install Skills

Tell your agent:

> "Install the Kite Passport skills so you can use my wallet."

The agent runs:

```bash
npx skills add ./passport-skills \
  --skill authenticate-user \
  --skill request-session \
  --skill form-session-delegation \
  --skill x402-execute \
  --skill wallet-send \
  --skill manage-agents \
  -y
```

> If `skills-lock.json` contains absolute paths from another machine, delete it and re-run.

---

## Step 2: Authenticate

The agent will ask for your email, then:

- **Sign up:** Passport sends a magic link — click it in your browser
- **Log in:** Passport sends an 8-character code — paste it into chat

---

## Step 3: Dashboard Setup (one-time)

1. **Register a passkey** — open the Passport dashboard and add device biometrics, Face ID, or a security key
2. **Fund your wallet** — use the on-ramp, or on testnet ask the agent: "Request test tokens from the faucet"

> **Testnet token:** The testnet uses **PIEUSD**. Use this name when asking for faucet drops or payments.

---

## Step 4: Authorize a Spending Session

Required before x402 payments (not needed for direct wallet transfers).

> "I want to pay the test merchant — authorize up to 5 PIEUSD per transaction."

1. Agent handles registration and session creation automatically, then shares an **approval URL**
2. Open the URL, approve with your passkey
3. Agent confirms: "Session approved — up to 5 PIEUSD per transaction until [time]."

---

## Step 5: Make Payments

> "POST to the test x402 service at `https://passport.dev.gokite.ai/x402/test`."
>
> "Send 2 PIEUSD to wallet address `0xabc...def`."

If the amount exceeds the session limit, the agent will request a new session before proceeding.

---

## Step 6: Review in the Dashboard

- **Sessions** — active/past sessions, limits, expiry, status
- **Transactions** — full payment ledger
- **Revoke** — immediately revoke a session or disable an agent

---

## Quick Reference

| Step | Agent | You |
|---|---|---|
| Install skills | Installs from `passport-skills` | Confirm |
| Authenticate | Calls signup/login API | Email + magic link or OTP |
| Fund wallet (testnet) | Requests faucet drop | Ask for it |
| Create session | Handles registration + session creation automatically | Approve in browser with passkey |
| Execute payment | Executes payment | Ask in natural language |

---

## Optional: Add Kite Passport to Your Agent Instructions

Skills are automatically discovered by your agent after installation. If you want
your agent to **proactively** consider Kite Passport for tasks like shopping or
API access, add a line to your project's agent instruction file:

| Agent | File | What to add |
|---|---|---|
| Claude Code | `CLAUDE.md` | `When the task involves shopping, paid APIs, or wallet operations, use the Kite Passport skills (shopping, kite-discovery, x402-execute, wallet-send).` |
| Codex / Copilot | `AGENTS.md` | Same as above |
| Cursor | `.cursor/rules/kite.mdc` | Same content with `alwaysApply: true` frontmatter |
| Cline | `.clinerules` | Same as above |
| Windsurf | `.windsurf/rules/kite.md` | Same content with `trigger: always_on` frontmatter |

This is optional — the skills work without it, but a one-line hint in your agent
instructions helps the agent reach for Kite Passport first instead of web search.

---

## Repositories

| Repo | Purpose |
|---|---|
| `passport-cli` | Go CLI tool (`kpass`) |
| `passport-skills` | SKILL.md files that teach the agent what commands to run |
| `passport-web` | Web dashboard for approvals, session review, and wallet funding |
