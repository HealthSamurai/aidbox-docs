---
description: Run Aidbox on managed PostgreSQL services like AWS Aurora, Azure Database, GCP Cloud SQL, and Databricks Lakebase. Setup guide for extensions and user configuration.
---

# Run Aidbox on managed PostgreSQL

This guide explains how to run Aidbox on a managed PostgreSQL instance (AWS Aurora, Azure Database for PostgreSQL, GCP Cloud SQL, Databricks Lakebase, etc.).

Compared to a self-hosted PostgreSQL where Aidbox connects as superuser and provisions everything itself, managed services impose constraints that require extra configuration:

* **No superuser access.** The DB user Aidbox connects with usually cannot `CREATE EXTENSION` for restricted extensions. Either pre-install the [required extensions](#disable-installation-of-postgresql-extensions-on-aidbox-startup) manually and set [`BOX_DB_INSTALL_PG_EXTENSIONS`](../../reference/all-settings.md#db.install-pg-extensions) to `false`, or grant the role enough privileges to install them on startup.
* **Extensions may live outside `public`.** Some providers install extensions into a dedicated schema that is not on the default `search_path`. Set [`BOX_DB_EXTENSION_SCHEMA`](../../reference/all-settings.md#db.extension-schema) to the schema where extensions are installed — otherwise Aidbox won't find them and will fail to start.
* **Non-password authentication.** Some providers (e.g. Databricks Lakebase) use short-lived OAuth tokens instead of static passwords. Configure [`BOX_DB_AUTH_METHOD`](../../reference/all-settings.md#db.auth-method) and the provider-specific credentials — see the [Databricks Lakebase](#databricks-lakebase) section.
* **Database is not auto-created.** With some providers (e.g. Databricks) the database must already exist before Aidbox starts.
* **SSL is usually enforced** by the provider; Aidbox enables it automatically where required.

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
`BOX_DB_CREDENTIAL_REFRESH_INTERVAL` controls the token cache TTL in milliseconds (default: `2700000`, i.e. 45 minutes). Should be less than the Databricks token expiry (60 minutes).
The same auth settings are available for read-only replica with the `BOX_DB_RO_REPLICA_*` prefix (e.g. `BOX_DB_RO_REPLICA_AUTH_METHOD`, `BOX_DB_RO_REPLICA_DATABRICKS_HOST`, etc.).
{% endhint %}

### Disable installation of PostgreSQL extensions on Aidbox startup&#x20;

If your PostgreSQL user used by Aidbox does not have sufficient privileges to install extensions, you can disable the installation of extensions on startup of Aidbox by setting the environment variable [`BOX_DB_INSTALL_PG_EXTENSIONS`](../../reference/all-settings.md#db.install-pg-extensions) to `false`.

The list of required extensions:&#x20;

* pgcrypto
* pg\_trgm

If `BOX_DB_INSTALL_PG_EXTENSIONS` is set to `false`, Aidbox will not start without them, so you have to install them manually.&#x20; 

{% hint style="warning" %}
Note that Aidbox expects extensions to be installed in [`BOX_DB_EXTENSION_SCHEMA`](../../reference/all-settings.md#db.extension-schema) schema (`public` by default). If extensions are installed in different schema, Aidbox won't start.

```shell
BOX_DB_EXTENSION_SCHEMA=public
```
{% endhint %}

Optional list of extensions:&#x20;

* pg\_similarity
* unaccent
* &#x20;jsonknife
* &#x20;pg\_stat\_statements
* &#x20;postgis
* &#x20;fuzzystrmatch

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
