# Shopping — Command Reference

Full per-command reference for the `shopping` skill. Read this when constructing a command, validating flags, or interpreting an error response. The skill's `SKILL.md` contains trigger logic and conversation flow; this file contains command-level detail.

## `shop:search` — Search Products

Searches for products via the configured provider (currently Amazon via SerpAPI) and returns results with provider and external identifier.

```
kpass shop:search --query <QUERY> --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Search query | `--query` | Yes | From user's request | Non-empty string describing the product |
| Max results | `--max-results` | No | Default: 5 | Integer 1–20 |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "query": "usb c cable",
  "source": "serpapi",
  "items": [
    {
      "provider": "amazon",
      "external_identifier": "B01GGKZ2SC",
      "title": "Amazon Basics USB-C Cable, 6 Foot, White",
      "link": "https://www.amazon.com/dp/B01GGKZ2SC",
      "price": "$5.85",
      "rating": 4.5,
      "reviews": 54800,
      "thumbnail": "https://m.media-amazon.com/images/I/61c0UMl3MPL._AC_UY218_.jpg"
    }
  ],
  "_version": "1",
  "status": "success",
  "hint": "Found 5 products for 'usb c cable'.",
  "next_command": "kpass shop:cart add --provider amazon --external-id B01GGKZ2SC --output json"
}
```

**Key fields:**
- `items[].provider` — The product provider (e.g., `"amazon"`). Pass this to `shop:cart add`.
- `items[].external_identifier` — The provider-specific product ID (e.g., ASIN for Amazon). Pass this to `shop:cart add`.
- `items[].price` — Display price string (e.g., `"$5.85"`).
- `items[].rating` — Star rating (e.g., `4.5`).
- `items[].reviews` — Number of reviews.

### Error Output — Search Failed (exit code 1)

The SerpAPI request failed. Retry after a brief pause.

### What to Do After This Command

Present the results to the user using the display card below. Number them clearly so the user can say "add number 2" or "I want the Anker one". Do NOT invent products not in the search results.

**MANDATORY display card — you MUST show this after every search:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Search Results — "{query}"

{for each item, numbered:}
  {i}. {title}
     💲 {price}  ⭐ {rating} ({reviews} reviews)
     🏷️  ID: {external_identifier}

Reply with a number to add to cart.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{query}` | From JSON field `query` |
| `{i}` | Sequential number starting at 1 |
| `{title}` | From `items[i].title` — truncate to ~80 chars if very long |
| `{price}` | From `items[i].price` |
| `{rating}` | From `items[i].rating` |
| `{reviews}` | From `items[i].reviews` — format with commas (e.g., `54,800`) |
| `{external_identifier}` | From `items[i].external_identifier` |

**Example rendered card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Search Results — "usb c cable"

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
```

---

## `shop:cart add` — Add Item to Cart

Adds a product to the cart. Only requires the provider and external identifier — the backend automatically fetches the product title, price, link, and thumbnail from the provider.

```
kpass shop:cart add --provider <PROVIDER> --external-id <ID> --output json
```

Use the `provider` and `external_identifier` values exactly as returned from `shop:search`.

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Provider | `--provider` | Yes | From search results `provider` field — pass through exactly as returned | Do not hardcode or guess |
| External ID | `--external-id` | Yes | From search results `external_identifier` field — pass through exactly as returned | Do not hardcode or guess |
| Quantity | `--quantity` | No | Default: 1 | Positive integer |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

Returns the updated cart (same shape as `shop:cart view`).

### Error Output — Product Not Found (exit code 1)

The backend could not fetch product details from the provider. Verify the external ID is correct.

### What to Do After This Command

Confirm to the user what was added. Show the updated cart using the cart display card.

**MANDATORY display card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Added to Cart

  {title}
  💲 {price}  ×{quantity}

