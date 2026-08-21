---
description: Connect Aidbox to Google Cloud SQL for PostgreSQL through the Cloud SQL JDBC socket factory using IAM database authentication.
---

# How to run Aidbox with Cloud SQL Java Connector

{% hint style="info" %}
This functionality is available starting from Aidbox version **2608**.
{% endhint %}

Connect Aidbox to Google Cloud SQL for PostgreSQL through the [Cloud SQL JDBC socket factory](https://github.com/GoogleCloudPlatform/cloud-sql-jdbc-socket-factory) instead of the Cloud SQL Auth Proxy sidecar. The connector opens an mTLS tunnel to the instance and authenticates the database session with a short-lived IAM token, so you store no database password anywhere.

Google documents the GCP-side setup: enabling the API and IAM roles, the `cloudsql.iam_authentication` flag, and registering the IAM database user. See [IAM authentication](https://cloud.google.com/sql/docs/postgres/iam-authentication) and [manage IAM users](https://cloud.google.com/sql/docs/postgres/add-manage-iam-users).

Provisioning the instance, database and extensions works the same way as in any other Aidbox-on-GCP deployment. For example, you can follow [How to run Aidbox in GCP Cloud Run](how-to-run-aidbox-in-gcp-cloud-run.md) and replace only its connection settings with the ones below. Pre-creating the extensions as `postgres` and setting `BOX_DB_INSTALL_PG_EXTENSIONS=false`, as that tutorial does, is mandatory here: an IAM database user is not a member of `cloudsqlsuperuser` and cannot run `CREATE EXTENSION` itself.

## Put the connector on the classpath

Aidbox does not bundle the connector. Mount its jars and point `JAVA_EXTRA_PATH` at them. Aidbox appends the variable to the container classpath after `aidbox.jar`.

There is no fat jar to download, so resolve the dependency closure (~48 jars, 14 MB) from Maven Central once. Run this next to your `docker-compose.yaml` to produce `./jars`:

```sh
cat > pom.xml <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>local</groupId><artifactId>aidbox-cloudsql-jars</artifactId>
  <version>1.0.0</version><packaging>pom</packaging>
  <dependencies>
    <dependency>
      <groupId>com.google.cloud.sql</groupId>
      <artifactId>postgres-socket-factory</artifactId>
      <version>1.29.0</version>
    </dependency>
  </dependencies>
</project>
EOF
mvn -B dependency:copy-dependencies -DoutputDirectory=jars -DincludeScope=runtime
```

## Configure Aidbox

```yaml
services:
  aidbox:
    image: healthsamurai/aidboxone:edge
    ports: ["8765:8080"]
    volumes:
      - ./jars:/extra:ro                   # must match JAVA_EXTRA_PATH
      - ${HOME}/.config/gcloud:/gcloud:ro  # local development only
    environment:
      JAVA_EXTRA_PATH:  "/extra/*"
      GOOGLE_APPLICATION_CREDENTIALS: "/gcloud/application_default_credentials.json"

      BOX_DB_HOST:     "ignored-but-must-be-nonempty"
      BOX_DB_PORT:     "1111" # ignored
      BOX_DB_DATABASE: "<DATABASE>"
      BOX_DB_USER:     "<IAM_DB_USER>"
      BOX_DB_PASSWORD: "ignored-but-must-be-nonempty"

      AIDBOX_DB_PARAM_SOCKET_FACTORY:     "com.google.cloud.sql.postgres.SocketFactory"
      AIDBOX_DB_PARAM_CLOUD_SQL_INSTANCE: "<INSTANCE_CONNECTION_NAME>"
      AIDBOX_DB_PARAM_ENABLE_IAM_AUTH:    "true"

      # ... other Aidbox settings
```

{% hint style="warning" %}
For a service account, `<IAM_DB_USER>` is the account email without the `.gserviceaccount.com` suffix: `my-sa@my-project.iam`, not `my-sa@my-project.iam.gserviceaccount.com`. For a user account, use the full email address.

Cloud SQL strips the suffix when it registers the IAM database user, and the connector does not strip it for you. Passing the full service account email fails with `password authentication failed`, not an IAM error, because PostgreSQL finds no role under that name and falls back to password authentication. Check the registered name with `gcloud sql users list --instance=<INSTANCE>`.
{% endhint %}

Any other connector property works the same way. `AIDBOX_DB_PARAM_<UPPER_SNAKE>` becomes the JDBC parameter `<lowerCamel>`, so `AIDBOX_DB_PARAM_IP_TYPES=PRIVATE` sets `ipTypes=PRIVATE` (needed for private-IP instances) and `AIDBOX_DB_PARAM_CLOUD_SQL_REFRESH_STRATEGY=lazy` sets `cloudSqlRefreshStrategy=lazy` (recommended on Cloud Run and other serverless runtimes). See [AIDBOX\_DB\_PARAM](../../configuration/configure-aidbox-and-multibox.md) and the [connector properties](https://github.com/GoogleCloudPlatform/cloud-sql-jdbc-socket-factory/blob/main/docs/configuration.md).

The compose file above takes credentials from ADC, so run `gcloud auth application-default login` first. On Kubernetes, drop the `gcloud` mount and `GOOGLE_APPLICATION_CREDENTIALS`, let Workload Identity supply credentials, and mount the jar directory the same way.

On Cloud Run there is no bind mount and the runtime service account supplies credentials through the metadata server. See [How to run Aidbox in GCP Cloud Run](how-to-run-aidbox-in-gcp-cloud-run.md#connect-through-the-cloud-sql-java-connector) for the jar delivery options and the roles to grant.
