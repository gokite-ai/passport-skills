# Kite Discovery — Worked Examples

End-to-end walkthroughs for the `kite-discovery` skill. Per-command syntax lives in `commands.md`; the decision flow lives in `SKILL.md`. This file shows concrete agent transcripts for browse-then-inspect, pagination, and catalog export scenarios.

## Browse and Inspect a Service

**Context:** The user asks "find me a web search API."

**Step 1:** Search the catalog.
```bash
ksearch services list --query "web search" --output json
```
Output:
```json
{
  "services": [
    {
      "service_id": "stable-search",
      "name": "Stable Search",
      "summary": "Search the public web and return structured results.",
      "base_url": "https://search.example.com",
      "categories": ["research"],
      "tags": ["search", "web"],
      "payment_approach": "x402",
      "assets": ["USDC"],
      "starting_price": { "amount": "0.01", "asset": "USDC", "unit": "request" }
    },
    {
      "service_id": "deep-web-search",
      "name": "Deep Web Search",
      "summary": "Deep web crawling and structured extraction.",
      "base_url": "https://deepweb.example.com",
      "categories": ["research"],
      "tags": ["search", "crawl", "extract"],
      "payment_approach": "x402",
      "assets": ["USDC"],
      "starting_price": { "amount": "0.05", "asset": "USDC", "unit": "request" }
    }
  ],
  "count": 2,
  "total": 2,
  "limit": 100,
  "cursor": "",
  "next_cursor": "",
  "_version": "1",
  "status": "success",
  "hint": "Found 2 service(s) in this page (2 total).",
  "next_command": ""
}
```

Display the catalog card:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔎 Service Catalog -- 2 result(s)

  1. Stable Search
     📝 Search the public web and return structured results.
     💰 From 0.01 USDC / request
     🏷️  search, web
     🔗 https://search.example.com

  2. Deep Web Search
     📝 Deep web crawling and structured extraction.
     💰 From 0.05 USDC / request
     🏷️  search, crawl, extract
     🔗 https://deepweb.example.com
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Step 2:** User picks "Stable Search." Inspect it.
```bash
ksearch services get --service-id stable-search --output json
```
Output:
```json
{
  "service": {
    "service_id": "stable-search",
    "name": "Stable Search",
    "summary": "Search the public web and return structured results.",
    "base_url": "https://search.example.com",
    "tags": ["search", "web"],
    "payment_approach": "x402",
    "assets": ["USDC"],
    "starting_price": { "amount": "0.01", "asset": "USDC", "unit": "request" },
    "auth_requirements": { "mode": "payment_only" },
    "featured_endpoints": [
      { "method": "POST", "path": "/v1/search", "summary": "Run a keyword search." },
      { "method": "POST", "path": "/v1/extract", "summary": "Extract structured facts from a URL." }
    ]
  },
  "_version": "1",
  "status": "success",
  "hint": "Loaded service metadata for stable-search.",
  "next_command": ""
}
```

Display the details card:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Service Details

📛 Name:      Stable Search
🆔 ID:        stable-search
📝 Summary:   Search the public web and return structured results.
🔗 Base URL:  https://search.example.com
💰 From:      0.01 USDC / request
🏷️  Tags:      search, web
🔒 Payment:   x402
💳 Assets:    USDC

📡 Featured Endpoints:
  POST /v1/search -- Run a keyword search.
  POST /v1/extract -- Extract structured facts from a URL.

Ready to hand off into Passport approval and execution.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Step 3:** Hand off to Passport skills.

Tell the user: "Stable Search looks like a good fit. To use it, I'll set up a spending session. The search endpoint is `POST https://search.example.com/v1/search` at 0.01 USDC per request."

Then use the **`request-session`** skill to create a session with delegation targeting `search.example.com`, and **`x402-execute`** to make the paid call.

---

## Complete Worked Example: Paginated Catalog Browsing

**Context:** The user asks "show me all available services, 5 at a time."

**Step 1:** First page.
```bash
ksearch services list --limit 5 --output json
```
Output includes `"count": 5, "total": 42, "next_cursor": "svc_page2_token"`.

Display the catalog card. Note "More results available."

**Step 2:** User says "show more."
```bash
ksearch services list --limit 5 --cursor svc_page2_token --output json
```
Output includes `"count": 5, "total": 42, "next_cursor": "svc_page3_token"`.

Display the next catalog card. Continue until `next_cursor` is empty or the user is satisfied.

---

## Complete Worked Example: Export Catalog for LLM Workspace

**Context:** The user asks "export the service catalog so I can search it locally."

```bash
ksearch export markdown --output-dir ./.kite/catalog --split both
```

Display the export card:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📄 Catalog Exported

📂 Location:   ./.kite/catalog
📑 Mode:       both
📋 Manifest:   manifest.json

The catalog is ready for offline browsing or LLM workspace indexing.
Refresh periodically -- discovery data updates roughly hourly.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Tell the user: "The catalog is exported to `.kite/catalog/`. You can search `catalog.md` for an overview or browse individual service pages in `services/`."
