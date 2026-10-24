---
name: request-session
description: >-
  Create a separate spending session that the user approves with a passkey. Use
  when the account allowance can't pay (the CLI says so), the user asks for a
  separate spending session, or for a shopping checkout (the allowance never pays
  checkouts). Paid API calls on an account with an allowance need no session: go to
  x402-execute. Handles agent registration, merchant preflight, delegation
  construction, the preview the user sees first, and passkey approval. For
  card-only merchants it also creates session-bound scoped-card (virtual card)
  sessions via `--use-card`, gated on backend cards support and user card KYC.
  Wallet transfers (wallet-send) use their own flow and don't need a session.
user-invocable: true
allowed-tools:
  - "Bash(bash */setup.sh*)"
  - "Bash(kpass agent:register*)"
  - "Bash(kpass session *)"
  - "Bash(curl *)"
---

# Request Session

Register the agent identity and create, monitor, or reuse separate spending sessions with user approval. **The account allowance comes first:** on an account with an allowance, paid API calls go straight to `x402-execute` and need nothing from this skill. The CLI enforces this: `kpass session create` creates a passkey request only with `--separate`, and only after it has told you why the allowance can't pay. A separate session authorizes the agent to spend funds on behalf of the user, gated by a delegation policy (task description, payment policy with per-tx and total caps, optional execution constraints).

## Step 0: Ensure CLI is Installed — MANDATORY

Run the setup script before any `kpass` command — the script verifies the CLI is installed and configured for this user, and a missing or stale binary surfaces as a confusing exit-3 ("Not logged in") rather than a clean "CLI not installed" error if you skip it.

```bash
bash <skill-directory>/scripts/setup.sh
```

Where `<skill-directory>` is the directory containing this SKILL.md file (e.g., the directory this skill is installed in).

**If setup succeeds** (`status: "ok"`): proceed.
**If setup fails** (`status: "error"`): **STOP immediately.** Show the user the error and installation instructions. Do NOT search for the binary elsewhere.

## When to Use This Skill

- The CLI said the account allowance can't pay (`allowance_unavailable`, `allowance_disabled`, `recurring_budget_exhausted`, `allowance_too_small`) and the task still needs a paid call.
- The user asks for a separate spending session ("set up a separate spending limit for X").
- The **`shopping`** skill needs a session before checkout (always `--separate`; the allowance does not pay checkouts). The cart total is the budget source, no 402 preflight needed.
- Another skill (e.g., `x402-execute`) fails with "Agent not registered".
- The user wants to see their active sessions.

Do NOT use this skill when the user already has an **attachable session ID**
(e.g., a session pre-created in the Passport web dashboard). Use the
**`attach-session`** skill instead — attaching binds the existing session with
one approval; creating here would mint a redundant session and burn a second
approval on a policy the owner already defined.

**Never reach Passport over MCP.** Passport has no MCP surface: the hosted connector and the `passport-mcp` stdio server are both deleted, and the CLI (`kpass`) is the whole access path. An `mcp__kite-passport__*` tool still listed in this session is a stale local build of a server that no longer exists -- do not call any of them. Its session and funding tools now hit routes that 404, but its registry and binding tools still work against live APIs, which is why the rule is the whole family rather than the broken half.

## Sessions Are Protocol-Agnostic

A separately approved legacy session is fungible across paid-API and shopping flows. The settlement protocol (x402, paygate, tempo, or crossmint checkout) is detected at execute time from the merchant's preflight response — the delegation does **not** carry a protocol field. The authorization boundary is per-tx / total spending caps (`max_amount_per_tx` / `max_total_amount`, denominated in `payment_policy.currency`, default `USD`) plus optional `execution_constraints` endpoint scoping — there is **no `assets` allowlist field** and the caps are never expressed per-asset. The settlement asset itself is a separate, merchant-selected concern: the merchant's 402 dictates which token settles (normalized into the budget currency for cap enforcement), and the session locks to that first settled asset automatically (single-asset lock) — this lock is an emergent side effect of settlement, not a user-configurable allowlist. See the **`form-session-delegation`** skill for the full schema.

For the full delegation schema and derivation rules, see the **`form-session-delegation`** skill.

## Prerequisites

