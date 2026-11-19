---
name: defi-aave-loop
description: >-
  Run the Aave v4 leveraged stablecoin loop on Avalanche through the user's
  Passport wallet: supply USDe as collateral, borrow USDt, swap back to USDe and
  repeat up to a target leverage. Previews total borrowed, the liquidation point
  and the expected net yield (negative at current rates) before asking the user
  to approve a mandate with their passkey, then opens the loop, reports its
  status and unwinds it back to USDC. Every action stays inside the limits the
  user approved; Passport refuses anything outside them. Invoke when the user
  wants to loop, lever up, leverage or farm a stablecoin position on Aave v4,
  asks about their loop position, health factor or leverage on Avalanche, or
  wants to unwind or exit a loop.
user-invocable: true
allowed-tools:
  - "Bash(kpass defi *)"
---

# DeFi Aave Loop (Aave v4 on Avalanche)

**Prerequisite**: Before using any Passport skill, check if `kpass` is installed by running `command -v kpass`. If it returns nothing, invoke the `passport-setup` skill first to install the CLI.

Run a **leveraged stablecoin loop** on **Aave v4 (Core Hub + Ethena spoke) on Avalanche**: Passport supplies **USDe** as collateral, borrows **USDt** against it, swaps the USDt back into USDe and re-supplies, repeating until the position reaches the target leverage. The user funds the loop in **USDC** from their **Passport wallet**, and an unwind returns **USDC** to that wallet.

The user's **mandate** is what makes the loop possible: principal, maximum leverage, minimum health factor and maximum borrow rate, approved once with their passkey. **This skill never grants authority.** Passport enforces the mandate on every action and refuses anything outside it. When it refuses, your job is to hand the refusal back to the user, not to find a way around it.

**At current rates the expected net yield of this loop is negative**: USDt borrow costs more than USDe collateral earns, and each loop step pays swap costs. Say so plainly, and show the number even when it is negative. Never present the loop as a way to earn yield.

> **Reference files** (read when you need exact detail):
> - `@references/commands.md`: every flag, JSON shape, error code and exit code.
> - `@references/examples.md`: end-to-end worked examples, including the refusal paths.

## When to Use This Skill

- The user wants to **loop, lever up, leverage or farm** a stablecoin position on Aave ("loop my USDC on Aave", "open a 3x USDe position").
- The user asks **what a loop would look like** at some size and leverage, without committing.
- The user asks about **their loop position**: leverage, health factor, debt, borrow rate, or what it has been doing.
- The user wants to **unwind, close or exit** the loop and get their USDC back.

## When NOT to Use This Skill

- To keep an existing Aave v3 loan on Base healthy, use **`defi-auto-repay`**.
- For a one-off token swap, use **`defi-swap`**.
- To send tokens to an address, use **`wallet-send`**.
- For other markets, chains, assets or protocols: the loop is **one fixed market** read from `kpass defi loop market`. You cannot choose the collateral or debt asset. Say so rather than trying.

## Prerequisites

The user must be logged in. If a command exits **3** with "Not logged in", use **`authenticate-user`** first, then retry.

**Availability: staging only.** Where the loop is switched off, every command answers `error_code: "aave_loop_disabled"` with "DeFi loop is not available in this environment." (exit **4**). Tell the user it is not available here and stop. **Never pass or change `--base-url`**: use the agent's configured Passport, and do not retry against another environment.

If `kpass defi loop market` fails with an **unknown-command** error, the installed `kpass` is too old for the loop. Tell the user to run `kpass upgrade` (see **`upgrade-passport`**) and stop.

## Rules (Do Not Skip)

