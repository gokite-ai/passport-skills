# Report Feedback — Worked Example

End-to-end walkthrough for the `report-feedback` skill. Per-command syntax, argument tables, and error handling live in `commands.md`; the confirmation gate and mandatory display cards live in `SKILL.md`.

---

## Worked Example

**User:** "the checkout has failed three times with the same error, please file a bug about this."

**Agent (1) — gather context** (no extra commands required; agent has the prior session in memory).

**Agent (2) — show pre-submit card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Feedback to submit
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Category:  bug
  Session:   sess_91xyz
  Metadata:  model, last_exit_code, retries, command

  Content:
  Shopping checkout via `kpass shop:checkout` failed three
  times in a row with the same error: "treasury wallet
  underfunded for asset USDC on base-sepolia". Cart total
  was $12.49, session sess_91xyz had a max_total_amount of...
  ...(truncated)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

"Send this feedback?"

**User:** "yes, send it"

**Agent (3) — run the command:**

The feedback content is short enough to pass inline, so use `--content` rather than `--content-file` (which would require first writing the text to a file):

```bash
kpass agent:feedback submit \
  --content 'Shopping checkout via `kpass shop:checkout` failed three times in a row with the same error: "treasury wallet underfunded for asset USDC on base-sepolia". Cart total was $12.49, session sess_91xyz had a max_total_amount of...' \
  --category bug \
  --session-id sess_91xyz \
  --metadata '{"model":"claude-opus-4-7","last_exit_code":1,"retries":3,"command":"kpass shop:checkout"}' \
  --output json
```

**Agent (4) — show post-submit card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Feedback submitted
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ID:         feedback_4a7e8c9d-1234-...
  Created:    2026-05-20T17:30:00Z
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

"Filed. The Passport team will see this with the session and error context attached."
