# DeFi Aave Loop — Command Reference

The loop is **Aave v4 on Avalanche**: Core Hub with the Ethena spoke, **USDe** collateral, **USDt** debt, funded and returned in **USDC** from the user's Passport wallet.

All commands require login (`kpass login …`) and `--output json` (always use it). **Never pass `--base-url`**: the loop runs only where the agent's configured Passport has it enabled.

Every response uses the shared envelope: `{"_version": …, "status": …, "hint": …, "next_command": …, …data}`.

## `kpass defi loop market`

No flags. Read this first: it names the market and carries the `limits` every input must satisfy. **Never hard-code the limits into a prompt or a message.** They come from here.

```json
{
  "market_key": "aave-v4-avalanche-usde-usdt",
  "chain": "avalanche",
  "collateral": { "symbol": "USDe" },
  "debt": { "symbol": "USDt" },
  "borrow_apr_bps": 850,
  "available_debt_liquidity": "4210000.000000",
  "limits": {
    "max_leverage_cap": "5",
    "min_health_factor_floor": "1.05",
    "max_principal_usd": "10000",
    "min_principal_usd": "20",
    "max_steps": 8,
    "swap_slippage_cap_bps": 50,
    "max_mandate_days": 30
  },
  "_version": "1",
  "status": "success"
}
```

Status `success`, exit 0. The `collateral` and `debt` objects carry more fields than the symbol; the symbol is what you show.

This command is also the probe for two environment problems:

- An **unknown-command** error means the installed `kpass` predates the loop. Tell the user to run `kpass upgrade` and stop.
- `aave_loop_disabled` (exit 4) with "DeFi loop is not available in this environment." means the feature is off here. Tell the user and stop.

## `kpass defi loop preview`

| Flag | Required | Notes |
|------|----------|-------|
| `--amount` | yes | Principal in **USDC**, between `limits.min_principal_usd` and `limits.max_principal_usd` |
| `--max-leverage` | yes | Target leverage, at or below `limits.max_leverage_cap` |
| `--min-health-factor` | yes | Health-factor floor, at or above `limits.min_health_factor_floor` |
| `--max-borrow-rate` | yes | **Percent**, so `8.5` means 8.5%. The JSON reports rates in **bps**, so `850` means the same thing |

A missing or invalid flag exits **2**. Nothing moves: a preview is a read.

```json
{
  "target_leverage": "3",
  "total_supplied_usde": "3000.000000",
  "total_borrowed_usdt": "2000.000000",
  "projected_health_factor": "1.4200",
  "liquidation_price_usde_in_usdt": "0.9650",
  "effective_borrow_apr_bps": 850,
  "collateral_supply_apr_bps": 520,
  "swap_cost_bps": 30,
  "expected_net_yield_apr_bps": -410,
  "expected_net_yield_usd_month": "-10.25",
  "wallet_usdc_available": "1500.000000",
  "warnings": [],
  "_version": "1",
  "status": "success"
}
```

Three of these are **mandatory on screen** before you ask for a mandate:

- `total_borrowed_usdt`: what the loop owes at target leverage.
- `liquidation_price_usde_in_usdt`: the USDe price in USDt at which the position liquidates.
- `expected_net_yield_apr_bps` with `expected_net_yield_usd_month`: **normally negative**, because USDt borrow costs more than USDe collateral earns and every loop step pays `swap_cost_bps`. Show it as a cost in words when it is negative. Never hide it, and never round it to zero.

Show every `warnings` entry too.

## `kpass defi loop mandate create`

Same four required flags as `preview`, with the same meanings. Pass the **same values the user just saw in the preview**: the mandate approves those terms.

Response `status: "human_action_required"`, exit **0** (not an error):