The user MUST be authenticated before using this skill. If not logged in (exit code 3 with "No user_id found" or "Not logged in"), use the **`authenticate-user`** skill first.

**Diagnostics:** If you encounter "agent not registered" or "no active sessions" errors and need to investigate, use the **`manage-agents`** skill to inspect registered agents (`user agents`) and session history (`user sessions`) from the user's perspective.

## Defaults (Do Not Ask the User Unless They Specify Otherwise)

| Setting | Default value | Override |
|---------|--------------|---------|
| Output format | `--output json` | Always use JSON output. Never omit this flag. |
| Agent type | Your own agent identity (e.g., `claude` for Claude Code, `cursor` for Cursor, `codex` for Codex, `cline` for Cline, `grok-bot` for Grok Bot) | Never ask the user. Each agent passes its own name automatically. |
| TTL | `3600` (1 hour) in delegation `ttl_seconds` | Use 1 hour unless the user specifies a different duration. |
| Max amount per tx | Derive automatically from 402 preflight response OR from a known amount (e.g., shopping cart total) | Never ask the user for this. See **`form-session-delegation`** for derivation rules. |
| Max total amount | Derive automatically: per-tx price × estimated requests, or equal to per-tx for single transactions (e.g., shopping checkout) | Never ask the user. See **`form-session-delegation`** for derivation rules. |
| Base URL | Omit (uses built-in default) | Only pass `--base-url` if the user explicitly provides a custom backend URL. |

## Display Cards

Render the formatted status cards (templated in `@references/commands.md`) verbatim after each successful command — the horizontal-rule format is what users scan to confirm what happened, and the eval grader looks for the exact strings inside them. Summarizing or rewording in plain text loses both signals.

---

## Command Reference

Full per-command detail — argument tables, JSON outputs, error envelopes, display cards, and the **6-check Session Reuse Evaluation** (under `session list`) — lives in:

→ **`@references/commands.md`**

Read that file before running any `agent:register` or `session` command.

---

## Full Session Creation Flow

The delegation model adds preflight discovery and structured delegation construction. Here is the complete flow.

### Step 1: Ensure Agent is Registered

```bash
kpass agent:register --type <agent-type> --output json
# Replace <agent-type> with your agent's identity: claude, cursor, codex, cline, etc.
```

Idempotent, safe to call every time. Display the registration card (see `@references/commands.md`).

### Step 1b: The Account Allowance First

Skip this step for a shopping checkout, a `--use-card` session, or when the user asked for a separate session.

```bash
kpass session create --output json
```

- **Exit 0 with `source: "separate"`**: a separate session the user approved is current and still pays. Go to **`x402-execute`**; nothing to create.
- **`separate_session_used_up`**: the separate session the user approved is used up. Stop and put the CLI's `user_message` in your reply. With the user's yes to a new separate session, continue with Step 3 (do not run this step again); with their yes to the allowance, pay with `x402-execute` plus `--use-allowance`.
- **Exit 0** (`source: "allowance"`): the account allowance pays. Put its `user_message` in your reply if useful and go to **`x402-execute`**. Stop here; no passkey request.
- **An `allowance_*` or `recurring_budget_exhausted` error**: the allowance can't pay. Its `user_message` says why with the numbers (no active allowance, turned off by the owner, used up until a date in UTC, too little left), and for none, used up and too small it says the CLI opened the owner's allowance page in the browser (with the link). Put it in your reply as is. Continue with Step 3 to build the separate session, as the other way to pay.
- **Exit 3**: sign in first (`authenticate-user`).

### Step 2: Reuse Is Detected Automatically at Create Time

You no longer need to run `session list` and eyeball matches before creating. `session create --separate` (Step 7) automatically scans existing active sessions and applies the mechanical reuse checks (asset, per-tx, budget, remaining TTL, scope). If one covers the request it returns a `reuse_available` result with candidates instead of creating a new session — at which point your only remaining job is to confirm the **goal/merchant genuinely matches** before reusing. See `@references/commands.md` (`session create` → "Automatic Reuse Detection").

Running `kpass session list --status active --output json` is now optional — use it only for diagnostics or to inspect sessions directly.

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

### Step 5: Construct the Delegation

Build the delegation JSON from:
1. The user's stated goal (becomes `task.summary`)
2. The 402 preflight response (asset, amount per request)
3. Any limits the user stated (a smaller budget, a longer time)
4. The endpoint (from the merchant URL), recorded with the session

