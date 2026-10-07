---
name: defi-auto-repay
description: >-
  Arm a one-shot Aave v3 auto-repay on Base: when the health factor of an Aave
  position (in any wallet) drops below a threshold the user picks, Kite repays
  its USDC debt once from the user's Passport wallet. Reads a position's health
  factor and debt, creates a trigger (armed with a passkey in the browser), and
  lists, checks or cancels triggers. Invoke when the user wants to keep an Aave
  loan healthy, avoid or reduce liquidation risk, set a health-factor alert that
  repays automatically, or asks about their Aave position's health.
user-invocable: true
allowed-tools:
  - "Bash(kpass defi *)"
  - "Bash(open *)"
  - "Bash(xdg-open *)"
---

# DeFi Auto-Repay (Aave v3 on Base)

Arm a **one-shot** repay trigger on an Aave v3 position: when its health factor drops below the user's threshold, **Kite repays its USDC debt once** from the user's **Passport wallet**. The position can live in **any wallet** (MetaMask, a Safe, anything): Kite repays on its behalf, and never needs that wallet's keys. This **reduces liquidation risk**; never say it "protects" against or "guarantees" anything.

> **Reference files** (read when you need exact detail):
> - `@references/commands.md`: every flag, validation rule, JSON shape and error code.
> - `@references/examples.md`: end-to-end worked examples.

## When to Use This Skill

- The user wants to keep an Aave loan from being liquidated, or "repay automatically if my health factor gets low".
- The user asks for their Aave position's health factor or debt.
- The user wants to see, check or cancel their repay triggers.

## When NOT to Use This Skill

- To send tokens to an address, use **`wallet-send`**.
- To pay for an API, use **`request-session`** then **`x402-execute`**.
- For positions on other protocols (Morpho, Spark, Compound) or other chains: not supported yet. Say so.

## Prerequisites

The user must be logged in. If a command exits **3** with "Not logged in", use **`authenticate-user`** first, then retry.

**Availability:** on in production, staging and dev. Production and staging run on **Base mainnet with Circle USDC — a repay spends real funds**. Dev runs on Base Sepolia with **Aave's own test USDC**, not Circle's. An environment with the feature switched off answers `error_code: "aave_repay_disabled"` (exit 4).

## Rules (Do Not Skip)

1. **Never invent the inputs.** Ask the user for the **position address**, the **trigger health factor**, the **amount** (a USDC number, or "max" for the full debt) and the **expiry**. Do not pick values for them.
2. **Show the position first.** Run `defi position` and show the Position card before asking for the trigger, so the user picks a threshold below their current health factor.
3. **Show the wrong-address warning verbatim** on the Approval Required card. Kite repays whatever address is entered; if it isn't the user's, their funds repay someone else's loan and cannot be recovered.
4. **Say it fires once.** After it repays, the trigger is done; to keep auto-repay on, the user creates a new one.
5. Always use `--output json`.

## Commands at a Glance

| Command | Purpose |
|---------|---------|
| `kpass defi position --address <addr> --output json` | Position health, debt, eligibility; your Passport wallet's USDC/ETH |
| `kpass defi repay-trigger create --address <addr> --hf <n> --amount <usdc\|max> --expires <7d\|24h\|RFC3339> --output json` | Create a pending trigger (needs passkey approval) |
| `kpass defi repay-trigger get --id <id> --wait --output json` | Poll until armed |
| `kpass defi repay-trigger list --output json` | Your triggers, newest first |
| `kpass defi repay-trigger cancel --id <id> --output json` | Cancel a pending or armed trigger (no passkey) |

## Display Cards — MANDATORY

**You MUST show these cards at each step, in this exact horizontal-rule format. Never skip or replace them with plain text.**

### Step 1: `defi position`

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🏦 Aave v3 Position — {chain}

📍 Address:        {position_address}
❤️  Health factor:  {health_factor}
💵 Debt:           ${total_debt_usd} (USDC debt {usdc_debt})
🧱 Collateral:     ${total_collateral_usd}
✅ Eligible:       {supported}

👛 Your Passport wallet {wallet.address}: {wallet.usdc} USDC, {wallet.eth} ETH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If `has_debt` is false, show "Health factor: no debt" and stop: there is nothing to repay. If `supported` is false, explain that auto-repay needs USDC to be the position's **only** debt. If the wallet holds little USDC, note that it must hold enough when the trigger fires.

### Step 2: `repay-trigger create` → approval required

The response is `status: "human_action_required"` (exit **0**, not an error) with `approval_url`, `warning`, `trigger`, optional `notices`, and `next_command`.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ Aave Auto-Repay — Approval Required

⚠️ {warning}

📍 Loan address:  {trigger.position_address}
🎯 Repays when:   health factor < {trigger.trigger_hf}
💵 Repays:        {trigger.amount} USDC  ("max" = the full debt at that moment)
👛 Pays from:     {trigger.wallet_address}
🔁 Fires:         once
⏳ Expires:       {trigger.expires_at}

🌐 {approval_url}

👆 Open the link and arm it with your passkey.
⏳ I'll wait automatically...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Show every `notices` entry under the card (e.g. the wallet holds less USDC than the repay may need). Optionally open the URL (`open`/`xdg-open`), then **immediately** run `next_command`.

### Step 3: `repay-trigger get --wait` → armed

In JSON the envelope's `status` is `success`/`pending`; the trigger's own state is **`trigger_status`** and the trigger is under **`trigger`**. Judge by `trigger_status`, never by `status`.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Aave Auto-Repay Armed

Kite will repay {trigger.amount} USDC once if the health factor of
{trigger.position_address} drops below {trigger.trigger_hf},
until {trigger.expires_at}.

This reduces liquidation risk. Cancel any time:
kpass defi repay-trigger cancel --id {trigger_id}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If `trigger_status` is `cancelled`, `expired` or `failed` (exit **3**), tell the user it will not fire and offer to create a new one.

## Error Handling

| Exit | `error_code` | Meaning | Recovery |
|------|--------------|---------|----------|
| 0 | | Success, pending, or `human_action_required` | Continue the flow |
| 2 | `invalid_request`, `aave_position_no_debt`, `aave_position_unsupported_debt`, `aave_trigger_not_below_hf`, `aave_trigger_already_active`, `aave_trigger_not_cancellable` | Bad input, or the position doesn't qualify | Show the reason; re-check with `defi position`; for an active trigger, `list` then `cancel` it first |
| 3 | | Not logged in; trigger `cancelled`/`expired`/`failed`; `--wait` timed out | `authenticate-user`, or create a new trigger |
| 4 | `aave_repay_disabled`, `aave_trigger_not_found` | Feature off in this environment; unknown ID | Check `--base-url`; `list` to find IDs |
| 1 | `aave_chain_unavailable` | The chain couldn't be read | Retry in a moment |

## Commands That DO NOT Exist

- `kpass defi` (no sub-command), `kpass aave …`, `kpass defi repay` / `defi borrow` / `defi supply` / `defi withdraw`: the CLI only reads positions and manages repay triggers.
- `kpass defi repay-trigger create --position` / `--trigger` / `--health-factor`: the flags are `--address` and `--hf`.
- `kpass defi repay-trigger arm` / `approve`: arming happens in the browser at the `approval_url`.
- `kpass defi repay-trigger update` / `edit`: cancel and create a new one.
- `--json`: the flag is `--output json`.

## Cross-Skill References

- **Prerequisite:** **`authenticate-user`**.
- **Funding the Passport wallet** (it pays the repay): **`wallet-send`** for its address and balance.
- **After it fires:** check the repay in history with **`activity`**.