```json
{
  "action": "approve_aave_loop_mandate",
  "mandate_id": "aave_loop_mandate_…",
  "approval_url": "https://passport-web.staging.gokite.ai/defi/loop/approve?token=alm_…",
  "_version": "1",
  "status": "human_action_required",
  "hint": "Approving these limits needs the user's passkey. Show them the limits and this approval URL.",
  "next_command": "kpass defi loop mandate get aave_loop_mandate_… --wait --output json"
}
```

Give the `approval_url` to the user as text, then run `next_command` straight away.

While **any** mandate is open, including an **expired** one, `mandate create` fails with HTTP **409** `mandate_already_open`. An expired mandate is **renewed** by the user, not replaced. Only `closed` or `revoked` lead to a new `mandate create`.

## `kpass defi loop mandate get <id>`

The id is a **positional argument**, not `--id`.

| Flag | Required | Notes |
|------|----------|-------|
| `--wait` | no | Poll while the mandate is `pending` |
| `--timeout` | no | Duration, e.g. `10m` |
| `--poll-interval` | no | Duration, e.g. `3s` |

```json
{
  "mandate_id": "aave_loop_mandate_…",
  "mandate_status": "active",
  "mandate": {
    "id": "aave_loop_mandate_…",
    "status": "active",
    "limits": { },
    "target_leverage": "3",
    "expires_at": "2026-12-01T12:00:00Z",
    "has_position": false,
    "start_command": "kpass defi loop open --mandate aave_loop_mandate_… --output json"
  },
  "_version": "1",
  "status": "success"
}
```

Judge the mandate by **`mandate_status`**, never by the envelope's `status`. `mandate.limits` echoes the terms the user approved.

| `mandate_status` | Envelope `status` | Exit | Meaning and what you do |
|------------------|-------------------|------|-------------------------|
| `pending` | `pending` | 0 | Waiting for the passkey. `--wait` keeps polling |
| `pending` (after `--wait` timed out) | `pending` | 3 | Not a failure of the mandate. Tell the user the approval is still outstanding, then re-run `mandate get <id> --wait` |
| `active` | `success` | 0 | Ready. `open` is allowed |
| `closing` | `success` | 0 | An unwind is in progress. Report it from `status`; do not `open` |
| `expired` | `error`, `error_code: "loop_mandate_expired"` | 3 | The user **renews** it with their passkey. Do **not** `mandate create` |
| `closed` | `error`, `error_code: "loop_mandate_closed"` | 3 | Finished. A new `preview` + `mandate create` is correct |
| `revoked` | `error`, `error_code: "loop_mandate_revoked"` | 3 | Finished. A new `preview` + `mandate create` is correct |

An id that is not the current mandate exits **4** with `mandate_not_found`.

**The `expired` hint is wrong.** For an expired mandate the CLI prints that it "can never become active, create a new one". A renewal *does* reactivate it, and `mandate create` is refused with `mandate_already_open` while it is open. Tell the user to renew, and ignore that hint. The renewal link reaches you as the `Ask the user to approve: <url>` line on the next refused action (exit 11), or the user renews on the DeFi page in Passport.

## `kpass defi loop open`

| Flag | Required | Notes |
|------|----------|-------|
| `--mandate` | yes | Mandate id. It must be `active` |
| `--target-leverage` | no | Below the mandate's leverage. Above it is refused (exit 11, `outside_mandate`) |

```json
{
  "run_id": "aave_loop_run_…",
  "mandate_id": "aave_loop_mandate_…",
  "run_status": "running",
  "_version": "1",
  "status": "success"
}
```

Exit 0. HTTP **409** `loop_run_in_progress` also comes back as `status: "success"`, exit **0**, with `run_status: "running"`: **a run is already going, which is not a failure.** Report it and read `status`. Do not open again.

## `kpass defi loop status`

No flags. Succeeds even with no mandate, with `mandate: null`.

