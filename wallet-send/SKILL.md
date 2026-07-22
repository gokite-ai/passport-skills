---
name: wallet-send
description: >-
  Check a multichain wallet balance, send crypto on a specific chain
  (base/tempo/solana/robinhood), look up per-chain wallet addresses, or get test tokens
  from the faucet (staging/testnet only). Proactively invoke for any task
  involving token transfers, balance inquiries, "how much do I have?",
  "what's my address?", or funding a wallet on testnet. No spending session
  required -- works directly with the user's wallet. Sends require a passkey
  approval in the browser.
user-invocable: true
allowed-tools:
  - "Bash(kpass wallet *)"
  - "Bash(kpass faucet *)"
---

# Wallet Send

Check a wallet balance across chains, send tokens **on a specific chain**, list per-chain wallet addresses, and request test tokens from the faucet. These commands use the user's own JWT (not an agent session) and do NOT require a spending session.

Kite is **multichain**. Every send targets one of four chains — **`base`**, **`tempo`**, **`solana`**, or **`robinhood`** — and `--chain` is **required** (there is no default; `kite` is rejected). Balances are aggregated across all chains. A wallet send normally requires a **passkey approval in the browser** (step-up), so `wallet send` hands you an approval URL and you poll the result with `wallet send-status`.

> **Reference files** (read when you need exact detail):
> - `@references/commands.md` — full per-command flag tables, validation rules, and every JSON shape.
> - `@references/examples.md` — end-to-end worked examples (send + approval, balance, address, faucet).

## When to Use This Skill

- The user asks to check their wallet balance or "how much do I have?"
- The user asks to send or transfer tokens to an address.
- The user asks "what's my wallet address?" or needs an address to receive funds.
- The user asks for test tokens, wants to "top up" on testnet, or needs to fund a wallet for development. **Faucet is staging/testnet only** — the CLI blocks it on production automatically.

## When NOT to Use This Skill

- To pay for a service or access a paid API, use **`x402-execute`** (which requires a spending session), set up via **`request-session`**.

## Prerequisites

**All commands here require the user to be logged in** — `wallet balance`, `wallet send`, `wallet send-status`, `wallet address`, **and `faucet drop`** (the faucet is no longer anonymous). If a command returns exit code 3 with "Not logged in", use the **`authenticate-user`** skill first, then retry.

No agent registration or spending session is required. Wallet commands operate with the user's JWT directly.

## Chains & Assets

| Chain | VM family | Assets | Notes |
|-------|-----------|--------|-------|
| `base` | `evm` (`0x…`) | USDC | base + tempo + robinhood share **one EVM address** |
| `tempo` | `evm` (`0x…`) | USDC | physically USDC.e (surfaced as USDC); ~0.01 USDC is reserved for gas — the `amount` the CLI shows is already the spendable figure |
| `solana` | `solana` (base58) | USDC, PYUSD | separate Solana address; optional (omitted if the user has no Solana wallet) |
| `robinhood` | `evm` (`0x…`) | USDG | **USDG only**; same EVM address as base/tempo; no faucet |

**Use `USDC` on base/tempo/solana, `PYUSD` on solana, and `USDG` on robinhood.** Never imply that USDG is supported on base/tempo or that USDC is supported on robinhood. `KITE` is not part of the multichain surface — do not suggest it as a send/receive asset even though the CLI's `--asset` help still lists it as an example.

## Defaults (Do Not Ask the User Unless They Specify Otherwise)

| Setting | Default value | Override |
|---------|--------------|---------|
| Output format | `--output json` | Always use JSON output. Never omit this flag. |
| Chain | Ask the user | **Required for `wallet send`.** There is no default. If the user did not say which chain, ask (e.g. "base, tempo, solana, or robinhood?"). |
| Asset | Ask the user | There is no default. You must know which token to send (e.g. `USDC`, `PYUSD`). |
| Base URL | Omit (uses built-in default) | Only pass `--base-url` if the user explicitly provides a custom backend URL. |

## Display Cards — MANDATORY

