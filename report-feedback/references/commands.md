# Report Feedback — Command Reference

Full reference for the `report-feedback` skill's `agent:feedback submit` command. SKILL.md carries the trigger logic, the pre-submit checklist, and mandatory display cards; this file has the command-level detail (argument table, every JSON shape, error handling, and input validation). A worked end-to-end example lives in `examples.md`.

---

## `agent:feedback submit` -- Submit Feedback

Posts feedback to the Passport backend under the authenticated agent's owner. Idempotency is not enforced — calling it twice creates two rows.

Minimal form:

```bash
kpass agent:feedback submit --content "<text>" --output json
```

Full form:

```bash
kpass agent:feedback submit \
  --content "<text>" \
  --category <category> \
  --session-id <session_id> \
  --metadata '<json-object>' \
  --output json
```

For long content (multi-KB transcripts), write to a file first:

```bash
kpass agent:feedback submit \
  --content-file /tmp/feedback.txt \
  --category incident \
  --metadata '{"model":"claude-opus-4-7","tool_call_count":42}' \
  --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Content | `--content` | Yes (or `--content-file`) | Free-form text | Non-empty after trim; ≤ 1 MiB |
| Content file | `--content-file` | Yes (or `--content`) | Path to a UTF-8 text file | File exists, readable, non-empty |
| Category | `--category` | No | One of the suggested tokens | Short single token; free-form on backend |
| Session ID | `--session-id` | No | An existing session ID | String; backend does not require it |
| Metadata | `--metadata` | No | JSON object | Must parse as a flat JSON object (e.g. `'{"k":"v"}'`); array or scalar values inside object keys are fine |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

**Mutual exclusion:** Pass exactly one of `--content` or `--content-file`. Passing both fails with exit code 2.

### Success Output (exit code 0)

```json
{
  "feedback_id": "feedback_4a7e8c9d-...-...",
  "created_at": "2026-05-20T17:30:00Z",
  "_version": "1",
  "status": "success",
  "hint": "Feedback submitted.",
  "next_command": ""
}
```

**Key fields:**
- `feedback_id` — server-assigned identifier. Useful if a human follows up about this feedback.
- `created_at` — ISO 8601 timestamp when the row was persisted.

### Error Output -- Missing content (exit code 2 USAGE)

```json
{
  "status": "error",
  "error": "Missing --content. Usage: kpass agent:feedback submit --content <text> --output json (or --content-file <path>)",
  "error_code": "USAGE"
}
```

**Recovery:** Provide either `--content "<text>"` or `--content-file <path>`.

### Error Output -- Invalid metadata (exit code 2 USAGE)

```json
{
  "status": "error",
  "error": "Invalid --metadata JSON object: ...",
  "error_code": "USAGE"
}
```

**Recovery:** Re-quote the JSON. Use single quotes around the whole flag value and double quotes inside: `--metadata '{"model":"claude-opus-4-7"}'`.

### Error Output -- Not registered (exit code 3 AUTH)

```json
{
  "status": "error",
  "error": "Agent not registered. Run 'kpass agent:register --type <agent-type> --output json' first.",
  "error_code": "AUTH"
}
```

**Recovery:** Run `kpass agent:register --type <agent-type> --output json` (substitute your agent's identity), then retry.

### Error Output -- Content too large (exit code 1 NETWORK or USAGE)

If `--content` exceeds 1 MiB the backend returns 413. Recovery: trim content to the most relevant slice, or split into multiple feedback rows.

### Error Output -- Server error (exit code 1)

```json
{"status": "error", "error": "...", "error_code": "NETWORK"}
```

**Recovery:** Submission is not idempotent (see above) — a network/server error does not tell you whether the row was actually persisted before the response was lost. Do not automatically retry. Tell the user it failed and let them decide whether to resubmit (accepting a possible duplicate row) or drop it.

### What to Do After This Command

On success:
1. Show the **Post-submit confirmation** display card.
2. Briefly thank the user.
3. Return to whatever task was in progress, or end the session cleanly.

On failure:
1. Tell the user the submission failed and why.
2. Offer to save the content locally so it isn't lost (e.g., paste it to a file path or scratch buffer).
3. Only resubmit if the user explicitly asks to try again — since there is no idempotency key, a blind retry can create a duplicate feedback row.

---

## Error Handling

| Exit code | Meaning | Recovery |
|-----------|---------|----------|
| 0 | Success | Show post-submit card |
| 1 | Network / server error / oversized content | Do not auto-retry (no idempotency — the row may have already been written). Surface the error and offer to save locally; only resubmit if the user explicitly asks. |
| 2 | Usage error (missing/invalid flag) | Fix the flag and re-run |
| 3 | Auth error (agent not registered or token expired) | Run `kpass agent:register --type <agent-type> --output json`; if still failing, use `authenticate-user` skill |
| 4 | Not found | Should not happen for this command; surface error to user |

---

## Input Validation Checklist

Before running the command, verify:

- [ ] `--content` (or file content from `--content-file`) is non-empty after trimming whitespace.
- [ ] Content is under ~1 MiB. If larger, trim to the most relevant slice.
- [ ] **Redact credentials, cookies, tokens, payment data, and unnecessary PII** from both the content and `--metadata` before submitting — feedback is stored server-side and read by humans; do not forward secrets or sensitive personal data just because they appeared in the session transcript.
- [ ] `--category`, if passed, is a single short token (no spaces; lowercase preferred).
- [ ] `--metadata`, if passed, parses as a JSON **object** (not an array, not a scalar). Quote it with single quotes so the shell doesn't mangle it.
- [ ] Exactly one of `--content` or `--content-file` is set.
- [ ] `--output json` is present.
