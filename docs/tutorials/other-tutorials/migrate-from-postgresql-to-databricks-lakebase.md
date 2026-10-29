---
description: Move an existing Aidbox database from self-hosted PostgreSQL to Databricks Lakebase with pg_dump and pg_restore, and switch Aidbox to Databricks OAuth authentication.
---

# Migrate from PostgreSQL to Databricks Lakebase

This tutorial moves an existing Aidbox database from a self-hosted PostgreSQL to a [Databricks Lakebase](https://docs.databricks.com/aws/en/oltp/) Autoscaling project. You copy the data with `pg_dump` and `pg_restore`, then point Aidbox at Lakebase with Databricks OAuth authentication. The Aidbox image, its settings and FHIR packages stay the same.

{% hint style="warning" %}
Aidbox 2608 and 2609 fail to start with `BOX_DB_AUTH_METHOD=databricks-autoscale` or `databricks-provisioned`: the main connection pool sends `BOX_DB_PASSWORD` instead of the OAuth token, and Lakebase rejects it with `Provided authentication token is not a valid JWT encoding`. Aidbox 2607 and earlier, and 2610 and later, work with Databricks authentication. If you run 2608 or 2609, move to 2610 or later before you switch to Lakebase.

The ClickHouse topic destination can't run its initial export under Databricks authentication: it passes the database password to ClickHouse, and that password is the `BOX_DB_PASSWORD` placeholder.
{% endhint %}

## Objectives

* Provision a Lakebase project and a service principal role that owns the Aidbox schema.
* Copy the Aidbox database to Lakebase and verify the copy.
* Run Aidbox against Lakebase with OAuth tokens that Aidbox refreshes on its own.

## Before you begin

* A Databricks workspace with Lakebase enabled and permission to create Lakebase projects and service principals.
* [Databricks CLI](https://docs.databricks.com/aws/en/dev-tools/cli/install) 0.285 or later, logged in with `databricks auth login --host https://<workspace>.cloud.databricks.com`.
* `pg_dump`, `pg_restore` and `psql` with the same major version as the source and the target. Without a local install, run them from the official image, for example `docker run --rm postgres:17 pg_dump ...`.
* `jq`.
* A maintenance window: Aidbox must stay stopped while `pg_dump` and `pg_restore` run.

Read [Run Aidbox on managed PostgreSQL](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-on-managed-postgresql.md#databricks-lakebase) for the Lakebase settings reference.

## Compatibility

| Area | Lakebase behavior | What to do |
| --- | --- | --- |
| PostgreSQL version | 16, 17 (default) and 18; no in-place major upgrade | Create the project on the same major version as the source. |
| Required extensions | `pg_trgm` and `unaccent` are available | Pre-create them as the Aidbox role. |
| Optional extensions | `pgcrypto`, `fuzzystrmatch`, `postgis`, `pg_stat_statements` are available; `jsonknife` and `jsquery` are not | Find objects that depend on missing extensions before the move. |
| Superuser | None; members of `databricks_superuser` hold elevated privileges | Set `BOX_DB_INSTALL_PG_EXTENSIONS=false`. |
| Authentication | OAuth tokens with a 1-hour lifetime; password login is off by default | Use a service principal with `BOX_DB_AUTH_METHOD=databricks-autoscale`. |
| Collation | `C.UTF-8`, fixed at database creation | Expect a different `_sort` order on strings with accented letters. |
| Idle compute | Scale-to-zero suspends the compute and drops connections | Disable scale-to-zero for the endpoint Aidbox uses. |
| Connection pooler | PgBouncer in transaction mode, password roles only | Connect Aidbox to the direct endpoint host, not the `-pooler` host. |
| Backups | No access to WAL or physical backups | Use Lakebase [point-in-time restore](https://docs.databricks.com/aws/en/oltp/projects/point-in-time-restore) and branches. |

Lakebase Provisioned instances have moved to Autoscaling, so this tutorial uses Autoscaling projects and the `databricks postgres` CLI commands. See [Upgrade to Autoscaling](https://docs.databricks.com/aws/en/oltp/upgrade-to-autoscaling).

## Provision Lakebase

{% stepper %}
{% step %}
**Create the project**

Check the source version with `psql "$SRC_URL" -c 'show server_version'` and create the project on the same major version:

```bash
export SRC_URL="postgresql://aidbox:<password>@localhost:5432/aidbox"
export DATABRICKS_WS="https://<workspace>.cloud.databricks.com"
export PROJECT_ID="aidbox"

databricks postgres create-project "$PROJECT_ID" \
  --json '{"spec": {"display_name": "Aidbox", "pg_version": "17"}}'

# A new project has the "production" branch with the read-write endpoint "primary"
export BRANCH="projects/$PROJECT_ID/branches/production"
export ENDPOINT="$BRANCH/endpoints/primary"
export LB_HOST=$(databricks postgres get-endpoint "$ENDPOINT" -o json | jq -r .status.hosts.host)
```

`LB_HOST` looks like `ep-<name>.database.<region>.cloud.databricks.com`.
{% endstep %}

{% step %}
**Disable scale-to-zero and size the compute**

A suspended compute closes the Aidbox connection pool. Pick the CU range from the load on the source database. The spread between minimum and maximum can't exceed 16 CU.

```bash
databricks postgres update-endpoint "$ENDPOINT" spec.suspension \
  --json '{"spec": {"no_suspension": true}}'

databricks postgres update-endpoint "$ENDPOINT" \
  "spec.autoscaling_limit_min_cu,spec.autoscaling_limit_max_cu" \
  --json '{"spec": {"autoscaling_limit_min_cu": 1.0, "autoscaling_limit_max_cu": 8.0}}'
```
{% endstep %}

{% step %}
**Create a service principal**

```bash
databricks service-principals create --display-name aidbox-lakebase -o json
# Note "id" and "applicationId" from the output
databricks service-principal-secrets-proxy create <id> -o json
# Store "secret" in your secret manager; Databricks shows it once
export SP_CLIENT_ID=<applicationId>
export SP_CLIENT_SECRET=<secret>
```
{% endstep %}

{% step %}
**Create a Postgres role for the service principal**

The role name is the application ID.

```bash
databricks postgres create-role "$BRANCH" --role-id aidbox-sp \
  --json "{\"spec\": {\"identity_type\": \"SERVICE_PRINCIPAL\", \"postgres_role\": \"$SP_CLIENT_ID\"}}"
```
{% endstep %}

{% step %}
**Grant the role access to the database**

Connect as the project owner with a short-lived token. Aidbox creates and alters its own tables, so the role needs `CREATE` on the database and on the `public` schema.

```bash
export PGPASSWORD=$(databricks postgres generate-database-credential "$ENDPOINT" -o json | jq -r .token)

psql "postgresql://<your-email>@$LB_HOST:5432/databricks_postgres?sslmode=require" <<SQL
GRANT CONNECT, CREATE, TEMPORARY ON DATABASE databricks_postgres TO "$SP_CLIENT_ID";
GRANT ALL ON SCHEMA public TO "$SP_CLIENT_ID";
SQL
```

URL-encode the `@` in your email as `%40`.
{% endstep %}

{% step %}
**Create extensions as the service principal**

The Databricks CLI authenticates as the service principal when you set `DATABRICKS_HOST`, `DATABRICKS_CLIENT_ID` and `DATABRICKS_CLIENT_SECRET`. Create every extension the source database has that Lakebase supports, so the service principal owns them.

```bash
sp_token() {
  DATABRICKS_HOST=$DATABRICKS_WS DATABRICKS_CLIENT_ID=$SP_CLIENT_ID DATABRICKS_CLIENT_SECRET=$SP_CLIENT_SECRET \
    databricks postgres generate-database-credential "$ENDPOINT" -o json | jq -r .token
}
export LB_SP_URL="postgresql://$SP_CLIENT_ID@$LB_HOST:5432/databricks_postgres?sslmode=require"
export PGPASSWORD=$(sp_token)

psql "$LB_SP_URL" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_trgm            SCHEMA public;
CREATE EXTENSION IF NOT EXISTS unaccent           SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgcrypto           SCHEMA public;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch      SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements SCHEMA public;
CREATE EXTENSION IF NOT EXISTS postgis            SCHEMA public; -- only if the source has it
SQL
```

Check: `psql "$LB_SP_URL" -c 'select current_user'` returns the application ID, and `\dx` lists the extensions.
{% endstep %}
{% endstepper %}

## Inspect the source database

Run these queries before the maintenance window:

```bash
# Version, size, extensions, collation
psql "$SRC_URL" -c 'show server_version' \
  -c 'select pg_size_pretty(pg_database_size(current_database()))' \
  -c 'select extname, extversion from pg_extension order by 1' \
  -c 'select datcollate from pg_database where datname = current_database()'

# Indexes that depend on jsonknife or jsquery
psql "$SRC_URL" -c "select indexrelid::regclass, pg_get_indexdef(indexrelid)
  from pg_index where pg_get_indexdef(indexrelid) ~* 'knife|jsquery'"

# Exact row counts per table, kept for the comparison after the restore
psql "$SRC_URL" -At -c "select format('select %L, count(*) from %I.%I;', table_name, table_schema, table_name)
  from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE' order by 1" \
  | psql "$SRC_URL" -At > counts_source.txt
```

If the index query returns rows, drop those indexes and recreate them without `jsonknife` functions before the move. When the `jsonknife` extension is missing, Aidbox installs a `jsonpath`-based shim of the same functions, so FHIR search keeps working.

## Copy the data

{% stepper %}
{% step %}
**Stop Aidbox and dump the database**

```bash
docker compose stop aidbox

pg_dump -Fc -v -d "$SRC_URL" -f aidbox.dump
```
{% endstep %}

{% step %}
**Build the restore list**

The target already has the extensions. `spatial_ref_sys` belongs to PostGIS on the target, and the service principal can't write to it.

```bash
pg_restore -l aidbox.dump \
  | grep -v -E ' EXTENSION |TABLE DATA public spatial_ref_sys' > restore.list
```
{% endstep %}

{% step %}
**Restore as the service principal**

`--no-owner --no-acl` makes the service principal the owner of every restored object. Each `-j` worker opens its own connection with the token from `PGPASSWORD`, and Lakebase checks the token at login, so generate a fresh one right before the restore.

```bash
export PGPASSWORD=$(sp_token)

pg_restore -v --no-owner --no-acl -j 4 -L restore.list \
  -d "$LB_SP_URL" aidbox.dump 2> restore.log

grep -E '^pg_restore: error' restore.log
psql "$LB_SP_URL" -c 'ANALYZE'
```

`ANALYZE` prints `permission denied to analyze "pg_..."` warnings for system catalogs. You can ignore them.
{% endstep %}

{% step %}
**Compare row counts**

```bash
psql "$LB_SP_URL" -At -c "select format('select %L, count(*) from %I.%I;', table_name, table_schema, table_name)
  from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE' order by 1" \
  | psql "$LB_SP_URL" -At > counts_target.txt

diff counts_source.txt counts_target.txt && echo "counts match"
```
{% endstep %}
{% endstepper %}

## Point Aidbox at Lakebase

Replace the database settings of the Aidbox service. Keep every other setting as it is.

{% code title="docker-compose.yaml" %}
```yaml
services:
  aidbox:
    environment:
      BOX_DB_HOST: <LB_HOST>
      BOX_DB_PORT: '5432'
      BOX_DB_DATABASE: databricks_postgres
      BOX_DB_USER: <SP_CLIENT_ID>
      BOX_DB_PASSWORD: placeholder
      BOX_DB_AUTH_METHOD: databricks-autoscale
      BOX_DB_DATABRICKS_HOST: https://<workspace>.cloud.databricks.com
      BOX_DB_DATABRICKS_AUTOSCALE_ENDPOINT: projects/<project-id>/branches/production/endpoints/primary
      BOX_DB_DATABRICKS_CLIENT_ID: <SP_CLIENT_ID>
      BOX_DB_DATABRICKS_CLIENT_SECRET: <SP_CLIENT_SECRET>
      BOX_DB_INSTALL_PG_EXTENSIONS: 'false'
      BOX_DB_EXTENSION_SCHEMA: public
```
{% endcode %}

Remove the local database service from `depends_on`, then start Aidbox and wait for the health check:

```bash
docker compose up -d aidbox
curl -fsS http://localhost:8080/health
```

Aidbox fetches a token for the service principal, caches it for 45 minutes and rotates pool connections before the token expires.

With the default `BOX_DB_POOL_MINIMUM_IDLE=0`, the pool closes every connection after an idle period, and the first request afterwards waits while Aidbox reconnects and reloads its caches. Set [`BOX_DB_POOL_MINIMUM_IDLE`](../../reference/all-settings.md#db.pool.minimum-idle) above zero to keep connections open.

{% hint style="info" %}
Run Aidbox in the same cloud region as the Lakebase project. Each FHIR request makes several SQL round trips, and with a cross-region network every round trip adds the full network latency to the response time.
{% endhint %}

### Add a read replica (optional)

A read-only endpoint on the same branch serves as a [read-only replica](../../database/overview.md#postgresql-with-read-only-replica). The service principal role works on it without extra grants.

```bash
databricks postgres create-endpoint "$BRANCH" ro-replica \
  --json '{"spec": {"endpoint_type": "ENDPOINT_TYPE_READ_ONLY", "autoscaling_limit_min_cu": 0.5, "autoscaling_limit_max_cu": 2.0}}'

databricks postgres get-endpoint "$BRANCH/endpoints/ro-replica" -o json | jq -r .status.hosts.host
```

Add the replica settings to the Aidbox service:

```yaml
BOX_DB_RO_REPLICA_ENABLED: 'true'
BOX_DB_RO_REPLICA_HOST: <replica host>
BOX_DB_RO_REPLICA_PORT: '5432'
BOX_DB_RO_REPLICA_DATABASE: databricks_postgres
BOX_DB_RO_REPLICA_USER: <SP_CLIENT_ID>
BOX_DB_RO_REPLICA_PASSWORD: placeholder
BOX_DB_RO_REPLICA_AUTH_METHOD: databricks-autoscale
BOX_DB_RO_REPLICA_DATABRICKS_HOST: https://<workspace>.cloud.databricks.com
BOX_DB_RO_REPLICA_DATABRICKS_AUTOSCALE_ENDPOINT: projects/<project-id>/branches/production/endpoints/ro-replica
BOX_DB_RO_REPLICA_DATABRICKS_CLIENT_ID: <SP_CLIENT_ID>
BOX_DB_RO_REPLICA_DATABRICKS_CLIENT_SECRET: <SP_CLIENT_SECRET>
```

Aidbox sends a request to the replica when the request carries the `x-use-ro-replica` header. A write sent with this header fails with `cannot execute INSERT in a read-only transaction`.

## Verify the migration

Before you switch traffic, check that:

* Aidbox starts without extension or permission errors in the logs.
* Resources created before the move read back by id, and `_history` returns their earlier versions.
* Create, update with `If-Match`, conditional create and update, and transaction bundles return the same status codes as on the source.
* Saved search requests return the same totals as on the source. Results sorted by string fields can differ because of the `C.UTF-8` collation.
* Traffic keeps flowing for more than one hour, past the first token expiry.

## Roll back

Until Aidbox writes to Lakebase, rolling back means restoring the old `BOX_DB_*` settings and starting Aidbox against the source database. Keep the source database read-only for a period you agree on with your team. After Aidbox has written to Lakebase, dump Lakebase with the same commands in the reverse direction. To undo a mistake made on Lakebase, restore to a point in time or create a branch from before the incident.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Provided authentication token is not a valid JWT encoding` at startup | Aidbox 2608 or 2609 | Use Aidbox 2610 or later, or 2607 or earlier. |
| Aidbox refuses to start: missing extension | `pg_trgm` or `unaccent` isn't in `BOX_DB_EXTENSION_SCHEMA` | Create the extension as the service principal in `public`. |
| `permission denied for schema public` | The service principal lacks `CREATE` on `public` | Run the grants from the provisioning steps again. |
| `must be owner of table ...` | Another role restored the tables | Restore again as the service principal with `--no-owner`. |
| `password authentication failed` during `pg_restore` | The token expired before a worker connected | Generate a new token and lower `-j`. |
| Connections drop after idle periods | Scale-to-zero is on | Run `update-endpoint` with `no_suspension: true`. |
| `prepared statement does not exist` | Aidbox connects through the `-pooler` host | Use the direct endpoint host. |
