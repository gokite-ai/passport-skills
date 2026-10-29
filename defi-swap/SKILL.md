---
name: defi-swap
description: >-
  Swap one token for another on Uniswap (Base) through the user's Passport
  wallet: e.g. "swap 10 USDC for ETH", "convert my USDC to ETH on Base", "trade
  ETH into USDC". Always previews a live quote first (expected output, slippage,
  route) and only executes after the user confirms. Respects USDC set aside by
  armed Aave repay triggers. Invoke when the user wants to swap, convert, trade
  or exchange one on-chain asset for another on Base, or asks what a swap would
  return.
user-invocable: true
allowed-tools:
  - "Bash(kpass defi *)"
---

# DeFi Swap (Uniswap on Base)

**Prerequisite**: Before using any Passport skill, check if `kpass` is installed by running `command -v kpass`. If it returns nothing, invoke the `passport-setup` skill first to install the CLI.

Swap `--amount` of one token (`--sell`) into another (`--buy`) on **Base**, routed through Uniswap's Trading API and settled from the user's **Passport wallet**. The swap **respects USDC set aside by armed Aave repay triggers** — it refuses with `balance_reserved` rather than spend reserved funds.

> **Reference files** (read when you need exact detail):
> - `@references/commands.md`: every flag, JSON shape, error code and exit code.
> - `@references/examples.md`: end-to-end worked examples.

## When to Use This Skill

- The user wants to **swap, convert, trade or exchange** one token for another on Base ("swap 10 USDC for ETH", "convert my USDC to ETH").
- The user asks **what a swap would return** (a quote/preview) without committing.

## When NOT to Use This Skill

- To **send** tokens to an address, use **`wallet-send`**.
- To keep an Aave loan healthy / auto-repay, use **`defi-auto-repay`**.
- For chains other than Base, or cross-chain swaps/bridging: **not supported here**. Say so.
- For assets not in the registry (only assets Passport knows on Base, e.g. **USDC** and **ETH**): the quote returns `defi_swap_unsupported`.

## Prerequisites

The user must be logged in. If a command exits **3** with "Not logged in", use **`authenticate-user`** first, then retry.

**Availability:** on in production, staging and dev.
- **Production and staging** run on **Base mainnet with real funds** — an executed swap moves real money.
- **Dev** runs on **Base Sepolia**, which has **no Uniswap liquidity**, so a quote there returns `defi_swap_unsupported` ("no route for this pair/size"). Dev can exercise the wiring but **cannot complete a real swap**. Say so rather than retrying.

An environment with the feature switched off answers `error_code: "defi_swap_disabled"` (exit 4).

## Rules (Do Not Skip)

1. **Never invent the inputs.** Ask the user for the **sell asset**, the **buy asset** and the **amount** (a decimal number of the sell asset). The chain is **base**. Do not pick values for them.
2. **Always preview first, then confirm, then execute — never in one step.** The CLI does **not** prompt: running `kpass defi swap` **without** `--dry-run` moves real funds immediately. So:
   - First run **`--dry-run`** and show the **Quote** card.
   - Ask the user to confirm in plain words (e.g. "Reply **yes** to execute this swap").
   - Only after an explicit **yes**, run the same command **without** `--dry-run`.
3. **A quote expires.** Each quote has an `expires_at` (~30s). If the user takes longer to confirm, re-run the `--dry-run` to refresh it before executing.
4. **Respect `balance_reserved`.** If an execute returns `balance_reserved`, USDC is set aside by an armed Aave repay trigger. **Do not retry or work around it.** Tell the user, and point them to `defi-auto-repay` (list/cancel a trigger) or to swapping a smaller amount.
5. Always use `--output json`.

## Commands at a Glance

| Command | Purpose |
|---------|---------|
| `kpass defi swap --chain base --sell <A> --buy <B> --amount <n> [--slippage-bps <bps>] --dry-run --output json` | **Preview** a quote (expected out, slippage, proxy). No funds move. |
| `kpass defi swap --chain base --sell <A> --buy <B> --amount <n> [--slippage-bps <bps>] --output json` | **Execute** the swap. Moves real funds on mainnet. |

