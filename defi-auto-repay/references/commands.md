# DeFi Auto-Repay — Command Reference

All commands require login (`kpass login …`) and accept `--output json` (always use it) and `--base-url`.

## `kpass defi position`

| Flag | Required | Notes |
|------|----------|-------|
| `--address` | yes | The address that owns the Aave position (wallet A). `0x` + 40 hex; checked locally (exit 2). |

Success (`status: "success"`):

```json
{
  "chain": "base",
  "position_address": "0x1111111111111111111111111111111111111111",
  "has_debt": true,
  "health_factor": "1.5000",
  "total_collateral_usd": "3000.00000000",
  "total_debt_usd": "1500.00000000",
  "usdc_debt": "1500.000000",
  "borrowing_reserves": 1,
  "supported": true,
  "wallet": { "address": "0xabc…", "usdc": "750.000000", "eth": "0.002000000000000000" },
  "_version": "1",
  "status": "success",
  "hint": "Position is eligible for auto-repay. Create a trigger with 'kpass defi repay-trigger create'."
}
```

- `health_factor` is absent when `has_debt` is false (Aave reports infinity).
- `supported` is true only when the position has debt **and USDC is its only debt**.
- `wallet` is the caller's Passport wallet (wallet B), which pays any repay. Absent if the user has no Passport EVM wallet yet.

## `kpass defi repay-trigger create`

| Flag | Required | Notes |
|------|----------|-------|
| `--address` | yes | Position owner (wallet A) |
| `--hf` | yes | Trigger health factor. Must be above 1.0 locally; the server also requires it to be **below the current** health factor |
| `--amount` | yes | USDC to repay (e.g. `500`), or `max` for the full debt at fire time (case-insensitive, sent as `max`) |
| `--expires` | yes | `7d`, `24h`, `90m`, or an RFC3339 time. At most 30 days away (server-enforced) |

Response (`status: "human_action_required"`, exit 0):

```json
{
  "action": "approve_aave_repay_trigger",
  "trigger_id": "aave_repay_trigger_…",
  "approval_url": "https://passport-web.dev.gokite.ai/wallet/send/approve?token=arr_…",
  "approval_expires_at": "2026-10-01T12:10:00Z",
  "trigger": {
    "id": "aave_repay_trigger_…",
    "status": "pending_approval",
    "chain": "base",
    "position_address": "0x1111…",
    "wallet_address": "0xabc…",
    "asset": "USDC",
    "trigger_hf": "1.3",
    "amount": "500",
    "expires_at": "2026-10-08T12:00:00Z",
    "hf_at_create": "1.5000"
  },
  "warning": "Kite will repay the loan of the address you entered. If it isn't yours, your funds will repay someone else's loan and cannot be recovered.",
  "notices": ["Your Passport wallet holds 100.000000 USDC, less than the 500.000000 USDC this repay may need. Top it up before the trigger fires."],
  "_version": "1",
  "status": "human_action_required",
  "hint": "Arming this repay trigger needs passkey approval. Show the user this warning and approval URL verbatim. …",
  "next_command": "kpass defi repay-trigger get --id aave_repay_trigger_… --wait --output json"
}
```

The approval link expires at `approval_expires_at` (minutes, not days). If it lapses, the trigger becomes `expired`; create a new one.

## `kpass defi repay-trigger get`

| Flag | Required | Notes |
|------|----------|-------|
| `--id` | yes | Trigger ID |
| `--wait` | no | Poll while `pending_approval` |
| `--poll-interval` | no | Seconds, default 3 |
| `--timeout` | no | Seconds, default 300 (exit 3 on timeout) |

The trigger is nested under `trigger`; its state is `trigger_status` (the envelope's `status` is `success`, `pending` or `error`):

| `trigger_status` | Exit | Envelope `status` | Meaning |
|------------------|------|-------------------|---------|
| `pending_approval` | 0 | `pending` | Waiting for the passkey |
| `armed` | 0 | `success` | Will repay once below the trigger, until expiry |
| `firing` | 0 | `success` | Repay in progress |
| `fired` | 0 | `success` | Repaid: see `trigger.repaid_amount`, `trigger.repay_tx_hash` |
| `cancelled` / `expired` / `failed` | 3 | `error`, `error_code: "aave_trigger_<status>"` | Will not fire; create a new one |

## `kpass defi repay-trigger list`

No flags. `status: "success"` with `triggers: [ … ]`, newest first (up to 50). Each entry has its own `status` field (the list is nested, so it is not overwritten).

## `kpass defi repay-trigger cancel`

| Flag | Required | Notes |
|------|----------|-------|
| `--id` | yes | Trigger ID |

Cancels a `pending_approval` or `armed` trigger. No passkey (cancelling only removes authority). Returns `trigger_status: "cancelled"`. A firing or finished trigger can't be cancelled (`aave_trigger_not_cancellable`, exit 2).

## Error codes

| `error_code` | Exit | Cause |
|--------------|------|-------|
| `aave_repay_disabled` | 4 | Feature switched off in this environment |
| `invalid_request` | 2 | Malformed address, number, amount or expiry |
| `aave_position_no_debt` | 2 | The position owes nothing |
| `aave_position_unsupported_debt` | 2 | USDC is not the position's only debt |
| `aave_trigger_not_below_hf` | 2 | `--hf` is not above 1.0 and below the current health factor |
| `aave_trigger_already_active` | 2 | A pending/armed/firing trigger already exists for this position |
| `aave_trigger_not_found` | 4 | No trigger with that ID for this user |
| `aave_trigger_not_cancellable` | 2 | Trigger is firing or finished |
| `aave_chain_unavailable` | 1 | The chain couldn't be read; retry |
| `passkey_high_risk_blocked` | 2 | Passkey cooldown or recovery in progress (create is blocked); try again later |
| `wallet_not_found` | 4 | The user has no Passport EVM wallet to pay from yet |
