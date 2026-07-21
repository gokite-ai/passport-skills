# Activity — Command Reference

Full command reference for the `activity` skill. SKILL.md carries the trigger logic, prerequisites, defaults, the mandatory display card formats, and a condensed error-handling table; this file has the command-level detail (flags, validation, activity kinds, and every JSON shape). Worked end-to-end examples live in `examples.md`.

---

## `activity` -- List Activity Events

Returns a paginated list of recent activity events for the authenticated user.

```
kpass activity --output json
```

Full form with all optional filters:

```
kpass activity \
  --kind <KIND> \
  --limit <N> \
  --offset <N> \
  --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Kind filter | `--kind` | No | One of the allowed kind values | String: `wallet_transfer`, `wallet_faucet`, `x402_payment`, `agent_registration`, `session_approval`, `passkey_registration`, or `shopping_checkout` |
| Limit | `--limit` | No | Default: 20. Pass to control page size. | Integer between 1 and 100 |
| Offset | `--offset` | No | Default: 0. Pass for pagination. | Non-negative integer (0 or greater) |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

All filter flags are optional. Omit them to list all activity.

### Activity Kinds

| Kind | Description |
|------|-------------|
| `wallet_transfer` | User transferred tokens to an external wallet |
| `wallet_faucet` | Wallet funded via testnet faucet |
| `x402_payment` | x402 HTTP API payment made by agent |
| `agent_registration` | New agent registered |
| `session_approval` | Agent session approved via passkey |
| `passkey_registration` | Passkey credential added |
| `shopping_checkout` | Shopping checkout completed or failed |

### Success Output -- Events Found (exit code 0)

```json
{
  "events": [
    {
      "id": "activity_abc123",
      "user_id": "user_789xyz",
      "kind": "shopping_checkout",
      "status": "completed",
      "title": "Shopping checkout -- 2 items",
      "error_code": "",
      "error_message": "",
      "details": {
        "transaction": {
          "agent_id": "agent_def456",
          "direction": "debit",
          "chain_id": 8453,
          "chain_name": "base",
          "asset_symbol": "USDC",
          "amount_raw": "124900000",
          "decimals": 6,
          "tx_hash": "0xabc123...",
          "source_address": "0x1234...",
          "wallet_id": "wallet_xyz",
          "shopping": {
            "order_id": "order_abc123",
            "crossmint_order_id": "cm_xyz789",
            "item_count": 2,
            "item_titles": ["Wireless Mouse", "USB-C Hub"],
            "total_amount_display": "$12.49",
            "provider": "amazon"
          }
        }
      },
      "occurred_at": "2026-03-18T14:30:00Z",
      "created_at": "2026-03-18T14:30:05Z",
      "updated_at": "2026-03-18T14:30:05Z"
    },
    {
      "id": "activity_def456",
      "user_id": "user_789xyz",
      "kind": "wallet_transfer",
      "status": "completed",
      "title": "Transfer to external wallet",
      "details": {
        "transaction": {
          "direction": "debit",
          "chain_id": 8453,
          "chain_name": "base",
          "asset_symbol": "USDC",
          "amount_raw": "5000000",
          "decimals": 6,
          "tx_hash": "0xdef456...",
          "source_address": "0x1234...",
          "destination_address": "0x5678...",
          "wallet_id": "wallet_xyz"
        }
      },
      "occurred_at": "2026-03-17T10:00:00Z",
      "created_at": "2026-03-17T10:00:02Z",
      "updated_at": "2026-03-17T10:00:02Z"
    },
    {
      "id": "activity_ghi789",
      "user_id": "user_789xyz",
      "kind": "agent_registration",
      "status": "completed",
      "title": "Agent registered",
      "details": {
        "agent": {
          "agent_id": "agent_def456",
          "agent_type": "claude"
        }
      },
      "occurred_at": "2026-03-16T09:00:00Z",
      "created_at": "2026-03-16T09:00:01Z",
      "updated_at": "2026-03-16T09:00:01Z"
    }
  ],
  "total": 3,
  "limit": 20,
  "offset": 0,
  "_version": "1",
  "status": "success",
  "hint": "Found 3 activity event(s) (total: 3).",
  "next_command": ""
}
```

**Key fields:**
- `events` -- Array of activity event objects (newest first).
- `events[].id` -- Unique activity event identifier.
- `events[].kind` -- The type of activity (see Activity Kinds table).
- `events[].status` -- `completed` or `failed`.
- `events[].title` -- Human-readable title summarizing the event.
- `events[].error_code` -- Error code if the event failed (empty on success).
- `events[].error_message` -- Error message if the event failed (empty on success).
- `events[].details.transaction` -- Present for transaction-related events (wallet_transfer, wallet_faucet, x402_payment, shopping_checkout). Contains chain, asset, amount, tx hash, addresses. Kite is multichain: `chain_name` reflects the chain the transaction settled on (`base`, `tempo`, or `solana`, or their testnet variants such as `base-sepolia`), and `chain_id` is that chain's numeric EVM ID; Solana has no EVM chain ID, so `chain_id` is omitted for Solana transactions (treat an absent `chain_id` as Solana). Display `chain_name` rather than `chain_id`.
- `events[].details.transaction.shopping` -- Present only for `shopping_checkout` events. Contains order ID, item count, item titles, total amount display, provider.
- `events[].details.transaction.x402` -- Present only for `x402_payment` events. Contains session ID, request URL, merchant name/host.
- `events[].details.agent` -- Present for `agent_registration` events. Contains agent ID and type.
- `events[].details.session` -- Present for `session_approval` events. Contains agent ID, session ID, request ID.
- `events[].details.passkey` -- Present for `passkey_registration` events. Contains passkey ID.
- `events[].occurred_at` -- ISO 8601 timestamp of when the action actually happened.
- `total` -- Total number of events matching the filter (for pagination).
- `limit` -- The page size used.
- `offset` -- The offset used.

### Success Output -- No Events (exit code 0)

```json
{
  "events": [],
  "total": 0,
  "limit": 20,
  "offset": 0,
  "_version": "1",
  "status": "success",
  "hint": "No activity found.",
  "next_command": ""
}
```

### Error Output -- Not Logged In (exit code 3)

```json
{
  "_version": "1",
  "status": "error",
  "error": "Not logged in. Run 'kpass login init --email <EMAIL> --output json' to authenticate, or 'kpass signup init --email <EMAIL> --output json' to create an account.",
  "hint": "Run 'kpass login init --email <EMAIL> --output json' to authenticate.",
  "next_command": ""
}
```

### What to Do After This Command

- Present the events to the user using the Display Card format above.
- For transaction events, convert `amount_raw` to human-readable amounts using `decimals` (e.g., `5000000` with `decimals: 6` = `5.00 USDC`).
- For shopping events, use the `shopping.total_amount_display` field directly (already human-readable).
- For paginated results, check if `offset + events.length < total`. If so, there are more pages -- run again with `--offset <next_offset>`.
- If the user asked about a specific transaction and it's not found, suggest filtering by kind or increasing the limit.

---

## Input Validation Checklist

Before running any command, verify:

1. **Authentication:** The user must be logged in. Use `kpass me --output json` to check.
2. **Kind (`--kind`):** If provided, must be one of: `wallet_transfer`, `wallet_faucet`, `x402_payment`, `agent_registration`, `session_approval`, `passkey_registration`, `shopping_checkout`.
3. **Limit (`--limit`):** If provided, must be an integer between 1 and 100.
4. **Offset (`--offset`):** If provided, must be a non-negative integer (0 or greater).
