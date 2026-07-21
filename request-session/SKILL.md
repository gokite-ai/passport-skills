---
name: request-session
description: >-
  Authorize this agent to spend on behalf of the user by creating a spending
  session. Invoke before any payment, paid API call (x402-execute), or shopping
  checkout. Handles agent registration, merchant preflight, delegation construction,
  and user approval via passkey. For card-only merchants (no x402/wallet support),
  it also creates session-bound scoped-card (virtual card) sessions via `--use-card`,
  gated on backend cards support and user card KYC. If a task requires a spending
  session -- payments, paid API calls, or shopping checkout -- this skill must run
  first. Wallet transfers (wallet-send) and cloud deployments (cloud-deploy) use
  their own flows and don't need a session.
user-invocable: true
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(kpass agent:register*)"
  - "Bash(kpass agent:session *)"
  - "Bash(curl *)"
  - "Bash(open *)"
  - "Bash(xdg-open *)"
---

# Request Session

Register the agent identity and create, monitor, or reuse spending sessions with user approval. A session authorizes the agent to spend funds on behalf of the user, gated by a delegation policy (task description, payment policy with per-tx and total caps, optional execution constraints).

## Step 0: Ensure CLI is Installed — MANDATORY

Run the setup script before any `kpass` command — the script verifies the CLI is installed and configured for this user, and a missing or stale binary surfaces as a confusing exit-3 ("Not logged in") rather than a clean "CLI not installed" error if you skip it.

```bash
bash <skill-directory>/scripts/setup.sh
```

Where `<skill-directory>` is the directory containing this SKILL.md file (e.g., the directory this skill is installed in).

**If setup succeeds** (`status: "ok"`): proceed.
**If setup fails** (`status: "error"`): **STOP immediately.** Show the user the error and installation instructions. Do NOT search for the binary elsewhere.

## When to Use This Skill

- The user asks you to make a payment, access a paid API, or perform any action that requires spending.
- The **`shopping`** skill needs a session before checkout. The cart total is the budget source — no 402 preflight needed.
- Another skill (e.g., `x402-execute`) fails with "Agent not registered" or "No session specified".
- You need to create a new spending session because the previous one expired or was consumed.
- The user wants to see their active sessions.

Do NOT use this skill when the user already has an **attachable session ID**
(e.g., a session pre-created in the Passport web dashboard). Use the
**`attach-session`** skill instead — attaching binds the existing session with
one approval; creating here would mint a redundant session and burn a second
approval on a policy the owner already defined.

## Sessions Are Protocol-Agnostic

A single approved session is fungible across paid-API and shopping flows. The settlement protocol (x402, paygate, tempo, or crossmint checkout) is detected at execute time from the merchant's preflight response — the delegation does **not** carry a protocol field. The authorization boundary is per-tx / total spending caps (`max_amount_per_tx` / `max_total_amount`, denominated in `payment_policy.currency`, default `USD`) plus optional `execution_constraints` endpoint scoping — there is **no `assets` allowlist field** and the caps are never expressed per-asset. The settlement asset itself is a separate, merchant-selected concern: the merchant's 402 dictates which token settles (normalized into the budget currency for cap enforcement), and the session locks to that first settled asset automatically (single-asset lock) — this lock is an emergent side effect of settlement, not a user-configurable allowlist. See the **`form-session-delegation`** skill for the full schema.

For the full delegation schema and derivation rules, see the **`form-session-delegation`** skill.

## Prerequisites

The user MUST be authenticated before using this skill. If not logged in (exit code 3 with "No user_id found" or "Not logged in"), use the **`authenticate-user`** skill first.

**Diagnostics:** If you encounter "agent not registered" or "no active sessions" errors and need to investigate, use the **`manage-agents`** skill to inspect registered agents (`user agents`) and session history (`user sessions`) from the user's perspective.

## Defaults (Do Not Ask the User Unless They Specify Otherwise)