Cart now has {item_count} item(s).
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{title}` | From the matching item in `items[]` in the response |
| `{price}` | From the matching item's `price` field |
| `{quantity}` | From the matching item's `quantity` field |
| `{item_count}` | From `item_count` in the response |

---

## `shop:cart view` — View Cart

Returns the current cart contents.

```
kpass shop:cart view --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "items": [
    {
      "provider": "amazon",
      "external_identifier": "B0CXYYWL6G",
      "product_locator": "amazon:B0CXYYWL6G",
      "title": "Maxwell House Coffee 27.5oz",
      "link": "https://www.amazon.com/dp/B0CXYYWL6G",
      "price": "$12.49",
      "thumbnail": "https://...",
      "quantity": 1
    }
  ],
  "item_count": 1,
  "payment": {
    "chain": "ethereum-sepolia",
    "currency": "USDC"
  },
  "_version": "1",
  "status": "success",
  "hint": "Cart has 1 item(s).",
  "next_command": ""
}
```

### What to Do After This Command

Display the cart card. If the cart is empty, tell the user and suggest searching for products.

**MANDATORY display card:**

When cart has items:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛒 Shopping Cart ({item_count} item(s))

{for each item, numbered:}
  {i}. {title}
     💲 {price}  ×{quantity}
     🏷️  {provider}:{external_identifier}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

When cart is empty:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛒 Shopping Cart

  Your cart is empty.
  Search for products with: shop:search --query "..."
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## `shop:cart remove` — Remove Item from Cart

Removes an item by provider and external identifier.

```
kpass shop:cart remove --provider <PROVIDER> --external-id <ID> --output json
```

Use the `provider` and `external_identifier` values from `shop:cart view`.

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Provider | `--provider` | Yes | From cart item's `provider` field — pass through exactly | Must match an item in cart |
| External ID | `--external-id` | Yes | From cart item's `external_identifier` field — pass through exactly | Must match an item in cart |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

Returns the updated cart.

### What to Do After This Command

Show the updated cart using the cart display card.

---

## `shop:cart clear` — Clear Cart

Removes all items from the cart.

```
kpass shop:cart clear --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

Returns an empty cart.

---

## `shop:shipping view` — View Shipping Profile

Returns the user's shipping profile with a list of missing required fields.

```
kpass shop:shipping view --output json
```

### Success Output (exit code 0)

```json
{
  "name": "Jane Doe",
  "email": "jane@example.com",
  "line1": "456 Oak Ave",
  "line2": "",
  "city": "Austin",
  "state": "TX",
  "postal_code": "78701",
  "country": "US",
  "missing": [],
  "complete": true,
  "_version": "1",
  "status": "success",
  "hint": "Shipping profile is complete.",
  "next_command": ""
}
```

**Key fields:**
- `complete` — `true` if all required fields are filled. `false` if any are missing.
- `missing` — Array of missing field names (e.g., `["email", "line1", "city"]`). Empty when complete.

### What to Do After This Command

If `complete` is `true`: show the profile card and confirm with the user.
If `complete` is `false`: list the `missing` fields and ask the user to provide them. Then call `shop:shipping update`.

**MANDATORY display card:**

When complete:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Shipping Profile ✅

  👤 {name}
  📧 {email}
  🏠 {line1}
     {line2}
     {city}, {state} {postal_code}
     {country}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

When incomplete:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Shipping Profile ⚠️  Incomplete

  Missing: {missing fields, comma-separated}

  Please provide:
  {for each missing field:}
  - {field name}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Omit `{line2}` from the card if it is empty.

---

## `shop:shipping update` — Update Shipping Profile

Merges provided fields into the shipping profile. Only pass fields that need updating — omitted fields are left unchanged.

