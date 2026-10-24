# Shopping — Worked Examples

End-to-end walkthroughs for the `shopping` skill. Read this when you need to understand how a full shopping conversation flows from search through checkout to delivery tracking. Per-command details live in `commands.md`.

## Buy a USB-C Cable

**Context:** User says "I want to buy a type C cable".

---

**Step 1: Search.** User wants a type C cable — run a product search.
```bash
kpass shop:search --query "type C cable" --output json
```

**Agent says:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Search Results — "type C cable"

  1. Amazon Basics USB-C Cable, 6 Foot, White
     💲 $5.85  ⭐ 4.5 (54,800 reviews)
     🏷️  ID: B01GGKZ2SC

  2. LISEN USB C to USB C Cable, 5-Pack
     💲 $8.99  ⭐ 4.6 (13,800 reviews)
     🏷️  ID: B0CFQ5T5F6

  3. Anker USB C to USB C Cable (6 FT, 2Pack)
     💲 $9.99  ⭐ 4.7 (79,300 reviews)
     🏷️  ID: B088NRLMPV

Reply with a number to add to cart.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Which one would you like? You can also say "the cheapest" or "the best rated".
```

---

**Step 2: User picks an item.** User says "add the Anker one".

The user said "the Anker one" (singular), so add 1:
```bash
kpass shop:cart add --provider amazon --external-id B088NRLMPV --output json
```

**Agent says:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Added to Cart

  Anker USB C to USB C Cable (6 FT, 2Pack)
  💲 $9.99  ×1

Cart now has 1 item(s).
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Would you like to keep shopping, or proceed to checkout?
```

---

**Step 3: User wants to checkout.** User says "let's checkout".

**Agent checks shipping first:**
```bash
kpass shop:shipping view --output json
```
Response: `"missing": ["email", "line1", "city", "state", "postal_code"]`, `"complete": false`.

**Agent says:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Shipping Profile ⚠️  Incomplete

  Missing: email, line1, city, state, postal_code

  Please provide:
  - Email address
  - Street address
  - City, State, ZIP code
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

I need a few details to ship your order. You can provide them all at once, like:

"Jane Doe, jane@example.com, 456 Oak Ave, Austin, TX 78701"
```

---

**Step 4: User provides shipping.** User says "Jane Doe, jane@example.com, 456 Oak Ave, Austin, TX 78701".

```bash
kpass shop:shipping update --name "Jane Doe" --email "jane@example.com" --line1 "456 Oak Ave" --city "Austin" --state "TX" --postal "78701" --output json
```

**Agent says:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Shipping Profile ✅

  👤 Jane Doe
  📧 jane@example.com
  🏠 456 Oak Ave
     Austin, TX 78701
     US
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

**Step 5: Order summary and confirmation.** Agent shows the mandatory confirmation card:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Order Summary — Please Confirm

🛒 Cart:
  1. Anker USB C to USB C Cable (6 FT, 2Pack)
     💲 $9.99  ×1

📦 Ship to:
  Jane Doe
  456 Oak Ave
  Austin, TX 78701, US

💰 Subtotal:        $9.99
🧾 Charged up front: $15.99  (cap $14.99 incl. tax & shipping, + $1 provider fee; the unused part is refunded to your wallet)
💳 Payment: USDC on base

⚠️  Do you want to place this order?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

**Step 6: User confirms.** User says "yes, place the order".

Cart subtotal is $9.99, so the checkout charge is cap $14.99 (subtotal + $5 floor) + $1 fee = $15.99. Agent needs a spending session — uses the **`request-session`** skill with that charge as the budget source. Example delegation:

```json
{"task":{"summary":"Shopping checkout — cart subtotal $9.99, charge up to $15.99"},"payment_policy":{"max_amount_per_tx":"20","max_total_amount":"20","ttl_seconds":3600}}
```

The `form-session-delegation` skill (Path B) derives the parameters (per-tx limit, total budget, TTL) from the charge. Create it with `kpass session create --delegation "$DELEGATION_JSON" --separate --output json` (the account allowance never pays checkouts), put the reply's `user_message` (link and limits) in your reply, then wait. The user approves the session via passkey.

Once the session is active (session ID is automatically saved in agent config), run checkout:
```bash
kpass shop:checkout --confirmed --output json
```
The checkout automatically uses the current session and deducts the charge ($15.99) from its budget; the provider refunds the unused part of the cap to the wallet once the real total is known.

**Agent says:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 Order Placed!

📦 Order ID:          ord_abc123
🧾 Provider Order:    550e8400-e29b-41d4-a716-446655440000
💰 Charged up front:  $15.99 USDC on base (cap 14.99 + $1 fee; unused part refunded)
🔗 Tx Hash:           0xdeadbeef...
📋 Status:            pending

Track with: kpass shop:order status --order-id ord_abc123 --output json
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Your order is placed! I'll keep the order ID so you can check status anytime.
```

---

**Step 7: Order tracking.** User asks "what's the status of my order?" later.

```bash
kpass shop:order status --order-id ord_abc123 --output json
```

**Agent says:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Order Status

  📋 Order:     ord_abc123
  📋 Status:    completed
  💳 Payment:   confirmed
  🔗 Tx Hash:   0xdeadbeef...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If the user asks about delivery: `kpass shop:order delivery --order-id ord_abc123 --output json`

---

## Multiple Items with Quantity

**Context:** User says "I need 3 of those LISEN cables and also add the Amazon Basics one".

**Agent recognizes two items from the previous search results.**

```bash
kpass shop:cart add --provider amazon --external-id B0CFQ5T5F6 --quantity 3 --output json
```
**Agent says:** "Added 3x LISEN USB C Cable ($8.99 each) to your cart."

```bash
kpass shop:cart add --provider amazon --external-id B01GGKZ2SC --output json
```
**Agent says:** "Added 1x Amazon Basics USB-C Cable ($5.85) to your cart."

```bash
kpass shop:cart view --output json
```
**Agent says:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛒 Shopping Cart (2 item(s))

  1. LISEN USB C to USB C Cable, 5-Pack
     💲 $8.99  ×3
     🏷️  amazon:B0CFQ5T5F6

  2. Amazon Basics USB-C Cable, 6 Foot, White
     💲 $5.85  ×1
     🏷️  amazon:B01GGKZ2SC

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Subtotal: $32.82 (up to $40.38 will be charged at checkout — a $39.38 cap plus the $1 provider fee — and the unused part is refunded). Ready to checkout, or want to keep shopping?
```

---

## User Says "Buy This" Without Searching

**Context:** User says "add this coffee to cart" without a prior search.

**Agent says:** "I'd need to find that product first. What kind of coffee are you looking for? For example, 'ground coffee', 'coffee pods', or a specific brand?"

User says: "Maxwell House ground coffee".

```bash
kpass shop:search --query "Maxwell House ground coffee" --output json
```

Agent displays results. User picks one.

User says: "add 2 of those".

```bash
kpass shop:cart add --provider amazon --external-id B0CXYYWL6G --quantity 2 --output json
```

---

## Insufficient Balance at Checkout

**Step 1:** Checkout fails with "ERC20: transfer amount exceeds balance".

**Agent says:**
```
⚠️ Checkout failed — your wallet doesn't have enough {currency} on {chain} to cover this order.

Checkout charges up to $15.99 in {currency} (the $14.99 cap plus the $1 provider fee). You can check your wallet balance with the `wallet-send` skill, or fund your wallet before trying again.
```

**Agent does NOT auto-retry.** The user needs to fund the wallet first.
