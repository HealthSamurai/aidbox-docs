---
description: Connect Aidbox to Azure Database for PostgreSQL flexible server with a managed identity through the Azure JDBC authentication plugin and Microsoft Entra ID tokens.
---

# How to run Aidbox with Azure PostgreSQL managed identity

{% hint style="info" %}
This functionality is available starting from Aidbox version **2608**.
{% endhint %}

Connect Aidbox to Azure Database for PostgreSQL flexible server with a managed identity through the [Azure Identity JDBC extension](https://learn.microsoft.com/en-us/azure/developer/java/sdk/identity-azure-hosted-auth). The extension plugs into the PostgreSQL JDBC driver: on every new connection it requests a short-lived Microsoft Entra ID token for the identity Aidbox runs as and sends it as the password, so you store no database password anywhere.

Microsoft documents the Azure-side setup: enabling Microsoft Entra authentication, assigning an Entra admin, and creating roles for managed identities. See [Microsoft Entra authentication](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/security-entra-concepts) and [connect with managed identity](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/security-connect-with-managed-identity).

## Prepare the database

Connect to the `postgres` database as the Entra admin. The password is an access token:

```sh
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)
psql "host=<SERVER>.postgres.database.azure.com dbname=postgres user=<ENTRA_ADMIN> sslmode=require"
```

Create a role for the managed identity and a database for Aidbox:

```sql
SELECT * FROM pgaadauth_create_principal_with_oid('<ROLE_NAME>', '<MI_PRINCIPAL_ID>', 'service', false, false);
CREATE DATABASE aidbox;
GRANT ALL ON DATABASE aidbox TO "<ROLE_NAME>";
```

`<MI_PRINCIPAL_ID>` is the identity's object (principal) ID: `az identity show -g <RG> -n <MI_NAME> --query principalId -o tsv`. `<ROLE_NAME>` is the PostgreSQL role name and becomes `BOX_DB_USER`. Use the managed identity name to keep it recognizable.

Allow the extensions on the server, then create them in the `aidbox` database as the Entra admin:

```sh
az postgres flexible-server parameter set -g <RG> -s <SERVER> \
  -n azure.extensions -v "PG_TRGM,UNACCENT,PGCRYPTO,FUZZYSTRMATCH"
```

```sql
-- psql "host=<SERVER>.postgres.database.azure.com dbname=aidbox user=<ENTRA_ADMIN> sslmode=require"
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
GRANT ALL ON SCHEMA public TO "<ROLE_NAME>";
```

Pre-creating the extensions and setting `BOX_DB_INSTALL_PG_EXTENSIONS=false` is mandatory: the managed identity role is not a member of `azure_pg_admin` and cannot run `CREATE EXTENSION` itself. See [PostgreSQL extensions](../../database/postgresql-extensions.md) for the full list.

## Put the plugin on the classpath

Aidbox does not bundle the plugin. Mount its jar and point `JAVA_EXTRA_PATH` at it. Aidbox appends the variable to the container classpath after `aidbox.jar`.

Aidbox already ships the Azure Identity SDK, so you need the plugin jar alone, without its dependencies:

```sh
mkdir -p jars
curl -fLo jars/azure-identity-extensions-1.3.1.jar \
  https://repo1.maven.org/maven2/com/azure/azure-identity-extensions/1.3.1/azure-identity-extensions-1.3.1.jar
```

{% hint style="warning" %}
Mount the plugin jar only. The full dependency closure of `azure-identity-extensions` (54 jars) duplicates the Azure SDK classes in `aidbox.jar` and adds `azure-core-http-netty` with Netty 4.2, a second HTTP client next to the JDK client Aidbox uses for the Azure SDK.
{% endhint %}

## Configure Aidbox

```yaml
services:
  aidbox:
    image: healthsamurai/aidboxone:edge
    ports: ["8765:8080"]
    volumes:
      - ./jars:/extra:ro   # must match JAVA_EXTRA_PATH
    environment:
      JAVA_EXTRA_PATH: "/extra/*"
      AZURE_CLIENT_ID: "<MI_CLIENT_ID>"

      BOX_DB_HOST:     "<SERVER>.postgres.database.azure.com"
      BOX_DB_PORT:     "5432"
      BOX_DB_DATABASE: "aidbox"
      BOX_DB_USER:     "<ROLE_NAME>"
      BOX_DB_PASSWORD: "ignored-but-must-be-nonempty"
      BOX_DB_INSTALL_PG_EXTENSIONS: "false"

      AIDBOX_DB_PARAM_AUTHENTICATION_PLUGIN_CLASS_NAME: "com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin"
      AIDBOX_DB_PARAM_SSLMODE: "require"

      # ... other Aidbox settings
```

The plugin authenticates with [`DefaultAzureCredential`](https://learn.microsoft.com/en-us/java/api/com.azure.identity.defaultazurecredential), which picks the identity from the environment. `AZURE_CLIENT_ID` selects a user-assigned managed identity: set it to the identity's client ID (`az identity show ... --query clientId`), not the principal ID used for the role. Omit it for a system-assigned identity.

{% hint style="warning" %}
`BOX_DB_USER` is the role name you passed to `pgaadauth_create_principal_with_oid`, not the identity's client ID or object ID.
{% endhint %}

The plugin fetches a new token for each new connection, and Azure checks the token only at login, so open connections keep working after the token expires. `AIDBOX_DB_PARAM_<UPPER_SNAKE>` becomes the JDBC parameter `<lowerCamel>`, see [AIDBOX\_DB\_PARAM](../../configuration/configure-aidbox-and-multibox.md).

## Where the identity comes from

* **Azure VM, Container Apps, App Service:** assign the user-assigned managed identity to the resource and set `AZURE_CLIENT_ID`. The plugin gets tokens from the instance metadata endpoint.
* **AKS:** enable [Microsoft Entra Workload ID](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview), create a federated credential for the Aidbox service account, annotate the service account with `azure.workload.identity/client-id` and label the pod with `azure.workload.identity/use: "true"`. The webhook injects `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_FEDERATED_TOKEN_FILE`, so drop `AZURE_CLIENT_ID` from the Aidbox environment. Mount the jar directory the same way, for example from a ConfigMap or an init container.
* **Local development:** a managed identity is unavailable outside Azure. Use a service principal instead: set `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` and `AZURE_TENANT_ID`, and create its role with `pgaadauth_create_principal_with_oid` and the service principal's object ID.