```
kpass shop:shipping update --name <NAME> --email <EMAIL> --line1 <ADDR> --city <CITY> --state <STATE> --postal <ZIP> --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Full name | `--name` | No* | Ask user | Non-empty string |
| Email | `--email` | No* | Ask user | Valid email address |
| Address line 1 | `--line1` | No* | Ask user | Non-empty string |
| Address line 2 | `--line2` | No | Ask user | Optional |
| City | `--city` | No* | Ask user | Non-empty string |
| State/Province | `--state` | No* | Ask user | Non-empty string |
| Postal/ZIP code | `--postal` | No* | Ask user | Non-empty string |
| Country code | `--country` | No | Default: `US` | 2-letter country code |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

*Required if listed in `missing` from `shop:shipping view`.

### Success Output (exit code 0)

Returns the updated shipping profile (same shape as `shop:shipping view`).

### What to Do After This Command

Show the updated shipping profile card. If now complete, proceed toward checkout.

---

## `shop:checkout` — Place Order

Executes the checkout flow: validates cart and shipping, creates order, signs and broadcasts payment.

**Timeout:** This command has a **5-minute timeout**. Checkout involves creating a Crossmint order, signing and broadcasting an on-chain transaction, and polling for receipt confirmation. This can take 1-3 minutes. The CLI shows a progress spinner with elapsed time in non-JSON mode. Do NOT treat a slow response as a failure — wait for the full timeout before giving up.

**CRITICAL PREREQUISITES:**
1. Cart must not be empty.
2. Shipping profile must be complete.
3. Agent must have an active spending session with sufficient budget to cover the cart total.

**CRITICAL: NEVER call this unless the user has explicitly confirmed the purchase.**

```
kpass shop:checkout --confirmed --output json
```

The CLI automatically resolves the session ID from the agent config (`current_session_id`, set when a session is approved). You do not need to pass `--session-id` explicitly unless overriding.

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Confirmed | `--confirmed` | Yes | User must explicitly say "confirm", "buy now", "place order" | Must be present |
| Session ID | `--session-id` | No | Auto-resolved from agent config. Only pass to override. | Must be an active session with sufficient budget |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Pre-Checkout Checklist

Before calling checkout, you MUST do ALL of the following in order:

1. **Cart is not empty** — run `shop:cart view`. Calculate the estimated total by summing each item's price × quantity.
2. **Shipping is complete** — run `shop:shipping view` and check `complete: true`.
3. **Show confirmation dialog** — display the order summary card below and ask for explicit confirmation. Do NOT proceed without a "yes".
4. **Active spending session** — if none exists, use the **`request-session`** skill. The cart total is the budget source — the `form-session-delegation` skill will derive the session parameters from it (no 402 preflight needed). Sessions are protocol-agnostic, so any active session with a matching asset allowlist and sufficient budget can be used for checkout. Tell the user the estimated total so they know what they're approving.

**MANDATORY — You MUST show this confirmation card before calling checkout. No exceptions:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Order Summary — Please Confirm

🛒 Cart:
{for each item, numbered:}
  {i}. {title}
     💲 {price}  ×{quantity}

📦 Ship to:
  {name}
  {line1}
  {city}, {state} {postal_code}, {country}

💰 Estimated total: {sum of price × quantity for all items}
💳 Payment: {currency} on {chain}

⚠️  Do you want to place this order?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| Cart items | From `shop:cart view` response `items[]` |
| Shipping fields | From `shop:shipping view` response |
| `{chain}` | From `shop:cart view` response field `payment.chain` |
| `{currency}` | From `shop:cart view` response field `payment.currency` |
| Estimated total | Sum of each item's price × quantity. Parse the `$X.XX` price strings. If a price cannot be parsed, show "see cart" instead of a number. |

**Only after the user responds with "yes", "confirm", "place order", or equivalent, proceed to create a session (if needed) and call `shop:checkout`.**

**Session budget:** The checkout deducts the cart total from the session's spending budget. If the payment fails (e.g., insufficient balance), the reservation is released and the budget is restored. You do not need to manage the budget manually.

### Success Output (exit code 0)

```json
{
  "order_id": "ord_abc123",
  "crossmint_order_id": "ce5bcec3-b6a0-...",
  "order_status": "payment_submitted",
  "tx_hash": "0xdeadbeef...",
  "currency": "usdc",
  "chain": "ethereum-sepolia",
  "_version": "1",
  "status": "success",
  "hint": "Order placed. Order ID: ord_abc123.",
  "next_command": "kpass shop:order status --order-id ord_abc123 --output json"
}
```

**Note:** The envelope `status` field (`"success"`) is the CLI status. The `order_status` field (`"payment_submitted"`) is the payment provider's order status.

### Error Output — Cart Empty (exit code 2, `error_code: "cart_empty"`)

```json
{"_version": "1", "status": "error", "error": "cart is empty", "error_code": "cart_empty", "hint": "Cart is empty. Add items before checking out. Run 'kpass shop cart add' to add items.", "next_command": ""}
```
Recovery: Add items to cart first.

### Error Output — Shipping Incomplete (exit code 2, `error_code: "shipping_incomplete"`)

```json
{"_version": "1", "status": "error", "error": "shipping profile is incomplete", "error_code": "shipping_incomplete", "hint": "Shipping profile is incomplete. Run 'kpass shop shipping view --output json' to see missing fields, then update with 'kpass shop shipping update'.", "next_command": ""}
```
Recovery: Run `shop:shipping view` to see missing fields, then `shop:shipping update`.

### Error Output — Checkout Not Confirmed (exit code 2, `error_code: "checkout_not_confirmed"`)

```json
{"_version": "1", "status": "error", "error": "checkout not confirmed by user", "error_code": "checkout_not_confirmed", "hint": "Checkout was not confirmed. Include --confirmed flag to proceed with checkout.", "next_command": ""}
```
Recovery: You called checkout without `--confirmed`. The `--confirmed` flag is required.

### Error Output — No Active Session (exit code 2)

```json
{"status": "error", "error": "No active session."}
```
Recovery: Create a spending session first using the **`request-session`** skill with the cart total as budget.

### Error Output — No Session Private Key (exit code 3)

```json
{"status": "error", "error": "No session private key found."}
```
Recovery: The session is missing its signing credentials. Re-create and approve a session with `kpass agent:session create`.

### Error Output — Signature Verification Failed (exit code 3)

```json
{"status": "error", "error": "signature verification failed"}
```
Recovery: The session credentials don't match what the server expects. Re-create and approve a session with `kpass agent:session create`.

### Error Output — Session Budget Exceeded (exit code 6, `error_code: "session_total_exceeded"`)

```json
{"_version": "1", "status": "error", "error": "payment amount exceeds max_total_amount", "error_code": "session_total_exceeded", "hint": "Payment amount exceeds the session's total budget. Create a new session with a higher --max-total-amount.", "next_command": ""}
```
Recovery: The session budget is too small for the cart total. Create a new session with a higher budget using the **`request-session`** skill.

### Error Output — Per-Transaction Limit Exceeded (exit code 6, `error_code: "session_rule_exceeded"`)

```json
{"_version": "1", "status": "error", "error": "payment amount exceeds max_amount_per_tx", "error_code": "session_rule_exceeded", "hint": "Payment amount exceeds the session's per-transaction limit. Create a new session with a higher --max-amount-per-tx.", "next_command": ""}
```
Recovery: The cart total exceeds the session's per-transaction limit. Create a new session with a higher `--max-amount-per-tx`.

### Error Output — Wallet Not Found (exit code 4)

```json
{"status": "error", "error": "user wallet not found"}
```
Recovery: The user's wallet has not been provisioned. This usually means authentication is incomplete. Re-run login.

### Error Output — Insufficient Balance (exit code 6, `error_code: "insufficient_balance"`)

```json
{"_version": "1", "status": "error", "error": "user Kite balance is insufficient", "error_code": "insufficient_balance", "hint": "Wallet balance is insufficient for this payment. Fund the wallet or reduce the payment amount.", "next_command": ""}
```
Recovery: The user's wallet does not have enough of the payment currency. Check `payment.chain` and `payment.currency` from `shop:cart view` to know which chain and currency are needed. Use the **`wallet-send`** skill to check balance, and fund the wallet before retrying.

### Error Output — Payment Cap Exceeded (exit code 6, `error_code: "payment_cap_exceeded"`)

```json
{"_version": "1", "status": "error", "error": "payment amount exceeds per-transaction cap", "error_code": "payment_cap_exceeded", "hint": "Payment amount exceeds the per-transaction cap. Try a smaller amount or contact support for higher limits.", "next_command": ""}
```
Recovery: The cart total exceeds the system's per-transaction cap. Try splitting the order into smaller purchases or contact support.

### Error Output — Service Temporarily Unavailable (exit code 1)

The payment service may be temporarily paused or unavailable. The CLI will return exit code 1 with a message like `"treasury relay is paused"` or `"too many undercollected payments, relay paused until resolved"`. Recovery: Wait and retry after a few minutes. This is a transient infrastructure issue.

### Error Output — Payment Provider Timeout (exit code 1)

The CLI has a 5-minute timeout for checkout. If it still times out, the payment may have been submitted on-chain but the receipt wasn't confirmed in time. Check `shop:order list` to see if the order was recorded, and `kpass activity` to see the payment attempt status. Retry only after verifying the previous attempt didn't succeed.

### What to Do After This Command

**MANDATORY display card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎉 Order Placed!

📦 Order ID:          {order_id}
🧾 Crossmint Order:   {crossmint_order_id}
💰 Payment:           {currency} on {chain}
🔗 Tx Hash:           {tx_hash}
📋 Status:            {order_status}

Track with: kpass shop:order status --order-id {order_id} --output json
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{order_id}` | From JSON field `order_id` |
| `{crossmint_order_id}` | From JSON field `crossmint_order_id` |
| `{currency}` | From JSON field `currency` — uppercase (e.g., `USDC`) |
| `{chain}` | From JSON field `chain` |
| `{tx_hash}` | From JSON field `tx_hash` |
| `{order_status}` | From JSON field `order_status` |

