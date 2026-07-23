# Wallet & Faucet — Command Reference

Full per-command reference for the `wallet-send` skill. SKILL.md carries the trigger logic, the send-approval flow, and the mandatory display cards; this file has the command-level detail (flags, validation, and every JSON shape). Worked end-to-end examples live in `examples.md`.

**Common envelope.** Every JSON response spreads its data fields at the top level alongside `_version: "1"`, `status`, `hint`, and `next_command`. `status` is one of `success`, `human_action_required`, `pending`, `expired`, or `error`. An `update_available` key may appear on any envelope — tolerate unknown top-level keys. All five commands require the user to be logged in (exit code 3 otherwise).

---

## `wallet balance` — Aggregated Multichain Balance

Returns per-asset totals with a per-chain breakdown, plus an approximate USD total. Hits the multichain `GET /v1/wallets/balances` endpoint.

```
kpass wallet balance --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "total_usd_approx": "1251.50",
  "assets": [
    {
      "asset": "USDC",
      "total": "1000.00",
      "decimals": 6,
      "chains": [
        { "chain": "base", "amount": "600.00", "partial": false },
        { "chain": "tempo", "amount": "400.00", "partial": false },
        { "chain": "solana", "amount": "0.00", "partial": false }
      ],
      "partial": false
    },
    {
      "asset": "PYUSD",
      "total": "250.50",
      "decimals": 6,
      "chains": [
        { "chain": "solana", "amount": "250.50", "partial": false }
      ],
      "partial": false
    },
    {
      "asset": "USDG",
      "total": "1.00",
      "decimals": 6,
      "chains": [
        { "chain": "robinhood", "amount": "1.00", "partial": false }
      ],
      "partial": false
    }
  ],
  "as_of": "2026-06-23T18:00:00Z",
  "_version": "1",
  "status": "success",
  "hint": "Total balance ≈ $1251.50 across 3 asset(s).",
  "next_command": ""
}
```

**Key fields:**
- `total_usd_approx` — approximate total value across all assets and chains (string).
- `assets[]` — one entry per asset symbol.
  - `asset` — symbol (e.g. `USDC`, `PYUSD`, `USDG`). `KITE` does not appear on the multichain surface.
  - `total` — summed spendable amount across chains (string).
  - `decimals` — token decimals.
  - `chains[]` — per-chain breakdown: `{ chain, amount, partial }`. `chain` is `base`, `tempo`, `solana`, or `robinhood`.
  - `partial` (on an asset or a chain) — `true` means that chain's read failed and the figure is incomplete. Tell the user the number may be understated.
- `as_of` — timestamp the balances were read.

> The old single-chain shape (`wallet_address`, `wallet_type`, `chain_id`, `assets[].{symbol,balance,native}`) is gone. There is no `chain_id` in this response.

### Not Logged In (exit code 3)

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

Display the balance card (SKILL.md). Before a send, confirm the user has enough of the asset **on the target chain** — a USDC balance on `base` cannot fund a `solana` send, and only USDG can be sent on `robinhood`.

---

## `wallet send` — Send Tokens on a Chain

Transfers tokens from the user's wallet on a specific chain to a recipient address. A send normally requires a passkey approval in the browser (step-up); this command starts that flow.