1. **Never invent the inputs.** Ask the user for the **principal** (USDC), the **maximum leverage**, the **minimum health factor** and the **maximum borrow rate**. Do not pick values for them. Read the allowed ranges from `kpass defi loop market` (`limits`) and never hard-code them.
2. **Always `preview` before `mandate create`.** Show the Preview card with **total borrowed**, the **liquidation point** and the **expected net yield**, including when the yield is negative. The user approves a mandate only after seeing those three numbers.
3. **Never `open` without an active mandate.** Confirm `mandate_status` is `active` first. An `open` without one is refused (exit **11**), which is a wasted round trip and a confusing message for the user.
4. **On exit 11, stop.** A refusal (`mandate_required` or `outside_mandate`) means Passport blocked the action and **nothing was sent onchain**. Show the user `details.reason` and, when present, `details.approval_url`, then stop and wait for them.
5. **Never retry with different terms.** Do not lower the leverage, shrink the amount, raise the borrow rate or change the asset to get an action through. Terms the user did not ask for are not yours to choose. Re-run only the exact action the user asked for, and only after they tell you the mandate is approved.
6. **An expired mandate is renewed, not recreated.** Tell the user their limits expired and that they renew with their passkey. Do **not** run `mandate create`; it fails with `mandate_already_open` while the expired mandate is still open. Only `closed` or `revoked` lead to a new mandate.
7. **Deleveraging is not yours to trigger.** Passport deleverages the position by itself to defend the health factor. Read it from `kpass defi loop status` as events with `kind: "deleveraged"`. There is **no `deleverage` command**.
8. **`unwind` only when the user asks to exit.** It closes the whole position and returns USDC. Never unwind to tidy up, to recover from an error, or because a run looks stuck.
9. Always use `--output json`.

## Commands at a Glance

| Command | Purpose |
|---------|---------|
| `kpass defi loop market --output json` | The market, its assets and the `limits` every input must satisfy |
| `kpass defi loop preview --amount <usdc> --max-leverage <x> --min-health-factor <hf> --max-borrow-rate <percent> --output json` | **Preview** the loop: total borrowed, liquidation point, expected net yield. Nothing moves. |
| `kpass defi loop mandate create --amount <usdc> --max-leverage <x> --min-health-factor <hf> --max-borrow-rate <percent> --output json` | Ask the user to approve those limits with their passkey |
| `kpass defi loop mandate get <id> --wait --output json` | Poll until the mandate is approved |
| `kpass defi loop open --mandate <id> [--target-leverage <x>] --output json` | Start the loop inside the mandate |
| `kpass defi loop status --output json` | Position, mandate, 10 newest events, loop phase |
| `kpass defi loop unwind --mandate <id> --output json` | Close the position and return USDC |

All four of `--amount`, `--max-leverage`, `--min-health-factor` and `--max-borrow-rate` are **required** on `preview` and on `mandate create`. Pass the same four values to both, because the mandate approves the terms the user saw in the preview. `--max-borrow-rate` is a **percent** (`8.5` means 8.5%), while the JSON reports rates in **bps** (`850` means 8.5%).

## Display Cards — MANDATORY

**You MUST show these cards at each step, in this exact horizontal-rule format. Never skip or replace them with plain text.**

### Step 1: `loop market` → what the loop is and what it allows

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔁 Aave v4 Loop Market — {chain}

🪙 Collateral:     {collateral.symbol}
💳 Debt:           {debt.symbol}
📈 Borrow APR:     {borrow_apr_bps} bps
💧 Debt liquidity: {available_debt_liquidity}

Your limits: principal ${limits.min_principal_usd} to ${limits.max_principal_usd},
leverage up to {limits.max_leverage_cap}x, health factor at or above
{limits.min_health_factor_floor}, mandate up to {limits.max_mandate_days} days.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then ask the user for the four inputs, inside those limits.

### Step 2: `loop preview` → the three numbers, before any approval

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Loop Preview — {target_leverage}x

💵 You fund:        {the --amount you passed} USDC  (wallet has {wallet_usdc_available})
🪙 Total supplied:  {total_supplied_usde} USDe
💳 Total borrowed:  {total_borrowed_usdt} USDt
❤️  Health factor:   {projected_health_factor}  (your floor {the --min-health-factor you passed})
⚠️  Liquidates at:   USDe = {liquidation_price_usde_in_usdt} USDt
📈 Borrow APR:      {effective_borrow_apr_bps} bps  (your cap {the --max-borrow-rate you passed}%)
🌾 Collateral APR:  {collateral_supply_apr_bps} bps
🔀 Swap cost:       {swap_cost_bps} bps

📉 Expected net yield: {expected_net_yield_apr_bps} bps
                       ({expected_net_yield_usd_month} USD per month)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Show every `warnings` entry under the card. **When `expected_net_yield_apr_bps` is negative, say so in words**: at these rates the loop is expected to **cost** the user about that much per month, because USDt borrow costs more than USDe collateral earns. Then ask whether they still want to approve a mandate with these limits. Do not create one until they say yes.