---

## `shop:order status` — Check Order Status

Fetches the latest order status, refreshing from the payment provider if the order is not yet completed.

```
kpass shop:order status --order-id <ID> --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Order ID | `--order-id` | Yes | From checkout response `order_id` | Non-empty string |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "order_id": "ord_abc123",
  "crossmint_order_id": "ce5bcec3-...",
  "phase": "completed",
  "payment_status": "confirmed",
  "tx_hash": "0xdeadbeef...",
  "currency": "usdc",
  "chain": "ethereum-sepolia",
  "_version": "1",
  "status": "success",
  "hint": "Order ord_abc123: completed",
  "next_command": ""
}
```

**Note:** This endpoint does NOT include delivery status. For delivery tracking, use `shop:order delivery`.

### Error Output — Order Not Found (exit code 4)

Check the order ID is correct.

### What to Do After This Command

**MANDATORY display card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Order Status

  📋 Order:     {order_id}
  🔄 Phase:     {phase}
  💳 Payment:   {payment_status}
  🔗 Tx Hash:   {tx_hash}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If the user asks about delivery or tracking, use `shop:order delivery` instead.

---

## `shop:order delivery` — Check Delivery Status

Fetches the latest delivery status from the payment provider. Unlike `shop:order status` (which uses cached data for completed orders), this always makes a live API call to get real-time delivery and tracking info.