**CRITICAL: You MUST display the formatted status cards below after every major step. This is NOT optional. Never skip, summarize, or replace these cards with plain text. The exact horizontal-rule format must be used every time.**

---

## Commands at a Glance

| Command | Purpose | Auth | Detail |
|---------|---------|------|--------|
| `kpass wallet balance --output json` | Aggregated multichain balance | login | `@references/commands.md` |
| `kpass wallet send --chain <c> --to <addr> --amount <n> --asset <sym> --output json` | Transfer on one chain (passkey step-up) | login | `@references/commands.md` |
| `kpass wallet send-status --request-id <id> --wait --output json` | Poll a pending send approval | login | `@references/commands.md` |
| `kpass wallet address [--chain <c>] --output json` | Per-chain receive addresses | login | `@references/commands.md` |
| `kpass faucet drop --recipient <addr> --token <sym> --output json` | Test tokens (testnet only) | login | `@references/commands.md` |

`--chain` accepts `base`, `tempo`, `solana`, or `robinhood`. `--to`/`--recipient` is validated **client-side per chain**: an EVM address (`0x` + 40 hex; EIP-55 checksum enforced when mixed-case) for base/tempo/robinhood, a base58 32-byte public key for solana. A malformed address fails with exit 2 before any network call.

---

## The Wallet Send Flow (passkey step-up — the normal path)

A wallet send requires a passkey ceremony the CLI cannot perform, so the flow is **two steps**:

1. **Run `wallet send`.** The response is almost always `status: "human_action_required"` (exit code **0** — this is NOT an error). It contains an `approval_url`, a `request_id`, and a `next_command`.
2. **Show the `approval_url` to the user verbatim** (display the Approval Required card), then **run the `next_command`** (`wallet send-status --request-id <id> --wait --output json`) to poll until the user approves in the browser.

> **Rollback path:** if the backend has step-up disabled, `wallet send` instead returns `status: "success"` directly with a `transaction_hash` — skip straight to the Transfer Complete card.
>
> **Judging send-status success:** the success envelope's top-level `status` is `"success"` and it carries a `transaction_hash`. (The CLI's internal `"sent"` state is overwritten to `"success"` in the envelope — judge success by `status: "success"` **plus** the presence of `transaction_hash`, never by a `"sent"` string.)

### Step 1 — `wallet send` returns an approval handoff

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

**MANDATORY card (show before polling):**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ Wallet Send — Approval Required

A transfer needs your passkey approval:

🌐 {approval_url}

📤 Send:        {amount} {asset}
⛓️  Chain:       {chain}
📬 To:          {to}
📋 Request ID:  {request_id}

👆 Open the link and approve with your passkey.
⏳ I'll wait automatically...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{approval_url}` | response field `approval_url` |
| `{amount}` | response field `amount` |
| `{asset}` | response field `asset` |
| `{chain}` | response field `chain` |
| `{to}` | response field `to` |
| `{request_id}` | response field `request_id` |

Optionally open the URL in the user's browser (`open`/`xdg-open`/`start "{approval_url}"`), then **immediately** run the `next_command`.

### Step 2 — `wallet send-status --wait` resolves the send

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

**MANDATORY card (show on success):**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💸 Transfer Complete

