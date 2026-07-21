# Phase 2 — GCP deployment patterns

How to deploy detected components into the tenant with `gcloud`, authenticated
by the minted deployer key. Everything here runs **locally**; Kite is not
involved. All values in `<…>` come from `kpass cloud project deploy-info`.

Deployment is open-ended — treat these as composable patterns, not a fixed
script. Inspect the repo first, decide the component set (see the decision tree
in `SKILL.md`), then apply the matching patterns in dependency order.

---

## 0. Isolated, authenticated gcloud session

Always use a dedicated `CLOUDSDK_CONFIG` so the deployer-SA login never disturbs
the user's normal gcloud account. Re-export it before every command (or in each
shell):

```bash
export CLOUDSDK_CONFIG="$(pwd)/.kite-passport/cloud/<id>/gcloud"
gcloud auth activate-service-account --key-file="<deployer_key_path>"
gcloud config set project "<gcp_project_id>"
gcloud config list account --format='value(core.account)'   # must be deployer@<pid>...
```

Confirm you're acting as the deployer SA before creating anything.

## Capability check (do this before assuming a component is possible)

The deployer SA can only do what the tenant was provisioned with. A freshly
provisioned tenant should already have the needed APIs enabled and roles granted
(via the broker's provisioning profile). To verify what's available:

```bash
gcloud services list --enabled --project <pid> | grep -E "run|cloudbuild|artifactregistry|sqladmin"
gcloud projects get-iam-policy <pid> --flatten="bindings[].members" \
  --filter="bindings.members:<deployer_sa_email>" \
  --format="value(bindings.role)"
```

If a needed API/role is missing (e.g. `sqladmin` / `roles/cloudsql.admin` for
Cloud SQL), **stop and report it**: the tenant must be re-provisioned with that
capability, or an owner must grant it. Do not attempt to enable APIs / grant
roles as the deployer SA — it normally lacks permission, and silently widening a
tenant's surface is not this skill's job.

`<deployer_sa_email>` above is the exact value from `deploy-info`'s
`deployer_sa_email` field — do not guess it from a naming convention (e.g.
`deployer@<pid>.iam.gserviceaccount.com`); the service-account email format is
an implementation detail of the broker, not a fixed pattern.

---

## A. Cloud Run service (always — the compute tier)

Two build paths. Prefer `--source` (no local docker); use the image path when
you need a specific platform build or local control.

**From source (Cloud Build in the tenant):**

```bash
gcloud run deploy <service> \
  --region <region> --project <pid> \
  --source . \
  --port <container-port> \
  --service-account "<runtime_sa_email>" \
  [--allow-unauthenticated] \
  [--set-env-vars "K1=V1,K2=V2"] \
  [--add-cloudsql-instances "<conn>"]
```

**From a locally built image (needs docker buildx; amd64 for Cloud Run):**

```bash
gcloud auth configure-docker <region>-docker.pkg.dev --quiet
docker buildx build --platform linux/amd64 -t "<artifact_registry>/<name>:v1" --push .
gcloud run deploy <service> --region <region> --project <pid> \
  --image "<artifact_registry>/<name>:v1" \
  --port <port> --service-account "<runtime_sa_email>" [flags as above]
```

Notes:
- `<artifact_registry>` is the **full repo path** from `deploy-info` —
  `<region>-docker.pkg.dev/<pid>/apps` (the broker creates the `apps` repo). So an
  image ref is `<artifact_registry>/<image>:<tag>`, e.g.
  `us-central1-docker.pkg.dev/<pid>/apps/notes-api:v1`. No need to look up the repo
  name separately — `deploy-info` already returns it.
- Do **not** set a `PORT` env var — Cloud Run injects it from `--port`.
- `--allow-unauthenticated` only for public endpoints; omit for internal.
- Capture the URL: `gcloud run services describe <service> --region <region>
  --project <pid> --format='value(status.url)'`.

## B. Cloud SQL (when the app needs a managed Postgres/MySQL)

Confirm cost with the user first (bills hourly while it exists). Create as the
deployer SA (needs `roles/cloudsql.admin`):

```bash
INSTANCE=<app>-pg ; CONN="<pid>:<region>:$INSTANCE"
DBNAME=app ; DBUSER=app ; DBPASS="$(openssl rand -hex 16)"   # don't log it

gcloud sql instances create "$INSTANCE" --project <pid> --region <region> \
  --database-version=POSTGRES_16 --edition=ENTERPRISE --tier=db-f1-micro \
  --storage-size=10 --availability-type=zonal --no-backup   # blocks until RUNNABLE (~5-10 min)
gcloud sql databases create "$DBNAME" --instance "$INSTANCE" --project <pid>
gcloud sql users create "$DBUSER" --instance "$INSTANCE" --project <pid> --password "$DBPASS"
```

`$DBPASS` is carried into the backend's `DATABASE_URL` env var below (that's where
it "lives"), so it isn't lost — but it's plaintext in the service config. For
production, move it out of `--set-env-vars` into Secret Manager. Note
`--set-secrets` injects a secret's value into an env var **verbatim** — it does
NOT substitute `$DBPASS` into a `DATABASE_URL` template — so pick one:

