---
description: Export FHIR resources to Google BigQuery analytics using SQL-on-FHIR ViewDefinitions for real-time reporting.
---

# BigQuery AidboxTopicDestination

{% hint style="info" %}
This functionality is available starting from version 2603.
{% endhint %}

## Overview

The BigQuery Topic Destination module provides integration between Aidbox's topic-based subscriptions and Google BigQuery. It enables real-time export of FHIR resources from Aidbox to BigQuery in a flattened format using [ViewDefinitions](../../modules/sql-on-fhir/defining-flat-views-with-view-definitions.md) and SQL-on-FHIR technology.

Data is written to BigQuery using the [Storage Write API](https://cloud.google.com/bigquery/docs/write-api) (gRPC), which provides exactly-once delivery semantics and high throughput.

## Before you begin

- Make sure your Aidbox version is 2603 or newer
- Set up a local Aidbox instance using the getting started [guide](../../getting-started/run-aidbox-locally.md)
- Have a Google Cloud project with BigQuery enabled, or use the [BigQuery Emulator](#local-testing-with-bigquery-emulator) for local testing

## Setting up

1. Download the BigQuery module JAR file and place it next to your **docker-compose.yaml**:

   ```sh
   curl -O https://storage.googleapis.com/aidbox-modules/topic-destination-bigquery/topic-destination-bigquery-2603.jar
   ```

2. Edit your **docker-compose.yaml** and add these lines to the Aidbox service:

   ```yaml
   aidbox:
     volumes:
       - ./topic-destination-bigquery-2603.jar:/topic-destination-bigquery.jar
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

### Kubernetes

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
                https://storage.googleapis.com/aidbox-modules/topic-destination-bigquery/topic-destination-bigquery-2603.jar
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
          volumeMounts:
            - name: modules-volume
              mountPath: /modules
      volumes:
        - name: modules-volume
          emptyDir: {}
```

## Key Features

- **Real-time data export**: Automatically exports FHIR resources to BigQuery as they are created, updated, or deleted
- **Data flattening**: Uses ViewDefinitions to transform complex FHIR resources into flat, analytical-friendly tables
- **At-least-once delivery**: Persistent message queue with guaranteed delivery and batch processing
- **Initial export**: Automatically exports existing data when setting up a new destination
- **Storage Write API**: Uses BigQuery's gRPC-based Storage Write API for high throughput and exactly-once semantics
- **Monitoring**: Built-in metrics and status reporting via `$status` endpoint

## Configuration

### Parameters

| Parameter           | Type        | Required | Description                         |
| ------------------- | ----------- | -------- | ----------------------------------- |
| `projectId`         | string      | Yes      | Google Cloud project ID             |
| `dataset`           | string      | Yes      | BigQuery dataset name               |
| `destinationTable`  | string      | Yes      | Target table name in BigQuery       |
| `viewDefinition`    | string      | Yes      | Name of the ViewDefinition resource |
| `serviceAccountKey` | string      | Yes      | Google Service Account JSON key     |
| `batchSize`         | unsignedInt | Yes      | Number of messages per batch        |
| `sendIntervalMs`    | unsignedInt | Yes      | Maximum time between sends (ms)     |

### Optional Parameters

| Parameter              | Type   | Description                                                                        |
| ---------------------- | ------ | ---------------------------------------------------------------------------------- |
| `cloudSqlConnectionId` | string | BigQuery Connection ID for Cloud SQL federated query (initial export optimization) |
| `location`             | string | GCP location for the BigQuery Connection (default: `us`)                           |

## Usage Example: Patient Data Export

### Step 1: Create Subscription Topic

```yaml
POST /fhir/AidboxSubscriptionTopic
Content-Type: application/json

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

```yaml
POST /fhir/ViewDefinition
Content-Type: application/json

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

### Step 3: Materialize ViewDefinition

```yaml
POST /fhir/ViewDefinition/patient_flat/$materialize
Content-Type: application/json

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
The ViewDefinition must be materialized as a **view** (not a table). This is required for the BigQuery module to transform data correctly.
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

### Step 5: Create Service Account

1. Go to [Google Cloud IAM](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. Create a new Service Account
3. Grant it the **BigQuery Data Editor** role on your dataset
4. Create a JSON key and download it

### Step 6: Configure BigQuery Destination

```yaml
POST /fhir/AidboxTopicDestination
Content-Type: application/json

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
    {"name": "serviceAccountKey", "valueString": "{\"type\":\"service_account\",\"project_id\":\"...\"}"},
    {"name": "batchSize", "valueUnsignedInt": 50},
    {"name": "sendIntervalMs", "valueUnsignedInt": 5000}
  ]
}
```

{% hint style="info" %}
The `serviceAccountKey` parameter should contain the full JSON content of the Service Account key file as a string.
{% endhint %}

### Step 7: Verify

Create a test patient:

```yaml
POST /fhir/Patient
Content-Type: application/json

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

