# DeFi Swap — Worked Examples

## 1. Happy path — swap 1 USDC for ETH (preview → confirm → execute)

**User:** "Swap 1 USDC for ETH on Base."

**Step 1 — preview (always first):**

```
kpass defi swap --chain base --sell USDC --buy ETH --amount 1 --dry-run --output json
```

Show the Quote card from the response, then ask the user to confirm:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💱 Swap Quote — base

   Sell:          1 USDC
   Receive (est): ~0.000431704 ETH
   Max slippage:  100 bps
   Route:         Uniswap via 0x02E5be68D46DAc0B524905bfF209cf47EE6dB2a9
   Quote expires: 2026-10-29T08:23:28Z

👉 Reply "yes" to execute, or tell me a different amount/pair.
   (A quote is a preview — no funds move until you confirm.)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Step 2 — after the user replies "yes":**

```
kpass defi swap --chain base --sell USDC --buy ETH --amount 1 --output json
```

Show the Swap Complete card with `approve_tx_hash` and `swap_tx_hash`.

If the quote had expired before the user confirmed, re-run the `--dry-run` first to refresh it, re-show the card, then execute.

## 2. User only wants a quote

**User:** "What would I get for 50 USDC in ETH?"

Run the `--dry-run` form, show the Quote card, and stop — do not execute. If they then say "do it", execute as in example 1.

## 3. Blocked by an armed repay trigger

**User:** "Swap 100 USDC for ETH." → execute returns:

```json
{ "status": "error", "error_code": "balance_reserved",
  "error": "...USDC reserved by an armed repay trigger..." }
```

Show the **Swap Blocked — USDC Reserved** card. Do not retry. Offer to swap a smaller amount, or to review/cancel the trigger via the **`defi-auto-repay`** skill.

## 4. On dev (Base Sepolia) — no liquidity

A `--dry-run` on a dev `--base-url` returns:

```json
{ "status": "error", "error_code": "defi_swap_unsupported",
  "error": "unsupported chain or asset for defi swap: no route for this pair/size" }
```

Explain that dev runs on Base Sepolia, which has no Uniswap liquidity, so swaps can be previewed for wiring but not completed there. Suggest staging/production for a real swap.

## 5. Tightening slippage

**User:** "Swap 10 USDC to ETH but no more than 0.3% slippage."

Add `--slippage-bps 30` to both the preview and execute:

```
kpass defi swap --chain base --sell USDC --buy ETH --amount 10 --slippage-bps 30 --dry-run --output json
```

`--slippage-bps` can only tighten below the server cap (100 bps), never loosen it.
