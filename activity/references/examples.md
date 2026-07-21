# Activity — Worked Examples

End-to-end walkthroughs for the `activity` skill. Per-command syntax, arguments, and JSON shapes live in `commands.md`; the mandatory display card formats live in SKILL.md.

---

## Complete Worked Example: View All Recent Activity

**Context:** The user asks "Show me my recent activity."

**Step 1:** Verify authentication.
```bash
kpass me --output json
```
Output:
```json
{
  "user_id": "user_789xyz",
  "email": "user@example.com",
  "_version": "1",
  "status": "success",
  "hint": "Logged in as user@example.com.",
  "next_command": ""
}
```

**Step 2:** Fetch activity.
```bash
kpass activity --output json
```
Output:
```json
{
  "events": [
    {
      "id": "activity_abc123",
      "kind": "shopping_checkout",
      "status": "completed",
      "title": "Shopping checkout -- 2 items",
      "details": {
        "transaction": {
          "direction": "debit",
          "chain_name": "base",
          "asset_symbol": "USDC",
          "amount_raw": "124900000",
          "decimals": 6,
          "tx_hash": "0xabc123...",
          "shopping": {
            "order_id": "order_abc123",
            "item_count": 2,
            "item_titles": ["Wireless Mouse", "USB-C Hub"],
            "total_amount_display": "$12.49",
            "provider": "amazon"
          }
        }
      },
      "occurred_at": "2026-03-18T14:30:00Z"
    },
    {
      "id": "activity_def456",
      "kind": "wallet_transfer",
      "status": "completed",
      "title": "Transfer to external wallet",
      "details": {
        "transaction": {
          "direction": "debit",
          "asset_symbol": "USDC",
          "amount_raw": "5000000",
          "decimals": 6,
          "tx_hash": "0xdef456..."
        }
      },
      "occurred_at": "2026-03-17T10:00:00Z"
    }
  ],
  "total": 2,
  "limit": 20,
  "offset": 0,
  "_version": "1",
  "status": "success",
  "hint": "Found 2 activity event(s) (total: 2).",
  "next_command": ""
}
```

**Step 3:** Present to the user:

> **Shopping checkout -- 2 items** -- completed
> Kind: shopping_checkout | Mar 18, 2026 2:30 PM UTC
> Items: 2 (Wireless Mouse, USB-C Hub)
> Total: $12.49 | Order: order_abc123
> Tx: 0xabc123...
>
> **Transfer to external wallet** -- completed
> Kind: wallet_transfer | Mar 17, 2026 10:00 AM UTC
> Amount: 5.00 USDC
> Tx: 0xdef456...

---

## Complete Worked Example: Filter by Shopping Checkouts

**Context:** The user asks "Show me my shopping purchases."

```bash
kpass activity --kind shopping_checkout --output json
```
Output:
```json
{
  "events": [
    {
      "id": "activity_abc123",
      "kind": "shopping_checkout",
      "status": "completed",
      "title": "Shopping checkout -- 2 items",
      "details": {
        "transaction": {
          "tx_hash": "0xabc123...",
          "shopping": {
            "order_id": "order_abc123",
            "item_count": 2,
            "item_titles": ["Wireless Mouse", "USB-C Hub"],
            "total_amount_display": "$12.49",
            "provider": "amazon"
          }
        }
      },
      "occurred_at": "2026-03-18T14:30:00Z"
    }
  ],
  "total": 1,
  "limit": 20,
  "offset": 0,
  "_version": "1",
  "status": "success",
  "hint": "Found 1 activity event(s) (total: 1).",
  "next_command": ""
}
```

Present: "You have 1 shopping checkout: **2 items** (Wireless Mouse, USB-C Hub) for **$12.49** on Mar 18. Order ID: order_abc123."

---

## Complete Worked Example: Paginated Activity

**Context:** The user has many activity events.

**Page 1:**
```bash
kpass activity --limit 10 --offset 0 --output json
```

Check response: if `offset + events.length < total`, fetch next page:

**Page 2:**
```bash
kpass activity --limit 10 --offset 10 --output json
```

Continue until `offset + events.length >= total`.
