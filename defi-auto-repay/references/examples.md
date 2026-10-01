# DeFi Auto-Repay — Worked Examples

## 1. "Repay my Aave loan automatically if it gets risky"

1. Ask for the position address (do not guess it), then read it:

   ```bash
   kpass defi position --address 0x1111111111111111111111111111111111111111 --output json
   ```

   Show the Position card: health factor `1.5000`, USDC debt `1500.000000`, eligible.

2. Ask the user for the trigger health factor (below 1.5, e.g. 1.3), the amount (e.g. 500 USDC, or "max") and how long it should stay armed (e.g. 7 days). Do not choose these yourself.

3. Create it:

   ```bash
   kpass defi repay-trigger create --address 0x1111111111111111111111111111111111111111 --hf 1.3 --amount 500 --expires 7d --output json
   ```

   Show the Approval Required card **with the warning verbatim** and the `approval_url`, plus any `notices`.

4. Run the `next_command` straight away:

   ```bash
   kpass defi repay-trigger get --id aave_repay_trigger_… --wait --output json
   ```

   When `trigger_status` is `armed`, show the Armed card. Remind the user it fires **once**.

## 2. "What's my Aave health factor?"

```bash
kpass defi position --address 0x1111111111111111111111111111111111111111 --output json
```

Show the Position card. If `has_debt` is false, say the position has no debt (and no health-factor risk).

## 3. Position not eligible

`defi position` returns `supported: false` with `borrowing_reserves: 2`. Explain that auto-repay currently needs USDC to be the position's **only** debt, so it can't be armed for this position.

## 4. A trigger already exists

`create` fails with `aave_trigger_already_active` (exit 2):

```bash
kpass defi repay-trigger list --output json
kpass defi repay-trigger cancel --id aave_repay_trigger_old --output json
```

Then create the new one. Ask the user before cancelling their existing trigger.

## 5. Approval link expired

`get --wait` ends with `trigger_status: "expired"` (exit 3). Tell the user the trigger was not armed, and offer to create a new one.

## 6. Not available in this environment

Any command returns `aave_repay_disabled` (exit 4): the feature is on in dev only for now. Do not retry against production.