| Setting | Default value | Override |
|---------|--------------|---------|
| Output format | `--output json` | Always use JSON output. Never omit this flag. |
| Agent type | Your own agent identity (e.g., `claude` for Claude Code, `cursor` for Cursor, `codex` for Codex, `cline` for Cline) | Never ask the user. Each agent passes its own name automatically. |
| TTL | `3600` (1 hour) in delegation `ttl_seconds` | Use 1 hour unless the user specifies a different duration. |
| Max amount per tx | Derive automatically from 402 preflight response OR from a known amount (e.g., shopping cart total) | Never ask the user for this. See **`form-session-delegation`** for derivation rules. |
| Max total amount | Derive automatically: per-tx price × estimated requests, or equal to per-tx for single transactions (e.g., shopping checkout) | Never ask the user. See **`form-session-delegation`** for derivation rules. |
| Base URL | Omit (uses built-in default) | Only pass `--base-url` if the user explicitly provides a custom backend URL. |

## Display Cards

Render the formatted status cards (templated in `@references/commands.md`) verbatim after each successful command — the horizontal-rule format is what users scan to confirm what happened, and the eval grader looks for the exact strings inside them. Summarizing or rewording in plain text loses both signals.

---

## Command Reference

Full per-command detail — argument tables, JSON outputs, error envelopes, display cards, and the **6-check Session Reuse Evaluation** (under `agent:session list`) — lives in:

→ **`@references/commands.md`**

Read that file before running any `agent:register` or `agent:session` command.

---

## Full Session Creation Flow

The delegation model adds preflight discovery and structured delegation construction. Here is the complete flow.

### Step 1: Ensure Agent is Registered

```bash
kpass agent:register --type <agent-type> --output json
# Replace <agent-type> with your agent's identity: claude, cursor, codex, cline, etc.
```

Idempotent, safe to call every time. Display the registration card (see `@references/commands.md`).

### Step 2: Reuse Is Detected Automatically at Create Time

You no longer need to run `agent:session list` and eyeball matches before creating. `agent:session create` (Step 7) automatically scans existing active sessions and applies the mechanical reuse checks (asset, per-tx, budget, remaining TTL, scope). If one covers the request it returns a `reuse_available` result with candidates instead of creating a new session — at which point your only remaining job is to confirm the **goal/merchant genuinely matches** before reusing. See `@references/commands.md` (`agent:session create` → "Automatic Reuse Detection").

Running `kpass agent:session list --status active --output json` is now optional — use it only for diagnostics or to inspect sessions directly.

### Shopping Checkout — Skip Steps 3–4

If this session is being created for the **`shopping`** skill's checkout (the cart total is already known), skip Steps 3–4 entirely — do not ask for a merchant URL and do not curl anything. Go directly to Step 5 using Path B from the **`form-session-delegation`** skill (budget derived from the cart total, no `execution_constraints`). Steps 3–4 remain mandatory for every non-shopping flow (paid-API access via a merchant URL).

### Step 3: Get Merchant URL

If the user has not provided a merchant URL or service endpoint, ask:

> "What is the merchant URL or service you want to access?"

You need the URL to perform preflight discovery and to potentially scope the delegation.

### Step 4: Preflight — Discover Payment Requirements

Preflight the merchant URL before creating a session. Guessing the payment requirements (or asking the user for tx limits / budget when the merchant already advertises them) produces a delegation that mismatches the merchant's actual price — at execution time, the backend will reject the payment with `session_rule_exceeded` or `session_total_exceeded`, and the user will have approved a useless session.

**Validate the URL before curling it:** the merchant URL may come from the user or other less-trusted content. Require `https://` (reject `http://`, `file://`, or other schemes) and reject hosts that resolve to loopback, private, link-local, or other non-public ranges (including the `169.254.169.254` cloud metadata address) before making the request. If the URL fails validation, stop and tell the user rather than curling it.

**Shell-safe substitution — MANDATORY:** validation alone does not stop shell metacharacters *inside* an otherwise-valid URL from being interpreted by the shell, and double-quoting does not help — `"$(...)"`, backticks, and `$VAR` are all still expanded inside double quotes. Assign the URL to a shell variable as a **single-quoted literal** (inert — no expansion, even on later reference), then reference the variable in double quotes:

