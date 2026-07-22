# Kite Discovery — Command Reference

Full per-command reference for the `kite-discovery` skill. Read this when constructing a `ksearch` command, validating flags, or interpreting an error. SKILL.md contains trigger logic and decision flow; this file contains command-level detail.

## `services list` -- Search the Service Catalog

Lists services from the catalog. Supports free-text search and structured filters.

```bash
ksearch services list --output json
```

Full form with optional filters:

```bash
ksearch services list \
  --query <QUERY> \
  --tag <TAG> \
  --asset <ASSET> \
  --payment-approach <APPROACH> \
  --limit <N> \
  --cursor <CURSOR> \
  --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Search query | `--query` | No | User request or inferred task keyword | Non-empty string |
| Tag filter | `--tag` | No | User request or known category | String label. Maps to backend category filtering. |
| Asset filter | `--asset` | No | User preference (e.g., `USDC`) | Asset symbol string |
| Payment approach | `--payment-approach` | No | Only if user requests a specific payment model | `x402` or `tempo_http` |
| Limit | `--limit` | No | Default `100` | Positive integer, max 100 |
| Cursor | `--cursor` | No | From prior `services list` response `next_cursor` field | Opaque pagination token string |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "services": [
    {
      "service_id": "stable-search",
      "name": "Stable Search",
      "summary": "Search the public web and return structured results.",
      "base_url": "https://search.example.com",
      "categories": ["research"],
      "tags": ["search", "web", "research"],
      "payment_approach": "x402",
      "assets": ["USDC"],
      "starting_price": {
        "amount": "0.01",
        "asset": "USDC",
        "unit": "request"
      }
    }
  ],
  "count": 1,
  "total": 42,
  "limit": 100,
  "cursor": "",
  "next_cursor": "eyJsYXN0X2lkIjoiNDIifQ",
  "_version": "1",
  "status": "success",
  "hint": "Found 1 service(s) in this page (42 total).",
  "next_command": ""
}
```

**Key fields:**
- `services` -- Array of service summaries.
- `services[].service_id` -- Stable identifier to use with `services get`.
- `services[].base_url` -- Root service URL for Passport handoff.
- `services[].payment_approach` -- Payment model (`x402` or `tempo_http`). Both are Passport-settled rails handled transparently by `request-session`/`x402-execute` at execute time -- not a per-service decision the agent needs to make.
- `services[].starting_price` -- Cheapest known endpoint price. Contains `amount`, `asset`, and `unit`.
- `count` -- Number of services in this page.
- `total` -- Total number of matching services across all pages.
- `next_cursor` -- Opaque token for the next page. Empty string when no more results.

### What to Do After This Command

1. Show the display card below.
2. If the user asked for the "best" service, rank by fit to task, then pricing clarity, then lower starting price.
3. If `next_cursor` is non-empty and the user wants more, rerun with `--cursor <next_cursor>`.
4. If no results (`count` is 0), suggest broadening the query or removing filters.

**MANDATORY -- After this command succeeds, you MUST display the following card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔎 Service Catalog -- {count} result(s)

{for each service, numbered:}
  {i}. {name}
     📝 {summary}
     💰 From {starting_price.amount} {starting_price.asset} / {starting_price.unit}
     🏷️  {tags}
     🔗 {base_url}

{if next_cursor is non-empty:}
More results available. Say "show more" to continue.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{count}` | From JSON response field `count` |
| `{name}` | From `services[i].name` |
| `{summary}` | From `services[i].summary` |
| `{starting_price.amount}` | From `services[i].starting_price.amount` |
| `{starting_price.asset}` | From `services[i].starting_price.asset` |
| `{starting_price.unit}` | From `services[i].starting_price.unit` |
| `{tags}` | From `services[i].tags`, joined with commas |
| `{base_url}` | From `services[i].base_url` |

**You MUST always display this card after a successful response. No exceptions.**

---

## `services get` -- Inspect One Service

Returns detailed metadata for one service, including featured endpoints and payment requirements.

```bash
ksearch services get --service-id <SERVICE_ID> --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Service ID | `--service-id` | Yes (one of these two) | From `services list` output `service_id` field | String identifier |
| Service host ID | `--service-host-id` | Yes (one of these two) | Alternative form, same identifier family | String identifier |
| Output format | `--output json` | Yes | Always pass | Literal value `json` |

Prefer `--service-id`. The CLI also accepts `--service-host-id` but use `--service-id` consistently.

### Success Output (exit code 0)

