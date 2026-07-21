---
name: activity
description: >-
  View transaction history and recent account activity. Invoke when the user asks
  about past spending, wants to verify a payment went through, check if an order
  completed, review wallet transfers, or see a log of all account actions. Covers
  wallet transfers, faucet drops, API payments, shopping checkouts, agent
  registrations, and session approvals.
user-invocable: true
allowed-tools:
  - "Bash(kpass activity *)"
  - "Bash(kpass me*)"
---

# Activity Feed

View recent account activity for the authenticated user. Returns a paginated list of activity events including wallet transfers, faucet drops, x402 API payments, agent registrations, session approvals, passkey registrations, and shopping checkouts.

> **Reference files** (read when you need exact detail):
> - `@references/commands.md` — full command reference, argument table, activity kinds, every JSON output shape, and the input validation checklist.
> - `@references/examples.md` — worked examples (view all recent activity, filter by kind, paginate).

## When to Use This Skill

- The user asks "show me my recent activity" or "what have I done recently?"
- The user asks "show me my transaction history" or "what transactions have I made?"
- The user wants to review spending history or verify a payment went through.
- The user asks "did my shopping checkout go through?" or "show me my purchases."
- You need to verify an action was recorded (e.g., confirm a wallet transfer completed).
- The user asks to filter activity by type (e.g., "show me only my wallet transfers").

## When NOT to Use This Skill

- If the user wants to **send** tokens or check wallet balance, use the **`wallet-send`** skill.
- If the user wants to **execute** a payment through a session, use the **`x402-execute`** skill.
- If the user wants to **list agents or sessions**, use the **`manage-agents`** skill.
- If the user wants to **search products or checkout**, use the **`shopping`** skill.

## Prerequisites

The user MUST be authenticated before using this skill. If not logged in (exit code 3 with "Not logged in"), use the **`authenticate-user`** skill first.

No agent registration or spending session is required. This command uses the user's JWT directly.

## Defaults (Do Not Ask the User Unless They Specify Otherwise)

| Setting | Default value | Override |
|---------|--------------|---------|
| Output format | `--output json` | Always use JSON output. Never omit this flag. |
| Kind filter | Omit (returns all kinds) | Only pass `--kind` when the user asks to filter by activity type. |
| Limit | Server default (20, omit) | Only pass `--limit` if the user requests pagination or you need to limit results. |
| Offset | `0` (omit) | Only pass `--offset` for pagination when combined with `--limit`. |
| Base URL | Omit (uses built-in default) | Only pass `--base-url` if the user explicitly provides a custom backend URL. |

---

## Display Cards (MANDATORY)

When presenting activity events to the user, format each event as a card:

**For transaction events** (wallet_transfer, wallet_faucet, x402_payment, shopping_checkout):
> **{title}** -- {status}
> Kind: {kind} | {occurred_at}
> Amount: {details.transaction.amount_raw} {details.transaction.asset_symbol} | Chain: {details.transaction.chain_name}
> Tx: {details.transaction.tx_hash}

**For shopping checkout events** (shopping_checkout):
> **{title}** -- {status}
> Kind: shopping_checkout | {occurred_at}
> Items: {details.transaction.shopping.item_count} ({details.transaction.shopping.item_titles joined})
> Total: {details.transaction.shopping.total_amount_display} | Order: {details.transaction.shopping.order_id}
> Tx: {details.transaction.tx_hash}

**For non-transaction events** (agent_registration, session_approval, passkey_registration):
> **{title}** -- {status}
> Kind: {kind} | {occurred_at}

---

## Error Handling

| Exit Code | Meaning | Error Message Pattern | Recovery Action |
|-----------|---------|----------------------|-----------------|
| 0 | Success | `status: "success"` | Present the result to the user. |
| 1 | Network error | `network error: ...` | Check connectivity. Retry after a brief pause. |
| 2 | Usage error | `--limit must be an integer between 1 and 100`, `--offset must be a non-negative integer` | Fix the flag value. See validation rules in `@references/commands.md`. |
| 3 | Auth error | `Not logged in. Run ...` | Use the **`authenticate-user`** skill to log in. |
| 5 | Rate limited | `rate limit` | Wait 30 seconds, then retry. |
| 6 | Session policy violation | N/A for activity | Activity commands do not use spending sessions. This exit code is not expected. |

See `@references/commands.md` for the exact error envelope of every state.

---

## Commands That DO NOT Exist

Do NOT attempt any of the following. They will fail:

- `kpass activity list` -- does not exist; use `kpass activity` directly
- `kpass activity --type` -- the flag is `--kind`, not `--type`
- `kpass activity --filter` -- does not exist; use `--kind`
- `kpass transactions` -- does not exist; use `kpass activity`
- `kpass history` -- does not exist; use `kpass activity`
- `kpass activity --status` -- does not exist; status is part of the event data, not a filter
- Any command with `--json` -- the correct flag is `--output json` (two separate tokens)

---

## Cross-Skill References

- **Prerequisite:** User must be logged in. Use the **`authenticate-user`** skill.
- **To send tokens or check balance:** Use the **`wallet-send`** skill.
- **To execute API payments:** Use the **`x402-execute`** skill.
- **To list agents and sessions:** Use the **`manage-agents`** skill.
- **To search products or checkout:** Use the **`shopping`** skill.