```
kpass wallet send --chain <base|tempo|solana|robinhood> --to <RECIPIENT_ADDRESS> --amount <N> --asset <SYMBOL> --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Chain | `--chain` | **Yes** | Ask the user | One of `base`, `tempo`, `solana`, `robinhood`. No default. `kite` and anything else are rejected (exit 2). |
| Recipient address | `--to` | Yes | Ask the user | Validated **for the chosen chain**: base/tempo/robinhood = EVM `0x` + 40 hex (EIP-55 checksum enforced when mixed-case); solana = base58 decoding to 32 bytes. Invalid → exit 2 before any network call. |
| Amount | `--amount` | Yes | Ask the user | Positive decimal string (e.g. `"25"`, `"0.50"`). |
| Asset symbol | `--asset` | Yes | Ask the user | Token symbol: `USDC` on base/tempo/solana, `PYUSD` on solana, `USDG` on robinhood. |
| Idempotency key | `--idempotency-key` | No | Omit | Forwarded as the `Idempotency-Key` header; auto-generated when omitted. **The backend accepts but does not yet de-duplicate on it — treat it as reserved; do not rely on it to make retries safe.** |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Output A — Approval Required (the normal path, exit code 0)

```json
{
  "action": "approve_wallet_send",
  "request_id": "req_abc123",
  "approval_url": "https://passport.dev.gokite.ai/approve/req_abc123",
  "chain": "base",
  "to": "0x9876fedc5432ba10...",
  "asset": "USDC",
  "amount": "25",
  "_version": "1",
  "status": "human_action_required",
  "hint": "Wallet send needs passkey approval. Show this approval URL to the user verbatim: https://passport.dev.gokite.ai/approve/req_abc123",
  "next_command": "kpass wallet send-status --request-id req_abc123 --wait --output json"
}
```

- `status` is `"human_action_required"` — exit code 0, NOT an error.
- Show `approval_url` to the user verbatim (Approval Required card), then run `next_command`.

### Output B — Direct Send (rollback path: step-up disabled server-side, exit code 0)

```json
{
  "chain": "base",
  "to": "0x9876fedc5432ba10...",
  "asset": "USDC",
  "amount": "25",
  "transaction_hash": "0xdeadbeef12345678...",
  "_version": "1",
  "status": "success",
  "hint": "Sent 25 USDC to 0x9876fedc5432ba10... on base.",
  "next_command": ""
}
```

- When step-up is disabled, the send executes immediately and returns `status: "success"` with a `transaction_hash`. Skip straight to the Transfer Complete card.

> The old send shape (`wallet_address`, `wallet_type`, `chain_id`, `recipient_address`, `recipient`) is gone. The recipient is now `to`, and the response carries `chain`.

### Validation Errors (exit code 2)

```json
{ "_version": "1", "status": "error", "error": "Missing --chain flag. Usage: kpass wallet send --chain <base|tempo|solana|robinhood> --to <RECIPIENT_ADDRESS> --amount <N> --asset <SYMBOL> --output json", "hint": "", "next_command": "" }
```

Other exit-2 messages: `--chain must be one of base|tempo|solana|robinhood (got: "...")`; `--to is not a valid <chain> address: EVM address must be 0x + 40 hex chars (got N)` / `EVM address fails EIP-55 checksum (possible typo)` / `Solana address must decode to 32 bytes (got N)`; `--amount must be a positive number (got: "...")`; `Missing --to flag`; `Missing --asset flag`.

---

## `wallet send-status` — Poll a Pending Send

Polls a wallet-send approval started by `wallet send`. The send executes server-side when the user approves with their passkey in the browser; this command reports the outcome. (Invoked via the `next_command` from `wallet send`. It is a real command even though the top-level `kpass` help menu does not list it.)

```
kpass wallet send-status --request-id <REQUEST_ID> --wait --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Request ID | `--request-id` | Yes | From `wallet send` output: `request_id` | String starting with `req_` |
| Wait for resolution | `--wait` | Recommended | Pass to poll until resolved | Polls every `--poll-interval` seconds up to `--timeout` |
| Poll interval | `--poll-interval` | No | Default `3` (seconds) | Positive integer |
| Timeout | `--timeout` | No | Default `300` (seconds) | Positive integer |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success — Sent (exit code 0)

```json
{
  "request_id": "req_abc123",
  "transaction_hash": "0xdeadbeef12345678...",
  "_version": "1",
  "status": "success",
  "hint": "Wallet send completed.",
  "next_command": ""
}
```

> **Judge success by `status: "success"` + the presence of `transaction_hash`.** The CLI's internal `"sent"` state is overwritten to `"success"` when the envelope is built, so a literal `"sent"` string never reaches you. This response does **not** echo `chain`/`to`/`asset`/`amount` — carry those forward from the original `wallet send` response for the Transfer Complete card.

### Failed (exit code 1)

```json
{ "_version": "1", "status": "error", "error": "Wallet send failed: <reason>", "error_code": "<code>", "hint": "Start a new send with 'kpass wallet send'.", "next_command": "" }
```

### Rejected / Expired (exit code 3)

```json
{ "_version": "1", "status": "error", "error": "Wallet send was rejected.", "hint": "Start a new send with 'kpass wallet send'.", "next_command": "" }
```

`expired` is identical with "Wallet send approval expired before it was approved." Both exit 3. Tell the user the send did not go through and offer to start a new one.