## Initial Export

When a new destination is created, the module automatically exports all existing data that matches the subscription topic. This ensures your BigQuery table has complete historical data.

The initial export process:

1. Reads existing data from PostgreSQL via the materialized ViewDefinition
2. Sends data to BigQuery in batches using the Storage Write API (pending mode)
3. Commits all data atomically — either all data appears or none
4. Reports progress via the `$status` endpoint

### Cloud SQL Optimization

If your Aidbox PostgreSQL database runs on [Google Cloud SQL](https://cloud.google.com/sql), you can speed up initial export using BigQuery's federated query feature. Add the `cloudSqlConnectionId` parameter:

```json
{"name": "cloudSqlConnectionId", "valueString": "your-connection-id"},
{"name": "location", "valueString": "us-central1"}
```

This allows BigQuery to read directly from Cloud SQL without routing data through the module.

## Monitoring

### Status Endpoint

```http
GET /fhir/AidboxTopicDestination/patient-bigquery/$status
```

Returns current metrics:

- `messagesDelivered` — total messages sent to BigQuery
- `messagesQueued` — messages waiting in queue
- `messagesInProcess` — messages currently being sent
- `messagesDeliveryAttempts` — total delivery attempts (including retries)
- `initialExportStatus` — `not_started`, `export-in-progress`, `completed`, or `failed`

## Data Transformation

The module automatically:

1. **Applies ViewDefinition**: Transforms each FHIR resource using the specified ViewDefinition SQL
2. **Adds deletion flag**: Sets `is_deleted = 0` for create/update, `is_deleted = 1` for delete operations
3. **Batches messages**: Groups messages according to `batchSize` and `sendIntervalMs` parameters

## Local Testing with BigQuery Emulator

You can test the BigQuery integration locally without a GCP account using the [BigQuery Emulator](https://github.com/goccy/bigquery-emulator).

### Start the Emulator

```yaml
# docker-compose.yaml
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

```yaml
POST /fhir/AidboxTopicDestination
Content-Type: application/json

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
    { "name": "projectId", "valueString": "test-project" },
    { "name": "dataset", "valueString": "test" },
    { "name": "destinationTable", "valueString": "patients" },
    { "name": "viewDefinition", "valueString": "patient_flat" },
    { "name": "batchSize", "valueUnsignedInt": 10 },
    { "name": "sendIntervalMs", "valueUnsignedInt": 100 },
    { "name": "emulatorUrl", "valueString": "http://bigquery:9050" },
    { "name": "emulatorGrpcHost", "valueString": "bigquery:9060" }
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

## Troubleshooting

### Common Issues

1. **Authentication errors**: Verify the Service Account JSON key is valid and has BigQuery Data Editor permissions
2. **Table not found**: Ensure the BigQuery table exists and the project/dataset/table names are correct
3. **Schema mismatch**: The BigQuery table columns must match the ViewDefinition output columns plus `is_deleted`
4. **Initial export timeout**: For large datasets, the initial export may take time. Monitor progress via `$status`

### Debug Tips

- Check the `$status` endpoint for error details
- Verify ViewDefinition works correctly: `GET /fhir/ViewDefinition/patient_flat`
- Test BigQuery access independently using the same Service Account
- Check Aidbox logs for detailed error messages

## Related Documentation

- [ViewDefinitions](../../modules/sql-on-fhir/defining-flat-views-with-view-definitions.md)
- [Topic-based Subscriptions](../../modules/topic-based-subscriptions/README.md)
- [BigQuery Storage Write API](https://cloud.google.com/bigquery/docs/write-api)
