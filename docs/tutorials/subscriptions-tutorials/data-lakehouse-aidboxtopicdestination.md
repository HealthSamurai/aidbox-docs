---
description: Export FHIR resources to a Data Lakehouse — Databricks Unity Catalog managed tables or non-managed external Delta tables on S3 / GCS / Azure ADLS — using SQL-on-FHIR ViewDefinitions.
---

# Data Lakehouse AidboxTopicDestination

{% hint style="info" %}
This functionality is available starting from Aidbox version **2605**.
{% endhint %}

This page sets up an `AidboxTopicDestination` that streams FHIR resource changes into Delta-Lake tables — Databricks-managed Unity Catalog tables, or external Delta tables on S3 / GCS / Azure ADLS that you own. Rows are flattened by a [ViewDefinition](../../modules/sql-on-fhir/defining-flat-views-with-view-definitions.md) so analytics consumers see columns, not nested FHIR JSON.

## Background

"Data Lakehouse" is the generic name for the destination category — a hybrid of object-storage data lake and warehouse, implemented here on top of the Delta Lake table format. Concretely the module writes Delta-formatted tables that can live on plain cloud object storage you own, or in Databricks Unity Catalog managed storage; either way the destination kind is the same (`data-lakehouse-at-least-once`).

If you're already comfortable with Databricks, Unity Catalog, and Delta Lake, skip to [Overview](#overview).

### Databricks