### Still Pending

- **Without `--wait`** (exit code 0): `status: "pending"` with `request_id` and `expires_at`, and a `next_command` to poll with `--wait`.
- **With `--wait`, on timeout** (exit code 3): `status: "pending"`, `"Polling timed out after Ns. Wallet send is still pending."` Retry `send-status --wait` to keep waiting, or tell the user to approve in the browser.

---

## `wallet address` — Per-Chain Wallet Addresses

Lists the user's receive addresses per chain (read from `GET /v1/me`). Use this whenever the user needs an address to receive funds.

```
kpass wallet address --output json
kpass wallet address --chain solana --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Chain filter | `--chain` | No | Pass to show one chain | One of `base`, `tempo`, `solana`, `robinhood`. Omit for all. Invalid → exit 2. |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "wallets": [
    { "chain": "base", "vm_family": "evm", "address": "0x1234abcd5678ef90..." },
    { "chain": "tempo", "vm_family": "evm", "address": "0x1234abcd5678ef90..." },
    { "chain": "robinhood", "vm_family": "evm", "address": "0x1234abcd5678ef90..." },
    { "chain": "solana", "vm_family": "solana", "address": "9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin" }
  ],
  "_version": "1",
  "status": "success",
  "hint": "4 wallet(s) found.",
  "next_command": ""
}
```

**Key fields:**
- `wallets[]` — `{ chain, vm_family, address }`.
  - `vm_family` is `"evm"` for base/tempo/robinhood and `"solana"` for solana.
  - **base, tempo, and robinhood share one EVM address** (same `address` value). When rows match, tell the user it is one wallet, not a duplicate.
  - The solana entry is **optional** — it is omitted if the user has no Solana wallet.
- With `--chain`, only the matching entries are returned (hint becomes "N wallet(s) on <chain>.").

### Required Receive-Asset Warning

Before displaying any address, state that Passport sponsors gas and users must not send native gas tokens. Then show the receive rules for each returned chain:

| Chain | Supported receive assets | Explicit warning |
|-------|--------------------------|------------------|
| `base` | USDC only | Do not send ETH |
| `tempo` | USDC only | Do not send unsupported assets |
| `robinhood` | USDG only | Do not send ETH |
| `solana` | USDC or PYUSD | Do not send SOL |

Never return a bare wallet address without this guidance. The same EVM address does not imply that an asset supported on one chain is supported on the others.

---

## `faucet drop` — Request Test Tokens (Testnet Only)

Dispenses test tokens. **Testnet/staging only** — the CLI blocks production base URLs automatically (exit 2 there). **Requires login** (the faucet is no longer anonymous).

```
kpass faucet drop --recipient <WALLET_ADDRESS> --token <TOKEN_NAME> --output json
```

**This is a TESTNET faucet.** It dispenses test tokens for development only. Never tell the user they are receiving real funds. Robinhood is not a faucet-supported chain.

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Recipient address | `--recipient` | Yes | From `wallet address` (the chain's `address`) | Valid wallet address |
| Token name | `--token` | Yes | Ask the user or infer | Token symbol (e.g. `USDC`) |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "amount": "100.00",
  "asset": "USDC",
  "chain_id": 2368,
  "recipient": "0x1234abcd5678ef90...",
  "recipient_address": "0x1234abcd5678ef90...",
  "transaction_hash": "0xfaucet12345678...",
  "wallet_address": "0xfaucet_sender...",
  "wallet_type": "custodial",
  "_version": "1",
  "status": "success",
  "hint": "Dropped 100.00 USDC to 0x1234abcd5678ef90....",
  "next_command": ""
}
```

> The faucet did **not** move to the multichain shape — it still returns `chain_id`, `wallet_address`, and `wallet_type`. Treat `chain_id` as informational (testnet). Use `amount`, `asset`, `recipient_address`, and `transaction_hash` for the card.

### Errors

- **Production** (exit code 2): `"Faucet is only available on staging/testnet environments. It is disabled on production."`
- **Not logged in** (exit code 3): standard "Not logged in" envelope. Authenticate, then retry.
- **Missing flags** (exit code 2): `"Missing --recipient flag. ..."` / `"Missing --token flag. ..."`

### What to Do After This Command

Display the Tokens Received card (SKILL.md), then optionally run `wallet balance` to confirm the tokens arrived.