```json
{
  "service": {
    "service_id": "stable-search",
    "name": "Stable Search",
    "summary": "Search the public web and return structured results.",
    "base_url": "https://search.example.com",
    "tags": ["search", "web", "research"],
    "payment_approach": "x402",
    "assets": ["USDC"],
    "starting_price": {
      "amount": "0.01",
      "asset": "USDC",
      "unit": "request"
    },
    "auth_requirements": {
      "mode": "payment_only"
    },
    "featured_endpoints": [
      {
        "method": "POST",
        "path": "/v1/search",
        "summary": "Run a keyword search.",
        "example_request": {
          "body": {"query": "latest AI news", "numResults": 3},
          "headers": {}
        },
        "probe_status": "works",
        "last_verified_at": "2026-07-13T15:04:05Z",
        "pitfalls": [
          {"http_status": 403, "tag": "SOURCE_NOT_AVAILABLE", "count_30d": 12, "last_seen": "2026-07-12T04:04:14Z"}
        ],
        "observed_params": {
          "last_seen": "2026-07-13T15:04:05Z",
          "params": [
            {"key": "query", "count_30d": 480, "share": 1.0},
            {"key": "numResults", "count_30d": 300, "share": 0.63}
          ]
        }
      },
      {
        "method": "POST",
        "path": "/v1/extract",
        "summary": "Extract structured facts from a URL."
      }
    ]
  },
  "_version": "1",
  "status": "success",
  "hint": "Loaded service metadata for stable-search.",
  "next_command": ""
}
```

**Key fields:**
- `service.service_id` -- Stable identifier.
- `service.base_url` -- Root service URL for Passport handoff.
- `service.auth_requirements.mode` -- Currently `payment_only`.
- `service.featured_endpoints[]` -- Up to 5 candidate endpoints, ordered by price (cheapest first). Each has `method`, `path`, and `summary`, plus five optional verification fields (omitted when unset):
  - `example_request` -- A minimal request (`body` + optional **non-secret** `headers` -- the catalog never publishes `Authorization`, `Cookie`, or API-key headers) that provably succeeded against this endpoint. **This is the correct starting point for building the paid request** -- pass it to `x402-execute` and change only what the task requires. Do not invent extra parameters from knowledge of the merchant's public API: on MPP charge endpoints, payment settles before the merchant validates, so a rejected request still costs money.
  - `probe_status` -- `works` / `broken` / `unknown`, set by daily paid verification probes. `broken` means the endpoint failed its most recent probe: keep it listed, but prefer an alternative provider.
  - `last_verified_at` -- When the endpoint last passed a probe (RFC 3339).
  - `pitfalls` -- Recent known failure tags aggregated from real payments (e.g. `{"http_status": 403, "tag": "SOURCE_NOT_AVAILABLE", "count_30d": 12}`). Surface these before executing, and check them before any paid retry.
  - `observed_params` -- Request-body **key names** (values never recorded) seen in real, successfully-paid calls, each with a `count_30d` and a `share` in `(0,1]` (fraction of successful calls that included it). Answers what `example_request` cannot: *is this extra parameter legal here?* A key at high share is proven safe to send; **a key that never appears is a paid gamble** -- on MPP charge endpoints payment settles before the merchant validates, so an invented parameter still costs money if rejected.
- `service.starting_price` -- Cheapest known price across all endpoints.

### What to Do After This Command

1. Show the display card below.
2. Explain whether the service matches the user's task.
3. Call out the payment approach, supported asset(s), starting price, and one or two relevant endpoints.
4. If an endpoint's `probe_status` is `broken`, or its `pitfalls` are relevant to the user's task, say so before recommending execution.
5. If the user wants to proceed, hand off to Passport skills with this context:
   - Service name and base URL
   - Chosen endpoint method and path
   - The endpoint's `example_request`, `pitfalls`, and `observed_params`, when present (x402-execute starts from the example body and treats observed params as the safe set to add beyond it)
   - Payment approach and asset(s)
   - Pricing context

Then use **`request-session`** to prepare approval and **`x402-execute`** to perform the paid call.

**MANDATORY -- After this command succeeds, you MUST display the following card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Service Details

📛 Name:      {name}
🆔 ID:        {service_id}
📝 Summary:   {summary}
🔗 Base URL:  {base_url}
💰 From:      {starting_price.amount} {starting_price.asset} / {starting_price.unit}
🏷️  Tags:      {tags}
🔒 Payment:   {payment_approach}
💳 Assets:    {assets}

📡 Featured Endpoints:
{for each endpoint:}
  {method} {path} -- {summary}

