---
name: cloud-deploy
description: >-
  Deploy a local project to its own Google Cloud (Cloud Run + friends) using
  Kite's `kpass cloud` feature. Proactively invoke when the user wants to
  "deploy to the cloud / GCP / Cloud Run", "ship this app", "host my backend",
  or "get my project running in Kite cloud". Provisions a per-customer GCP
  project via kpass (create -> fund -> provision -> credentials -> deploy-info),
  then figures out which GCP components the project needs (Cloud Run services,
  Cloud SQL, env, ports) and deploys them with gcloud using the minted key.
user-invocable: true
allowed-tools:
  - "Bash(kpass cloud *)"
  - "Bash(gcloud *)"
  - "Bash(docker *)"
  - "Read"
  - "Grep"
  - "Glob"
---

# Cloud Deploy

Take a project the user built locally and stand it up in its own Google Cloud
project, end to end. This skill spans **two layers**:

1. **Provision (kpass cloud)** — create a per-customer GCP tenant, fund it,
   provision it, mint a deployer key, and read the deploy facts. Only Kite can
   do this; `kpass` is the only interface.
2. **Deploy (gcloud)** — inspect the local project, decide which GCP components
   it needs, and deploy them with `gcloud`, authenticated by the minted key.
   This is open-ended reasoning, not a fixed template — you adapt to the app.

Kite is never in the deploy path: provisioning hands you a credentialed,
isolated GCP project; the actual build/deploy runs locally with `gcloud`.

## When to Use This Skill

- The user wants to deploy / host / ship a local project to the cloud, GCP, or
  Cloud Run.
- The user has a repo (Dockerfile, `docker-compose.yml`, a web service, an API,
  a DB) and asks to get it running in Kite cloud.
- The user references a "tenant", "cloud project", or `kite-tnt-…` project and
  wants to deploy into it.

## When NOT to Use This Skill

- Pure wallet/payment/session tasks → `wallet-send`, `request-session`,
  `x402-execute`.
- The user only wants to *provision* a cloud project (no deploy) — you can still
  use the Phase 1 commands here, but don't run the gcloud deploy phase.

## Prerequisites

- **Logged in.** All `kpass cloud` commands need the user's JWT. If a command
  returns exit code 3 / "Not logged in", use the **`authenticate-user`** skill
  first.
- **`gcloud` installed locally** for the deploy phase. If absent, deploy with
  `--print-only`-style guidance is impossible — tell the user to install the
  Google Cloud SDK, or stop after provisioning and hand them the facts.
- **`docker` (buildx)** only if you build images locally (the `--image` path);
  the `--source` path builds in the tenant's Cloud Build and needs no local
  docker.
- Always pass `--output json` to `kpass` and parse the envelope
  (`status`/`data`/`error`/`error_code`).

## The End-to-End Flow

### Phase 1 — Provision the GCP tenant (kpass cloud)

Run these in order. Full argument tables, JSON shapes, and error codes are in
`@references/kpass-cloud.md`.

1. **Create (or select) the project.** `kpass cloud project create --name <n>`
   (region optional; server defaults and returns it). It becomes the current
   project. To target an existing one: `kpass cloud project use <id>`.
2. **Fund it.** `kpass cloud project fund --amount <USD>` prints a passkey
   approval URL. Funding is a **browser step** (passkey, gasless) — show the URL
   to the user verbatim and wait for them to confirm they approved. Do not poll
   or fake progress.
3. **Provision.** `kpass cloud project provision --wait`. Gated on balance ≥ the
   minimum; on `INSUFFICIENT_CREDIT` (402) the funding hasn't settled — tell the
   user to approve, then retry. `--wait` polls until `active` or `error`.
4. **Mint the deployer key.** `kpass cloud project credentials --project <id>` —
   returned once, stored at `.kite-passport/cloud/<id>/deployer-key.json`. Don't
   re-run needlessly; re-minting **rotates** and breaks prior keys.
5. **Read the deploy facts.** `kpass cloud project deploy-info --project <id>
   --output json` → `gcp_project_id`, `region`, `artifact_registry`,
   `deployer_sa_email`, `runtime_sa_email`, and `deployer_key_path`. **These are
   the only inputs the deploy phase needs from Kite.**

### Phase 2 — Decide what to deploy, then deploy it (gcloud)

**First, inspect the project** (Read/Glob/Grep) to infer its architecture — do
not assume. Then map findings to GCP components and deploy. Full command
patterns per component are in `@references/gcp-deploy.md`; worked end-to-end
examples in `@references/examples.md`.

#### Component-detection decision tree

