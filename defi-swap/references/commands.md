# DeFi Swap — Command Reference

All commands require login (`kpass login …`), accept `--output json` (always use it) and `--base-url`, and run on **Base** (`--chain base`, the default). Two forms of the same command: add `--dry-run` to preview, omit it to execute.

## Flags

| Flag | Required | Notes |
|------|----------|-------|
| `--sell` | yes | Asset to sell, e.g. `USDC`. Must be a registry asset on Base. |
| `--buy` | yes | Asset to buy, e.g. `ETH`. Must differ from `--sell`. |
| `--amount` | yes | Decimal amount of the **sell** asset, e.g. `10` or `0.5`. |
| `--chain` | no | Defaults to `base` (the only supported chain). |
| `--slippage-bps` | no | Max slippage in basis points. `0` / omitted = server cap (100 bps = 1%). A smaller value tightens it; it can only tighten, never loosen, the cap. |
| `--dry-run` | no | Preview the quote without moving funds. |

Missing `--sell`, `--buy` or `--amount` exits **2** (`USAGE`) without calling the backend.

## `kpass defi swap … --dry-run` (preview)

`POST /v2/defi/swap/quote`. No funds move. Success (`status: "success"`):

```json
{
  "chain": "base",
  "sell": "USDC",
  "buy": "ETH",
  "sell_amount": "1",
  "expected_out": "0.000431704323067759",
  "min_out": "",
  "slippage_bps": 100,
  "proxy_router": "0x02E5be68D46DAc0B524905bfF209cf47EE6dB2a9",
  "quote_id": "01a186c1-4e6a-8000-96ce-4cbacc310100",
  "expires_at": "2026-10-29T08:23:28.244708343Z",
  "_version": "1",
  "status": "success",
  "hint": "Preview only — no funds moved. Re-run without --dry-run to execute."
}
```

Note: `min_out` is currently returned blank (the Trading API's classic quote does not include a minimum; on-chain protection comes from the slippage cap sent with the quote). Show `slippage_bps`, not a blank minimum.

## `kpass defi swap …` (execute)

`POST /v2/defi/swap`. Moves real funds on mainnet. Success:

```json
{
  "chain": "base",
  "sell": "USDC",
  "buy": "ETH",
  "sell_amount": "1",
  "expected_out": "0.000432345950002801",
  "min_out": "",
  "approve_tx_hash": "0xdae2d87e8d0a88ec931e802e7cc6ec7506694f3295ba818d8889600b1b69d949",
  "swap_tx_hash": "0x403bbd861327b09aae145de4a59a089818a35ec46779f36653b5f31b36cc2be8",
  "status": "completed",
  "_version": "1",
  "hint": "Swap completed."
}
```

- `approve_tx_hash` is present when selling an ERC-20 (e.g. USDC) — an exact-amount approve precedes the swap. It is absent when selling native ETH.
- `status` is `completed` when the swap confirmed on-chain, or `submitted` when it broadcast but confirmation was inconclusive (hint: "Swap submitted; it may still be confirming on-chain."). On `submitted`, do **not** re-run — the tx may still mine; check `activity`.

## Error codes → exit codes

The backend `error_code` maps to a CLI exit code. Swap codes classify by HTTP status (they have no dedicated CLI mapping yet), except `insufficient_balance`.

| `error_code` | HTTP | Exit | Meaning |
|--------------|------|------|---------|
| `defi_swap_unsupported` | 422 | 2 | Unsupported chain/asset, or no route for the pair/size (all dev/Sepolia quotes land here — no testnet liquidity). |
| `balance_reserved` | 400 | 2 | USDC set aside by an armed Aave repay trigger; the swap won't spend reserved funds. |
| `invalid_request` | 400 | 2 | Unparseable/invalid amount or params. |
| `swap_validation_failed` | 422 | 2 | The built tx failed a pre-sign safety check (destination/recipient/token/amount/slippage). |
| `swap_in_progress` | 409 | 2 | A swap with the same idempotency key is in flight. |
| `idempotency_mismatch` | 409 | 2 | The idempotency key was reused with different parameters. |
| `swap_execution_failed` | 502 | 1 | Approve/swap could not send, confirm, or reverted on-chain. Message carries the revert reason + tx hash; often transient. |
| `defi_swap_disabled` | 404 | 4 | Feature off in this environment. |
| `insufficient_balance` | — | 6 | Wallet lacks the sell asset (or gas). |
| (not logged in) | 401 | 3 | Run `authenticate-user`. |
