---
name: shopping
description: >-
  Buy products, shop on Amazon, find deals, compare prices, build a product list,
  and checkout with crypto. Proactively invoke for any task involving purchasing
  physical items, product search, product recommendations, price comparison, adding
  to cart, order placement, order tracking, or delivery status -- even if the user
  does not say "shop" or "buy". Also handles "build me a [thing]", "find the best
  [product] under $X", or "curate items within a budget" requests. Supports Amazon
  (more providers coming).
user-invocable: true
allowed-tools:
  - "Bash(kpass shop:*)"
---

# Shopping

Search for products, manage a shopping cart, collect shipping information, and place orders paid with cryptocurrency via headless checkout.

**Currently supported providers:** `amazon`. More providers will be added — the system is provider-agnostic.

## When to Use This Skill

- The user asks to buy something, shop for a product, or search for a product.
- The user says "I want to buy a type C cable" or "find me a phone charger under $10".
- The user asks to view, modify, or clear their shopping cart.
- The user asks to checkout, place an order, or confirm a purchase.
- The user asks about their shipping info or wants to update it.
- The user asks about their order status.

## When NOT to Use This Skill

- If the user asks to pay for a digital service or API — use **`x402-execute`**.
- If the user asks for a direct wallet-to-wallet transfer — use **`wallet-send`**.
- If the user asks about their wallet balance without shopping context — use **`wallet-send`**.

## Prerequisites