```
kpass shop:order delivery --order-id <ID> --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Order ID | `--order-id` | Yes | From checkout response `order_id` | Non-empty string |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "order_id": "ord_abc123",
  "crossmint_order_id": "ce5bcec3-...",
  "delivery_status": "shipped",
  "tracking_number": "1Z999AA10123456784",
  "tracking_url": "https://track.example.com/1Z999AA10123456784",
  "carrier": "UPS",
  "estimated_arrival": "2026-04-10",
  "_version": "1",
  "status": "success",
  "hint": "Order ord_abc123 delivery: shipped",
  "next_command": ""
}
```

**Key fields:**
- `delivery_status` — Current delivery state (e.g., `"pending"`, `"shipped"`, `"delivered"`, `"unknown"`).
- `tracking_number` — Carrier tracking number (may be empty if not yet shipped).
- `tracking_url` — URL to track the shipment (may be empty).
- `carrier` — Shipping carrier name (may be empty).
- `estimated_arrival` — Estimated delivery date (may be empty).

### What to Do After This Command

**MANDATORY display card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚚 Delivery Status

  📋 Order:     {order_id}
  📦 Status:    {delivery_status}
  🏢 Carrier:   {carrier}
  🔢 Tracking:  {tracking_number}
  🔗 Track URL: {tracking_url}
  📅 ETA:       {estimated_arrival}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Omit lines where the value is empty (e.g., if no tracking number yet, don't show the Tracking line).

---

## `shop:order list` — List All Orders

Returns all orders for the user, newest first.

```
kpass shop:order list --output json
```

### Success Output (exit code 0)

```json
{
  "orders": [
    {
      "order_id": "ord_abc123",
      "phase": "completed",
      "payment_status": "confirmed",
      "currency": "usdc",
      "chain": "ethereum-sepolia"
    }
  ],
  "_version": "1",
  "status": "success",
  "hint": "Found 1 order(s).",
  "next_command": ""
}
```
