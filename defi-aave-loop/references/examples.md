# DeFi Aave Loop — Worked Examples

The market is Aave v4 on Avalanche: USDe collateral, USDt debt, funded in USDC. The example inputs below sit inside the market's limits (principal $20 to $10,000, leverage up to 5x).

## 1. "Loop my USDC on Aave at 3x"

1. Read the market and its limits first:

   ```bash
   kpass defi loop market --output json
   ```

   Show the Loop Market card, then ask the user for the four inputs: principal, maximum leverage, minimum health factor and maximum borrow rate. Do not choose them.

2. Preview, before anything else:

   ```bash
   kpass defi loop preview --amount 1000 --max-leverage 3 --min-health-factor 1.15 --max-borrow-rate 8.5 --output json
   ```

   Show the Preview card with `total_borrowed_usdt`, `liquidation_price_usde_in_usdt` and `expected_net_yield_apr_bps` / `expected_net_yield_usd_month`. The net yield comes back negative, for example `-410` bps and `-10.25` USD per month. Say that in words: at these rates the loop is expected to **cost** about $10.25 a month, because USDt borrow costs more than USDe collateral earns and every step pays a swap cost. Ask whether they still want to approve a mandate on these terms.

3. Only after they say yes, create the mandate with the **same four values**:

   ```bash
   kpass defi loop mandate create --amount 1000 --max-leverage 3 --min-health-factor 1.15 --max-borrow-rate 8.5 --output json
   ```

   The response is `status: "human_action_required"` (exit 0) with `mandate_id` and `approval_url`. Show the Approval Required card and give the user the URL as text.

4. Run the `next_command` straight away:

   ```bash
   kpass defi loop mandate get aave_loop_mandate_abc --wait --output json
   ```

   When `mandate_status` is `active`, show the Mandate Active card.

5. Open the loop:

   ```bash
   kpass defi loop open --mandate aave_loop_mandate_abc --output json
   ```

   `run_status: "running"`. Show the Loop Running card, then report progress:

   ```bash
   kpass defi loop status --output json
   ```

## 2. No mandate yet (exit 11, `mandate_required`)

The user asks to open the loop before approving anything:

```bash
kpass defi loop open --mandate aave_loop_mandate_abc --output json
```

Exits **11** with `error_code: "mandate_required"`. **Nothing went onchain.** Show the Refused card with `details.reason` and, if present, `details.approval_url`, then stop. Do not open again until the user tells you the mandate is approved.

The right order is always `preview`, then `mandate create`, then `mandate get --wait` until `active`, then `open`.

## 3. Higher leverage than the user approved (exit 11, `outside_mandate`)

The mandate approves 3x. The user says "actually make it 4x", so you ask for 4x:

```bash
kpass defi loop open --mandate aave_loop_mandate_abc --target-leverage 4 --output json
```

Exits **11** with `error_code: "outside_mandate"` and `details.reason` naming the 3x limit. Nothing went onchain. Show the Refused card with the reason and the `details.approval_url`, and tell the user that raising the leverage needs their passkey.

**Do not** retry at 3x to "get something done", and do not re-run at 4x hoping it goes through. A borrow rate above the mandate's cap, a principal above it, and a health factor below its floor all refuse the same way. A different asset is not even expressible, because the market is fixed. Terms the user did not ask for are not yours to pick.

## 4. The mandate expired

`mandate get` returns `mandate_status: "expired"` (exit 3, `loop_mandate_expired`), or an action refuses with exit 11 and a reason about expired limits.

Show the Mandate Expired card: the user's limits expired, and they **renew** them with their passkey, either from the renewal link in `details.approval_url` or with Renew on the DeFi page in Passport. A renewal brings the same mandate back.

Do **not** run `mandate create`. While the expired mandate is open it fails with `mandate_already_open` (409). The CLI's own hint that an expired mandate "can never become active, create a new one" is wrong; follow this instead.

## 5. The mandate was closed or revoked

`mandate get` returns `mandate_status: "closed"` or `"revoked"` (exit 3). That mandate is finished for good. These are the only states that lead to a new mandate: run `preview` again, show the numbers, and create a new mandate once the user agrees.

## 6. Passport deleveraged the position

`kpass defi loop status` shows events with `kind: "deleveraged"`.

Passport deleverages by itself to defend the health factor. Report it as that in the Loop Status card, with the current `health_factor` and `leverage`. There is **no `kpass defi loop deleverage` command**, so never try to trigger or repeat one.

## 7. A run is already going

```bash
kpass defi loop open --mandate aave_loop_mandate_abc --output json
```

Comes back `status: "success"`, exit **0**, `run_status: "running"`, from a 409 `loop_run_in_progress` upstream. That means the loop is **already running**, not that the command failed. Show the Loop Running card and read `kpass defi loop status`. Do not open a second time.

## 8. "Get me out of the loop"

Only on the user's ask:

```bash
kpass defi loop unwind --mandate aave_loop_mandate_abc --output json
```

`run_status: "closing"`, exit 0. Show the Unwind Started card: Passport repays the USDt debt, withdraws the USDe collateral and returns USDC to the Passport wallet. Follow it with `kpass defi loop status` until `loop_phase` is `closed` or `finished`. While the unwind runs, `mandate_status` is `closing`, so do not `open`.

## 9. Not available in this environment

Any loop command returns `aave_loop_disabled` (exit 4) with "DeFi loop is not available in this environment."

The loop is switched off here. Tell the user it is not available in this environment and stop. Never pass or change `--base-url`, and never retry against another environment.

## 10. The user's kpass is too old

`kpass defi loop market` fails with an unknown-command error, because the installed CLI predates `defi loop`.

Tell the user to run `kpass upgrade` (see the **`upgrade-passport`** skill), then stop. Do not guess at other command spellings.
