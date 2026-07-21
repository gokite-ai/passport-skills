# Wallet & Faucet — Worked Examples

End-to-end walkthroughs for the `wallet-send` skill. Per-command syntax and JSON shapes live in `commands.md`; the send-approval flow and mandatory cards live in `SKILL.md`. All commands require the user to be logged in.

---

## Check a Multichain Balance

**Context:** The user asks "how much do I have?"

```bash
kpass wallet balance --output json
```
Output:
```json
{
  "total_usd_approx": "1250.50",
  "assets": [
    { "asset": "USDC", "total": "1000.00", "decimals": 6,
      "chains": [
        { "chain": "base", "amount": "600.00", "partial": false },
        { "chain": "tempo", "amount": "400.00", "partial": false },
        { "chain": "solana", "amount": "0.00", "partial": false }
      ], "partial": false },
    { "asset": "PYUSD", "total": "250.50", "decimals": 6,
      "chains": [ { "chain": "solana", "amount": "250.50", "partial": false } ], "partial": false }
  ],
  "as_of": "2026-06-23T18:00:00Z",
  "_version": "1", "status": "success",
  "hint": "Total balance ≈ $1250.50 across 2 asset(s).", "next_command": ""
}
```

Display the balance card:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💰 Wallet Balance — ≈ $1250.50

USDC    1000.00
   base     600.00
   tempo    400.00
   solana   0.00
PYUSD   250.50
   solana   250.50
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then summarize: "You hold **1000.00 USDC** (600 on base, 400 on tempo) and **250.50 PYUSD** on solana — about **$1250.50** total."

---

## Send Tokens (with passkey approval)

**Context:** The user says "Send 25 USDC to `0x9876fedc5432ba10...` on base."

**Step 1 — Confirm funds on the target chain.** From the balance above, base USDC is 600.00 ≥ 25 → proceed. (A balance on a *different* chain would not qualify — funds must be on `base`.)

**Step 2 — Start the send.**
```bash
kpass wallet send --chain base --to 0x9876fedc5432ba10... --amount 25 --asset USDC --output json
```
Output (the normal path):
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

Display the Approval Required card and (optionally) open the URL:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ Wallet Send — Approval Required

A transfer needs your passkey approval:

🌐 https://passport.dev.gokite.ai/approve/req_abc123

📤 Send:        25 USDC
⛓️  Chain:       base
📬 To:          0x9876fedc5432ba10...
📋 Request ID:  req_abc123

👆 Open the link and approve with your passkey.
⏳ I'll wait automatically...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Step 3 — Poll for the result.** Run the `next_command` immediately:
```bash
kpass wallet send-status --request-id req_abc123 --wait --output json
```
Output (user approved in the browser):
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
(`status: "success"` + a `transaction_hash` = sent. `send-status` does not echo the chain/to/amount/asset, so carry those forward from Step 2.)

Display the Transfer Complete card:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💸 Transfer Complete

📤 Sent:     25 USDC
⛓️  Chain:    base
📬 To:       0x9876fedc5432ba10...
🧾 Tx Hash:  0xdeadbeef12345678...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**If `send-status` times out** (exit 3, `status: "pending"`): tell the user you're still waiting for their approval. When they say they've approved, run `send-status` again (with or without `--wait`).
**If it returns `rejected`/`expired`** (exit 3) **or `failed`** (exit 1, with `error_code`): tell the user it didn't go through and offer to start a new send.

---

## Look Up Receive Addresses

**Context:** The user asks "what's my wallet address?" or someone needs to send them funds.

```bash
kpass wallet address --output json
```
Output:
```json
{
  "wallets": [
    { "chain": "base", "vm_family": "evm", "address": "0x1234abcd5678ef90..." },
    { "chain": "tempo", "vm_family": "evm", "address": "0x1234abcd5678ef90..." },
    { "chain": "solana", "vm_family": "solana", "address": "9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin" }
  ],
  "_version": "1", "status": "success",
  "hint": "3 wallet(s) found.", "next_command": ""
}
```

Display the addresses card:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📬 Wallet Addresses

base     0x1234abcd5678ef90...
tempo    0x1234abcd5678ef90...
solana   9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin

base + tempo share one EVM address.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

To show just one chain: `kpass wallet address --chain solana --output json`.

---

## Fund a Wallet from the Faucet (testnet)

**Context:** The user is on testnet and needs USDC to test with.

**Step 1 — Get the receive address** (faucet drops to an address, so fetch it):
```bash
kpass wallet address --chain base --output json
```
Take the `base` `address`.

**Step 2 — Request test tokens** (requires login; testnet only):
```bash
kpass faucet drop --recipient 0x1234abcd5678ef90... --token USDC --output json
```
Output:
```json
{
  "amount": "100.00", "asset": "USDC", "chain_id": 2368,
  "recipient": "0x1234abcd5678ef90...", "recipient_address": "0x1234abcd5678ef90...",
  "transaction_hash": "0xfaucet12345678...", "wallet_address": "0xfaucet_sender...", "wallet_type": "custodial",
  "_version": "1", "status": "success",
  "hint": "Dropped 100.00 USDC to 0x1234abcd5678ef90....", "next_command": ""
}
```

Display the Tokens Received card:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🪂 Tokens Received!

💰 Amount:     100.00 USDC
📬 Dropped to: 0x1234abcd5678ef90...
🧾 Tx Hash:    0xfaucet12345678...

Test tokens only — your wallet is funded for development.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Step 3 — Confirm** with `kpass wallet balance --output json`.

> On production the faucet is blocked (exit 2: "Faucet is only available on staging/testnet environments"). Do not offer it there; the user must fund their wallet another way.

---

## Insufficient Balance on the Target Chain

**Context:** The user wants to send 25 USDC on `solana`, but the balance shows USDC only on `base`/`tempo` (solana USDC = 0.00).

Do NOT attempt the send. Funds must be on the chain you send from. Tell the user: "You have USDC on base and tempo, but **0 USDC on solana**. To send on solana, either send from base/tempo instead, or move funds to your solana wallet first." If the backend rejects a send for low funds, it returns exit 6 with `error_code: "insufficient_balance"`.