| Signal in the repo | Component to deploy | Key gcloud bits |
|---|---|---|
| A `Dockerfile` or buildable source, listens on a port | **Cloud Run service** | `gcloud run deploy --source .` (or build+push then `--image`), `--port`, `--service-account <runtime_sa>` |
| `docker-compose.yml` with multiple app services | **Multiple Cloud Run services** (one deploy each) | Deploy backend first; frontend after (it may need the backend URL) |
| A `db`/`postgres`/`mysql` service in compose, or `DATABASE_URL`, `asyncpg`, `pg`, `prisma`, `sequelize`, an ORM, or migrations | **Cloud SQL instance** | `gcloud sql instances create`, DB + user, `--add-cloudsql-instances`, socket `DATABASE_URL` |
| Frontend that bakes an API URL at build time (`VITE_API_URL`, `NEXT_PUBLIC_*`, `REACT_APP_*`) | Build-time **build-arg**, deploy order matters | Deploy backend → get its URL → build frontend with that URL → deploy frontend |
| App reads config from env (`CORS_ORIGINS`, secrets, feature flags) | `--set-env-vars` (or Secret Manager for secrets) | Tighten CORS to the frontend URL after both are up |
| Public web endpoint expected | `--allow-unauthenticated` | Omit for internal-only services |
| Caching/queue (`redis`, `REDIS_URL`, pub/sub) | Memorystore / Pub/Sub | Out of the simple path — confirm scope with the user |

If you can't infer a component confidently, **ask the user** rather than guess
(especially anything that costs money or stores data).

#### Authenticate gcloud with the minted key (isolated session)

Use an **isolated gcloud config** so you never clobber the user's default
gcloud login:

```bash
export CLOUDSDK_CONFIG="$(pwd)/.kite-passport/cloud/<id>/gcloud"
gcloud auth activate-service-account --key-file="<deployer_key_path>"
gcloud config set project "<gcp_project_id>"
```

Then deploy per the detected components (see `@references/gcp-deploy.md`).

#### Capability gaps (important)

The deployer SA can only do what the tenant was provisioned with. If a step
fails with `PERMISSION_DENIED` or `FailedPrecondition` (e.g. creating Cloud SQL
when `sqladmin` isn't enabled or `cloudsql.admin` isn't granted), the tenant
lacks that capability. **Do not silently work around it** — report exactly which
API/role is missing and that the tenant needs those granted (an owner-level /
re-provision action). See the capability notes in `@references/gcp-deploy.md`.

#### Cost + safety

- **Confirm before creating cost-incurring resources** (Cloud SQL bills hourly
  while it exists). State what will be created and the rough cost shape.
- Generate a strong DB password locally; never hardcode or echo secrets into
  logs you keep.
- Offer the teardown commands when done (`@references/gcp-deploy.md`).

## Minimal Example — single stateless Cloud Run service

```bash
# Phase 1 (after `authenticate-user`)
kpass cloud project create --name my-api --output json          # -> proj_abc, becomes current
kpass cloud project fund --amount 10 --output json              # -> open approval_url, user approves
kpass cloud project provision --wait --output json              # -> state: active
kpass cloud project credentials --project proj_abc --output json
INFO=$(kpass cloud project deploy-info --project proj_abc --output json)
# parse INFO.data: gcp_project_id, region, runtime_sa_email, deployer_key_path

# Phase 2 — one Cloud Run service from source (Cloud Build; no local docker)
export CLOUDSDK_CONFIG="$(pwd)/.kite-passport/cloud/proj_abc/gcloud"
gcloud auth activate-service-account --key-file="<deployer_key_path>"
gcloud config set project "<gcp_project_id>"
gcloud run deploy my-api \
  --region "<region>" --source . --port 8080 \
  --service-account "<runtime_sa_email>" --allow-unauthenticated
```

For a 3-tier app (frontend + backend + Cloud SQL), follow the full pattern in
`@references/examples.md` — it covers ordering, the Cloud SQL socket
`DATABASE_URL`, build-time frontend API URL, and CORS tightening.

## Error Matrix

| Symptom | Meaning | Action |
|---|---|---|
| kpass exit 3 / "Not logged in" | No JWT | Run `authenticate-user`, retry |
| `INSUFFICIENT_CREDIT` (402) on provision | Funding not settled / below min | Have user approve `fund`, retry `provision` |
| provision `state: error`, `error_message` mentions billing/quota | Tenant-side GCP/billing issue | Surface `error_message`; this is an infra/quota problem, not fixable in the deploy phase |
| `deploy-info` shows "not minted" / no key | Key never minted | Run `kpass cloud project credentials` first |
| gcloud `PERMISSION_DENIED` / `FailedPrecondition` | Tenant lacks that API/role | Report the missing API/role; needs re-provision/owner grant |
| gcloud not found | SDK not installed | Ask user to install Google Cloud SDK |
| Cloud Run `--source` build fails on permissions | Cloud Build/AR roles missing | Fall back to local `docker build`+`--image`, or report the missing role |

## References

- `@references/kpass-cloud.md` — Phase 1 kpass cloud commands: argument tables, JSON shapes, error codes.
- `@references/gcp-deploy.md` — Phase 2 GCP deployment patterns per component (auth, Cloud Run, Cloud SQL, env, multi-service, CORS, teardown, capability notes).
- `@references/examples.md` — worked examples: single service, and a 3-tier app with Cloud SQL.