```json
{
  "position": {
    "wallet": "0xabc…",
    "collateral_amount": "3000.000000",
    "collateral_usd": "3000.00",
    "debt_amount": "2000.000000",
    "debt_usd": "2000.00",
    "health_factor": "1.4200",
    "leverage": "3",
    "effective_borrow_apr_bps": 850,
    "net_yield_apr_bps": -410
  },
  "mandate": { },
  "events": [ { "kind": "deleveraged" } ],
  "loop_phase": "looping",
  "_version": "1",
  "status": "success"
}
```

- `position.health_factor` is `null` when the position has no debt.
- `events` holds the **10 newest** events.
- `loop_phase` is `idle`, `looping`, `failed`, `closed` or `finished`.
- Events with `kind: "deleveraged"` are **Passport deleveraging the position by itself** to defend the health factor. This is the only way deleveraging is ever reported, and there is **no command** that triggers one.

On `loop_phase: "failed"`, report what the events say and ask the user what they want. Do not unwind or re-open on your own.

## `kpass defi loop unwind`

| Flag | Required | Notes |
|------|----------|-------|
| `--mandate` | yes | Mandate id |

Shaped like `open`, with `run_status: "closing"`, exit 0. Passport repays the USDt debt, withdraws the USDe collateral and returns **USDC** to the Passport wallet. Run it **only** when the user asks to exit.

## Refusals: exit 11

This is the path the acceptance test exercises. A refusal is an **error** and exits **11** (`PERMISSION`). It is not the `human_action_required` hand-off that `defi-auto-repay` uses, and it is not exit 0.

```json
{
  "status": "error",
  "error_code": "outside_mandate",
  "error": "4x leverage is above the 3x you approved\nAsk the user to approve: https://passport-web.staging.gokite.ai/defi/loop/approve?token=alm_…",
  "details": {
    "code": "outside_mandate",
    "reason": "4x leverage is above the 3x you approved",
    "approval_url": "https://passport-web.staging.gokite.ai/defi/loop/approve?token=alm_…"
  },
  "user_message": "…",
  "hint": "…",
  "_version": "1"
}
```

| `error_code` | Cause |
|--------------|-------|
| `mandate_required` | No mandate to act under: none was ever approved, or the only one is expired, closed or revoked |
| `outside_mandate` | The action asked for more than the user approved: higher leverage, a bigger principal, a health factor below the floor, a borrow rate above the cap, or an asset this market does not hold |

**Nothing is sent onchain when a command exits 11.** What you do:

1. Show `details.reason`.
2. Show `details.approval_url` **when it is present**. It is there only when there is something for the user to approve. Without one, show the reason only.
3. **Stop.** Never retry the action, never change the terms to get it through, and never reach for another command to achieve the same thing.

`status: "human_action_required"` at exit 0 happens on **`mandate create`** only. That is the normal approval hand-off, not a refusal.

## Error codes

| `error_code` | Exit | Cause |
|--------------|------|-------|
| `mandate_required` | 11 | Refused: no mandate to act under |
| `outside_mandate` | 11 | Refused: outside the approved limits |
| `invalid_request` | 2 | A required flag is missing or invalid |
| `loop_mandate_expired` | 3 | The mandate expired; the user renews it |
| `loop_mandate_closed` | 3 | The mandate is closed |
| `loop_mandate_revoked` | 3 | The mandate was revoked |
| `mandate_not_found` | 4 | That id is not the current mandate |
| `aave_loop_disabled` | 4 | "DeFi loop is not available in this environment." The loop is off here |
| `mandate_already_open` | 409 | A mandate is already open, including an expired one |
| `loop_run_in_progress` | 0 | 409 upstream, but `status: "success"` with `run_status: "running"`. Still running, not a failure |

Exit **3** with "Not logged in" is the shared Passport auth failure: use **`authenticate-user`**, then retry.

## Version

The loop commands are not in a released `kpass` yet, so no version floor pins them. `skills.json` keeps `min_kpass_version` at `6.8.9`; Release raises it when it cuts the version that ships the loop. Until then, treat an unknown-command error from `kpass defi loop market` as "the user's `kpass` is too old" and point them at `kpass upgrade`.
