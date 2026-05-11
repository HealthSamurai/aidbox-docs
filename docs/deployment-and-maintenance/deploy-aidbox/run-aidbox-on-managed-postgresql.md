---
description: Run Aidbox on managed PostgreSQL services like AWS Aurora, Azure Database, GCP Cloud SQL, and Databricks Lakebase. Setup guide for extensions and user configuration.
---

# Run Aidbox on managed PostgreSQL

This guide explains how to run Aidbox on a managed PostgreSQL instance (AWS Aurora, Azure Database for PostgreSQL, GCP Cloud SQL, Databricks Lakebase, etc.).

Compared to a self-hosted PostgreSQL where Aidbox connects as superuser and provisions everything itself, managed services impose constraints that require extra configuration:

* **No superuser access.** The DB user Aidbox connects with usually cannot `CREATE EXTENSION` for restricted extensions. Either pre-install the [required extensions](../../database/postgresql-extensions.md) manually and set [`BOX_DB_INSTALL_PG_EXTENSIONS`](../../reference/all-settings.md#db.install-pg-extensions) to `false`, or grant the role enough privileges to install them on startup.
* **Extensions may live outside `public`.** Some providers install extensions into a dedicated schema that is not on the default `search_path`. Set [`BOX_DB_EXTENSION_SCHEMA`](../../reference/all-settings.md#db.extension-schema) to the schema where extensions are installed — otherwise Aidbox won't find them and will fail to start.
* **Non-password authentication.** Some providers (e.g. Databricks Lakebase) use short-lived OAuth tokens instead of static passwords. Configure [`BOX_DB_AUTH_METHOD`](../../reference/all-settings.md#db.auth-method) and the provider-specific credentials — see the [Databricks Lakebase](#databricks-lakebase) section.
* **Database is not auto-created.** With some providers (e.g. Databricks) the database must already exist before Aidbox starts.
* **SSL is usually enforced** by the provider; Aidbox enables it automatically where required.

## Aidbox configuration

### Database connection

Set the following environment variables so Aidbox can connect to the database. Make sure the role has `CREATE` privilege on the database — otherwise Aidbox won't be able to install most of the extensions.

```shell
BOX_DB_HOST=<host>
BOX_DB_PORT=5432
BOX_DB_DATABASE=aidbox
BOX_DB_USER=aidbox
BOX_DB_PASSWORD=aidboxpass
```

{% hint style="info" %}
Deprecated names `PGUSER`, `PGPASSWORD`, and `PGDATABASE` are still accepted but [`BOX_DB_USER`](../../reference/all-settings.md#db.user) / [`BOX_DB_PASSWORD`](../../reference/all-settings.md#db.password) / [`BOX_DB_DATABASE`](../../reference/all-settings.md#db.database) are recommended.
{% endhint %}

### PostgreSQL extensions

Aidbox needs a set of PostgreSQL extensions — see [PostgreSQL Extensions](../../database/postgresql-extensions.md) for the full list of required and optional ones.

If the Aidbox role does not have privileges to install extensions, set [`BOX_DB_INSTALL_PG_EXTENSIONS`](../../reference/all-settings.md#db.install-pg-extensions) to `false` and install required extensions manually. With this flag set Aidbox still refuses to start unless all required extensions are present.

```shell
BOX_DB_INSTALL_PG_EXTENSIONS=false
```

{% hint style="warning" %}
Aidbox expects extensions to be installed in the [`BOX_DB_EXTENSION_SCHEMA`](../../reference/all-settings.md#db.extension-schema) schema (`public` by default). If extensions live in a different schema, Aidbox won't start.

```shell
BOX_DB_EXTENSION_SCHEMA=public
```
{% endhint %}

{% hint style="info" %}
You may hit a `permission denied` error when Aidbox tries to create extensions. Connect to PostgreSQL as a user that can create extensions (usually the admin user created with the server) and create the failing extension manually.
{% endhint %}

## Provider-specific setup

### Aurora PostgreSQL

#### Prerequisites

* aws CLI
* psql

#### Connect to db cluster

Follow [AWS documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.Connecting.AWSCLI.PostgreSQL.html) to connect to cluster using aws-cli and psql.

#### Create role

Execute the following SQL in psql:

```sql
CREATE USER aidbox WITH CREATEDB ENCRYPTED PASSWORD 'aidboxpass';
```

### Azure Database for PostgreSQL flexible server

#### Prerequisites

* azure CLI

#### Create role

Follow [Azure documentation](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/connect-azure-cli) and execute the following SQL to create a role:

```sql
CREATE USER aidbox WITH CREATEDB ENCRYPTED PASSWORD 'aidboxpass';
```

### Databricks Lakebase

#### Prerequisites

* A Databricks workspace with [Lakebase Postgres](https://docs.databricks.com/aws/en/oltp/) enabled
* A [service principal](https://docs.databricks.com/aws/en/admin/users-groups/service-principals) with a generated OAuth secret, [added to the workspace](https://docs.databricks.com/aws/en/admin/users-groups/service-principals#add-a-service-principal-to-a-workspace)
* Follow [Databricks documentation](https://docs.databricks.com/aws/en/oltp/instances/pg-roles?language=PostgreSQL) to create a PostgreSQL role for the service principal
* The database must already exist before starting Aidbox — Aidbox will not create it automatically when using Databricks authentication

#### Configure Aidbox

Lakebase uses OAuth token-based authentication. Aidbox supports both Lakebase deployment modes: [Provisioned](https://docs.databricks.com/aws/en/oltp/instances/) (fixed-capacity instances) and [Autoscaling](https://docs.databricks.com/aws/en/oltp/projects/about) (scale-to-zero projects).

Aidbox fetches short-lived tokens (1 hour expiry) from Databricks and caches them for 45 minutes (configurable via [`BOX_DB_CREDENTIAL_REFRESH_INTERVAL`](../../reference/all-settings.md#db.credential-refresh-interval)). When the cache expires, a fresh token is fetched on the next connection. HikariCP `max-lifetime` is set to match the cache TTL so existing connections rotate before tokens expire. SSL is enforced automatically.

{% tabs %}
{% tab title="Provisioned" %}
```shell
BOX_DB_HOST=<instance-id>.database.cloud.databricks.com
BOX_DB_PORT=5432
BOX_DB_DATABASE=databricks_postgres
BOX_DB_USER=<client-id>
BOX_DB_PASSWORD=placeholder

BOX_DB_AUTH_METHOD=databricks-provisioned
BOX_DB_DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
BOX_DB_DATABRICKS_PROVISIONED_INSTANCE_NAME=<instance-name>
BOX_DB_DATABRICKS_CLIENT_ID=<client-id>
BOX_DB_DATABRICKS_CLIENT_SECRET=<client-secret>
BOX_DB_DATABRICKS_SCOPE=all-apis
```
{% endtab %}
{% tab title="Autoscaling" %}
```shell
BOX_DB_HOST=<project-id>.database.cloud.databricks.com
BOX_DB_PORT=5432
BOX_DB_DATABASE=databricks_postgres
BOX_DB_USER=<client-id>
BOX_DB_PASSWORD=placeholder

BOX_DB_AUTH_METHOD=databricks-autoscale
BOX_DB_DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
BOX_DB_DATABRICKS_AUTOSCALE_ENDPOINT=projects/<project-id>/branches/<branch-id>/endpoints/<endpoint-id>
BOX_DB_DATABRICKS_CLIENT_ID=<client-id>
BOX_DB_DATABRICKS_CLIENT_SECRET=<client-secret>
BOX_DB_DATABRICKS_SCOPE=all-apis
```
{% endtab %}
{% endtabs %}

{% hint style="info" %}
[`BOX_DB_USER`](../../reference/all-settings.md#db.user) and [`BOX_DB_DATABRICKS_CLIENT_ID`](../../reference/all-settings.md#db.databricks-client-id) are both the service principal's application ID.
[`BOX_DB_PASSWORD`](../../reference/all-settings.md#db.password) is a placeholder — the credentials provider overrides it.
[`BOX_DB_DATABRICKS_HOST`](../../reference/all-settings.md#db.databricks-host) is the workspace URL (from your browser), not the database hostname.
[`BOX_DB_DATABRICKS_SCOPE`](../../reference/all-settings.md#db.databricks-scope) defaults to `all-apis`. Do not change unless you know your workspace requires a different scope.
The same auth settings are available for the read-only replica with the `BOX_DB_RO_REPLICA_*` prefix (e.g. `BOX_DB_RO_REPLICA_AUTH_METHOD`, `BOX_DB_RO_REPLICA_DATABRICKS_HOST`, etc.).
{% endhint %}