- **Store the whole DSN as one secret** and inject it directly:
  `--set-secrets DATABASE_URL=db-url:latest` (the secret's value is the full
  `postgresql+asyncpg://…` string). Simplest; the app reads `DATABASE_URL` unchanged.
- **Store only the password** and assemble at runtime:
  `--set-secrets DB_PASSWORD=db-pass:latest`, then have the app build
  `DATABASE_URL` from `DB_USER`/`DB_PASSWORD`/`DB_NAME`/socket at startup.

**MySQL:** for a MySQL app, set `--database-version=MYSQL_8_0` and use a MySQL
`DATABASE_URL` (e.g. `mysql+pymysql://$DBUSER:$DBPASS@/$DBNAME?unix_socket=/cloudsql/$CONN`)
instead of the Postgres `asyncpg` form below.

Cloud Run connects over the built-in Cloud SQL **Unix socket** (no public IP /
authorized networks). The runtime SA needs `roles/cloudsql.client`. Wire it on
the service deploy:

```bash
gcloud run deploy <backend> ... \
  --add-cloudsql-instances "$CONN" \
  --set-env-vars "DATABASE_URL=postgresql+asyncpg://$DBUSER:$DBPASS@/$DBNAME?host=/cloudsql/$CONN"
```

Adjust the `DATABASE_URL` scheme to the app's driver (`asyncpg`, `psycopg`,
`pg`, etc.); the socket form is `@/<db>?host=/cloudsql/<conn>`.

## C. Environment / config

- Plain config → `--set-env-vars "K=V,..."` (or `--update-env-vars` to change
  without a rebuild).
- Secrets → prefer Secret Manager + `--set-secrets` over plaintext env (if the
  tenant has `secretmanager` enabled); otherwise env vars as a stopgap.

## D. Multi-service ordering (e.g. frontend + backend)

1. Deploy the **backend** first; capture its URL.
2. If the **frontend bakes the API URL at build time** (`VITE_API_URL`,
   `NEXT_PUBLIC_API_URL`, `REACT_APP_*`), build it with that URL as a build-arg,
   then deploy:
   ```bash
   docker buildx build --platform linux/amd64 \
     --build-arg VITE_API_URL="<backend_url>" -t "<ar>/web:v1" --push .
   gcloud run deploy web --region <region> --project <pid> --image "<ar>/web:v1" \
     --port 8080 --service-account "<runtime_sa_email>" --allow-unauthenticated
   ```
3. **Tighten CORS** on the backend to the frontend origin (no rebuild):
   ```bash
   gcloud run services update <backend> --region <region> --project <pid> \
     --update-env-vars "CORS_ORIGINS=<frontend_url>"
   ```

## E. Smoke test

```bash
curl -s "<backend_url>/healthz"     # or the app's health route
curl -s "<backend_url>/readyz"      # readiness (DB reachable) if present
# open <frontend_url> in a browser for the full path
```

## F. Teardown (stop billing)

Cloud SQL bills while it exists — tear down when done. (Full tenant teardown,
including the project itself, is `kpass cloud project delete --yes`.)

```bash
gcloud run services delete <web> --region <region> --project <pid> --quiet
gcloud run services delete <backend> --region <region> --project <pid> --quiet
gcloud sql instances delete "$INSTANCE" --project <pid> --quiet
```

## Component → pattern map

| Detected | Pattern |
|---|---|
| One web service / Dockerfile | A (single Cloud Run) |
| Multiple app services | A ×N + D (ordering) |
| Postgres/MySQL dependency | B (Cloud SQL) + runtime `cloudsql.client` |
| Build-time API URL in a frontend | D step 2 (build-arg, order) |
| Cross-origin frontend↔backend | D step 3 (CORS) |
| Secrets | C (Secret Manager) |
| Redis/queue/other | out of the simple path — confirm scope, check capability first |
