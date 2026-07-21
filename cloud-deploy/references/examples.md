# Worked examples

Two end-to-end walkthroughs. Both assume the user is logged in
(`authenticate-user`) and `gcloud` is installed. Replace `<…>` with values from
`kpass cloud project deploy-info`.

---

## Example 1 — single stateless service (e.g. a static site or one API)

Detected: one `Dockerfile`, listens on a port, no database, no env wiring.
Components: **one Cloud Run service**.

```bash
# --- Phase 1: provision ---
kpass cloud project create --name my-site --output json          # -> proj_abc (current)
kpass cloud project fund --amount 10 --output json               # show approval_url; user approves
kpass cloud project provision --wait --output json               # -> active
kpass cloud project credentials --project proj_abc --output json # mints key
# Capture deploy-info and extract the fields Phase 2 needs (data flow made explicit):
INFO=$(kpass cloud project deploy-info --project proj_abc --output json)
PID=$(echo "$INFO"        | jq -r .data.gcp_project_id)
REGION=$(echo "$INFO"     | jq -r .data.region)
RUNTIME_SA=$(echo "$INFO" | jq -r .data.runtime_sa_email)
KEY=$(echo "$INFO"        | jq -r .data.deployer_key_path)   # .kite-passport/cloud/proj_abc/deployer-key.json

# --- Phase 2: deploy (isolated gcloud session) ---
export CLOUDSDK_CONFIG="$(pwd)/.kite-passport/cloud/proj_abc/gcloud"
gcloud auth activate-service-account --key-file="$KEY"
gcloud config set project "$PID"

gcloud run deploy my-site \
  --region "$REGION" --source . --port 8080 \
  --service-account "$RUNTIME_SA" --allow-unauthenticated

gcloud run services describe my-site --region "$REGION" \
  --format='value(status.url)'   # -> the live URL
```

---

## Example 2 — 3-tier app (frontend + backend + Cloud SQL)

Detected: `docker-compose.yml` with `frontend`, `backend`, and a `db` (Postgres);
backend reads `DATABASE_URL` and `CORS_ORIGINS`; frontend bakes `VITE_API_URL`
at build time. Components: **2 Cloud Run services + 1 Cloud SQL instance**.

Phase 1 is identical (create → fund → provision → credentials → deploy-info).
Phase 2:

```bash
export CLOUDSDK_CONFIG="$(pwd)/.kite-passport/cloud/<id>/gcloud"
gcloud auth activate-service-account --key-file="<deployer_key_path>"
gcloud config set project "<gcp_project_id>"

# 0. Capability check — Cloud SQL must be available on the tenant
gcloud services list --enabled --project <pid> | grep sqladmin    # else: report, needs re-provision
gcloud projects get-iam-policy <pid> --flatten="bindings[].members" \
  --filter="bindings.members:deployer@<pid>.iam.gserviceaccount.com" \
  --format="value(bindings.role)" | grep cloudsql.admin

# 1. Cloud SQL (confirm cost with the user first — hourly billing)
INSTANCE=app-pg ; CONN="<pid>:<region>:$INSTANCE"
DBNAME=app ; DBUSER=app ; DBPASS="$(openssl rand -hex 16)"   # save; don't log
gcloud sql instances create "$INSTANCE" --project <pid> --region <region> \
  --database-version=POSTGRES_16 --edition=ENTERPRISE --tier=db-f1-micro \
  --storage-size=10 --availability-type=zonal --no-backup
  # `instances create` blocks until the instance is RUNNABLE (~5-10 min), so no
  # separate readiness poll is needed before the backend deploy below.
gcloud sql databases create "$DBNAME" --instance "$INSTANCE" --project <pid>
gcloud sql users create "$DBUSER" --instance "$INSTANCE" --project <pid> --password "$DBPASS"

# 2. Backend — Cloud SQL socket + migrations on startup.
#    CORS_ORIGINS=* is intentional and TEMPORARY: it lets the backend boot and be
#    smoke-tested before the frontend URL exists. It's tightened to the real
#    frontend origin in step 5 (an env update, no rebuild).
gcloud run deploy notes-api \
  --region <region> --project <pid> --source ./backend --port 8000 \
  --service-account "<runtime_sa_email>" \
  --add-cloudsql-instances "$CONN" \
  --set-env-vars "DATABASE_URL=postgresql+asyncpg://$DBUSER:$DBPASS@/$DBNAME?host=/cloudsql/$CONN,CORS_ORIGINS=*" \
  --allow-unauthenticated
BACKEND_URL=$(gcloud run services describe notes-api --region <region> --project <pid> --format='value(status.url)')

# 3. Smoke-test the backend (DB reachable). The first request warms the revision
#    + DB connection, so retry on 503 for ~30s (curl --retry treats 5xx as transient).
curl -s --retry 15 --retry-delay 2 "$BACKEND_URL/readyz"

# 4. Frontend — bake in the backend URL at build time, then deploy
gcloud auth configure-docker <region>-docker.pkg.dev --quiet
docker buildx build --platform linux/amd64 \
  --build-arg VITE_API_URL="$BACKEND_URL" \
  -t "<artifact_registry>/notes-web:v1" --push ./frontend
gcloud run deploy notes-web \
  --region <region> --project <pid> --image "<artifact_registry>/notes-web:v1" \
  --port 8080 --service-account "<runtime_sa_email>" --allow-unauthenticated
FRONTEND_URL=$(gcloud run services describe notes-web --region <region> --project <pid> --format='value(status.url)')

# 5. Tighten CORS to the frontend origin (no rebuild)
gcloud run services update notes-api --region <region> --project <pid> \
  --update-env-vars "CORS_ORIGINS=$FRONTEND_URL"

echo "Open: $FRONTEND_URL"
```

**Teardown when done** (Cloud SQL bills hourly):

```bash
gcloud run services delete notes-web  --region <region> --project <pid> --quiet
gcloud run services delete notes-api  --region <region> --project <pid> --quiet
gcloud sql instances delete app-pg --project <pid> --quiet
# or full teardown incl. the GCP project:
kpass cloud project delete --project <id> --yes --output json
```

### Why the ordering matters

- The frontend's API URL is compiled into its bundle, so the **backend must
  exist first** to know its URL.
- CORS starts permissive so the backend boots, then is **tightened to the real
  frontend origin** once it's known — an env update, no rebuild.
- The backend reaches Cloud SQL over the Unix socket (`/cloudsql/<conn>`), which
  is why `--add-cloudsql-instances` + the socket-form `DATABASE_URL` + the
  runtime SA's `cloudsql.client` role must all line up.