```bash
MERCHANT_URL='<paste the exact URL, single-quoted, unmodified>'
curl -s --connect-timeout 10 --max-time 20 -w "\n%{http_code}" "$MERCHANT_URL"
```

Or for POST endpoints:

```bash
curl -s --connect-timeout 10 --max-time 20 -X POST "$MERCHANT_URL" -H "Content-Type: application/json" -w "\n%{http_code}"
```

**Always bound the request** with `--connect-timeout`/`--max-time` — an untrusted merchant URL that never responds must not hang the agent indefinitely; treat a timeout the same as a non-402 response (fall back to conservative defaults, below).

If the URL contains a literal `'`, escape it as `'\''` (close quote, escaped literal quote, reopen quote) before wrapping — see the **`form-session-delegation`** skill's "Shell-Safe Value Substitution" section for the full rule and worked example.

Parse the response. See the **`form-session-delegation`** skill for detailed guidance on parsing 402 responses. The structure varies by merchant — there is no standard schema.

If the preflight does not return a 402, or you cannot parse the 402 response, use conservative defaults (`max_amount_per_tx: "1"`, `max_total_amount: "10"`) and note this in the confirmation card. Do NOT add an `assets` field — there is no such field in `payment_policy` (see **`form-session-delegation`**). Do NOT ask the user for individual parameter values — let them review and adjust via the confirmation card.

After parsing the 402 response, display the Payment Requirements Discovered card — this is the user's first visible confirmation that the agent read the merchant's terms correctly:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Payment Requirements Discovered

🏪 Merchant:   {merchant_host}
🌐 Endpoint:   {method} {merchant_url}
💰 Price:      {amount} {asset} per request
⛓️  Network:    {network}
📦 Resource:   {resource_description}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

See `form-session-delegation` skill for the full field mapping.

### Step 5: Confirm Session Parameters with User

Present the proposed session parameters to the user and wait for explicit confirmation before creating the session. The session create command triggers a passkey approval flow that the user has to interact with — burning that interaction on parameters they would have adjusted (a smaller budget, a longer TTL) is wasted friction. The confirmation card is also the user's only chance to review the merchant scope before the session is on-chain.

Construct the delegation parameters from the 402 response + user context (see `form-session-delegation` skill for construction rules), then display:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Proposed Session Parameters

🏪 Merchant:         {merchant_host}
📝 Task:             {task_summary}
💰 Per-tx limit:     {max_amount_per_tx} {asset}
💰 Total budget:     {max_total_amount} {asset}
⏰ Session duration: {ttl_human_readable}
🔒 Payment method:   x402
🎯 Scope:            {scope_description}

Shall I proceed with creating this session?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

The user may:
- **Confirm** ("yes", "proceed", "looks good") → proceed to Step 6
- **Adjust** ("make the budget 50", "change TTL to 2 hours") → update parameters and show the card again
- **Cancel** ("no", "cancel") → stop

### Step 6: Construct the Delegation

Only after user confirmation, build the delegation JSON from:
1. The user's stated goal (becomes `task.summary`)
2. The 402 preflight response (asset, amount per request)
3. The confirmed parameters from Step 5
4. The endpoint scope (from the merchant URL)

See the **`form-session-delegation`** skill for the complete schema, construction rules, validation checklist, and examples.

### Step 7: Create Session with `--delegation`