### Step 3: `mandate create` → approval required

The response is `status: "human_action_required"` (exit **0**, not an error) with `action: "approve_aave_loop_mandate"`, `mandate_id`, `approval_url` and `next_command`.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ Aave Loop Mandate — Approval Required

These are the limits you are approving. Passport refuses anything
outside them, including anything I ask for.

💵 Principal:        {the --amount you passed} USDC
📊 Max leverage:     {the --max-leverage you passed}x
❤️  Min health factor: {the --min-health-factor you passed}
📈 Max borrow rate:  {the --max-borrow-rate you passed}%

🌐 {approval_url}

👆 Open the link and approve it with your passkey.
⏳ I'll wait automatically...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Give the user the `approval_url` as text. Then run `next_command` straight away: `kpass defi loop mandate get <mandate_id> --wait --output json`.

### Step 4: `mandate get --wait` → active

Judge by **`mandate_status`**, never by the envelope's `status`. The mandate itself is nested under **`mandate`**.

| `mandate_status` | Exit | What you do |
|------------------|------|-------------|
| `pending` | 0 | Still waiting for the passkey. With `--wait` it polls; see the timeout row below |
| `pending` after `--wait` timed out | 3 | Tell the user the approval is still outstanding and re-run `mandate get <id> --wait` |
| `active` | 0 | Show the Mandate Active card, then `open` |
| `closing` | 0 | An unwind is in progress. Report it from `status`; do **not** `open` |
| `expired` | 3 | Renew, do **not** create. See the Mandate Expired card |
| `closed`, `revoked` | 3 | The mandate is finished. Offer a new `preview` and `mandate create` |

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Mandate Active

Up to {mandate.target_leverage}x leverage, within the principal,
health-factor floor and borrow-rate cap you just approved
(echoed in {mandate.limits}), until {mandate.expires_at}.

Anything outside these limits is refused, and nothing goes onchain.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 5: `loop open` → running

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔁 Loop Running

Run {run_id} under mandate {mandate_id} is {run_status}.
Passport is supplying, borrowing and swapping in steps toward the
target leverage. I'll check it with `kpass defi loop status`.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

`loop_run_in_progress` comes back as `status: "success"` (exit **0**) with `run_status: "running"`. That means **a run is already going**, not a failure. Show the same card and check `status`. Do not open again.

### Step 6: `loop status` → position and events

`health_factor` is `null` when the position has no debt. With no mandate the command still succeeds, with `mandate: null`.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Loop Status — {loop_phase}

🪙 Collateral:   {position.collateral_amount} USDe  (${position.collateral_usd})
💳 Debt:         {position.debt_amount} USDt  (${position.debt_usd})
📊 Leverage:     {position.leverage}x
❤️  Health factor: {position.health_factor}
📈 Borrow APR:   {position.effective_borrow_apr_bps} bps
📉 Net yield:    {position.net_yield_apr_bps} bps

Recent events (10 newest):
 • {events[].kind}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

`loop_phase` is `idle`, `looping`, `failed`, `closed` or `finished`. List each event by its `kind` with whatever detail that event carries. On `failed`, report it from the events and ask the user what they want to do; do **not** unwind or re-open on your own. Events with `kind: "deleveraged"` are **Passport defending the health factor by itself**. Report them as that, and never try to trigger one.

### Step 7: `loop unwind` → closing

Only when the user asks to exit.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔓 Unwind Started

Run {run_id} under mandate {mandate_id} is {run_status}.
Passport is repaying the USDt debt, withdrawing the USDe collateral
and returning USDC to your Passport wallet. I'll check it with
`kpass defi loop status`.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

A second `unwind` while one is already closing answers the same way `open` does, with `status: "success"` at exit 0 from `loop_run_in_progress`. That is the same unwind still running. Read `status` instead of unwinding again.

### Refused (exit 11) → hand it back to the user