📤 Sent:     {amount} {asset}
⛓️  Chain:    {chain}
📬 To:       {to}
🧾 Tx Hash:  {transaction_hash}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{amount}`, `{asset}`, `{chain}`, `{to}` | carry forward from the **Step 1** `wallet send` response (send-status does not echo them) |
| `{transaction_hash}` | `wallet send-status` response field `transaction_hash` (or the direct-send response on the rollback path) |

If `send-status` returns `failed` (exit 1), `rejected` (exit 3), or `expired` (exit 3), tell the user the transfer did not go through and offer to start a new send. See `@references/commands.md` for every state.

---

## `wallet balance`, `wallet address` — display cards

After a successful **balance** check, present the aggregate and per-chain breakdown:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💰 Wallet Balance — ≈ ${total_usd_approx}

{asset}   {total}
   base     {amount}
   tempo    {amount}
   solana   {amount}
   robinhood {amount}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Repeat the asset block for each entry in `assets[]`; list one line per entry in that asset's `chains[]`. If any `partial` field is `true`, append "(partial — one chain's balance could not be read)".

After a successful **address** lookup:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📬 Wallet Addresses

base     {address}
tempo    {address}
robinhood {address}
solana   {address}

base + tempo + robinhood share one EVM address.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

One line per entry in `wallets[]` (`{chain}` → `{address}`). Show the shared-address note only when two chains report the same address.

When showing the Robinhood address, state clearly: **Only send USDG on Robinhood to this address.** The address may match Base and Tempo, but the supported asset does not.

## `faucet drop` — display card

The faucet is **testnet only** (the CLI blocks production automatically) and now **requires login**. After a successful drop:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🪂 Tokens Received!

💰 Amount:     {amount} {asset}
📬 Dropped to: {recipient_address}
🧾 Tx Hash:    {transaction_hash}

Test tokens only — your wallet is funded for development.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Error Handling

| Exit Code | Meaning | Error Message Pattern | Recovery Action |
|-----------|---------|----------------------|-----------------|
| 0 | Success **or** `human_action_required` | `status: "success"` / `status: "human_action_required"` | For `human_action_required`, show the approval URL and poll with `send-status`. It is NOT an error. |
| 1 | Network error / send failed | `network error: ...`; `send-status` returns `status: "error"` with `error_code` | A client-side network error while polling `send-status` is safe to retry — re-run the same status check, do not create a new send (the original request may still resolve). Only start a new send once `send-status` itself returns a confirmed terminal `error`/`failed` state — that means the backend has already determined the transfer did not go through. |
| 2 | Usage / validation error | `Missing --chain flag`, `--chain must be one of base\|tempo\|solana\|robinhood`, `--to is not a valid <chain> address: ...`, `--amount must be a positive number`, `Missing --recipient flag`, `Missing --token flag` | Fix the flags. `--chain` is required; the address must match the chain. |
| 3 | Auth error | `Not logged in. Run 'kpass login init ...'`; `send-status` `rejected`/`expired`/`--wait` timeout | Use **`authenticate-user`** to log in, then retry. For a rejected/expired send, start a new one. |
| 4 | Not found | `not found` | Check the request ID or recipient address. |
| 5 | Rate limited | `rate limit` | Wait ~30 seconds and retry. |
| 6 | Insufficient balance | `error_code: "insufficient_balance"` | The wallet's available balance is below the amount. Check `wallet balance`; on testnet use `faucet drop` to top up, otherwise fund the wallet. |

See `@references/commands.md` for the exact error envelope of every command and state.

---

## Commands That DO NOT Exist

Do NOT attempt any of the following — they will fail:

- `kpass wallet` (no sub-command) — use `wallet balance`, `wallet send`, `wallet send-status`, or `wallet address`.
- `kpass wallet send` **without `--chain`** — `--chain` is required (`base|tempo|solana|robinhood`).
- `kpass wallet send --chain kite` — `kite` is not a supported chain.
- `kpass wallet transfer` / `kpass send` / `kpass balance` — use `wallet send` / `wallet balance`.
- `kpass wallet send --recipient` — the flag is `--to`. `--token` / `--currency` — the flag is `--asset`.
- `kpass wallet fund` / `wallet deposit` / `wallet withdraw` — do not exist; use `faucet drop` for test tokens.
- `kpass faucet` (no sub-command) — use `faucet drop`. `faucet drop --to` — the flag is `--recipient`. `faucet drop --asset` — the flag is `--token`. `faucet drop --amount` — the faucet determines the amount.
- Any command with `--json` — the correct flag is `--output json` (two separate tokens).

---

## Cross-Skill References

- **Prerequisite (all commands):** the user must be logged in. Use **`authenticate-user`**.
- **For paid API access** (not direct transfers): use **`request-session`** then **`x402-execute`**.
- **For diagnostics:** to inspect registered agents and sessions, use **`manage-agents`**.
- **After a transfer or faucet drop:** suggest verifying it in history with the **`activity`** skill.
