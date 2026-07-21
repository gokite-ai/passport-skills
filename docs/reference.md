# Reference

CLI invocation patterns, the JSON envelope contract, the session delegation
model, and exit codes shared across all skills in this repository.

## CLI Invocation Patterns

Passport skills invoke:

```bash
kpass <command> [subcommand] [flags] --output json
```

Discovery skill invokes:

```bash
ksearch <command> [subcommand] [flags] --output json
```

Key conventions:
- `--output json` is required on every command for machine-readable output.
- `--no-interactive` should be passed on kpass commands that accept it (signup init, login init) to prevent stdin prompts.
- All JSON output follows the envelope: `{ ..., "_version": "1", "status": "...", "hint": "...", "next_command": "..." }`

## Session Delegation Model

Sessions use a delegation-based approval model. The agent:

1. Preflights the merchant URL (curl) to discover payment requirements (402 response)
2. Constructs a delegation object with task summary, payment policy, and optional execution constraints
3. Creates a session with `--delegation '<JSON>'`
4. The user reviews and approves the delegation via passkey

The delegation includes:
- **task** -- human-readable summary of what the agent is authorized to do
- **payment_policy** -- enforced spend limits (per-tx cap, total budget, allowed assets, TTL)
- **execution_constraints** -- optional scoped HTTP endpoint restrictions

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success, or human action required (not an error) |
| 1 | Network / general error |
| 2 | Usage error (missing flag, invalid argument) |
| 3 | Auth error (invalid OTP, expired session, bad token, delegation violation) |
| 4 | Not found (user not registered, session not found, service not found) |
| 5 | Rate limited |