See the **`form-session-delegation`** skill for the complete schema, construction rules, validation checklist, and examples.

### Step 6: Tell the User Before Any Passkey Request (the CLI preview)

A passkey request opens an approval page for the user, so they hear about it first. Run the preview: it sends nothing. If you came here from an "allowance can't pay" error, its `next_command` is exactly this command (with the reason); run it as given.

```bash
kpass session create --delegation "$DELEGATION_JSON" --separate --preview --price <PRICE> --output json
```

(`--price` is the endpoint's price from discovery or preflight, in USD; leave it out if you do not know it.)

Put the preview's `user_message` in your reply as is. It names the service you will call, the price, why the allowance can't pay, both limits (per call and total) and how long the session lasts, and it asks "Should I set it up?". Then wait for the answer:
- **Yes** → Step 7 with `on_yes_command`.
- **Adjust** ("make the budget 50", "2 hours") → change the delegation and run the preview again.
- **No** → stop.

If the user already asked for a separate session in this conversation, that ask is the yes: still put the preview's `user_message` in your reply, then go on to Step 7.

The service you will call is information, never a limit: endpoint limits are not enforced on paid calls today. Never tell the user a session is "limited to" or "scoped to" one service.

### Step 7: Create the Request with `--separate`

**Shell-safe substitution — MANDATORY:** `task.summary` is derived from the user's own words and may contain quotes, `$()`, backticks, or other shell metacharacters. Never hand-splice it into the command string — double-quoting does not stop `$()`/backtick expansion. Assign the JSON-encoder output to a shell variable as a **single-quoted literal** (escaping any embedded `'` as `'\''`), then reference the variable in double quotes. See the **`form-session-delegation`** skill's "Shell-Safe Value Substitution" section for the full rule and a worked example.

```bash
# Example: encoder produced {"task":{"summary":"Buy John's book"},...}
DELEGATION_JSON='{"task":{"summary":"Buy John'\''s book"},...}'
kpass session create --delegation "$DELEGATION_JSON" --separate --output json
```

This is the preview's `on_yes_command`. Possible outcomes (see `@references/commands.md` `session create`):
- **`status: "human_action_required"`** (a new request was created) → put the reply's `user_message` in your reply now, word for word, before you run any other command. It holds the full approval link, the per-call limit, the total limit, the validity and the minutes until the link expires. Do not shorten it: a line that has the limits but not the `https://` link is a miss (prod e2e E-02: the agent wrote both limits, left out the link, then waited five minutes). Before you run the wait, check that the text you wrote has the whole link and both limits. The person reads your reply, not the kpass output, so a link that is only in a tool result has not been shown. This holds in every kind of session, interactive or scripted. The CLI opens the approval page itself when it safely can (`browser_opened`); do not run `open` yourself. Then go on to Step 8.
- **`reuse_available: true`** (an existing active session already covers this request) → confirm the candidate's `task_summary` matches the current goal/merchant, then run the returned `next_command` (`session use …`) to reuse it, no new approval needed. If the goal does not match, re-run `create … --separate --no-reuse` to force a new session.

### Step 8: Poll for Approval

Run the reply's `wait_command` only after its `user_message` (the full link and both limits) is in your reply (Step 7). `next_command` is empty on purpose. The wait blocks for up to five minutes, and anything you have not written yet stays invisible for all of it.

```bash
kpass session status --request-id <request_id> --wait --output json
```

Follow the Polling Strategy described in `@references/commands.md` (`session status` → "Polling Strategy"). Display the mandatory approved card when the session is approved.

---

## Scoped-Card Sessions (`--use-card`)

Some merchants only take a card — no x402 header, no wallet transfer. For those, create the session with a **session-bound virtual card (scoped card)**: `session create --use-card`. The card is issued when the user approves, its spending limit is the session's `--max-total-amount`, and it can be used for **multiple purchases until that limit is used up or the card expires** (lifetime-limit, not single-use).

### When to use `--use-card`

- The user wants the agent to buy from / pay a merchant that accepts **card payment only** (no x402, no wallet transfer).
- A checkout flow (e.g. the `shopping` skill) that settles by card.
- Do NOT use it for x402 paid-API access — a normal (cardless) session via `--delegation` is correct there.

### Two prerequisites — the CLI enforces both; your job is to handle the failures

1. **Cards must be enabled on the backend for this environment.** If they are not, create fails with a cards-not-enabled error. Cards are **never available in sandbox mode**.
2. **The user must have completed card verification (KYC).** `session create --use-card` pre-flights the account's `can_create_agent_card` capability (which encodes KYC eligibility) and refuses early, with an actionable message pointing to the Passport dashboard (Cards), if the account is not yet card-eligible.

There is no separate command to check these — both are checked inside `session create --use-card`. Drive the command and map the specific errors (see Error Handling → "Scoped-card (`--use-card`) errors").

### Command — use the individual flags, not `--delegation`

`--use-card` **cannot** be combined with `--delegation` (the CLI builds the delegation and adds the card constraint for you). `--max-total-amount` is **required** — it becomes the card's spending limit.

```bash
kpass session create --use-card \
  --task-summary "<what the agent will buy, incl. merchant>" \
  --max-amount-per-tx <PER_TX> \
  --max-total-amount <CARD_LIMIT> \
  --ttl <DURATION> \
  --output json
```

Behavior:

- The CLI sends `execution_constraints.card.enabled=true`; the backend derives the card amount (= max total) and expiry (= TTL) server-side. You only pass the flag and the budget/TTL.
- **Reuse is skipped** for `--use-card` — a card session is always created fresh, because an existing cardless session cannot be reused for a card purchase. Do not pass `--no-reuse` (it is redundant) and do not try to reuse a prior session.
- `--use-card` never uses the account allowance, so it needs no `--separate`. Tell the user first all the same: run the same command with `--preview` added, put its `user_message` in your reply, and add that a virtual card will be issued (limit = the total, multi-use until the limit is reached or it expires).
- After create, it is the **same approval + polling flow** as a normal session (Steps 7–8). The card is issued at approval.

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
| 6 | Separate session used up | `error_code: "session_total_exceeded"`, `"separate_session_used_up"` | Stop and put the CLI's `user_message` in your reply. Never switch to the account allowance on your own. With the user's yes: a new separate session (Steps 3-8, preview first), or `--use-allowance` on execute. |
| 6 | Session policy / payment violation | `error_code: "session_asset_forbidden"`, `"session_rule_exceeded"`, `"session_endpoint_forbidden"`, `"session_forbidden"`, `"session_owner_forbidden"`, `"payment_target_forbidden"`, `"payment_redirect_not_allowed"`, `"session_request_forbidden"` | Do NOT re-authenticate. Check `error_code` and `hint`. A new separate session with corrected parameters goes through Steps 3-8 (preview, then the user's yes). |
| 6 | Allowance cancelled | `error_code: "allowance_cancelled"` | The CLI already bound once to the owner's current allowance and retried. Stop and tell the user the owner cancelled the allowance. Do not request a broader session to get around it. |
| 4 / 6 | The allowance can't pay (from `session create` without `--separate`) | `error_code: "allowance_unavailable"` (4), `"allowance_disabled"`, `"recurring_budget_exhausted"`, `"allowance_too_small"` (6) | No request was created. Run the CLI's `next_command` (the `--separate --preview` step, Step 6) and put its `user_message` in your reply. Never add `--separate` yourself without that step. |
| 0 | Allowance available (no request) | `allowance_available: true` | The account allowance pays. Run `next_command` and go to **`x402-execute`**. Use `--separate` only if the user asked for a separate session. |

**Error envelope fields:** Error responses include `error` (raw backend message), `error_code` (machine-readable classification — prefer this for programmatic matching), and `hint` (recovery guidance).

### Specific Error Scenarios

**"No user_id found. Run signup or login first." (exit code 3):**
- The user is not logged in. Use the **`authenticate-user`** skill to sign up or log in.

**"Agent not registered. Run 'kpass agent:register --type <type>' first." (exit code 3):**
- Run `agent:register --type <agent-type> --output json` before using any session commands. (Replace `<agent-type>` with your own agent identity: `claude`, `cursor`, `codex`, `cline`, `grok-bot`, etc.)
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

- `kpass session` (without a sub-command) — must use `list`, `create`, `status`, `use`, or `execute`
- `kpass agent:register --agent-app` — the flag is `--type`, not `--agent-app`
- `kpass agent:register --name` — does not exist; use `--type`
- `kpass agent:register --type <AGENT_TYPE>` with a user-provided value — the `--type` value is NEVER user-provided. The agent always passes its own identity (e.g., `claude`, `cursor`, `codex`, `cline`, `grok-bot`). Do not ask the user what agent type to use.
- `kpass agent:balance` — does not exist; use `wallet balance` for balance checks
- `kpass session create --max-amount-per-tx` — **REMOVED.** Use `--delegation` with the full delegation JSON instead.
- `kpass session create --ttl` — **REMOVED.** TTL is now inside the delegation JSON as `payment_policy.ttl_seconds`.
- `kpass session create --ttl-seconds` — **REMOVED.** Use `--delegation` with `payment_policy.ttl_seconds`.
- `kpass session create --budget` — does not exist
- `kpass session create --currency` — does not exist
- `kpass session create --expires-in` — does not exist
- `kpass session create --allowed-domains` — does not exist
- `kpass session create --spending-rules` — does not exist. The old `spending_rules` model is replaced by `delegation`.
- `kpass session create --delegation ...` **without `--separate`** does not create a request on an account with an allowance: it returns `allowance_available` (or the reason the allowance can't pay). Real flags for a separate session: `--separate`, `--preview`, `--no-browser`, `--price`.
- `kpass session status --session-id` — the flag is `--request-id`, not `--session-id`
- `kpass session status` without `--wait` as the primary polling method — Always use `--wait` for the initial polling phase. Only omit `--wait` for single follow-up checks after the user signals they have approved.
- Any command with `--json` — the correct flag is `--output json` (two separate tokens)

---

## Input Validation Checklist

Before running any command, verify:

1. **Agent type:** Your own agent identity string, no spaces. Use `claude` for Claude Code, `cursor` for Cursor, `codex` for Codex, `cline` for Cline, `grok-bot` for Grok Bot. Never ask the user.
2. **Delegation JSON:** Must be valid JSON. Must be the **inner** delegation object itself — do NOT wrap it in an outer `{"delegation": ...}` (the CLI does that automatically) — containing `task.summary`, `payment_policy.max_amount_per_tx`, and `payment_policy.ttl_seconds` at minimum. See the **`form-session-delegation`** skill for the complete schema.
3. **Session ID:** Must come from a `session list` or `session status` response. Do not fabricate values.
4. **Request ID:** Must come from a `session create` response. Do not fabricate values.

---

## Recommended Flow

The standard sequence for setting up agent spending capability:

```
1. authenticate-user skill       -->  User is logged in
2. agent:register                -->  Agent is registered
3. session create (plain)        -->  Account allowance pays? Go to x402-execute. Done.
4. Get merchant URL from user    -->  Know what service to access
5. curl preflight                -->  Discover payment requirements (402)
6. Construct delegation          -->  Build policy from 402 + user context
7. session create --separate --preview
                                 -->  Put user_message in your reply, ask
8. session create --separate     -->  After the yes (auto-detects a reusable
                                       active session: on reuse_available,
                                       goal-match then session use)
9. user_message in the reply     -->  Link, limits, expiry, BEFORE the wait
10. session status --wait        -->  Wait for user approval (new session only)
11. x402-execute or              -->  Execute transactions
    shopping checkout
```

---

## Cross-Skill References

- **Prerequisite:** The user must be authenticated. Use the **`authenticate-user`** skill if the user is not logged in.
- **Delegation construction:** For the complete delegation schema, construction rules, validation checklist, and examples, see the **`form-session-delegation`** skill.
- **Session already exists (attachable):** If the user provides a session ID created elsewhere (web dashboard), use the **`attach-session`** skill instead of creating.
- **After session is active:** To execute x402 paid API requests, use the **`x402-execute`** skill.
- **Account allowance:** paid API calls on an account with an allowance go straight to **`x402-execute`**; this skill is only for the separate session.
- **For direct wallet transfers (no session):** Use the **`wallet-send`** skill.
- **For diagnostics:** To inspect registered agents and sessions from the user's perspective, use the **`manage-agents`** skill (`user agents`, `user sessions`).
