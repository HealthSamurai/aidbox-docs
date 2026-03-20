---
description: Run Aidbox on managed PostgreSQL services like AWS Aurora, Azure Database, GCP Cloud SQL, and Databricks Lakebase. Setup guide for extensions and user configuration.
---

# Run Aidbox on managed PostgreSQL

This quickstart guide explains how to run Aidbox on managed PostgreSQL instance.

### Aurora PostgreSQL

#### Prerequisites

* aws CLI
* psql

#### Connect to db cluster

Follow [AWS documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.Connecting.AWSCLI.PostgreSQL.html) to connect to cluster using aws-cli and psql

#### Create role

Execute following sql in psql

```sql
CREATE USER aidbox WITH CREATEDB ENCRYPTED PASSWORD 'aidboxpass';
```

### Azure Database for PostgreSQL flexible server

#### Prerequisites

* azure CLI

#### Create Role

Follow [Azure Documentation](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/connect-azure-cli) and execute following SQL to create role:

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

Lakebase uses OAuth token-based authentication. Aidbox supports both **Provisioned** and **Autoscaling** deployment modes.

Aidbox fetches short-lived tokens (1 hour expiry) from Databricks and caches them for 45 minutes (configurable via `BOX_DB_CREDENTIAL_REFRESH_INTERVAL`). When the cache expires, a fresh token is fetched on the next connection. HikariCP `max-lifetime` is set to match the cache TTL so existing connections rotate before tokens expire. SSL is enforced automatically.

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
```
{% endtab %}
{% endtabs %}

{% hint style="info" %}
`BOX_DB_USER` and `BOX_DB_DATABRICKS_CLIENT_ID` are both the service principal's application ID.
`BOX_DB_PASSWORD` is a placeholder — the credentials provider overrides it.
`BOX_DB_DATABRICKS_HOST` is the workspace URL (from your browser), not the database hostname.
`BOX_DB_DATABRICKS_SCOPE` defaults to `all-apis`. Do not change unless you know your workspace requires a different scope.
`BOX_DB_CREDENTIAL_REFRESH_INTERVAL` controls the token cache TTL in milliseconds (default: `2700000`, i.e. 45 minutes). Should be less than the Databricks token expiry (60 minutes).
The same auth settings are available for read-only replica with the `BOX_DB_RO_REPLICA_*` prefix (e.g. `BOX_DB_RO_REPLICA_AUTH_METHOD`, `BOX_DB_RO_REPLICA_DATABRICKS_HOST`, etc.).
{% endhint %}

### Disable installation of PostgreSQL extensions on Aidbox startup&#x20;

If your PostgreSQL user used by Aidbox does not have sufficient privileges to install extensions, you can disable the installation of extensions on startup of Aidbox by setting the environment variable `AIDBOX_INSTALL_PG_EXTENSIONS` to `false`.&#x20;

The list of required extensions:&#x20;

* pgcrypto&#x20;
* unaccent
* &#x20;pg\_trgm
* &#x20;fuzzystrmatch

If `AIDBOX_INSTALL_PG_EXTENSIONS` is set to `false`, Aidbox will not start without them, so you have to install them manually.&#x20;

Optional list of extensions:&#x20;

* pg\_similarity
* &#x20;jsonknife
* &#x20;pg\_stat\_statements
* &#x20;postgis

### Setup Aidbox to use new user

{% hint style="warning" %}
You may encounter `permission denied` error when creating extensions. Just connect to PostgreSQL database using user that can create extension (usually admin user created with a server) and create failed extension manually.
{% endhint %}

Setup following environment variables. If you're using existing database make sure the `aidbox` role has `CREATE` privilege on it. Otherwise Aidbox won't be able to install most of the extensions.

```shell
BOX_DB_USER=aidbox
BOX_DB_PASSWORD=aidboxpass
BOX_DB_DATABASE=aidbox
```

{% hint style="info" %}
Deprecated names `PGUSER`, `PGPASSWORD`, and `PGDATABASE` are still accepted but `BOX_DB_*` variables are recommended.
{% endhint %}