[Databricks](https://www.databricks.com/) is a managed analytics platform. For this tutorial you only need to think of it as **three things bundled together**:

1. **[Unity Catalog](https://docs.databricks.com/aws/en/data-governance/unity-catalog/)** — the metadata + governance layer. Unity Catalog knows about every catalog, schema, table, column, and grant in your workspace. It also issues short-lived cloud-storage credentials on demand ("vending") so external clients can write data without being given long-lived bucket keys.
2. **[SQL warehouse](https://docs.databricks.com/aws/en/compute/sql-warehouse/)** — a compute cluster that runs SQL queries against tables in your Unity Catalog. Usually you query it from the Databricks UI's SQL Editor; the module can drive it programmatically over an API.
3. **[Zerobus Ingest](https://docs.databricks.com/aws/en/ingestion/zerobus-overview)** — a push-based ingestion service that writes data directly into Unity Catalog Delta tables. Databricks exposes Zerobus via two transports — gRPC and REST. The Aidbox module uses the [REST endpoint](https://docs.databricks.com/aws/en/ingestion/zerobus-ingest): batches are POSTed as JSON arrays and Zerobus durably commits them to the managed Delta table on the Databricks side.

### Data lakehouse, and Delta Lake as its implementation

A **data lakehouse** is a hybrid of two older patterns:

- A **data lake** stores raw files (Parquet, JSON, CSV) on cheap object storage (S3, GCS, ADLS). Scalable and cheap, but no schema enforcement, no ACID transactions, no time travel.
- A **data warehouse** (Snowflake, Redshift, BigQuery) gives you ACID + schema + indexes — at the cost of a proprietary storage format you don't own.

A lakehouse is the lake side with the warehouse's guarantees bolted on: ACID, schema, and time travel **on plain Parquet files in your own bucket**. The thing doing that bolting is an **open table format** — and [Delta Lake](https://delta.io/) is the one this module uses. A Delta table is a directory on object storage:

```text
s3://bucket/prefix/my_table/
├── _delta_log/
│   ├── 00000000000000000000.json       ← transaction log: each commit is one JSON file
│   ├── 00000000000000000001.json
│   └── ...
├── part-00000-xxx.snappy.parquet       ← row data
├── part-00001-xxx.snappy.parquet
└── ...
```

The `_delta_log/` directory is the source of truth: readers replay it; writers append a new commit. Concurrent writers race on the next log filename — that's where Delta's ACID comes from.

### External vs managed tables

Unity Catalog tables come in two flavours:

|                                | **Managed**                                                          | **External**                                                          |
| ------------------------------ | -------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Status                         | Databricks' **default and recommended** table type                   | Use when you need files in your own bucket                            |
| Storage location               | Databricks-managed cloud storage (path picked by Unity Catalog)      | Your bucket — declared with `LOCATION 's3://...' / 'gs://...' / 'abfss://...'` at `CREATE TABLE` |
| Who owns the files             | Unity Catalog — manages read, write, storage, and optimization       | You — Unity Catalog manages metadata only                                        |
| `DROP TABLE`                   | Deletes the data                                                     | Drops metadata only — files stay in your bucket                       |
| Supported write paths from Aidbox | **Zerobus REST ingest** (Aidbox `managed-zerobus`), or **SQL warehouse INSERT** (Aidbox `managed-sql`) | **Direct Parquet + Delta commit** via STS-vended Unity Catalog creds (Aidbox `external-direct`) |
| External STS credential vending| Not available for managed targets (`EXTERNAL USE SCHEMA` is only grantable on external schemas) | Allowed if the principal has `EXTERNAL USE SCHEMA` on the schema      |
| Predictive Optimization        | Enabled by default for accounts created on or after **2024-11-11**; runs `OPTIMIZE` / `VACUUM` / `ANALYZE` automatically. Billed under the **Jobs Serverless** SKU. | **Not supported** — Predictive Optimization runs only on managed tables |
| Liquid Clustering              | Opt-in per table (automatic liquid clustering requires Predictive Optimization and is also opt-in) | Opt-in per table                                                      |

The "Supported write paths" row drives the module's three `writeMode` values — see [Overview](#overview) for the resulting write paths.

## Overview

The module exports FHIR resources from Aidbox to a Delta Lake table in a flattened format using [ViewDefinitions](../../modules/sql-on-fhir/defining-flat-views-with-view-definitions.md) (SQL-on-FHIR).

```mermaid
graph LR
    Client[User / FHIR API client]:::blue2
    Aidbox[Aidbox]:::blue2
    PG[(Aidbox PostgreSQL)]:::neutral2
    Mod[Data Lakehouse module]:::yellow2
    DBX[Databricks workspace]:::green2
    FS[(Cloud storage<br/>S3 / GCS / ADLS)]:::violet2

    Client -- FHIR POST / PUT / DELETE --> Aidbox
    Aidbox -- write resource +<br/>enqueue topic event --> PG
    Mod -- poll batch --> PG
    Mod -- REST ingest<br/>(managed-zerobus) --> DBX
    Mod -- SQL INSERT<br/>(managed-sql) --> DBX
    Mod -- Delta write<br/>(external-direct) --> FS
    DBX -- read / write Delta files --> FS
```

The flow:

1. A FHIR API client (a user, an integration, a backfill script) sends a `POST` / `PUT` / `DELETE` to Aidbox.
2. Aidbox persists the resource and enqueues a topic event for the destination in PostgreSQL.
3. The Data Lakehouse module polls the destination's batch from the same PostgreSQL queue.
4. For `managed-zerobus` mode (default): the module POSTs each batch as a JSON array to Databricks' Zerobus REST ingest endpoint, which writes directly to the managed table. No SQL parsing / planning per write.
5. For `managed-sql` mode: the module sends `INSERT` (and `ALTER` / `DESCRIBE` when needed) to the Databricks SQL warehouse; the warehouse writes the Delta files to storage.
6. For `external-direct` mode: the module gets short-lived storage credentials from Unity Catalog and writes Delta files directly to your bucket.

The module may also perform an initial export of pre-existing resources at first start — see [Initial export](#initial-export) for when this runs and how to skip it.

### Write modes

The module supports three **write modes**, picked per-destination via the `writeMode` parameter (see the [Configuration](#configuration) section below for the full parameter list).

### managed-zerobus mode (default)

`writeMode=managed-zerobus` targets a **Databricks Unity Catalog managed table** via the [Zerobus REST ingest endpoint](https://docs.databricks.com/aws/en/ingestion/zerobus-ingest).

```mermaid
graph LR
    A(FHIR resource POST / PUT / DELETE):::blue2
    B(Aidbox Topics API):::blue2
    C(PostgreSQL queue):::neutral2
    D(ViewDefinition flatten):::yellow2
    Z(Zerobus REST ingest):::green2
    T0(Unity Catalog managed Delta table):::violet2

    A --> B --> C --> D --> Z --> T0
```

- Each batch is JSON-encoded as an array and POSTed to the Zerobus REST endpoint with an OAuth M2M bearer. No SQL parsing, no warehouse cold-start.
- Initial bulk export uses a one-shot staging Delta table + `MERGE INTO` — same path as `managed-sql`.
- Schema sync at sender bootstrap hits the SQL warehouse once (`INFORMATION_SCHEMA.COLUMNS` + optional `ALTER TABLE`); live writes don't.

### managed-sql mode

`writeMode=managed-sql` — same target as `managed-zerobus` (Unity Catalog **managed** table), but routes incoming batches through a Databricks SQL warehouse. Use this when Zerobus isn't available on your Databricks SKU.

```mermaid
graph LR
    A(FHIR resource POST / PUT / DELETE):::blue2
    B(Aidbox Topics API):::blue2
    C(PostgreSQL queue):::neutral2
    D(ViewDefinition flatten):::yellow2
    M(Databricks SQL warehouse):::green2
    T1(Unity Catalog managed Delta table):::violet2

    A --> B --> C --> D --> M --> T1
```

- Each batch becomes a single `INSERT INTO managed (cols) VALUES (...)` against the SQL warehouse.
- Initial bulk export uses a one-shot staging Delta table + `MERGE INTO`. See [Initial export](#how-it-works-managed-modes).

### external-direct mode

`writeMode=external-direct` targets a **non-managed external Delta table** that you own.

```mermaid
graph LR
    A(FHIR resource POST / PUT / DELETE):::blue2
    B(Aidbox Topics API):::blue2
    C(PostgreSQL queue):::neutral2
    D(ViewDefinition flatten):::yellow2
    K(Direct Delta writer):::green2
    T2(External Delta table on S3 / GCS / ADLS):::violet2

    A --> B --> C --> D --> K --> T2
```

- The module writes Delta files straight to your bucket from the Aidbox process. No SQL warehouse, no Databricks compute on the write path.
- Storage backends: AWS S3, Google Cloud Storage, Azure ADLS Gen2.
- You own table maintenance — schedule `OPTIMIZE` and `VACUUM` yourself. See [Compaction and maintenance](#compaction-and-maintenance).

## Choosing between the three modes

**Default to `managed-zerobus`.** Pick a different mode only when one of these applies:

- **Zerobus isn't available on your Databricks SKU** → `managed-sql`. Same managed target, but every batch hits a warm SQL warehouse.
- **You want the files in your own bucket and own table maintenance yourself** → `external-direct`. No Databricks compute on the write path.

|                                | `managed-zerobus` (default)                                              | `managed-sql`                                                            | `external-direct`                                            |
| ------------------------------ | ------------------------------------------------------------------------ | ------------------------------------------------------------------------ | ------------------------------------------------------------ |
| Table type                     | Unity Catalog **managed** (Databricks owns the files)                               | Unity Catalog **managed** (Databricks owns the files)                               | **External** (the User's bucket owns the files)              |
| Hot-path transport             | Zerobus REST ingest API                                                  | Databricks SQL warehouse (Statement Execution API)                       | Direct Delta commits via Hadoop FS                            |
| Who runs maintenance           | Databricks (Predictive Optimization handles `OPTIMIZE` / `VACUUM`)       | Databricks (Predictive Optimization handles `OPTIMIZE` / `VACUUM`)       | The User schedules `OPTIMIZE` / `VACUUM`                     |
| Databricks compute cost surface| **No warm warehouse** — pay-per-row Zerobus + storage only               | SQL warehouse must be running to accept INSERTs — Databricks bills uptime | No warehouse — no Databricks compute charge for write path   |
| Schema drift handling          | Auto-`ALTER` on mismatch                                                 | Auto-`ALTER` on mismatch                                                 | User runs `ALTER TABLE` and recreates the destination        |
| Initial export path            | Staging Delta on your bucket → `MERGE INTO` target                       | Staging Delta on your bucket → `MERGE INTO` target                       | Bulk written straight to the target in one Delta commit      |
| Storage backends               | Databricks-managed storage                                                | Databricks-managed storage                                                | AWS S3, GCS, Azure ADLS Gen2                                  |

## Authentication

All three modes authenticate to Databricks via [**OAuth Machine-to-Machine (M2M)**](https://docs.databricks.com/aws/en/dev-tools/auth/oauth-m2m) with a service principal: the module exchanges `client_id` + `client_secret` at the workspace token endpoint for a ~1h bearer token, caches it, and re-issues a fresh one when fewer than 5 minutes remain.

The bearer is sent on every Databricks call. What differs between modes is which Databricks surfaces see it:

| Mode                        | Unity Catalog REST                                       | SQL warehouse                              | Other transport            | Who talks to storage                 |
|-----------------------------|-----------------------------------------------|--------------------------------------------|----------------------------|--------------------------------------|
| `managed-zerobus` (default) | only during initial-export (staging vending)  | bootstrap + initial-export only            | Zerobus REST (every batch) | Zerobus ingest service, Databricks-side |
| `managed-sql`               | only during initial-export (staging vending)  | every batch (`INSERT` / `ALTER` / `DESCRIBE`) | —                          | SQL warehouse compute                 |
| `external-direct`           | every cred-refresh (~45 min)                  | none                                       | —                          | sender process, with Unity-Catalog-vended STS    |

In `external-direct` you can also skip Databricks entirely and authenticate against the bucket with static AWS keys (`awsAccessKeyId` + `awsSecretAccessKey`) or the [AWS default provider chain](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/credentials-chain.html). The service principal and the grants it needs are set up in the [Usage example](#usage-example-patient-data-export) below.

## Installation

### Prerequisites

- Aidbox **2605** or newer ([install guide](../../getting-started/run-aidbox-locally.md))
- A Databricks workspace (Free Edition works for evaluation, paid for production)
- The [Databricks CLI](https://docs.databricks.com/aws/en/dev-tools/cli/install) installed locally (`brew install databricks/tap/databricks` on macOS) — every Databricks-side operation in the tutorial uses it
- AWS CLI (only for `managed-*` modes that do initial-export — for the staging bucket + IAM role)
- A SQL warehouse (skip only for `external-direct`)
- For `managed-zerobus`: Zerobus enabled on your SKU (Databricks Free Edition supports it; for paid plans confirm with Databricks support)
- For initial-export in the `managed-*` modes: an S3/GCS/ADLS bucket you control

The service principal that authenticates the module is created in step 3 of the usage example — you don't need it before you start.

### Docker Compose

1. Download the Databricks module JAR file and place it next to your **docker-compose.yaml**:

   ```sh
   curl -O https://storage.googleapis.com/aidbox-modules/topic-destination-deltalake/topic-destination-deltalake-2605.0.jar
   ```

2. Edit your **docker-compose.yaml** and add these lines to the Aidbox service:

   ```yaml
   aidbox:
     volumes:
       - ./topic-destination-deltalake-2605.0.jar:/topic-destination-deltalake.jar
       # ... other volumes ...
     environment:
       BOX_MODULE_LOAD: io.healthsamurai.topic-destination.data-lakehouse.core
       BOX_MODULE_JAR: "/topic-destination-deltalake.jar"
       BOX_FHIR_SCHEMA_VALIDATION: "true"
       # ... other environment variables ...
   ```

3. Start Aidbox:

   ```sh
   docker compose up
   ```

4. Verify the module is loaded. In Aidbox UI, go to **FHIR Packages** and check that the Delta Lake profile is present:
   `http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-dataLakehouseAtLeastOnceProfile`

{% hint style="info" %}
The profile URL above is a FHIR canonical identifier, not an HTTP endpoint. You can find it in the Aidbox UI under FHIR Packages.
{% endhint %}

### Kubernetes

For Kubernetes deployments, the module can be downloaded automatically using an init container:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aidbox
spec:
  template:
    spec:
      initContainers:
        - name: download-deltalake-module
          image: debian:bookworm-slim
          command:
            - sh
            - -c
            - |
              apt-get -y update && apt-get -y install curl
              curl -L -o /modules/topic-destination-deltalake.jar \
                https://storage.googleapis.com/aidbox-modules/topic-destination-deltalake/topic-destination-deltalake-2605.0.jar
              chmod 644 /modules/topic-destination-deltalake.jar
          volumeMounts:
            - mountPath: /modules
              name: modules-volume
      containers:
        - name: aidbox
          image: healthsamurai/aidboxone:edge
          env:
            - name: BOX_MODULE_LOAD
              value: "io.healthsamurai.topic-destination.data-lakehouse.core"
            - name: BOX_MODULE_JAR
              value: "/modules/topic-destination-deltalake.jar"
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

## Configuration

All requests in this tutorial use `Content-Type: application/json`.

{% tabs %}
{% tab title="managed-zerobus mode (default)" %}
**Required:**

<table>
<thead>
<tr><th width="230">Parameter</th><th width="110">Type</th><th>Description</th></tr>
</thead>
<tbody>
<tr><td><code>viewDefinition</code></td><td>string</td><td>The <code>name</code> field of the ViewDefinition resource (not <code>id</code>)</td></tr>
<tr><td><code>batchSize</code></td><td>unsignedInt</td><td>Rows per worker tick / batch commit</td></tr>
<tr><td><code>sendIntervalMs</code></td><td>unsignedInt</td><td>Max time between batched commits, in ms</td></tr>
<tr><td><code>databricksWorkspaceUrl</code></td><td>string</td><td><code>https://&lt;workspace&gt;.cloud.databricks.com</code></td></tr>
<tr><td><code>databricksWorkspaceId</code></td><td>string</td><td>Numeric workspace ID (e.g. <code>1234567890123456</code>). Composes the Zerobus REST endpoint host</td></tr>
<tr><td><code>databricksRegion</code></td><td>string</td><td>Workspace AWS region (e.g. <code>us-east-1</code>). Composes the Zerobus REST endpoint host</td></tr>
<tr><td><code>databricksClientId</code></td><td>string</td><td>Service principal <code>client_id</code> for OAuth M2M</td></tr>
<tr><td><code>databricksClientSecret</code></td><td>string</td><td>Service principal <code>client_secret</code>; supports vault refs</td></tr>
<tr><td><code>tableName</code></td><td>string</td><td>Managed table full name: <code>catalog.schema.table</code></td></tr>
<tr><td><code>databricksWarehouseId</code></td><td>string</td><td>SQL warehouse ID — used at bootstrap for schema sync + (if initial-export runs) the final <code>MERGE INTO</code>. No warm-warehouse traffic during live writes.</td></tr>
<tr><td><code>awsRegion</code></td><td>string</td><td>AWS region of the staging bucket</td></tr>
<tr><td><code>stagingTablePath</code></td><td>string</td><td><code>s3://bucket/path/</code> for the staging Delta table created during initial export. Required when <code>skipInitialExport</code> is not <code>true</code></td></tr>
</tbody>
</table>

<details>

<summary>Advanced parameters</summary>

<table>
<thead>
<tr><th width="230">Parameter</th><th width="110">Type</th><th>Description</th></tr>
</thead>
<tbody>
<tr><td><code>writeMode</code></td><td>string</td><td><code>managed-zerobus</code> (default), <code>managed-sql</code>, or <code>external-direct</code>. Omit to get <code>managed-zerobus</code></td></tr>
<tr><td><code>skipInitialExport</code></td><td>boolean</td><td>Skip initial export of existing data (default: <code>false</code>)</td></tr>
<tr><td><code>targetFileSizeMb</code></td><td>unsignedInt</td><td>Parquet target size during initial export (default: <code>128</code>)</td></tr>
</tbody>
</table>

</details>

{% endtab %}

{% tab title="managed-sql mode" %}
**Required:**

<table>
<thead>
<tr><th width="230">Parameter</th><th width="110">Type</th><th>Description</th></tr>
</thead>
<tbody>
<tr><td><code>writeMode</code></td><td>string</td><td>Must be <code>managed-sql</code> (otherwise the default <code>managed-zerobus</code> path is used)</td></tr>
<tr><td><code>viewDefinition</code></td><td>string</td><td>The <code>name</code> field of the ViewDefinition resource (not <code>id</code>)</td></tr>
<tr><td><code>batchSize</code></td><td>unsignedInt</td><td>Rows per worker tick / batch commit</td></tr>
<tr><td><code>sendIntervalMs</code></td><td>unsignedInt</td><td>Max time between batched commits, in ms</td></tr>
<tr><td><code>databricksWorkspaceUrl</code></td><td>string</td><td><code>https://&lt;workspace&gt;.cloud.databricks.com</code></td></tr>
<tr><td><code>databricksClientId</code></td><td>string</td><td>Service principal <code>client_id</code> for OAuth M2M</td></tr>
<tr><td><code>databricksClientSecret</code></td><td>string</td><td>Service principal <code>client_secret</code>; supports vault refs</td></tr>
<tr><td><code>tableName</code></td><td>string</td><td>Managed table full name: <code>catalog.schema.table</code></td></tr>
<tr><td><code>databricksWarehouseId</code></td><td>string</td><td>SQL warehouse ID</td></tr>
<tr><td><code>awsRegion</code></td><td>string</td><td>AWS region of the staging bucket</td></tr>
<tr><td><code>stagingTablePath</code></td><td>string</td><td><code>s3://bucket/path/</code> for the staging Delta table created during initial export. Required when <code>skipInitialExport</code> is not <code>true</code></td></tr>
</tbody>
</table>

<details>

<summary>Advanced parameters</summary>

<table>
<thead>
<tr><th width="230">Parameter</th><th width="110">Type</th><th>Description</th></tr>
</thead>
<tbody>
<tr><td><code>skipInitialExport</code></td><td>boolean</td><td>Skip initial export of existing data (default: <code>false</code>)</td></tr>
<tr><td><code>targetFileSizeMb</code></td><td>unsignedInt</td><td>Parquet target size during initial export (default: <code>128</code>)</td></tr>
</tbody>
</table>

</details>
{% endtab %}

{% tab title="external-direct mode" %}
**Required:**

<table>
<thead>
<tr><th width="230">Parameter</th><th width="110">Type</th><th>Description</th></tr>
</thead>
<tbody>
<tr><td><code>viewDefinition</code></td><td>string</td><td>The <code>name</code> field of the ViewDefinition resource (not <code>id</code>)</td></tr>
<tr><td><code>batchSize</code></td><td>unsignedInt</td><td>Rows per worker tick / batch commit</td></tr>
<tr><td><code>sendIntervalMs</code></td><td>unsignedInt</td><td>Max time between batched commits, in ms</td></tr>
<tr><td><code>writeMode</code></td><td>string</td><td>Must be <code>external-direct</code> (otherwise the default <code>managed-zerobus</code> path is used)</td></tr>
<tr><td><code>tablePath</code></td><td>string</td><td><code>s3://...</code> / <code>gs://...</code> / <code>abfss://...</code>. Required unless <code>databricksWorkspaceUrl</code> set (then resolved from Unity Catalog)</td></tr>
<tr><td><code>awsRegion</code></td><td>string</td><td>Required for real AWS / GovCloud (skip for MinIO / LocalStack)</td></tr>
</tbody>
</table>

<details>

<summary>Authentication parameters</summary>

Pick **one** of: Unity Catalog credential vending, static AWS keys, or default AWS provider chain.

<table>
<thead>
<tr><th width="230">Parameter</th><th width="80">Type</th><th>Description</th></tr>
</thead>
<tbody>
<tr><td><code>databricksWorkspaceUrl</code></td><td>string</td><td>If set: Unity Catalog credential vending; <code>databricksClientId</code> + <code>databricksClientSecret</code> + <code>tableName</code> must also be set</td></tr>
<tr><td><code>databricksClientId</code></td><td>string</td><td>SP <code>client_id</code> (required iff <code>databricksWorkspaceUrl</code> set)</td></tr>
<tr><td><code>databricksClientSecret</code></td><td>string</td><td>SP <code>client_secret</code>; supports vault refs (required iff <code>databricksWorkspaceUrl</code> set)</td></tr>
<tr><td><code>tableName</code></td><td>string</td><td>Unity Catalog <code>catalog.schema.table</code> (when using Unity Catalog credential vending)</td></tr>
<tr><td><code>awsAccessKeyId</code></td><td>string</td><td>Static IAM key (falls back to default provider chain when absent). Supports vault refs</td></tr>
<tr><td><code>awsSecretAccessKey</code></td><td>string</td><td>Static IAM secret. Supports vault refs</td></tr>
</tbody>
</table>

</details>

<details>

<summary>Advanced parameters</summary>

<table>
<thead>
<tr><th width="230">Parameter</th><th width="110">Type</th><th>Description</th></tr>
</thead>
<tbody>
<tr><td><code>skipInitialExport</code></td><td>boolean</td><td>Skip initial export of existing data (default: <code>false</code>)</td></tr>
<tr><td><code>targetFileSizeMb</code></td><td>unsignedInt</td><td>Parquet target size during initial export (default: <code>128</code>)</td></tr>
<tr><td><code>s3Endpoint</code></td><td>string</td><td>MinIO / LocalStack endpoint (forces path-style URLs)</td></tr>
</tbody>
</table>

</details>
{% endtab %}
{% endtabs %}

## Output semantics

How writes show up in your Delta table, and how to query the result.

### Append-only

Every change to a FHIR resource is written as a **new row** — there are no in-place UPDATEs or DELETEs:

- **Create** → new row with `is_deleted = 0`
- **Update** → new row with `is_deleted = 0` (old row remains)
- **Delete** → new row with `is_deleted = 1`

Example — a single patient created, updated twice, then deleted produces four rows with the same `id`:

| `id` | `ts` (`meta.lastUpdated`) | `gender` | `family_name` | `is_deleted` |
|------|-----|---------|--------|---|
| `p-1` | `2026-04-01T10:00:00Z` | `male`   | `Smith`        | `0` |
| `p-1` | `2026-04-02T08:00:00Z` | `male`   | `Smith-Jones`  | `0` |
| `p-1` | `2026-04-03T14:00:00Z` | `other`  | `Smith-Jones`  | `0` |
| `p-1` | `2026-04-04T09:00:00Z` | `other`  | `Smith-Jones`  | `1` |

Use [the read-time projection below](#querying-the-table) to collapse history to "latest row per id, excluding deleted".

### At-least-once delivery

Messages are persisted in a PostgreSQL queue and retried on failure. The three modes differ on the crash-between-commit-and-ack window:

- **`managed-zerobus`** — initial export is idempotent; live writes are at-least-once (REST has no offset / transaction id, so a replay re-inserts).
- **`managed-sql`** — initial export is idempotent; live writes are at-least-once (SQL `INSERT` has the same constraint).
- **`external-direct`** — idempotent for both. Each Delta commit carries a transaction id; replays are silently deduped.

### Querying the table

Because every change is written as a new row (and `managed-*` modes can deliver duplicates on crash-replay), querying the table directly returns full history plus possible dupes. Most analytics workloads (cohort builds, longitudinal queries, time-windowed aggregates) want exactly this — full event history is the point.

If your query needs "latest state per resource", one common SQL pattern is window-function dedup. Add a timestamp column to your ViewDefinition (e.g. `meta.lastUpdated` as `ts`) and:

```sql
SELECT * EXCEPT(rn) FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts DESC) AS rn
  FROM aidbox_export.fhir.patients
)
WHERE rn = 1 AND is_deleted = 0;
```

This is one example, not the only approach — wrap it in a Databricks SQL view if used frequently, or skip it entirely if your queries already aggregate over history.

## Usage example: patient data export

The example below uses `managed-zerobus` (the default). For non-default modes see [`managed-sql`](#alternative-managed-sql-configuration) or [`external-direct`](#alternative-external-direct-configuration).

Authenticate the [Databricks CLI](https://docs.databricks.com/aws/en/dev-tools/cli/install) once — **as your own user** (PAT or `databricks auth login`), not as the service principal. Every step below — `databricks catalogs / schemas / grants / storage-credentials / external-locations` and the SQL DDL — runs as your user. The service principal is only created so Aidbox can authenticate at runtime; it never logs into the CLI in this tutorial, and the only privileges it ever gets are the ones explicitly listed in the "Grant the service principal" step (never `CREATE_SCHEMA` / `CREATE_MANAGED_STORAGE` / `MANAGE`). The destination resource you'll POST to Aidbox later carries the SP's `databricksClientId` / `databricksClientSecret` separately.

```shell
export DATABRICKS_HOST=https://<your-workspace>.cloud.databricks.com
# Use either a PAT for your own user, or run `databricks auth login`
# for browser-based SSO.
export DATABRICKS_TOKEN=<your-pat>
```

The rest of the example references the names below via environment variables — override any of them before sourcing, and the commands stay copy-pasteable:

```shell
# Identifiers the example creates — pick your own.
export CATALOG=aidbox_export
export TARGET_SCHEMA=fhir
export STAGING_SCHEMA=fhir_staging
export TARGET_TABLE=patients

# AWS / staging bucket. STAGING_BUCKET is created in a later step.
export STAGING_BUCKET=<your-bucket-name>
export AWS_REGION=us-east-1

# Unity Catalog resource names created in later steps.
export STORAGE_CRED_NAME=aidbox_staging_cred
export EXTERNAL_LOCATION_NAME=aidbox_staging_loc
export IAM_ROLE_NAME=aidbox-staging-role
```

{% stepper %}
{% step %}
### Create the subscription topic

Declares which FHIR resource changes trigger the export. The destination resource (later step) references this topic by URL.

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

{% endstep %}

{% step %}
### Create + materialize the ViewDefinition

A [ViewDefinition](../../modules/sql-on-fhir/defining-flat-views-with-view-definitions.md) flattens each FHIR resource into a row using [FHIRPath](https://hl7.org/fhirpath/) expressions. **Decide the column shape here first** — the Databricks target table will be created to match exactly.

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

Then [materialize](../../modules/sql-on-fhir/operation-materialize.md) it as a database view in the `sof` schema — the module reads rows from `sof.patient_flat`:

```http
POST /fhir/ViewDefinition/patient_flat/$materialize

{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "type", "valueCode": "view"}
  ]
}
```

{% hint style="info" %}
Must be materialized as a **view**, not a table. Details in the [`$materialize` operation](../../modules/sql-on-fhir/operation-materialize.md) docs.
{% endhint %}

{% endstep %}

{% step %}
### Create the service principal and SQL warehouse

In the Databricks UI: **Settings → Identity and access → Service principals → Add**, then under that SP **Secrets → Generate secret**. Under **Compute → SQL Warehouses**, pick or create a Serverless warehouse.

```sh
export SP_CLIENT_ID=<sp-client-id>
export SP_CLIENT_SECRET=<sp-client-secret>
export WAREHOUSE_ID=<warehouse-id>
```

Grant the SP `Can use` on the warehouse:

```sh
databricks warehouses update-permissions "$WAREHOUSE_ID" --json '{
  "access_control_list": [
    {"service_principal_name": "'"$SP_CLIENT_ID"'", "permission_level": "CAN_USE"}
  ]
}'
```

{% endstep %}

{% hint style="info" %}
**Heads up on ordering.** The next four steps register an S3 bucket as an External Location in Unity Catalog. The catalog you create for the target table after that has to point its managed-storage root at a sub-prefix of that External Location — otherwise on Default-Storage workspaces (most Free Edition and recent paid accounts) `managed-zerobus` rejects writes with `Unsupported table kind. Tables created in default storage are not supported`. So infra-first, target-table-second.
{% endhint %}

{% step %}
### Create the S3 bucket

Use the same region as your Databricks workspace. The same bucket holds both the managed target's storage root and the initial-export staging area, under separate prefixes.

```sh
aws s3api create-bucket --bucket "$STAGING_BUCKET" --region "$AWS_REGION"
```

{% endstep %}

{% step %}
### Create the IAM role Databricks will assume

Substitutions:

- `<DATABRICKS_AWS_ACCOUNT_ID>`: Databricks' own AWS account — `414351767826` for commercial regions. For GovCloud see [Databricks docs](https://docs.databricks.com/aws/en/connect/unity-catalog/cloud-storage/storage-credentials#create-an-iam-role).
- `<YOUR_AWS_ACCOUNT_ID>`: `aws sts get-caller-identity --query Account --output text`.
- `<EXTERNAL_ID>` is a placeholder — Databricks will hand us the real value when we register the Storage Credential in the next step. We create the role with a placeholder first, then patch the trust policy after the Storage Credential gives us the real value.

```sh
aws iam create-role --role-name "$IAM_ROLE_NAME" \
  --assume-role-policy-document "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": [
      "arn:aws:iam::<DATABRICKS_AWS_ACCOUNT_ID>:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL",
      "arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/${IAM_ROLE_NAME}"
    ]},
    "Action": "sts:AssumeRole",
    "Condition": { "StringEquals": { "sts:ExternalId": "PLACEHOLDER" } }
  }]
}
EOF
)"

aws iam put-role-policy --role-name "$IAM_ROLE_NAME" --policy-name s3-access \
  --policy-document "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation","s3:GetLifecycleConfiguration","s3:PutLifecycleConfiguration"],
    "Resource": ["arn:aws:s3:::${STAGING_BUCKET}","arn:aws:s3:::${STAGING_BUCKET}/*"]
  }]
}
EOF
)"

export STAGING_ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" \
  --query 'Role.Arn' --output text)
```

{% endstep %}

{% step %}
### Register the Storage Credential in Unity Catalog

Create the credential first; Databricks generates the External ID we need for the trust policy:

```shell
export EXTERNAL_ID=$(databricks storage-credentials create "$STORAGE_CRED_NAME" \
  --json '{"aws_iam_role": {"role_arn": "'"$STAGING_ROLE_ARN"'"}}' \
  --skip-validation \
  | jq -r .aws_iam_role.external_id)
```

Patch the role's trust policy with the real External ID and validate:

```shell
aws iam update-assume-role-policy --role-name "$IAM_ROLE_NAME" \
  --policy-document "$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": [
      "arn:aws:iam::<DATABRICKS_AWS_ACCOUNT_ID>:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL",
      "arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/${IAM_ROLE_NAME}"
    ]},
    "Action": "sts:AssumeRole",
    "Condition": { "StringEquals": { "sts:ExternalId": "${EXTERNAL_ID}" } }
  }]
}
EOF
)"

sleep 10  # IAM propagation
databricks storage-credentials validate --storage-credential-name "$STORAGE_CRED_NAME"
```

Empty `results` means success.

{% endstep %}

{% step %}
### Register the External Location

Combines the Storage Credential with the bucket prefix Databricks is allowed to write into. We register the bucket **root** so the same External Location backs both the managed-catalog storage root and the staging-schema prefix:

```sh
databricks external-locations create "$EXTERNAL_LOCATION_NAME" \
  "s3://$STAGING_BUCKET/" "$STORAGE_CRED_NAME"
```

{% endstep %}

{% step %}
### Create the catalog and target schema

The catalog's `--storage-root` must sit inside the External Location you just registered. A managed catalog created without `--storage-root` falls back to the workspace's default-storage prefix on most modern workspaces, and `managed-zerobus` refuses to write into default storage with `Unsupported table kind` (error code 4024).

```sh
databricks catalogs create "$CATALOG" \
  --storage-root "s3://$STAGING_BUCKET/managed/"

databricks api post /api/2.0/sql/statements --json '{
  "warehouse_id": "'"$WAREHOUSE_ID"'",
  "wait_timeout": "30s",
  "statement": "CREATE SCHEMA '"$CATALOG.$TARGET_SCHEMA"'"
}'
```

{% endstep %}

{% step %}
### Create the managed Delta target table

Columns must match the ViewDefinition you created above, plus a mandatory `is_deleted INT`:

```sh
databricks api post /api/2.0/sql/statements --json '{
  "warehouse_id": "'"$WAREHOUSE_ID"'",
  "wait_timeout": "30s",
  "statement": "CREATE TABLE '"$CATALOG.$TARGET_SCHEMA.$TARGET_TABLE"' (id STRING, gender STRING, birth_date DATE, family_name STRING, given_name STRING, is_deleted INT) USING DELTA"
}'
```

{% hint style="warning" %}
`is_deleted INT` is mandatory — the module sets it to `0` for create/update, `1` for delete.
{% endhint %}

**Type mapping ViewDefinition → SQL:**

| FHIR / ViewDefinition type | Databricks SQL type |
| -------------------------- | ------------------- |
| `id`, `string`, `code`     | `STRING`            |
| `date`                     | `DATE`              |
| `dateTime`, `instant`      | `TIMESTAMP`         |
| `integer`, `positiveInt`   | `INT`               |
| `decimal`                  | `DOUBLE`            |
| `boolean`                  | `BOOLEAN`           |

{% hint style="info" %}
In both `managed-*` modes the module issues `ALTER TABLE ADD COLUMNS` automatically when the ViewDefinition gains columns. See [Schema evolution](#schema-evolution).
{% endhint %}

{% endstep %}

{% hint style="info" %}
**The next step sets up initial-bulk staging.** Skip it (and the staging-specific grants in the next-but-one step) if you only need new data going forward — the destination has a parameter that turns the backfill off. `external-direct` doesn't use staging either.
{% endhint %}

{% step %}
### Create the sibling staging schema

Module convention places initial-export staging tables in `<catalog>.<target-schema>_staging.<…>` — a sibling schema next to the target. For target `$CATALOG.$TARGET_SCHEMA.$TARGET_TABLE` that's `$CATALOG.$STAGING_SCHEMA`:

```sh
databricks schemas create "$STAGING_SCHEMA" "$CATALOG" \
  --storage-root "s3://$STAGING_BUCKET/staging/"
```

{% hint style="warning" %}
`--storage-root` is **not optional**. Omitting it creates a managed schema that later silently rejects the `EXTERNAL_USE_SCHEMA` grant the module needs. The CLI form is the only one that works — `CREATE SCHEMA … LOCATION '…'` via SQL is rejected.
{% endhint %}

Run this as the catalog owner — needs `CREATE_SCHEMA` on the catalog and `CREATE_MANAGED_STORAGE` on the External Location. Don't grant either to the runtime SP.

{% endstep %}

{% step %}
### Grant the service principal

Grant only the set matching your `writeMode`. The SP runs the module at request time; nothing in this set lets it create or destroy catalog-level resources.

{% tabs %}
{% tab title="managed-zerobus" %}
| Privilege | Granted on | Purpose |
|---|---|---|
| `USE_CATALOG` | the catalog | navigate the catalog |
| `USE_SCHEMA` | the target schema | resolve the target table |
| `SELECT`, `MODIFY` | the target table | `DESCRIBE` + initial-bulk `MERGE INTO` |
| `USE_SCHEMA`, `EXTERNAL_USE_SCHEMA`, `CREATE_TABLE` | the staging schema | resolve the sibling schema, vend STS for the staging table, and let the sender register it (initial-export only) |
| `READ_FILES`, `WRITE_FILES`, `CREATE_EXTERNAL_TABLE` | the External Location | write bulk Parquet via vended STS (initial-export only) |
| `CAN_USE` | the SQL warehouse | bootstrap schema-sync statements + initial-bulk `MERGE` (no warehouse traffic during live writes) — already granted in the SP/warehouse step |

```sh
databricks grants update catalog "$CATALOG" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["USE_CATALOG"]}]}'

databricks grants update schema "$CATALOG.$TARGET_SCHEMA" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["USE_SCHEMA"]}]}'

databricks grants update table "$CATALOG.$TARGET_SCHEMA.$TARGET_TABLE" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["SELECT","MODIFY"]}]}'

# initial-export only:
databricks grants update schema "$CATALOG.$STAGING_SCHEMA" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["EXTERNAL_USE_SCHEMA","USE_SCHEMA","CREATE_TABLE"]}]}'

databricks grants update external-location "$EXTERNAL_LOCATION_NAME" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["READ_FILES","WRITE_FILES","CREATE_EXTERNAL_TABLE"]}]}'
```
{% endtab %}

{% tab title="managed-sql" %}
Identical privilege set to `managed-zerobus` — the SQL warehouse is hit on every batch instead of only at bootstrap + initial-bulk:

| Privilege | Granted on | Purpose |
|---|---|---|
| `USE_CATALOG` | the catalog | navigate the catalog |
| `USE_SCHEMA` | the target schema | resolve the target table |
| `SELECT`, `MODIFY` | the target table | `DESCRIBE` + every-batch `INSERT` + initial-bulk `MERGE INTO` |
| `USE_SCHEMA`, `EXTERNAL_USE_SCHEMA`, `CREATE_TABLE` | the staging schema | resolve the sibling schema, vend STS for the staging table, and let the sender register it (initial-export only) |
| `READ_FILES`, `WRITE_FILES`, `CREATE_EXTERNAL_TABLE` | the External Location | write bulk Parquet via vended STS (initial-export only) |
| `CAN_USE` | the SQL warehouse | every-batch INSERT + bootstrap + initial-bulk — already granted in the SP/warehouse step |

```sh
databricks grants update catalog "$CATALOG" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["USE_CATALOG"]}]}'

databricks grants update schema "$CATALOG.$TARGET_SCHEMA" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["USE_SCHEMA"]}]}'

databricks grants update table "$CATALOG.$TARGET_SCHEMA.$TARGET_TABLE" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["SELECT","MODIFY"]}]}'

# initial-export only:
databricks grants update schema "$CATALOG.$STAGING_SCHEMA" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["EXTERNAL_USE_SCHEMA","USE_SCHEMA","CREATE_TABLE"]}]}'

databricks grants update external-location "$EXTERNAL_LOCATION_NAME" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["READ_FILES","WRITE_FILES","CREATE_EXTERNAL_TABLE"]}]}'
```
{% endtab %}

{% tab title="external-direct" %}
Different — `EXTERNAL_USE_SCHEMA` is on the **target's** schema (writes go directly), and you grant against the External Location backing the target's bucket prefix (which can be the same one you registered above if both target and staging live under the same bucket):

```sh
databricks grants update catalog "$CATALOG" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["USE_CATALOG"]}]}'

databricks grants update schema "$CATALOG.$TARGET_SCHEMA" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["USE_SCHEMA","EXTERNAL_USE_SCHEMA"]}]}'

databricks grants update table "$CATALOG.$TARGET_SCHEMA.$TARGET_TABLE" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["SELECT","MODIFY"]}]}'

databricks grants update external-location "$EXTERNAL_LOCATION_NAME" --json '{
  "changes":[{"principal":"'"$SP_CLIENT_ID"'","add":["READ_FILES","WRITE_FILES","CREATE_EXTERNAL_TABLE"]}]}'
```

{% hint style="warning" %}
`EXTERNAL_USE_SCHEMA` is **only grantable on external schemas** (their own `storage_root` set, no inherited managed location). UC managed schemas refuse this grant by design.
{% endhint %}
{% endtab %}
{% endtabs %}

{% endstep %}

{% step %}
### Configure the destination (`managed-zerobus`)

```http
POST /fhir/AidboxTopicDestination

{
  "resourceType": "AidboxTopicDestination",
  "id": "patient-databricks",
  "topic": "http://example.org/subscriptions/patient-updates",
  "kind": "data-lakehouse-at-least-once",
  "meta": {
    "profile": [
      "http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-dataLakehouseAtLeastOnceProfile"
    ]
  },
  "parameter": [
    {"name": "writeMode", "valueString": "managed-zerobus"},
    {"name": "databricksWorkspaceUrl", "valueString": "$DATABRICKS_HOST"},
    {"name": "databricksWorkspaceId", "valueString": "<workspace-id>"},
    {"name": "databricksRegion", "valueString": "$AWS_REGION"},
    {"name": "databricksClientId", "valueString": "$SP_CLIENT_ID"},
    {"name": "databricksClientSecret", "valueString": "$SP_CLIENT_SECRET"},
    {"name": "tableName", "valueString": "$CATALOG.$TARGET_SCHEMA.$TARGET_TABLE"},
    {"name": "databricksWarehouseId", "valueString": "$WAREHOUSE_ID"},
    {"name": "awsRegion", "valueString": "$AWS_REGION"},
    {"name": "stagingTablePath", "valueString": "s3://$STAGING_BUCKET/staging/$TARGET_TABLE/"},
    {"name": "viewDefinition", "valueString": "patient_flat"},
    {"name": "batchSize", "valueUnsignedInt": 50},
    {"name": "sendIntervalMs", "valueUnsignedInt": 5000}
  ]
}
```

{% hint style="info" %}
Aidbox does **not** interpolate the `$…` placeholders for you — substitute the real values (either inline, or by `envsubst`-ing the payload through `curl --data-binary` before POSTing). The workspace ID is the numeric one — find it in **Settings → Workspace → Workspace ID**, or in the `o=…` query parameter of the workspace URL: `https://<dbc-id>.cloud.databricks.com/?o=<workspace-id>`.
{% endhint %}

{% hint style="warning" %}
`stagingTablePath` must be a **sub-prefix** of the External Location you registered (here `s3://$STAGING_BUCKET/staging/`), not the root itself. Setting it equal to the External Location root or to the staging schema's `storage_root` makes Databricks refuse with `LOCATION_OVERLAP`. The sender writes the staging Delta directly at this path, so reserve a per-destination subdirectory like `staging/patient_flat/` or `staging/<destination-id>/`.
{% endhint %}

In production, resolve `databricksClientSecret` from Aidbox's [External Secrets](../../configuration/secret-files.md) instead of inlining it:

```json
{
  "name": "databricksClientSecret",
  "_valueString": {
    "extension": [
      {"url": "http://hl7.org/fhir/StructureDefinition/data-absent-reason", "valueCode": "masked"},
      {"url": "http://health-samurai.io/fhir/secret-reference", "valueString": "dbx-sp-secret"}
    ]
  }
}
```

`dbx-sp-secret` is a key from your `BOX_VAULT_CONFIG` mapping. Same pattern works for any other credential parameter.

{% endstep %}

{% step %}
### Verify

Create a test patient:

```http
POST /fhir/Patient

{
  "name": [{"use": "official", "family": "Smith", "given": ["John"]}],
  "gender": "male",
  "birthDate": "1990-01-15"
}
```

Then query your Databricks table to confirm the data arrived:

```sql
SELECT * FROM aidbox_export.fhir.patients;
```

You should see one row for John Smith. If you left `skipInitialExport` at its default (`false`), the table also contains a row for every pre-existing row in `sof.patient_flat`. Set `skipInitialExport: true` if you only want forward-going data.

{% endstep %}
{% endstepper %}

### Stopping the export

To stop exporting data, delete the `AidboxTopicDestination` resource:

```
DELETE /fhir/AidboxTopicDestination/patient-databricks
```

This stops the export and cleans up the internal message queue. Data already written to Databricks is not affected.

## Alternative: `managed-sql` configuration

If Zerobus isn't available on your Databricks SKU (older paid plans, some regions), set `writeMode=managed-sql`. Same managed Unity Catalog target, same staging-MERGE initial-export, but live per-batch writes go through a Databricks SQL warehouse instead of Zerobus REST.

The destination payload differs from the `managed-zerobus` example by dropping `databricksWorkspaceId` + `databricksRegion` and changing `writeMode`:

```http
POST /fhir/AidboxTopicDestination

{
  "resourceType": "AidboxTopicDestination",
  "id": "patient-databricks-sql",
  "topic": "http://example.org/subscriptions/patient-updates",
  "kind": "data-lakehouse-at-least-once",
  "meta": {
    "profile": [
      "http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-dataLakehouseAtLeastOnceProfile"
    ]
  },
  "parameter": [
    {"name": "writeMode", "valueString": "managed-sql"},
    {"name": "databricksWorkspaceUrl", "valueString": "$DATABRICKS_HOST"},
    {"name": "databricksClientId", "valueString": "$SP_CLIENT_ID"},
    {"name": "databricksClientSecret", "valueString": "$SP_CLIENT_SECRET"},
    {"name": "tableName", "valueString": "$CATALOG.$TARGET_SCHEMA.$TARGET_TABLE"},
    {"name": "databricksWarehouseId", "valueString": "$WAREHOUSE_ID"},
    {"name": "awsRegion", "valueString": "$AWS_REGION"},
    {"name": "stagingTablePath", "valueString": "s3://$STAGING_BUCKET/staging/$TARGET_TABLE/"},
    {"name": "viewDefinition", "valueString": "patient_flat"},
    {"name": "batchSize", "valueUnsignedInt": 50},
    {"name": "sendIntervalMs", "valueUnsignedInt": 5000}
  ]
}
```

The Databricks setup is identical to `managed-zerobus` — same catalog, schema, target table, warehouse, staging chain, SP, and grants. The warehouse simply ends up servicing every batch instead of only the bootstrap.

## Alternative: `external-direct` configuration

If you don't need Unity Catalog managed-table governance and want the highest throughput (direct-to-storage Parquet writes, zero Databricks compute cost), use `writeMode=external-direct`. The module commits Parquet + Delta transaction-log entries straight to your bucket via Unity Catalog credential vending.

### Setup differences from the managed modes

1. **Create the target schema as external**, not managed. `EXTERNAL USE SCHEMA` is grantable only on external schemas (their own `storage_root` set, no inherited managed location). On most Free Edition and recent paid workspaces (Default Storage enabled), a plain `CREATE SCHEMA $CATALOG.$TARGET_SCHEMA` produces a managed schema that silently refuses the grant later. Create it with an explicit storage root pointed at an External Location you own:

   ```sh
   databricks schemas create "$TARGET_SCHEMA" "$CATALOG" \
     --storage-root "s3://$STAGING_BUCKET/target/"
   ```

   This replaces the plain `CREATE SCHEMA` from the catalog/schema step above. The bucket prefix must be covered by an External Location with `READ_FILES, WRITE_FILES, CREATE_EXTERNAL_TABLE` granted to the SP — the same `$EXTERNAL_LOCATION_NAME` you registered for the managed modes is fine if both target and staging live under the same bucket.

2. **Create the table with `LOCATION`** so it's external:

   ```sh
   databricks api post /api/2.0/sql/statements --json '{
     "warehouse_id": "'"$WAREHOUSE_ID"'",
     "wait_timeout": "30s",
     "statement": "CREATE TABLE '"$CATALOG.$TARGET_SCHEMA.$TARGET_TABLE"' (id STRING, gender STRING, birth_date DATE, family_name STRING, given_name STRING, is_deleted INT) USING DELTA LOCATION '"'"'s3://'"$STAGING_BUCKET"'/target/'"$TARGET_TABLE"'/'"'"'"
   }'
   ```

3. **No warehouse needed at runtime** — writes don't go through SQL compute. (The warehouse is still needed once for the `CREATE TABLE` above.)

4. **Different grants** — `EXTERNAL USE SCHEMA` on the **target's** schema (now external thanks to step 1), and `READ FILES, WRITE FILES, CREATE EXTERNAL TABLE` on the External Location backing the target bucket. See the `external-direct` tab in [Grant the service principal](#grant-the-service-principal).

5. **No `stagingTablePath`** — initial export writes directly to the final external table; no intermediate staging.

6. **The User owns the schema** — there's no auto-`ALTER` in this mode. If you add a column to the ViewDefinition, you must `ALTER TABLE` yourself before recreating the destination, or initial validation will fail.

### Destination configuration

```http
POST /fhir/AidboxTopicDestination

{
  "resourceType": "AidboxTopicDestination",
  "id": "patient-databricks-external",
  "topic": "http://example.org/subscriptions/patient-updates",
  "kind": "data-lakehouse-at-least-once",
  "meta": {
    "profile": [
      "http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-dataLakehouseAtLeastOnceProfile"
    ]
  },
  "parameter": [
    {"name": "writeMode", "valueString": "external-direct"},
    {"name": "databricksWorkspaceUrl", "valueString": "$DATABRICKS_HOST"},
    {"name": "databricksClientId", "valueString": "$SP_CLIENT_ID"},
    {"name": "databricksClientSecret", "valueString": "$SP_CLIENT_SECRET"},
    {"name": "tableName", "valueString": "$CATALOG.$TARGET_SCHEMA.$TARGET_TABLE"},
    {"name": "awsRegion", "valueString": "$AWS_REGION"},
    {"name": "viewDefinition", "valueString": "patient_flat"},
    {"name": "batchSize", "valueUnsignedInt": 50},
    {"name": "sendIntervalMs", "valueUnsignedInt": 5000}
  ]
}
```

### Static AWS keys (no Unity Catalog vending)

`external-direct` can also write to a Delta table that isn't governed by Unity Catalog — for example, a bucket your own AWS account owns directly, or a MinIO / non-Databricks S3 deployment. Omit `databricksWorkspaceUrl` entirely and provide static AWS keys + `tablePath`:

```http
POST /fhir/AidboxTopicDestination

{
  "resourceType": "AidboxTopicDestination",
  "id": "patient-deltalake-s3",
  "topic": "http://example.org/subscriptions/patient-updates",
  "kind": "data-lakehouse-at-least-once",
  "meta": {
    "profile": [
      "http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-dataLakehouseAtLeastOnceProfile"
    ]
  },
  "parameter": [
    {"name": "writeMode", "valueString": "external-direct"},
    {"name": "tablePath", "valueString": "s3://my-bucket/patients/"},
    {"name": "awsRegion", "valueString": "us-east-1"},
    {"name": "awsAccessKeyId", "valueString": "<key>"},
    {"name": "awsSecretAccessKey", "valueString": "<secret>"},
    {"name": "viewDefinition", "valueString": "patient_flat"},
    {"name": "batchSize", "valueUnsignedInt": 50},
    {"name": "sendIntervalMs", "valueUnsignedInt": 5000}
  ]
}
```

You can also omit `awsAccessKeyId` / `awsSecretAccessKey` to fall back to the [AWS SDK default credentials provider chain](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/credentials-chain.html) — env vars, EC2 instance profile / ECS task role, EKS IRSA, or shared profile from `~/.aws/credentials`.

## Initial export

When a new destination is created with `skipInitialExport` not set to `true`, the module exports the **current state** of every row in `sof.<view>` — one row per resource the ViewDefinition matches.

- **Updates after destination creation** append a new row each (`POST` / `PUT` / `DELETE`), accumulating a full audit trail.
- **Pre-existing history is not exported.** Initial export reads each resource's current row from `sof.<view>`, not Aidbox's `_history` table. Run a one-off ETL from `_history` before destination creation if you need older versions.

To skip the initial export (e.g., the table is already populated or you only need forward-going data), add `skipInitialExport` to the destination's `parameter` array:

```json
{ "name": "skipInitialExport", "valueBoolean": true }
```

### How it works — managed modes

Initial bulk export uses a **staging table** as a relay: the module writes Parquet to an external Delta table at `stagingTablePath` (via UC credential vending), then `MERGE INTO` the managed target on `id`, then drops the staging table. Identical for `managed-zerobus` and `managed-sql`.

```mermaid
graph LR
    PG[(Aidbox PostgreSQL<br/>sof.&lt;view&gt;)]:::neutral2
    M[Aidbox sender]:::blue2
    Staging[Staging external Delta table<br/>on stagingTablePath]:::yellow2
    WH[Databricks SQL warehouse]:::green2
    Target[(Unity Catalog managed Delta target)]:::violet2

    M -- 1. read rows --> PG
    M -- 2. write Parquet + Delta commit<br/>via Unity-Catalog-vended STS --> Staging
    M -- 3. MERGE INTO target USING staging ON id<br/>WHEN NOT MATCHED THEN INSERT * --> WH
    WH -- 4. read --> Staging
    WH -- 5. write --> Target
    M -- 6. DROP TABLE staging --> WH
```

Steps in detail:

1. Register a temporary external Delta table at `stagingTablePath` with the same schema as `sof.<view>`.
2. Unity Catalog vends short-lived STS credentials for the staging path.
3. The module writes all `sof.<view>` rows to the staging path as one Delta commit.
4. The module issues `MERGE INTO {managed_target} USING {staging} ON t.id = s.id WHEN NOT MATCHED THEN INSERT *` against the SQL warehouse. The MERGE reads the staging Delta snapshot through the Delta protocol and inserts any rows whose `id` is not yet present in the target.
5. The module drops the staging table.

The whole sequence runs as one atomic operation from the destination's lifecycle perspective. On failure: best-effort drop of the staging table, retry up to 3 times with exponential backoff (1s → 2s → 4s).

{% hint style="info" %}
The MERGE is idempotent on `id` — a retried export after a lost response inserts nothing instead of duplicating. Your ViewDefinition must have an `id` column.
{% endhint %}

### How it works — `external-direct` mode

```mermaid
graph LR
    PG[(Aidbox PostgreSQL<br/>sof.&lt;view&gt;)]:::neutral2
    M[Aidbox sender]:::blue2
    Target[(External Delta target<br/>on S3 / GCS / ADLS)]:::violet2

    M -- 1. read rows --> PG
    M -- 2. write Parquet + Delta commit<br/>via Unity-Catalog-vended STS --> Target
```

No staging — the module writes `sof.<view>` rows straight to the external target table. All rows land in one Delta commit at the end, so consumers see either zero rows or the full historical batch (all-or-nothing visibility). Requires `EXTERNAL USE SCHEMA` so Unity Catalog will vend write credentials for the target.

## Monitoring

### Status endpoint

```
GET /fhir/AidboxTopicDestination/patient-databricks/$status
```

Returns a FHIR [Parameters](https://www.hl7.org/fhir/parameters.html) resource:

```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "status", "valueString": "active" },
    { "name": "messagesDelivered", "valueDecimal": 100 },
    { "name": "messagesQueued", "valueDecimal": 0 },
    { "name": "messagesInProcess", "valueDecimal": 0 },
    { "name": "messagesDeliveryAttempts", "valueDecimal": 100 },
    { "name": "initialExportStatus", "valueString": "completed" },
    { "name": "initialExportProgress_rowsSent", "valueDecimal": 100 }
  ]
}
```

- `messagesDelivered` — total messages sent to Databricks
- `messagesQueued` — messages waiting in the PG queue
- `messagesInProcess` — messages currently being sent
- `messagesDeliveryAttempts` — total delivery attempts (including retries)
- `initialExportStatus` — `not_started`, `export-in-progress`, `completed`, `skipped`, or `failed`
- `initialExportProgress_rowsSent` — number of rows sent during initial export

## Data transformation

The module automatically:

1. **Applies ViewDefinition**: Transforms each FHIR resource using the specified ViewDefinition SQL
2. **Adds deletion flag**: Sets `is_deleted = 0` for create/update, `is_deleted = 1` for delete operations
3. **Batches messages**: Groups messages according to `batchSize` and `sendIntervalMs` parameters
4. **Coerces types per write path**:
   - `managed-sql` / `external-direct` — Java SQL dates / timestamps are converted to ISO-8601 strings; the SQL warehouse (or the Delta-Kernel writer) parses them into `DATE` / `TIMESTAMP` columns.
   - `managed-zerobus` — dates are encoded as `int32` epoch-days, timestamps as `int64` epoch-microseconds, as required by the Zerobus REST wire format. ISO strings would be rejected with a `400` from the endpoint.

See [Output semantics](#output-semantics) for append-only behaviour, at-least-once delivery, and the recommended read-time dedup query.

## Compaction and maintenance

**Managed modes (`managed-zerobus` and `managed-sql`)** — Databricks runs maintenance for you:

- [Predictive Optimization](https://docs.databricks.com/aws/en/optimizations/predictive-optimization) is enabled by default for Databricks accounts created on or after **2024-11-11**. Older accounts can enable it manually at the catalog / schema level.
- When enabled, it runs `OPTIMIZE`, `VACUUM`, and `ANALYZE` in the background.
- Predictive Optimization runs against managed tables **only** and is billed under the **Jobs Serverless** SKU.

**`external-direct` mode** — you own the table and the maintenance:

- Predictive Optimization does **not** apply to external tables (Databricks restricts it to managed tables).
- Recommended pattern: schedule a [Databricks SQL Job](https://docs.databricks.com/aws/en/jobs/) running

  ```sql
  OPTIMIZE aidbox_export.fhir.patients;
  VACUUM   aidbox_export.fhir.patients RETAIN 168 HOURS;
  ```

## Schema evolution

### Managed modes (auto-heal)

Both `managed-zerobus` and `managed-sql` auto-`ALTER TABLE ADD COLUMNS` when the ViewDefinition has new columns. Triggered at sender start and on per-batch schema-mismatch (retried once).

To add a column:

1. Add the column to your ViewDefinition.
2. Re-materialize: `POST /fhir/ViewDefinition/{id}/$materialize`.
3. Either delete and recreate the destination, OR wait for the next write — auto-heal will catch it on the first batch.

Existing rows will have `NULL` in the new column.

{% hint style="warning" %}
The module only ADDS columns automatically. Column drops, renames, or narrowing type changes (e.g., `BIGINT` → `INT`) are not auto-applied — you must run the corresponding `ALTER TABLE` manually.
{% endhint %}

### `external-direct` mode (manual)

The User owns the external table schema. If the ViewDefinition adds a column without a matching `ALTER TABLE` on the Databricks side, the destination's healthcheck will **fail at startup** with a clear error message pointing at the missing column.

To add a column:

1. Run `ALTER TABLE aidbox_export.fhir.patients ADD COLUMNS (new_col STRING)` in Databricks SQL.
2. Add the column to your ViewDefinition.
3. Re-materialize: `POST /fhir/ViewDefinition/{id}/$materialize`.
4. Delete and recreate the destination.

## Multiple destinations

You can create multiple destinations for the same topic — for example, to mirror the same data into both a managed analytics table and an external archive table, or to use different ViewDefinitions for different downstream consumers. Each destination operates independently with its own queue, writer, and status.

## Retry behavior

- **Failed batch** — message stays in the PostgreSQL queue and retries on the next `sendIntervalMs` tick. 1-second backoff between failed attempts.
- **OAuth bearer token** — cached; auto-refreshed via `/oidc/v1/token` when the current one has under 5 minutes remaining.
- **Worker thread crash** — auto-restarts with exponential backoff (1s initial, 60s max). The queue ensures no messages are lost.
- **Initial export failure** — retries up to 3 times with `1s → 2s → 4s` backoff. After 3 failures, `initialExportStatus = failed`, error available via `$status`, live delivery continues unaffected, and recreating the destination kicks off a fresh attempt.

## Troubleshooting

### Common issues

1. **`EXTERNAL_WRITE_NOT_ALLOWED_FOR_TABLE`** (writeMode=external-direct against a managed table) — Unity Catalog vending refuses managed tables by design. Either recreate the table as external (with explicit `LOCATION '...'`), or switch the destination to `writeMode=managed`.
2. **`EXTERNAL_ACCESS_DISABLED_ON_METASTORE`** — your Unity Catalog metastore has external data access disabled (the Databricks Free Edition default). In Catalog Explorer → Metastore → enable **External data access**.
3. **`Privilege EXTERNAL USE SCHEMA is not applicable to this entity`** — you're trying to grant `EXTERNAL USE SCHEMA` on a managed schema. Either recreate the schema as external, or switch to `writeMode=managed`.
4. **`INSUFFICIENT_PRIVILEGES` on table or warehouse** — verify all grants in [Grant the service principal](#grant-the-service-principal). Don't forget `CAN_USE` on the warehouse.
5. **`DELTA_INSERT_COLUMN_ARITY_MISMATCH`** in managed mode — the module should auto-heal this once. If it persists, check that the schema diff is column-add only (drops / renames are not auto-applied).
6. **Schema mismatch in external-direct mode** — the module fails at startup with a clear message naming the missing columns. Run the corresponding `ALTER TABLE` and recreate the destination.
7. **Slow first write** — Serverless warehouses cold-start in 30-90s on first use after idle. The module's HTTP timeout is 120s for SQL Statement Execution and uses `wait_timeout=50s` polling, so cold starts succeed transparently but the first batch's latency is high. Keep the warehouse warm with a periodic ping if first-batch latency matters.
8. **Duplicate rows after recreating destination** — deleting and recreating a destination triggers initial export again. Set `skipInitialExport: true` when recreating a destination that already has its data exported.
9. **`LOCATION_OVERLAP` during initial export** — `stagingTablePath` either equals the staging schema's `storage_root` (which UC treats as the schema's own managed location) or doesn't sit under your External Location. Set it to a sub-prefix of the External Location, e.g. `s3://<bucket>/staging/patient_flat/`, not the External Location root itself.
10. **`Unsupported table kind. Tables created in default storage are not supported` (Zerobus error 4024)** — the catalog backing your target table was created without `--storage-root`, so Unity Catalog placed it in the workspace's default-storage prefix. `managed-zerobus` refuses to write into default storage. Recreate the catalog with `databricks catalogs create <name> --storage-root s3://<bucket>/managed/` pointing inside a registered External Location (see [Create the catalog and target schema](#create-the-catalog-and-target-schema) in the usage example).

## Related documentation

- [ViewDefinitions](../../modules/sql-on-fhir/defining-flat-views-with-view-definitions.md)
- [`$materialize` operation](../../modules/sql-on-fhir/operation-materialize.md)
- [Topic-based Subscriptions](../../modules/topic-based-subscriptions/README.md)
- [External Secrets (Vault)](../../configuration/secret-files.md) — storing sensitive parameters like `databricksClientSecret` as file-backed secrets
- [HashiCorp Vault Integration](../../tutorials/other-tutorials/hashicorp-vault-external-secrets.md) — step-by-step tutorial for Kubernetes with Secrets Store CSI Driver
- [Azure Key Vault Integration](../../tutorials/other-tutorials/azure-key-vault-external-secrets.md) — step-by-step tutorial for AKS with Azure Key Vault
- [Databricks: Predictive Optimization](https://docs.databricks.com/aws/en/optimizations/predictive-optimization)
- [Databricks: Unity Catalog managed tables](https://docs.databricks.com/aws/en/tables/managed)
- [Databricks: Statement Execution API](https://docs.databricks.com/api/workspace/statementexecution)
- [Delta Lake protocol](https://github.com/delta-io/delta/blob/master/PROTOCOL.md)