`--slippage-bps` is optional (omit, or 0, to use the server's cap of 100 bps = 1%); a smaller value tightens it.

## Display Cards — MANDATORY

**You MUST show these cards at each step, in this exact horizontal-rule format. Never skip or replace them with plain text.**

### Step 1: `--dry-run` → Quote preview

The response is `status: "success"` with `chain`, `sell`, `buy`, `sell_amount`, `expected_out`, `slippage_bps`, `proxy_router`, `quote_id`, `expires_at`. (`min_out` may be blank — do not display a blank minimum; show the slippage cap instead.)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💱 Swap Quote — {chain}

   Sell:          {sell_amount} {sell}
   Receive (est): ~{expected_out} {buy}
   Max slippage:  {slippage_bps} bps
   Route:         Uniswap via {proxy_router}
   Quote expires: {expires_at}

👉 Reply "yes" to execute, or tell me a different amount/pair.
   (A quote is a preview — no funds move until you confirm.)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Stop here and wait for the user's confirmation. Do not execute without an explicit "yes".

### Step 2: execute → Swap complete

On success the response has `status` (`completed` or `submitted`), `sell_amount`, `sell`, `expected_out`, `buy`, `approve_tx_hash` (present when selling an ERC-20 like USDC), `swap_tx_hash`.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Swap {status}

   Swapped {sell_amount} {sell} → ~{expected_out} {buy} on {chain}

   Approve tx: {approve_tx_hash}
   Swap tx:    {swap_tx_hash}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If `status` is `submitted` (not `completed`), add: "The swap is broadcasting and may still be confirming on-chain — check `activity` shortly." Do **not** re-run the swap in that case (it would be a second swap).

### `balance_reserved` → blocked by an armed repay trigger

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ Swap Blocked — USDC Reserved

Some of your USDC is set aside by an armed Aave auto-repay trigger, so
this swap would dip into reserved funds and was refused.

Options:
 • Swap a smaller amount, or
 • Review/cancel the trigger with the defi-auto-repay skill.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Error Handling

| Exit | `error_code` | Meaning | Recovery |
|------|--------------|---------|----------|
| 0 | | Success / submitted | Show the Swap Complete card |
| 2 | `defi_swap_unsupported` | Chain/asset not supported, or **no route** for this pair/size (incl. all dev/Sepolia quotes) | Show the reason; try a supported pair (USDC↔ETH) on **base**; on dev, explain there's no testnet liquidity |
| 2 | `balance_reserved` | USDC set aside by an armed repay trigger | Show the Reserved card; swap less or cancel the trigger — **never** retry around it |
| 2 | `invalid_request`, `swap_validation_failed` | Bad amount/params, or the built tx failed a safety check | Re-check the amount/pair and re-quote |
| 2 | `swap_in_progress`, `idempotency_mismatch` | A swap with the same key is in flight / reused with different params | Wait, then check `activity`; do not resubmit |
| 1 | `swap_execution_failed` | The approve/swap could not send, confirm, or **reverted on-chain** | The message carries the revert reason + tx hash. Often transient (re-quote and retry once); if it persists, report it |
| 3 | | Not logged in | Use **`authenticate-user`**, then retry |
| 4 | `defi_swap_disabled` | Feature off in this environment | Check `--base-url`; the env may not have swap enabled |
| 6 | `insufficient_balance` | Wallet doesn't hold enough of the sell asset (or no gas) | Fund the Passport wallet (**`wallet-send`**) — needs the sell asset **and** a little ETH for gas |

## Commands That DO NOT Exist

- `kpass swap …` (it's `kpass defi swap`), `kpass defi buy` / `defi sell` / `defi trade`.
- `--from` / `--to`: the flags are **`--sell`** and **`--buy`**.
- `--amount-out` / limit orders / multi-hop tuning: not supported — only `--amount` of the sell asset, with an optional `--slippage-bps`.
- `--json`: the flag is **`--output json`**.
- A `--yes` / `--confirm` flag: there is none — the confirmation is **you** asking the user before running the non-`--dry-run` command.

## Cross-Skill References

- **Prerequisite:** **`authenticate-user`**.
- **Funding the Passport wallet** (needs the sell asset + ETH gas): **`wallet-send`**.
- **Keep an Aave loan healthy:** **`defi-auto-repay`** (also what reserves USDC that can block a swap).
- **After a swap:** see it in **`activity`**.
