# kpass cloud — Phase 1 command reference

Commands used to provision a GCP tenant and read its deploy facts. The cloud
feature is **live-only** (no sandbox). Always pass `--output json` and parse the
envelope: `{ "status": "...", "data": {...}, "error": "...", "error_code": "..." }`.

Project id resolution for every id-taking command: positional `[id]` →
`--project <id>` → the current project (set by `create`/`use`). When you've just
created a project it's already current, so `--project` is optional.

---

## `cloud project create` — make a draft project

```bash
kpass cloud project create --name <display-name> [--region <region>] [--budget <usd>] --output json
```

- Free and instant: a draft, no GCP resources, no charge. Becomes the current project.
- `--region` optional — the server defaults it (e.g. `us-central1`) and returns it.
- `--budget` optional — per-project GCP budget cap; server default otherwise.

`data`: `{ id, state: "draft", display_name, region, budget_usd, balance_usd }`.

## `cloud project list` / `status` — inspect

```bash
kpass cloud project list --output json
kpass cloud project status [<id>] [--wait] --output json
```

- `list`: all your projects (last-known values, no per-project broker refresh).
- `status`: one project, **broker-refreshed** (authoritative `state`/`balance`).
  `--wait` polls until a settled state (`active`, `error`, `paused`, `draft`,
  `deleted`). Use after `provision`.

`data`: `{ id, state, balance_usd, region, gcp_project_id, artifact_registry,
deployer_sa_email, runtime_sa_email, budget_usd, error_message }`.

States: `draft` → `provisioning` → `active` | `error`; plus `paused`, `deleted`.

## `cloud project fund` — add prepaid credit (browser passkey)

```bash
kpass cloud project fund [<id>] --amount <usd> --output json
```

- Funding settles **gaslessly via x402** and needs a **passkey**, which is a
  browser-only step. This prints an `approval_url` (status
  `human_action_required`) — **show it to the user verbatim** and wait for them
  to approve. There is no synchronous result; do not poll.
- After approval, the credit lands server-side. Verify with `status`, or just
  run `provision` (it errors cleanly until the credit settles).

`data`: `{ action: "approve_cloud_funding", project_id, amount_usd, approval_url }`.

## `cloud project provision` — create the GCP resources

```bash
kpass cloud project provision [<id>] [--wait] --output json
```

- Gated on `balance_usd ≥ min initial credit`. Below it → HTTP 402
  `error_code: INSUFFICIENT_CREDIT` (fund/approve first, then retry).
- Asynchronous at the broker; `--wait` polls until `active` or `error`.
- On `state: error`, read `error_message` (billing/quota/API failures surface here).

## `cloud project credentials` — mint the deployer key (once)

```bash
kpass cloud project credentials [<id>] [--rotate] [--out <path>] [--no-store] --output json
```

- Mints the deployer service-account key. The private key is returned **exactly
  once** and stored at `.kite-passport/cloud/<id>/deployer-key.json` (0600).
- **Re-minting rotates** — it disables the previous key. Mint once and reuse;
  don't call it per deploy.
- `--out <path>` also writes the JSON elsewhere; `--no-store` skips the local
  store (print/`--out` only).

`data`: `{ key_id, sa_email, stored_path }` (the key bytes are in the one-time
response; passport stores only the key id).

## `cloud project deploy-info` — the facts the deploy phase needs

```bash
kpass cloud project deploy-info [<id>] --output json
```

`data`:

| Field | Use |
|---|---|
| `gcp_project_id` | `gcloud config set project` / `--project` |
| `region` | `--region`; Artifact Registry host (`<region>-docker.pkg.dev`) |
| `artifact_registry` | image repo path, e.g. `<region>-docker.pkg.dev/<pid>/apps` — push images here |
| `deployer_sa_email` | the identity the key authenticates as (informational) |
| `runtime_sa_email` | pass to `gcloud run deploy --service-account` so the service runs as it; grant it resource roles (e.g. `cloudsql.client`) |
| `deployer_key_path` | local path to the minted key; `gcloud auth activate-service-account --key-file=<this>` |
| `deployer_key_present` | `false` ⇒ run `credentials` first |

When `deployer_key_present` is false the human output says "not minted" and
includes the exact `credentials` command to run — do that before deploying.

## Lifecycle

```bash
kpass cloud project pause   [<id>] --output json   # detach billing (keep resources)
kpass cloud project resume  [<id>] --output json
kpass cloud project delete  [<id>] --yes --output json   # offboard GCP + shred local key
```

`delete` requires `--yes` in all modes; it deletes the **entire GCP project**
(irreversible at Kite; GCP keeps it ~30 days restorable) and removes the local
key. Use `pause` to stop spend without destroying anything.

## Error codes (envelope `error_code`)

| code / signal | HTTP | meaning |
|---|---|---|
| (exit 3) "Not logged in" | 401 | no JWT → run `authenticate-user` |
| `INSUFFICIENT_CREDIT` | 402 | balance below min → fund/approve, retry provision |
| `NOT_FOUND` | 404 | unknown project / not yours |
| `ALREADY_PROVISIONED` | 409 | provision called on a non-draft project |
| `NOT_ACTIVE` | 409 | op needs an active project (e.g. credentials/deploy-info on a draft) |
| `REGION_NOT_ALLOWED` | 400 | region not in the allow-list |
| `INVALID_AMOUNT` | 400 | bad fund/top-up amount |
| `FUNDING_NOT_CONFIGURED` | 503 | funding not configured in this env |