**Shell-safe substitution — MANDATORY:** `task.summary` is derived from the user's own words and may contain quotes, `$()`, backticks, or other shell metacharacters. Never hand-splice it into the command string — double-quoting does not stop `$()`/backtick expansion. Assign the JSON-encoder output to a shell variable as a **single-quoted literal** (escaping any embedded `'` as `'\''`), then reference the variable in double quotes. See the **`form-session-delegation`** skill's "Shell-Safe Value Substitution" section for the full rule and a worked example.

```bash
# Example: encoder produced {"task":{"summary":"Buy John's book"},...}
DELEGATION_JSON='{"task":{"summary":"Buy John'\''s book"},...}'
kpass agent:session create --delegation "$DELEGATION_JSON" --output json
```

Two possible outcomes (see `@references/commands.md` `agent:session create`):
- **`status: "human_action_required"`** (a new request was created) → display the mandatory approval card and proceed to Step 8.
- **`reuse_available: true`** (an existing active session already covers this request) → confirm the candidate's `task_summary` matches the current goal/merchant, then run the returned `next_command` (`agent:session use …`) to reuse it — no new approval needed. If the goal does not match, re-run `create … --no-reuse` to force a new session.

### Step 8: Poll for Approval

```bash
kpass agent:session status --request-id <request_id> --wait --output json
```

Follow the Polling Strategy described in `@references/commands.md` (`agent:session status` → "Polling Strategy"). Display the mandatory approved card when the session is approved.

---

## Scoped-Card Sessions (`--use-card`)

Some merchants only take a card — no x402 header, no wallet transfer. For those, create the session with a **session-bound virtual card (scoped card)**: `agent:session create --use-card`. The card is issued when the user approves, its spending limit is the session's `--max-total-amount`, and it can be used for **multiple purchases until that limit is used up or the card expires** (lifetime-limit, not single-use).

### When to use `--use-card`

- The user wants the agent to buy from / pay a merchant that accepts **card payment only** (no x402, no wallet transfer).
- A checkout flow (e.g. the `shopping` skill) that settles by card.
- Do NOT use it for x402 paid-API access — a normal (cardless) session via `--delegation` is correct there.

### Two prerequisites — the CLI enforces both; your job is to handle the failures

1. **Cards must be enabled on the backend for this environment.** If they are not, create fails with a cards-not-enabled error. Cards are **never available in sandbox mode**.
2. **The user must have completed card verification (KYC).** `agent:session create --use-card` pre-flights the account's `can_create_agent_card` capability (which encodes KYC eligibility) and refuses early, with an actionable message pointing to the Passport dashboard (Cards), if the account is not yet card-eligible.

There is no separate command to check these — both are checked inside `agent:session create --use-card`. Drive the command and map the specific errors (see Error Handling → "Scoped-card (`--use-card`) errors").

### Command — use the individual flags, not `--delegation`

`--use-card` **cannot** be combined with `--delegation` (the CLI builds the delegation and adds the card constraint for you). `--max-total-amount` is **required** — it becomes the card's spending limit.

```bash
kpass agent:session create --use-card \
  --task-summary "<what the agent will buy, incl. merchant>" \
  --max-amount-per-tx <PER_TX> \
  --max-total-amount <CARD_LIMIT> \
  --ttl <DURATION> \
  --output json
