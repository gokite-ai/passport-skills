---
name: report-feedback
description: >-
  Submit free-form feedback or issue reports from the current agent session to
  Passport. Proactively invoke when the user says "report this", "file a bug",
  "send feedback", "log this issue", or describes a failure worth surfacing.
  Also invoke at the end of a multi-step task to capture successes or
  surprises that future debugging would benefit from.
user-invocable: true
allowed-tools:
  - "Bash(kpass agent:feedback*)"
  - "Bash(kpass agent:register*)"
  - "Bash(kpass me*)"
---

# Report Feedback

Submit free-form textual feedback or issue reports from the current Claude agent session to the Passport backend. Useful for filing bugs, capturing failures, recording successes, or attaching session context that humans on the Passport team can review later.

Feedback is written under the **agent's owner** (the authenticated user) using the agent's JWT. Each submission stores a body (up to 1 MiB), an optional category, an optional session ID, and a JSON metadata object queryable in Postgres.

> **Reference files** (read when you need exact detail):
> - `@references/commands.md` — full command reference, argument table, error handling.
> - `@references/examples.md` — worked example.

## When to Use This Skill

- The user says **"report this"**, **"file a bug"**, **"send feedback"**, **"let the team know"**, **"log this issue"**, or any phrasing that explicitly asks to surface something to Passport.
- The agent hits an **unrecoverable failure** during a multi-step task (e.g., checkout failed three times in a row, an API returned an unexpected schema, a tool emitted an exit code with no clear recovery) and capturing context would help the team.
- The user wraps up a complex session and wants to **leave a note** (positive or negative) — e.g., "before we wrap, file a quick note that the new search results were way better."
- The user reports something **confusing or unexpected** about the product behavior that the team should know about.

## When NOT to Use This Skill

