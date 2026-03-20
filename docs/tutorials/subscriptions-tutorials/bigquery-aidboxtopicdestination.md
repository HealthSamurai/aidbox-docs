---
description: Export FHIR resources to Google BigQuery for real-time analytics using SQL-on-FHIR ViewDefinitions.
---

# BigQuery AidboxTopicDestination

{% hint style="info" %}
This functionality is available starting from version 2603.
{% endhint %}

## Overview

The BigQuery Topic Destination module exports FHIR resources from Aidbox to Google BigQuery in a flattened format using [ViewDefinitions](../../modules/sql-on-fhir/defining-flat-views-with-view-definitions.md) and SQL-on-FHIR technology. Data is written using the [Storage Write API](https://cloud.google.com/bigquery/docs/write-api) (gRPC) for high throughput.

**Delivery guarantee:** The module uses an at-least-once delivery queue internally — messages are persisted in PostgreSQL and retried on failure. The BigQuery Storage Write API provides exactly-once semantics at the API level, so duplicate delivery attempts do not result in duplicate rows.

## Key Features

- **Real-time data export**: Automatically exports FHIR resources to BigQuery as they are created, updated, or deleted
- **Data flattening**: Uses ViewDefinitions to transform complex FHIR resources into flat, analytical-friendly tables
- **At-least-once delivery**: Persistent message queue with guaranteed delivery and batch processing
- **Initial export**: Automatically exports existing data when setting up a new destination
- **Monitoring**: Built-in metrics and status reporting via `$status` endpoint

## Before you begin

- Make sure your Aidbox version is 2603 or newer
- Set up a local Aidbox instance using the getting started [guide](../../getting-started/run-aidbox-locally.md)
- Have a Google Cloud project with BigQuery enabled, or use the [BigQuery Emulator](#local-testing-with-bigquery-emulator) for local testing

## Installation

### Docker Compose

1. Download the BigQuery module JAR file and place it next to your **docker-compose.yaml**:

   ```sh
   curl -O https://storage.googleapis.com/aidbox-modules/topic-destination-bigquery/topic-destination-bigquery-2603.1.jar
   ```

2. Edit your **docker-compose.yaml** and add these lines to the Aidbox service:

   ```yaml
   aidbox:
     volumes:
       - ./topic-destination-bigquery-2603.1.jar:/topic-destination-bigquery.jar
       # ... other volumes ...
     environment:
       BOX_MODULE_LOAD: io.healthsamurai.topic-destination.bigquery.core
       BOX_MODULE_JAR: "/topic-destination-bigquery.jar"
       # ... other environment variables ...
   ```

3. Start Aidbox:

   ```sh
   docker compose up
   ```

4. Verify the module is loaded. In Aidbox UI, go to **FHIR Packages** and check that the BigQuery profile is present:
   `http://aidbox.app/StructureDefinition/aidboxtopicdestination-bigquery-at-least-once`

{% hint style="info" %}
The profile URL above is a FHIR canonical identifier, not an HTTP endpoint. You can find it in the Aidbox UI under FHIR Packages.
{% endhint %}

### Kubernetes

For Kubernetes deployments, the module is downloaded automatically using an init container:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aidbox
spec:
  template:
    spec:
      initContainers:
        - name: download-bigquery-module
          image: debian:bookworm-slim
          command:
            - sh
            - -c
            - |
              apt-get -y update && apt-get -y install curl
              curl -L -o /modules/topic-destination-bigquery.jar \
                https://storage.googleapis.com/aidbox-modules/topic-destination-bigquery/topic-destination-bigquery-2603.1.jar
              chmod 644 /modules/topic-destination-bigquery.jar
          volumeMounts:
            - mountPath: /modules
              name: modules-volume
      containers:
        - name: aidbox
          image: healthsamurai/aidboxone:edge
          env:
            - name: BOX_MODULE_LOAD
              value: "io.healthsamurai.topic-destination.bigquery.core"
            - name: BOX_MODULE_JAR
              value: "/modules/topic-destination-bigquery.jar"
            - name: BOX_FHIR_SCHEMA_VALIDATION
              value: "true"
            # ... other environment variables ...
          volumeMounts:
            - name: modules-volume
              mountPath: /modules
      volumes:
        - name: modules-volume
          emptyDir: {}
```

{% hint style="info" %}
This is a partial Deployment manifest showing only the module-related configuration. You still need your existing Aidbox environment variables, Service, and other Kubernetes resources. Use a pinned Aidbox version (e.g., `healthsamurai/aidboxone:2603`) for production instead of `edge`.
{% endhint %}

### Updating the module

When a new version is released, update the JAR URL/filename in your deployment configuration and restart Aidbox. Available versions are listed in `gs://aidbox-modules/topic-destination-bigquery/`.

## Configuration

### Required Parameters

All requests in this tutorial use `Content-Type: application/json`.

| Parameter           | Type        | Description                         |
| ------------------- | ----------- | ----------------------------------- |
| `projectId`         | string      | Google Cloud project ID             |
| `dataset`           | string      | BigQuery dataset name               |
| `destinationTable`  | string      | Target table name in BigQuery       |
| `viewDefinition`    | string      | The `name` field of the ViewDefinition resource (not `id`) |
| `batchSize`         | unsignedInt | Number of messages per batch        |
| `sendIntervalMs`    | unsignedInt | Maximum time between sends (ms)     |

{% hint style="info" %}
**Choosing batch parameters:** For low-latency dashboards, use small batches (e.g., `batchSize: 10`, `sendIntervalMs: 1000`). For high-throughput bulk workloads, use larger batches (e.g., `batchSize: 500`, `sendIntervalMs: 5000`). Start with `batchSize: 50` and `sendIntervalMs: 5000` as a reasonable default.
{% endhint %}

### Optional Parameters

| Parameter              | Type    | Description                                                                        |
| ---------------------- | ------- | ---------------------------------------------------------------------------------- |
| `serviceAccountKey`    | string  | Google Service Account JSON key (omit when using Workload Identity or ADC)         |
| `skipInitialExport`    | boolean | Skip initial export of existing data (default: `false`)                            |
| `emulatorUrl`          | string  | BigQuery emulator REST URL, e.g., `http://bigquery:9050` (skips authentication)    |
| `emulatorGrpcHost`     | string  | BigQuery emulator gRPC host:port, e.g., `bigquery:9060` (uses plaintext gRPC)      |

### Authentication

The module supports three authentication methods:

1. **Service Account JSON key** — pass the full JSON key content as the `serviceAccountKey` parameter. Suitable for Docker Compose and environments without Workload Identity.
2. **Application Default Credentials (ADC)** — omit `serviceAccountKey`. The module automatically uses the attached service account credentials. Recommended for Cloud Run and GKE with Workload Identity.
3. **Emulator mode** — set `emulatorUrl` and `emulatorGrpcHost`. No authentication required.

{% hint style="warning" %}
Avoid hardcoding the Service Account JSON key directly in resource definitions. Use environment variables or a secrets manager to inject it at deployment time.
{% endhint %}

### Required IAM Roles

The service account (whether explicit key or ADC) needs these roles:

| Role | Purpose |
| ---- | ------- |
| `roles/bigquery.user` | Run queries, create jobs (healthcheck, federated queries) |
| `roles/bigquery.dataEditor` | Insert data, create/update tables via Storage Write API |

## Usage Example: Patient Data Export

### Step 1: Create Subscription Topic

```http
POST /fhir/AidboxSubscriptionTopic

{
  "resourceType": "AidboxSubscriptionTopic",
  "url": "http://example.org/subscriptions/patient-updates",
  "status": "active",
  "trigger": [
    {
      "resource": "Patient",
      "supportedInteraction": ["create", "update", "delete"],
      "fhirPathCriteria": "name.exists()"
    }
  ]
}
```

### Step 2: Create ViewDefinition

A [ViewDefinition](../../modules/sql-on-fhir/defining-flat-views-with-view-definitions.md) defines how to transform a complex FHIR resource into a flat table structure suitable for analytics. Each `column` maps a [FHIRPath](https://hl7.org/fhirpath/) expression to a named column in the output table.

In this example, we flatten Patient into 5 columns: `id`, `gender`, `birth_date` from top-level fields, and `family_name`, `given_name` from the first official name (using `forEach` to navigate into the nested `name` array).

```http
POST /fhir/ViewDefinition

{
  "resourceType": "ViewDefinition",
  "id": "patient_flat",
  "name": "patient_flat",
  "resource": "Patient",
  "status": "active",
  "select": [
    {
      "column": [
        {"name": "id", "path": "id"},
        {"name": "gender", "path": "gender"},
        {"name": "birth_date", "path": "birthDate"}
      ]
    },
    {
      "forEach": "name.where(use = 'official').first()",
      "column": [
        {"name": "family_name", "path": "family"},
        {"name": "given_name", "path": "given.join(' ')"}
      ]
    }
  ]
}
```

The column names you define here must match the columns in the BigQuery table (Step 4). See [ViewDefinition documentation](../../modules/sql-on-fhir/defining-flat-views-with-view-definitions.md) for the full syntax including `where` filters, `unionAll`, and type casting.

### Step 3: Materialize ViewDefinition

The ViewDefinition must be [materialized](../../modules/sql-on-fhir/operation-materialize.md) as a database view before the BigQuery module can use it to transform data. Materialization creates a SQL view in the `sof` schema that maps FHIR resources to the flat column structure you defined.

```http
POST /fhir/ViewDefinition/patient_flat/$materialize

{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "type",
      "valueCode": "view"
    }
  ]
}
```

{% hint style="info" %}
The ViewDefinition must be materialized as a **view** (not a table). See the [`$materialize` operation](../../modules/sql-on-fhir/operation-materialize.md) documentation for details.
{% endhint %}

### Step 4: Create BigQuery Table

Create a table in BigQuery that matches the ViewDefinition output. You can do this via the [BigQuery Console](https://console.cloud.google.com/bigquery) or using SQL:

```sql
CREATE TABLE your_project.your_dataset.patients (
    id STRING NOT NULL,
    gender STRING,
    birth_date DATE,
    family_name STRING,
    given_name STRING,
    is_deleted INT64 NOT NULL
);
```

{% hint style="warning" %}
The table **must** include an `is_deleted` column (`INT64 NOT NULL`). The module sets this to `0` for create/update operations and `1` for delete operations.
{% endhint %}

### Step 5: Configure Authentication

**Option A: Service Account key (Docker Compose)**

1. Go to [Google Cloud IAM](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. Create a new Service Account
3. Grant it `roles/bigquery.user` and `roles/bigquery.dataEditor` on your project
4. Create a JSON key and download it

**Option B: Application Default Credentials (Cloud Run / GKE)**

Attach a service account with the required BigQuery roles to your Cloud Run service or GKE workload. No key file needed — omit `serviceAccountKey` from the destination configuration.

### Step 6: Configure BigQuery Destination

```http
POST /fhir/AidboxTopicDestination

{
  "resourceType": "AidboxTopicDestination",
  "id": "patient-bigquery",
  "topic": "http://example.org/subscriptions/patient-updates",
  "kind": "bigquery-at-least-once",
  "meta": {
    "profile": [
      "http://aidbox.app/StructureDefinition/aidboxtopicdestination-bigquery-at-least-once"
    ]
  },
  "parameter": [
    {"name": "projectId", "valueString": "your-gcp-project-id"},
    {"name": "dataset", "valueString": "your_dataset"},
    {"name": "destinationTable", "valueString": "patients"},
    {"name": "viewDefinition", "valueString": "patient_flat"},
    {"name": "serviceAccountKey", "valueString": "<contents of your service account JSON key>"},
    {"name": "batchSize", "valueUnsignedInt": 50},
    {"name": "sendIntervalMs", "valueUnsignedInt": 5000}
  ]
}
```

{% hint style="info" %}
For Cloud Run / GKE with Workload Identity (ADC), omit the `serviceAccountKey` parameter — the module will use the attached service account automatically.
{% endhint %}

### Step 7: Verify

Create a test patient:

```http
POST /fhir/Patient

{
  "name": [{"use": "official", "family": "Smith", "given": ["John"]}],
  "gender": "male",
  "birthDate": "1990-01-15"
}
```

Then query your BigQuery table to confirm the data arrived:

```sql
SELECT * FROM your_project.your_dataset.patients;
```

### Stopping the export

To stop exporting data, delete the `AidboxTopicDestination` resource:

```http
DELETE /fhir/AidboxTopicDestination/patient-bigquery
```

This stops the export and cleans up the internal message queue. Data already written to BigQuery is not affected.

## Initial Export

When a new destination is created, the module automatically exports all existing data that matches the subscription topic. This ensures your BigQuery table has complete historical data.

To skip the initial export (e.g., the table is already populated or you only need real-time data), add `skipInitialExport`:

```json
{"name": "skipInitialExport", "valueBoolean": true}
```

### How it works

1. Reads existing data from PostgreSQL via the materialized ViewDefinition using a streaming JDBC cursor
2. Sends data to BigQuery in internal batches of 500 rows (hardcoded, separate from the `batchSize` parameter which controls real-time delivery) using the Storage Write API [pending stream](https://cloud.google.com/bigquery/docs/write-api#pending_type)
3. After all rows are sent, finalizes and commits the stream — data becomes visible atomically
4. Reports progress via the `$status` endpoint (`initialExportProgress_rowsSent`)

The export retries up to 3 times on failure.

### Alternative: Federated Query (Cloud SQL only)

If your Aidbox PostgreSQL runs on [Google Cloud SQL](https://cloud.google.com/sql), you can populate the BigQuery table manually using a [federated query](https://cloud.google.com/bigquery/docs/cloud-sql-federated-queries) instead of the built-in initial export. This can be useful if you want more control over the process or need to re-populate the table without recreating the destination.

1. [Create a BigQuery Connection](https://cloud.google.com/bigquery/docs/connect-to-sql) to your Cloud SQL instance
2. Run this query in the BigQuery Console:

```sql
INSERT INTO `your_project.your_dataset.patients`
  (id, gender, birth_date, family_name, given_name, is_deleted)
SELECT id, gender, CAST(birth_date AS DATE), family_name, given_name, 0 as is_deleted
FROM EXTERNAL_QUERY(
  'projects/your_project/locations/your_region/connections/your_connection_id',
  'SELECT * FROM sof.patient_flat'
)
```

3. Create the destination with `skipInitialExport` to avoid duplicates:

```json
{"name": "skipInitialExport", "valueBoolean": true}
```

{% hint style="warning" %}
The BigQuery dataset, the Connection, and the Cloud SQL instance must all be in the same region (e.g., `us-east1`).
{% endhint %}

## Monitoring

### Status Endpoint

```http
GET /fhir/AidboxTopicDestination/patient-bigquery/$status
```

Returns a FHIR [Parameters](https://www.hl7.org/fhir/parameters.html) resource:

```json
{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "status", "valueString": "active"},
    {"name": "messagesDelivered", "valueDecimal": 100},
    {"name": "messagesQueued", "valueDecimal": 0},
    {"name": "messagesInProcess", "valueDecimal": 0},
    {"name": "messagesDeliveryAttempts", "valueDecimal": 100},
    {"name": "initialExportStatus", "valueString": "completed"},
    {"name": "initialExportProgress_rowsSent", "valueDecimal": 100}
  ]
}
```

- `messagesDelivered` — total messages sent to BigQuery
- `messagesQueued` — messages waiting in the PG queue
- `messagesInProcess` — messages currently being sent
- `messagesDeliveryAttempts` — total delivery attempts (including retries)
- `initialExportStatus` — `not_started`, `export-in-progress`, `completed`, `skipped`, or `failed`
- `initialExportProgress_rowsSent` — number of rows sent during initial export

## Data Transformation

The module automatically:

1. **Applies ViewDefinition**: Transforms each FHIR resource using the specified ViewDefinition SQL
2. **Adds deletion flag**: Sets `is_deleted = 0` for create/update, `is_deleted = 1` for delete operations
3. **Batches messages**: Groups messages according to `batchSize` and `sendIntervalMs` parameters

### Soft Deletes and Updates

The module writes to BigQuery via the Storage Write API, which is append-only. Every change to a FHIR resource (create, update, or delete) appends a **new row** to BigQuery:

- **Create**: new row with `is_deleted = 0`
- **Update**: new row with `is_deleted = 0` (old row remains unchanged)
- **Delete**: new row with `is_deleted = 1`

This means a resource that was created and then updated 3 times will have 4 rows in BigQuery, all with the same `id`. The `is_deleted` column uses `INT64` with values `0` and `1`.

To query only non-deleted resources (ignoring history):

```sql
SELECT * FROM your_dataset.patients WHERE is_deleted = 0;
```

To get the latest version of each resource (handling both updates and deletes), add a timestamp column to your table and ViewDefinition, then use a window function:

```sql
-- Requires a timestamp column (e.g., ts from meta.lastUpdated) in the table
SELECT * EXCEPT(rn) FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts DESC) as rn
  FROM your_dataset.patients
)
WHERE rn = 1 AND is_deleted = 0;
```

{% hint style="info" %}
To track versions, add `meta.lastUpdated` to your ViewDefinition as a `ts` column (type `TIMESTAMP` in BigQuery). Each update appends a new row with a newer `ts`, so you can always find the latest state.
{% endhint %}

## Local Testing with BigQuery Emulator

You can test the BigQuery integration locally without a GCP account using the [BigQuery Emulator](https://github.com/goccy/bigquery-emulator).

### Start the Emulator

Add the BigQuery emulator to your existing `docker-compose.yaml`:

```yaml
services:
  bigquery:
    image: ghcr.io/goccy/bigquery-emulator:latest
    platform: linux/amd64 # required for Apple Silicon
    ports:
      - "9050:9050"
      - "9060:9060"
    command: --project=test-project --dataset=test
```

```sh
docker compose up -d bigquery
```

### Create a Test Table

```sh
curl -X POST http://localhost:9050/bigquery/v2/projects/test-project/datasets/test/tables \
  -H 'Content-Type: application/json' \
  -d '{
    "tableReference": {"projectId": "test-project", "datasetId": "test", "tableId": "patients"},
    "schema": {"fields": [
      {"name": "id", "type": "STRING", "mode": "REQUIRED"},
      {"name": "gender", "type": "STRING", "mode": "NULLABLE"},
      {"name": "birth_date", "type": "DATE", "mode": "NULLABLE"},
      {"name": "family_name", "type": "STRING", "mode": "NULLABLE"},
      {"name": "given_name", "type": "STRING", "mode": "NULLABLE"},
      {"name": "is_deleted", "type": "INTEGER", "mode": "REQUIRED"}
    ]}
  }'
```

### Configure Destination for Emulator

When using the emulator, omit `serviceAccountKey` and add emulator endpoints instead:

```http
POST /fhir/AidboxTopicDestination

{
  "resourceType": "AidboxTopicDestination",
  "id": "patient-bigquery-local",
  "topic": "http://example.org/subscriptions/patient-updates",
  "kind": "bigquery-at-least-once",
  "meta": {
    "profile": [
      "http://aidbox.app/StructureDefinition/aidboxtopicdestination-bigquery-at-least-once"
    ]
  },
  "parameter": [
    {"name": "projectId", "valueString": "test-project"},
    {"name": "dataset", "valueString": "test"},
    {"name": "destinationTable", "valueString": "patients"},
    {"name": "viewDefinition", "valueString": "patient_flat"},
    {"name": "batchSize", "valueUnsignedInt": 10},
    {"name": "sendIntervalMs", "valueUnsignedInt": 100},
    {"name": "emulatorUrl", "valueString": "http://bigquery:9050"},
    {"name": "emulatorGrpcHost", "valueString": "bigquery:9060"}
  ]
}
```

{% hint style="info" %}
Use the Docker service name (`bigquery`) as the emulator host — both Aidbox and the emulator run in the same Docker network.
{% endhint %}

### Query the Emulator

```sh
curl -s -X POST 'http://localhost:9050/bigquery/v2/projects/test-project/queries' \
  -H 'Content-Type: application/json' \
  -d '{"query": "SELECT * FROM test.patients", "useLegacySql": false}' | python3 -m json.tool
```

{% hint style="warning" %}
The emulator has a known limitation: `DATE` columns may return `null` when data is written via the Storage Write API (gRPC). `STRING`, `INTEGER`, and `TIMESTAMP` columns work correctly. This does not affect real BigQuery.
{% endhint %}

## Delivery Guarantees and Retry

The module provides **at-least-once delivery**. Messages are persisted in a PostgreSQL queue before being sent to BigQuery. If delivery fails, the message remains in the queue and is retried on the next batch cycle (every `sendIntervalMs`). There is a 1-second backoff between failed delivery attempts to prevent log storms.

If the gRPC connection to BigQuery drops (network issue, server maintenance), the writer is automatically reconnected with exponential backoff. Messages are not lost during reconnection — they stay in the PG queue.

Initial export retries up to 3 times with exponential backoff (1s, 2s, 4s) on failure.

## Multiple Destinations

You can create multiple destinations for the same topic, e.g., to export the same data to different BigQuery tables with different ViewDefinitions. Each destination operates independently with its own queue, writer, and status.

## Schema Evolution

If you need to add a column to the BigQuery table:

1. Add the column to your BigQuery table (`ALTER TABLE ... ADD COLUMN ...`)
2. Update the ViewDefinition with the new column
3. Re-materialize the ViewDefinition (`POST /fhir/ViewDefinition/{id}/$materialize`)
4. Delete and recreate the destination to pick up the new schema

Existing rows will have `NULL` in the new column. New rows will include the new data.

## Troubleshooting

### Common Issues

1. **Authentication errors**: Verify the Service Account JSON key is valid and has the required IAM roles, or check that ADC is properly configured
2. **Table not found**: Ensure the BigQuery table exists and the project/dataset/table names are correct
3. **Schema mismatch**: The BigQuery table columns must match the ViewDefinition output columns plus `is_deleted`
4. **Initial export timeout**: For large datasets, the initial export may take time. Monitor progress via `$status`
5. **Duplicate rows after recreating destination**: Deleting and recreating a destination triggers initial export again, adding duplicate rows to BigQuery. To avoid this, set `skipInitialExport: true` when recreating a destination that already has its data exported

### Debug Tips

- Check the `$status` endpoint for error details
- Verify ViewDefinition works correctly: `GET /fhir/ViewDefinition/patient_flat`
- Test BigQuery access independently using the same Service Account
- Check Aidbox logs for detailed error messages

## Related Documentation

- [ViewDefinitions](../../modules/sql-on-fhir/defining-flat-views-with-view-definitions.md)
- [`$materialize` operation](../../modules/sql-on-fhir/operation-materialize.md)
- [Topic-based Subscriptions](../../modules/topic-based-subscriptions/README.md)
- [BigQuery Storage Write API](https://cloud.google.com/bigquery/docs/write-api)