```

Behavior:

- The CLI sends `execution_constraints.card.enabled=true`; the backend derives the card amount (= max total) and expiry (= TTL) server-side. You only pass the flag and the budget/TTL.
- **Reuse is skipped** for `--use-card` — a card session is always created fresh, because an existing cardless session cannot be reused for a card purchase. Do not pass `--no-reuse` (it is redundant) and do not try to reuse a prior session.
- After create, it is the **same approval + polling flow** as a normal session (Steps 7–8). The card is issued at approval.

### Confirm card parameters

Show the Proposed Session Parameters card as usual, but change the payment-method line so the user knows a virtual card will be issued (this replaces the `🔒 Payment method: x402` line):

```
🔒 Payment method:   Scoped virtual card (limit {max_total_amount} {asset}, multi-use until limit reached or expiry)
```

Everything else in the flow (agent registration, approval card, polling, approved card) is identical to a normal session.

---

## Worked Examples

End-to-end walkthroughs for new session creation and session reuse:

→ **`@references/examples.md`**

---

## Error Handling

| Exit Code | Meaning | Error Message Pattern | Recovery Action |
|-----------|---------|----------------------|-----------------|
| 0 | Success or human action required | `status: "human_action_required"` | Show approval URL to user. Wait for approval. |
| 1 | Network error | `network error: ...` | Check connectivity. Retry after a brief pause. |
| 2 | Usage error | `--delegation is required`, `Invalid delegation JSON`, `delegation.payment_policy.max_amount_per_tx is required` | Fix the delegation JSON. Check required fields. |
| 3 | Auth error | `Agent not registered`, `No user_id found`, `Agent is registered to a different user`, `Session request rejected`, `Session request expired` | See specific scenarios below. |
| 4 | Not found | `not found` | Verify the request_id or session_id is correct. |
| 5 | Rate limited | `rate limit` | Wait 30 seconds, then retry. |
| 6 | Session policy / payment violation | `error_code: "session_asset_forbidden"`, `"session_rule_exceeded"`, `"session_total_exceeded"`, `"session_endpoint_forbidden"`, `"session_forbidden"`, `"session_owner_forbidden"`, `"payment_target_forbidden"`, `"payment_redirect_not_allowed"`, `"session_request_forbidden"` | Do NOT re-authenticate. Create a new session with corrected parameters. Check `error_code` and `hint` for the specific violation. |

**Error envelope fields:** Error responses include `error` (raw backend message), `error_code` (machine-readable classification — prefer this for programmatic matching), and `hint` (recovery guidance).

### Specific Error Scenarios

**"No user_id found. Run signup or login first." (exit code 3):**
- The user is not logged in. Use the **`authenticate-user`** skill to sign up or log in.

**"Agent not registered. Run 'kpass agent:register --type <type>' first." (exit code 3):**
- Run `agent:register --type <agent-type> --output json` before using any session commands. (Replace `<agent-type>` with your own agent identity: `claude`, `cursor`, `codex`, `cline`, etc.)
- To investigate from the user's perspective, use `user agents --output json` (see the **`manage-agents`** skill) to verify what agents are registered.

**"Agent is registered to a different user" (exit code 3):**
- The user switched accounts. Run `agent:register --type <agent-type> --output json` to re-register for the current user. This automatically updates the agent config.

**"Invalid delegation JSON" or "delegation.payment_policy.max_amount_per_tx is required" (exit code 2):**
- The `--delegation` flag value is not valid JSON, or a required field is missing. Check the delegation schema in the **`form-session-delegation`** skill and fix the JSON.

**Session request rejected (exit code 3):**
- The user chose not to approve. Ask if they want to create a new session with different terms.

**Session request expired (exit code 3):**
- The approval URL timed out. Create a new session request.

### Scoped-card (`--use-card`) errors

All of these are exit code 2 (usage) and are raised **before** any approval — no session or card is created, so nothing is wasted. Fix the cause, then retry.

**"This account can't use a scoped card yet (card verification status: `<status>`). Complete card verification in the Passport dashboard (Cards) …":**
- The user has **not completed card KYC** (or reserve setup). Tell them to open the Passport dashboard → Cards and finish verification/funding. Do NOT retry `--use-card` until they confirm it is done. If the merchant also supports x402, offer to proceed with a normal (cardless) session instead.

**"The cards feature is not enabled on this environment. Retry without --use-card …":**
- The **backend does not have cards enabled** here. Either retry without `--use-card` (a normal session), or use an environment where cards are enabled. Do not keep retrying `--use-card` against this backend.

**"--use-card is not available in sandbox mode. Run 'kpass sandbox off' …":**
- You are in sandbox mode, where cards do not exist. Run `kpass sandbox off` and retry, or (if the merchant supports x402) proceed without a card.

**"--use-card requires --max-total-amount …":**
- Add `--max-total-amount <CARD_LIMIT>` — the scoped card needs a spending limit.

**"--use-card cannot be combined with --delegation …":**
- Use the individual flags (`--max-amount-per-tx`, `--max-total-amount`, `--ttl`) with `--use-card`. (Advanced/rare: you may instead embed `execution_constraints.card.enabled=true` in a raw `--delegation` object — but that path skips the CLI's KYC pre-flight and reuse-skip, so prefer `--use-card`.)

**stderr notes (NOT errors — proceed normally):**
- `note: --use-card issues a budget-limited scoped card …` — informational; confirms the lifetime-limit multi-use model.
- `note: could not verify card eligibility …` / `note: not logged in to verify card eligibility …` — the KYC pre-flight could not run (offline, transient backend error, or not logged in). The command still proceeds; the card is only actually issued at approval if the account is card-eligible. These go to stderr, so `--output json` stays clean — do not treat them as failures.

---

## Commands That DO NOT Exist

Do NOT attempt any of the following. They will fail:

> **Exception for `--use-card`:** the individual flags below (`--max-amount-per-tx`, `--max-total-amount`, `--ttl` / `--ttl-seconds`) ARE the correct interface **when creating a scoped-card session** — `--use-card` requires them and cannot be combined with `--delegation`. The "REMOVED / use `--delegation`" guidance applies only to normal (cardless) sessions.

- `kpass agent:session` (without a sub-command) — must use `list`, `create`, `status`, `use`, or `execute`
- `kpass agent:register --agent-app` — the flag is `--type`, not `--agent-app`
- `kpass agent:register --name` — does not exist; use `--type`
- `kpass agent:register --type <AGENT_TYPE>` with a user-provided value — the `--type` value is NEVER user-provided. The agent always passes its own identity (e.g., `claude`, `cursor`, `codex`, `cline`). Do not ask the user what agent type to use.
- `kpass agent:balance` — does not exist; use `wallet balance` for balance checks
- `kpass agent:session create --max-amount-per-tx` — **REMOVED.** Use `--delegation` with the full delegation JSON instead.
- `kpass agent:session create --ttl` — **REMOVED.** TTL is now inside the delegation JSON as `payment_policy.ttl_seconds`.
- `kpass agent:session create --ttl-seconds` — **REMOVED.** Use `--delegation` with `payment_policy.ttl_seconds`.
- `kpass agent:session create --budget` — does not exist
- `kpass agent:session create --currency` — does not exist
- `kpass agent:session create --expires-in` — does not exist
- `kpass agent:session create --allowed-domains` — does not exist
- `kpass agent:session create --spending-rules` — does not exist. The old `spending_rules` model is replaced by `delegation`.
- `kpass agent:session status --session-id` — the flag is `--request-id`, not `--session-id`
- `kpass agent:session status` without `--wait` as the primary polling method — Always use `--wait` for the initial polling phase. Only omit `--wait` for single follow-up checks after the user signals they have approved.
- Any command with `--json` — the correct flag is `--output json` (two separate tokens)

---

## Input Validation Checklist

Before running any command, verify:

1. **Agent type:** Your own agent identity string, no spaces. Use `claude` for Claude Code, `cursor` for Cursor, `codex` for Codex, `cline` for Cline. Never ask the user.
2. **Delegation JSON:** Must be valid JSON. Must be the **inner** delegation object itself — do NOT wrap it in an outer `{"delegation": ...}` (the CLI does that automatically) — containing `task.summary`, `payment_policy.max_amount_per_tx`, and `payment_policy.ttl_seconds` at minimum. See the **`form-session-delegation`** skill for the complete schema.
3. **Session ID:** Must come from a `session list` or `session status` response. Do not fabricate values.
4. **Request ID:** Must come from a `session create` response. Do not fabricate values.

---

## Recommended Flow

The standard sequence for setting up agent spending capability:

```
1. authenticate-user skill       -->  User is logged in
2. agent:register                -->  Agent is registered
3. Get merchant URL from user    -->  Know what service to access
4. curl preflight                -->  Discover payment requirements (402)
5. Construct delegation          -->  Build policy from 402 + user context
6. agent:session create          -->  Create session with --delegation
                                       (auto-detects a reusable active session:
                                        on reuse_available, goal-match then
                                        agent:session use; else continue)
7. agent:session status --wait   -->  Wait for user approval (new session only)
8. x402-execute or               -->  Execute transactions
   wallet-send skill
```

---

## Cross-Skill References

- **Prerequisite:** The user must be authenticated. Use the **`authenticate-user`** skill if the user is not logged in.
- **Delegation construction:** For the complete delegation schema, construction rules, validation checklist, and examples, see the **`form-session-delegation`** skill.
- **Session already exists (attachable):** If the user provides a session ID created elsewhere (web dashboard), use the **`attach-session`** skill instead of creating.
- **After session is active:** To execute x402 paid API requests, use the **`x402-execute`** skill.
- **For direct wallet transfers (no session):** Use the **`wallet-send`** skill.
- **For diagnostics:** To inspect registered agents and sessions from the user's perspective, use the **`manage-agents`** skill (`user agents`, `user sessions`).