- The user is asking a navigation or how-to question — answer it directly; don't file feedback about it.
- The user is mid-task and just wants help — finish helping first; offer to file feedback only if the situation warrants it.
- There's no concrete observation, error, or intent to file. Don't invent feedback to seem helpful.
- The user is asking to **read** prior feedback or activity — use the **`activity`** skill instead (and note that feedback rows are not yet surfaced in the activity feed; that's a future feature).
- Payments, wallet ops, shopping checkout — use the dedicated skills (`x402-execute`, `wallet-send`, `shopping`).

## Prerequisites

1. **User authenticated** — if not (exit code 3 with "Not logged in"), use the **`authenticate-user`** skill first.
2. **Agent registered** — if the agent's local config is missing (`Agent not registered` on exit code 3), run:
   ```bash
   kpass agent:register --type <agent-type> --output json
   # Replace <agent-type> with your agent's identity: claude, cursor, codex, cline, etc.
   ```
3. **No spending session required** — feedback is a free agent-JWT call.

## Defaults (Do Not Ask the User Unless They Specify Otherwise)

| Setting | Default value | Override |
|---------|--------------|----------|
| Output format | `--output json` | Always use JSON output. Never omit this flag. |
| Category | Pick one from the suggested list (see below) | Override only if the user names a specific category. |
| Session ID | Omit (most calls do not have one in scope) | Pass `--session-id` only when a session is genuinely relevant. |
| Metadata | Always include at least `{"model": "<your-model-id>"}` | Add more keys when relevant. Keep it a flat JSON object. |
| Base URL | Omit (uses built-in default) | Only pass `--base-url` if the user explicitly provides a custom backend URL. |

## What to Capture (Checklist Before Running the Command)

Walk through this before invoking:

1. **Content** (`--content`, required): a clear summary of what happened. Include:
   - What the user was trying to do
   - What went wrong (if a failure), or what was notable (if positive feedback)
   - Key error messages or exit codes verbatim, if any
   - A short reproduction recipe if relevant
   Aim for a few sentences to a few paragraphs. If you have a very long transcript (>4 KB), write it to a temp file and use `--content-file`.

2. **Category** (`--category`, optional but recommended): pick the closest match:

   | Category | Use for |
   |----------|---------|
   | `bug` | Reproducible incorrect behavior |
   | `incident` | One-off failure or outage with unclear cause |
   | `success` | Notable positive outcome worth recording |
   | `feature_request` | User wants a capability that doesn't exist |
   | `confused` | Behavior was unexpected or unclear, but not necessarily broken |

3. **Session ID** (`--session-id`, optional): pass if a spending session was active when the issue happened and is relevant context.

4. **Metadata** (`--metadata`, optional but encouraged): a flat JSON object. At minimum include the model identifier. Add fields that help diagnose:
   ```json
   {
     "model": "claude-opus-4-7",
     "tool_call_count": 17,
     "last_exit_code": 5,
     "command": "kpass shop:checkout"
   }
   ```
   Keys are free-form; future queries (`metadata_json->>'model'`) decide what's useful.

## Verify Before Filing Payment / Settlement / Ledger Bugs

Claims that a payment "didn't settle", "was charged but the money never moved", "double-charged", or that the **ledger/balance disagrees with the chain** are high-severity and frequently turn out to be false alarms. Before filing one, verify on-chain — do **NOT** file off a `wallet balance` reading alone:

1. **Capture the settlement reference.** Pull the EVM `transaction_hash` or Solana signature from the execute response (`payment.payment_response.reference` / `payment_receipt`) or the **`activity`** record, and confirm it on-chain. Include that reference in the feedback.
2. **Re-read `wallet balance` — it reads fresh by default.** The command forces a fresh read (bypassing the backend's 30s cache) unless you pass `--cached` or run a very old client, so a re-read after a payment reflects the on-chain debit. An unchanged balance is far more likely a **cached read or the wrong wallet** than a missing debit — confirm you're looking at the **wallet that actually paid** (agent-session execute pays from the session/agent wallet). The on-chain settlement reference (step 1) remains the strongest evidence.
3. **State what you verified.** If you could not check on-chain, say "not verified on-chain" rather than asserting a ledger mismatch.

A settlement-integrity report without an on-chain reference is almost always a cache / wrong-wallet / wrong-method confound — capturing the reference up front saves a costly investigation.

## Confirmation Gate

**Show the user a pre-submit display card and wait for explicit confirmation before running the command.**

Exception: if the user **originated** the request (e.g., "file a bug about this"), confirmation is implicit — you may submit directly, but still show the pre-submit card so they know what's being sent.

Never auto-file feedback without the user being aware.

## Display Cards (MANDATORY)

### Pre-submit Preview

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Feedback to submit
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Category:  {category or "(none)"}
  Session:   {session_id or "(none)"}
  Metadata:  {comma-separated keys from --metadata}

  Content:
  {first ~200 chars of --content, then "...(truncated)" if longer}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Ask: **"Send this feedback?"** Wait for an explicit affirmative.

### Post-submit Confirmation

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Feedback submitted
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ID:         {feedback_id}
  Created:    {created_at}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

See `@references/commands.md` for the full `agent:feedback submit` argument table, every JSON output shape (success and error), and the input validation checklist. See `@references/examples.md` for a worked end-to-end example (filing a bug from a failed checkout).

## Error Handling

| Exit code | Meaning | Recovery |
|-----------|---------|----------|
| 0 | Success | Show post-submit card |
| 1 | Network / server error / oversized content | Do NOT auto-retry — submission is not idempotent, so a lost response doesn't tell you whether the row was already written. Surface the error and offer to save locally; only resubmit if the user explicitly asks (see `@references/commands.md`). |
| 2 | Usage error (missing/invalid flag) | Fix the flag and re-run |
| 3 | Auth error (agent not registered or token expired) | Run `kpass agent:register --type <agent-type> --output json`; if still failing, use `authenticate-user` skill |
| 4 | Not found | Should not happen for this command; surface error to user |

See `@references/commands.md` for the exact error envelope of every state.

## Cross-Skill References

- **Prerequisites:** [`authenticate-user`](../authenticate-user/SKILL.md) — the user must be logged in.
- **Related:**
  - [`activity`](../activity/SKILL.md) — view recent account activity. Note: feedback rows are stored in a separate table and are not currently surfaced in the activity feed.
  - [`manage-agents`](../manage-agents/SKILL.md) — inspect the agent's owner/session if the user asks "who is this filed under?"