Ready to hand off into Passport approval and execution.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{name}` | From `service.name` |
| `{service_id}` | From `service.service_id` |
| `{summary}` | From `service.summary` |
| `{base_url}` | From `service.base_url` |
| `{starting_price.amount}` | From `service.starting_price.amount` |
| `{starting_price.asset}` | From `service.starting_price.asset` |
| `{starting_price.unit}` | From `service.starting_price.unit` |
| `{tags}` | From `service.tags`, joined with commas |
| `{payment_approach}` | From `service.payment_approach` |
| `{assets}` | From `service.assets`, joined with commas |
| `{method}` | From `service.featured_endpoints[].method` |
| `{path}` | From `service.featured_endpoints[].path` |

**You MUST always display this card after a successful response. No exceptions.**

---

## `export markdown` -- Export Catalog as Local Snapshot

Exports the discovery catalog as markdown files for local workspace search and LLM-assisted exploration.

```bash
ksearch export markdown --output-dir ./.kite/catalog
```

Full form with options:

```bash
ksearch export markdown \
  --output-dir <DIR> \
  --split <MODE> \
  --include-curated
```

Single-file variant:

```bash
ksearch export markdown --single-file ./.kite/catalog/catalog.md
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Output directory | `--output-dir` | No | Default `./.kite/catalog` | Path string |
| Single output file | `--single-file` | No | Use when a one-file catalog is preferred | File path |
| Split mode | `--split` | No | Default `both` | `both`, `single`, or `service-pages` |
| Include curated | `--include-curated` | No | Flag, only when curated entries are useful | Boolean flag |

**Split modes:**
- `both` (default) -- Writes `catalog.md` index AND individual service files in `services/` directory
- `single` -- Writes only `catalog.md` index file
- `service-pages` -- Writes only individual service files in `services/` directory

### Output Files

- `catalog.md` -- Index markdown with summary of all services
- `services/<service_id>.md` -- Individual service detail pages (with endpoint-level pricing)
- `manifest.json` -- Metadata about the export (generation time, service count, refresh hint)

### What to Do After This Command

1. Show the display card below.
2. Tell the user where the snapshot was written.
3. Mention that `manifest.json` includes the generation time and refresh suggestion.
4. Suggest refreshing the snapshot periodically (discovery data updates roughly hourly).

**When to prefer export over repeated `services get` calls:**
- Comparative pricing across many services (endpoint-level prices are clearer in per-service markdown pages)
- Category reviews or broad catalog exploration
- Pre-loading LLM workspace context for offline agents (Codex, Claude Code)

**MANDATORY -- After this command succeeds, you MUST display the following card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📄 Catalog Exported

📂 Location:   {output_location}
📑 Mode:       {split_mode}
📋 Manifest:   manifest.json

The catalog is ready for offline browsing or LLM workspace indexing.
Refresh periodically -- discovery data updates roughly hourly.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{output_location}` | The `--output-dir` value or `--single-file` path used |
| `{split_mode}` | The `--split` value used (default: `both`) |

When `--single-file` is used, `manifest.json` may not exist. Show `Manifest: N/A` in that case.

**You MUST always display this card after a successful export. No exceptions.**

---

## `health` -- Backend Connectivity Check

Quick diagnostic to verify the discovery backend is reachable.

```bash
ksearch health --output json
```

### Arguments

| Argument | Flag | Required | Source | Validation |
|----------|------|----------|--------|------------|
| Output format | `--output json` | No | Pass for machine-readable output | Literal value `json` |

### Success Output (exit code 0)

```json
{
  "version": "1",
  "status": "ok",
  "backend_url": "https://service-discovery.dev.gokite.ai",
  "backend_status": "ok",
  "response_time_ms": 42
}
```

**Key fields:**
- `status` -- `"ok"` when the backend is reachable.
- `backend_url` -- The URL that was checked.
- `backend_status` -- Backend-reported health status.
- `response_time_ms` -- Round-trip latency in milliseconds.

### What to Do After This Command

- If healthy, proceed with service queries.
- If unreachable, inform the user and suggest checking network connectivity or the `DISCOVERY_BASE_URL` env var.

**MANDATORY -- After this command succeeds, you MUST display the following card:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🏥 Discovery Health Check

✅ Backend:    {backend_url}
📡 Status:     {backend_status}
⏱️  Latency:    {response_time_ms}ms
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

| Placeholder | Source |
|---|---|
| `{backend_url}` | From JSON response field `backend_url` |
| `{backend_status}` | From JSON response field `backend_status` |
| `{response_time_ms}` | From JSON response field `response_time_ms` |

---