1. **User authenticated** — The user MUST be logged in. If not (exit code 3), use the **`authenticate-user`** skill first.
2. **Agent registered** — The agent MUST be registered. If not (exit code 3 with "Agent not registered"), run `kpass agent:register --type <agent-type> --output json` (substitute your agent's identity: `claude`, `cursor`, `codex`, `cline`, etc.).
3. **Active spending session** — Required ONLY for `shop:checkout`. All other commands (search, cart, shipping) do NOT require a session. Before checkout, create one with the **`request-session`** skill (budget derived from the cart total), or bind an existing one with the **`attach-session`** skill. Sessions are protocol-agnostic and settlement-token-agnostic — there is no `assets` allowlist field — but a session locks to the first asset it settles in: an **unlocked** session, or one already **locked to the checkout's settlement asset** (`shop:cart view` → `payment.currency`), with sufficient remaining budget can be reused; a session locked to a different asset fails checkout with `session_asset_forbidden` and needs a fresh session instead. You do not need to mark the session as shopping-specific. See the `shop:checkout` entry in `@references/commands.md` for the Pre-Checkout Checklist.

## Defaults (Do Not Ask the User Unless They Specify Otherwise)

| Setting | Default value | Override |
|---------|--------------|---------|
| Output format | `--output json` | Always use JSON output. Never omit this flag. |
| Max search results | 5 | Only pass `--max-results` if user requests more/fewer. |
| Quantity | 1 | Only pass `--quantity` if user specifies a different quantity. |
| Base URL | Omit (uses built-in default) | Only pass `--base-url` if the user explicitly provides a custom backend URL. |

## How Providers Work

**You do NOT choose the provider.** The backend decides which provider(s) to search. Here's the flow:

1. **Search** — You pass only a query. The backend searches all enabled providers and returns results. Each result is tagged with its `provider` (e.g., `"amazon"`).
2. **Add to cart** — You pass through the `provider` and `external_identifier` exactly as they appeared in the search results. Never hardcode or guess a provider.
3. **Remove from cart** — Same: use the `provider` and `external_identifier` from the cart view.

**Never ask the user "which store?"** The search handles provider routing automatically. If a user asks to buy from a store that isn't supported, the search will return no results — tell them that store isn't available yet.

## Conversation Flow

Follow this flow for a full shopping transaction. You may skip steps if the user has already completed them (e.g., shipping is already on file).

1. **Search** — User describes what they want. Run a product search.
2. **Present results** — Show products in the display card format. Ask which to add.
3. **Confirm details before adding** — Ask quantity if user didn't specify. Default to 1 only if user says "add this" for a single item.
4. **Add to cart** — Add the selected item(s). Only `--provider` and `--external-id` are required; the backend fetches product details automatically.
5. **View cart** — Show the cart with totals. Offer to continue shopping or checkout.
6. **Check shipping** — View the shipping profile. If incomplete, ask for missing fields.
7. **Update shipping** — Fill in any missing fields the user provides.
8. **Cost summary** — Show the cart total + shipping info. Ask for **explicit confirmation**.
9. **Checkout** — ONLY after the user explicitly says "confirm", "buy now", "place order", or equivalent. Requires a spending session.
10. **Order tracking** — Report the order ID and allow status checks.

Do not run `shop:checkout` without an explicit user confirmation — once the command runs, the on-chain payment is signed and broadcast, and there's no recall after the transaction is mined. Phrases like "looks good", "sure", or "yes" in response to the Order Summary card count as confirmation; phrases like "buy this" or "order it" count. Anything ambiguous does not — show the Order Summary card and wait.

## Agent Behavior Guide — Be a Helpful Shopping Assistant

You are not just a CLI wrapper. You are guiding the user through a shopping experience. Follow these rules:

### Always Clarify Before Acting

- **User says "add this coffee to cart"** → If a specific product is clear from context, add 1 directly. Only ask quantity if the user's phrasing suggests they might want more than one (e.g., "add some coffee", "stock up on cables").
- **User says "buy a USB cable"** → Search first, show results, then ask which one. Never pick for them.
- **User says "add number 3"** after search results → Add it directly (user already made a clear choice). Show the "Added to Cart" card.
- **User says "I want 5 of those"** → Pass `--quantity 5`.
- **User says "remove the cable"** → If multiple items in cart match, ask which one. If only one, remove it.

### Always Confirm at Key Moments

- **Before checkout:** Always show the mandatory Order Summary confirmation card (defined in the `shop:checkout` Pre-Checkout Checklist section in `@references/commands.md`) with cart items, shipping address, estimated total, and payment method. Wait for explicit "yes" before proceeding.
- **Before clearing cart:** "This will remove all items from your cart. Are you sure?"
- **Before updating shipping:** If the user provides partial info, fill what they gave and ask for the rest. Don't leave fields blank.

### Guide Through Missing Information

- **Shipping is incomplete:** Don't just say "fields are missing". Instead, ask naturally:
  "I need a few details to ship your order:
  1. Full name
  2. Email address
  3. Street address
  4. City, State, ZIP code

  You can provide them all at once or one at a time."

- **No search results:** "I couldn't find anything for [query]. Try a different search term — maybe be more specific or use different keywords?"

- **Cart is empty at checkout:** "Your cart is empty! Would you like to search for something?"

### Proactive Suggestions

- After adding an item: "Added to cart! Would you like to keep shopping, or proceed to checkout?"
- After viewing an empty cart: "Your cart is empty. What would you like to shop for?"
- After a successful order: "Your order is placed! You can check the status anytime by asking me."
- If shipping is already complete when they go to checkout: Skip asking for shipping details — just show the summary.

### Handle Ambiguity

- **"Add the cheap one"** → Pick the lowest-priced item from the last search results. Confirm: "The cheapest option is [name] at $X.XX — adding that?"
- **"Add the best rated"** → Pick the highest-rated item. Confirm before adding.
- **"Get me something under $10"** → Search, filter results mentally, present only items under $10. If none, say so.
- **"Add all of them"** → Clarify: "You want to add all [N] items from the search results? That would be [list with prices]. Confirm?"

### Never Do These

- Never add items without the user knowing which product.
- Never checkout without explicit confirmation.
- Never guess an external ID — always use IDs from search results.
- Never silently fail — if a command errors, explain what went wrong and how to fix it.
- Never show raw JSON to the user — always use the display cards.

## Display Cards — MANDATORY

Render the formatted status cards verbatim after each successful command — the horizontal-rule format is what users scan to confirm what happened, and the eval grader looks for the exact strings inside them. Summarizing or rewording in plain text loses both signals.

If a command succeeds and has a display card template defined in `@references/commands.md`, you MUST output that card before doing anything else. Do not proceed to the next step until the card is displayed.

---

## Command Reference

Full argument tables, JSON output examples, per-command display cards, and full error response shapes live in:

→ **`@references/commands.md`**

Read that file when constructing any `shop:*` command or interpreting an error. The Pre-Checkout Checklist (with the mandatory Order Summary card) and the full Checkout error matrix are in the `shop:checkout` section.

---

## Worked Examples

End-to-end conversation walkthroughs — USB-C cable purchase, multi-item orders, "buy this" without searching, insufficient-balance recovery:

→ **`@references/examples.md`**

Read this when you need to model what a full shopping conversation looks like.

---

## Error Handling

| Exit Code | Meaning | Error Message Pattern | Recovery Action |
|-----------|---------|----------------------|-----------------|
| 0 | Success | `status: "success"` | Present the result using the appropriate display card. |
| 1 | Network error / service unavailable | `network error: ...`, `context deadline exceeded`, `treasury relay is paused`, `service is temporarily unavailable` | For `shop:search`/`shop:cart`/`shop:shipping` (no money moved): retry after 10–30 seconds. **For `shop:checkout` specifically: do NOT blindly retry** — a timeout doesn't mean the order wasn't placed. Check `shop:order list` / `activity` to confirm the previous attempt didn't succeed before retrying (see "Error Output — Payment Provider Timeout" in `@references/commands.md`). |
| 2 | Usage error | `Missing --query flag`, `Missing required flags`, `error_code: "checkout_not_confirmed"`, `"cart_empty"`, `"shipping_incomplete"`, `"cart_item_invalid_price"`, `No active session` | Fix the command flags or complete the prerequisite (fill cart, complete shipping, add `--confirmed`, create a session). Check `error_code` for the specific issue. |
| 3 | Auth error | `Agent not registered`, `invalid authorization header` | Register the agent: `kpass agent:register --type <agent-type> --output json` (use your agent's identity). If that fails with "Not logged in", use **`authenticate-user`** first. |
| 4 | Not found | `order not found`, `user wallet not found` | Check the ID is correct. For wallet errors, re-run login. |
| 5 | Rate limited | `rate limit` | Wait 30 seconds, then retry. |
| 6 | Session policy / payment violation | `error_code: "session_total_exceeded"`, `"session_rule_exceeded"`, `"session_asset_forbidden"`, `"session_endpoint_forbidden"`, `"insufficient_balance"`, `"payment_cap_exceeded"`, `"merchant_not_allowed"` | Do NOT re-authenticate. Check `error_code` and `hint` for the specific violation. For session policy errors, create a new session with corrected parameters using the **`request-session`** skill. For `insufficient_balance`, fund the wallet. For `payment_cap_exceeded`, reduce the order size. |

**Error envelope fields:** Error responses include `error` (raw backend message), `error_code` (machine-readable classification — prefer this for programmatic matching), and `hint` (recovery guidance).

### Specific Error Scenarios

**`error_code: "cart_empty"` (exit code 2):**
- The user tried to checkout with no items. Search for products and add to cart first.

**`error_code: "shipping_incomplete"` (exit code 2):**
- Missing shipping fields. Run `shop:shipping view` to see which fields are missing, ask the user, then `shop:shipping update`.

**`error_code: "checkout_not_confirmed"` (exit code 2):**
- You forgot `--confirmed`. Always pass this flag — but only after the user explicitly confirmed.

**`error_code: "cart_item_invalid_price"` (exit code 2):**
- A cart item has an invalid or missing price. Remove the item and re-add from a fresh search.

**"user wallet not found" (exit code 4):**
- The user's payment wallet is not provisioned. Usually means authentication is incomplete. Try logging out and back in.

**`error_code: "insufficient_balance"` (exit code 6):**
- The wallet does not have enough of the payment currency. Check `payment.chain` and `payment.currency` from `shop:cart view` to tell the user exactly what's needed. Use the **`wallet-send`** skill to check balance.

**`error_code: "payment_cap_exceeded"` (exit code 6):**
- The cart total exceeds the system's per-transaction cap. Try splitting the order into smaller purchases.

**`error_code: "merchant_not_allowed"` (exit code 6):**
- The merchant URL is not allowlisted for payments. This is an infrastructure issue — contact support.

**"Invalid product locator" (from checkout):**
- The `external_identifier` in the cart is invalid. Clear the cart and re-add items from a fresh search.

**Service temporarily unavailable (exit code 1):**
- The payment service is paused or temporarily unavailable (`"treasury relay is paused"`, `"too many undercollected payments"`). Wait a few minutes and retry.

**Timeout errors (exit code 1):**
- The payment provider can be slow in staging. Retry after 30 seconds. If persistent, try again later.

---

## Input Validation Checklist

Before running any command, verify:

1. **Search query (`--query`):** Non-empty string. If the user says "buy something" without specifics, ask what they're looking for.
2. **Provider (`--provider`):** Always pass through from search results or cart view. Never hardcode or guess.
3. **External ID (`--external-id`):** Always pass through from search results or cart view. Never invent or guess IDs. If the user says "add this" without specifying, ask which item number.
4. **Shipping fields:** Check `shop:shipping view` before checkout. All fields in `missing` must be filled.
5. **Checkout confirmation:** Must have explicit user approval. Never assume.
6. **Order ID (`--order-id`):** Must come from a previous checkout response.

---

## Cross-Skill References

### Prerequisites (before this skill)

- **Authentication:** User must be logged in. Use the **`authenticate-user`** skill.
- **Agent registration:** Agent must be registered. Use `agent:register` from the **`request-session`** skill.
- **Spending session (checkout only):** Use the **`request-session`** skill to create a session before checkout.
- **Wallet balance:** To check if the wallet has enough funds for checkout, use the **`wallet-send`** skill (`wallet balance`).
- **Diagnostics:** To inspect agent registration and sessions, use the **`manage-agents`** skill.

### After Completion (what to do next)

- **After successful checkout:** Suggest the user can track their order with `kpass shop:order status` or check delivery with `kpass shop:order delivery`. Mention that `activity` shows this purchase in their transaction history.
- **After adding items to cart:** If the user's task is complete (e.g., "add to cart only"), stop. Otherwise, guide toward shipping and checkout.
- **After order status check:** If the user seems done, mention that `activity` provides a full spending overview.
