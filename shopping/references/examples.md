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

💰 Estimated total: $9.99
💳 Payment: USDC on ethereum-sepolia

⚠️  Do you want to place this order?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

**Step 6: User confirms.** User says "yes, place the order".

Cart total is $9.99. Agent needs a spending session — uses the **`request-session`** skill with the cart total as the budget source. Example delegation:

```json
{"task":{"summary":"Shopping checkout — estimated total $9.99"},"payment_policy":{"max_amount_per_tx":"15","max_total_amount":"15","ttl_seconds":3600}}
```

The `form-session-delegation` skill derives the parameters (per-tx limit, total budget, TTL) from the cart total. The user approves the session via passkey.

Once the session is active (session ID is automatically saved in agent config), run checkout:
```bash
kpass shop:checkout --confirmed --output json
```
The checkout automatically uses the current session and deducts the cart total from its budget.

**Agent says:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 Order Placed!

📦 Order ID:          ord_abc123
🧾 Crossmint Order:   ce5bcec3-b6a0-...
💰 Payment:           USDC on ethereum-sepolia
🔗 Tx Hash:           0xdeadbeef...
📋 Status:            payment_submitted

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
  🔄 Phase:     completed
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

Estimated total: $32.82. Ready to checkout, or want to keep shopping?
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

Your cart total is approximately $9.99 in {currency}. You can check your wallet balance with the `wallet-send` skill, or fund your wallet before trying again.
```

**Agent does NOT auto-retry.** The user needs to fund the wallet first.