`mandate_required` means there is no mandate to act under. `outside_mandate` means the action asked for more than the user approved: higher leverage, a bigger principal, a health factor below the floor, or a borrow rate above the cap. The user cannot be moved to a different asset either, because the market is fixed and no flag names one. **Nothing was sent onchain.** The reason is in `details.reason`; the renewal or approval link is in `details.approval_url`, and only when there is something to approve.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛑 Refused — Outside Your Mandate

Passport refused this action and nothing went onchain.

Reason: {details.reason}

🌐 {details.approval_url}

👆 Approve it with your passkey if you want this, then tell me.
   I won't retry, and I won't change the terms to get around it.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

When `details.approval_url` is absent, drop the link lines and show the reason only. Then **stop**. Do not re-run the action, do not alter the terms, and do not try another command to achieve the same thing.

### Mandate expired → renew, not a new mandate

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⏳ Mandate Expired — Renew It

Your loop limits expired, so Passport refuses every loop action
until you renew them with your passkey. Renewing brings the same
mandate back; I can't create a second one while this one is open.

Renew on the DeFi page in Passport. The renewal link also comes
back to me on my next refused action, and I'll pass it straight on.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

`mandate get` may print that an expired mandate "can never become active, create a new one". **That wording is wrong for `expired`.** A renewal reactivates it, and `mandate create` fails with `mandate_already_open` while it is open. Follow this card, not that hint.

## Error Handling

| Exit | `error_code` | Meaning | Recovery |
|------|--------------|---------|----------|
| 0 | | Success, `pending`, or `human_action_required` on `mandate create` | Continue the flow |
| 0 | `loop_run_in_progress` | A run is already going. `run_status` is `running` after `open`, `closing` after `unwind` | Not a failure. Report it and check `status`. Do not run the command again |
| 11 | `mandate_required`, `outside_mandate` | **Refused.** No mandate, or outside the approved limits. Nothing went onchain | Show `details.reason` and `details.approval_url` if present, then **stop**. Never retry with changed terms |
| 2 | | A required flag is missing or invalid | All four of `--amount`, `--max-leverage`, `--min-health-factor`, `--max-borrow-rate` are required; check them against `market`'s `limits` |
| 3 | | Not logged in, or `--wait` timed out while still `pending` | **`authenticate-user`**, or re-run `mandate get <id> --wait` |
| 3 | `loop_mandate_expired` | The mandate expired | The user **renews** it. Do not `mandate create` |
| 3 | `loop_mandate_closed`, `loop_mandate_revoked` | The mandate is finished | `preview`, then a new `mandate create` |
| 4 | `mandate_not_found` | That id is not the current mandate | Run `status` and read the current mandate from it |
| 4 | `aave_loop_disabled` | "DeFi loop is not available in this environment." | Tell the user. Do **not** change `--base-url` or retry elsewhere |
| n/a | `mandate_already_open` | HTTP 409 from `mandate create`. A mandate is already open, including an expired one | No exit code is documented for it, so branch on the `error_code`. Read the mandate with `status`; renew an expired one instead of creating a second |

## Commands That DO NOT Exist

- `kpass defi loop deleverage`: **Passport deleverages on its own.** Read it from `status` as `deleveraged` events.
- `kpass defi loop close` / `exit` / `repay` / `withdraw`: the only way out is **`unwind --mandate <id>`**.
- `kpass defi loop mandate renew` / `approve` / `revoke`: renewal and approval happen in the browser with the user's passkey.
- `kpass defi loop mandate get --id <id>`: the id is a **positional argument**, not a flag.
- `kpass defi loop open` with no `--mandate`, or with `--leverage`: the flags are **`--mandate`** and the optional **`--target-leverage`**.
- `kpass defi loop preview --asset` / `--collateral` / `--debt` / `--chain`: the market is fixed; read it from `market`.
- `--base-url` on any loop command: never pass or change it.
- `--json`: the flag is **`--output json`**.

## Cross-Skill References

- **Prerequisite:** **`authenticate-user`**.
- **Funding the Passport wallet** (the loop is funded in USDC): **`wallet-send`** for its address and balance.
- **`kpass` too old for `defi loop`:** **`upgrade-passport`**.
- **A different Aave position, on Base:** **`defi-auto-repay`**.
- **A one-off swap instead of a loop:** **`defi-swap`**.
- **After a loop opens or unwinds:** see the transfers in **`activity`**.
