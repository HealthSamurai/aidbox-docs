---
description: Async bulk export of a ViewDefinition's materialized rows to a backend-provided sink (Databricks Delta, etc.)
---

# $viewdefinition-export operation

{% hint style="info" %}
Available in Aidbox versions **2605** and later. Requires **fhir-schema mode**. Implements [SQL-on-FHIR v2 `$viewdefinition-export`](https://build.fhir.org/ig/FHIR/sql-on-fhir-v2/OperationDefinition-ViewDefinitionExport.html).
{% endhint %}

Exports ViewDefinition results to a destination. Use `kind` to choose the Aidbox module backend.

## Registered backends

| `kind`           | Sink                                         | Module                                                                                                    |
| ---------------- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `data-lakehouse` | Databricks Unity Catalog managed Delta table | [Data Lakehouse module](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) |

## Databricks Delta table

{% hint style="warning" %}
The Databricks-side setup (catalog, schema, target table, staging schema, service principal, grants, warehouse) must be in place **before** you kick off an export. The [Data Lakehouse tutorial](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) documents it, and the same setup applies here.
{% endhint %}

### Kick-off

```http
POST /fhir/ViewDefinition/$viewdefinition-export
Content-Type: application/fhir+json
Prefer: respond-async

{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "view",
     "part": [{"name": "name",          "valueString": "patient_flat"},
              {"name": "viewReference", "valueReference": {"reference": "ViewDefinition/patient_flat"}}]},
    {"name": "kind",      "valueString": "data-lakehouse"},

    {"name": "writeMode",              "valueString": "managed-zerobus"},
    {"name": "databricksWorkspaceUrl", "valueString": "https://xxx.cloud.databricks.com"},
    {"name": "databricksWorkspaceId",  "valueString": "xxx"},
    {"name": "databricksRegion",       "valueString": "xxx"},
    {"name": "tableName",              "valueString": "xxx.xxx.patient_flat"},
    {"name": "databricksWarehouseId",  "valueString": "xxx"},
    {"name": "awsRegion",              "valueString": "xxx"},
    {"name": "stagingTablePath",       "valueString": "s3://xxx/staging/patient_flat/"},
    {"name": "chunkCount",             "valueUnsignedInt": 1},

    {"name": "_since", "valueInstant": "2026-01-01T00:00:00Z"}
  ]
}
```

Response:

```
202 Accepted
Content-Location: /fhir/ViewDefinition/$viewdefinition-export/status/<export-id>

{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "exportId", "valueString": "<uuid>"},
    {"name": "status",   "valueCode":   "in-progress"},
    {"name": "location", "valueUri":    "/fhir/ViewDefinition/$viewdefinition-export/status/<uuid>"}
  ]
}
```

### Spec parameters

<table>
<thead>
<tr><th width="230">Parameter</th><th width="110">Required</th><th>Notes</th></tr>
</thead>
<tbody>
<tr><td><code>view</code></td><td>yes</td><td>Exactly one entry. <code>viewReference</code> must point at a server-stored ViewDefinition. Inline <code>viewResource</code> is not yet supported.</td></tr>
<tr><td><code>kind</code></td><td>yes</td><td>Selects the backend (e.g. <code>data-lakehouse</code>).</td></tr>
<tr><td><code>clientTrackingId</code></td><td>no</td><td>Echoed back in the status response.</td></tr>
<tr><td><code>_format</code></td><td>no</td><td><code>ndjson</code>, <code>parquet</code>, <code>json</code>, or omitted. Ignored: the backend picks the sink format (Delta for <code>kind=data-lakehouse</code>).</td></tr>
<tr><td><code>header</code></td><td>no</td><td>Echoed; not meaningful for non-CSV sinks.</td></tr>
<tr><td><code>_since</code></td><td>no</td><td>ISO-8601 instant. Filters the source view by its timestamp column (the column whose ViewDefinition path is <code>getAidboxTs()</code>). 400 <code>:no-timestamp-column</code> if <code>_since</code> is set but the view exposes no such column. See <a href="#_since-incremental-export"><code>_since</code> (incremental export)</a>.</td></tr>
<tr><td><code>patient</code> (0..*)</td><td>no</td><td>List of Patient references. Accepted but <strong>not yet applied</strong>; the module exports the full view.</td></tr>
<tr><td><code>group</code> (0..*)</td><td>no</td><td>List of Group references. Same status as <code>patient</code>.</td></tr>
<tr><td><code>source</code></td><td>no</td><td>External data source URI. <strong>Not supported</strong>; the server rejects it.</td></tr>
</tbody>
</table>

### Data Lakehouse backend parameters

<table>
<thead>
<tr><th width="230">Parameter</th><th width="110">Required</th><th>Notes</th></tr>
</thead>
<tbody>
<tr><td><code>writeMode</code></td><td>yes</td><td><code>managed-zerobus</code> (default; REST row-insert) or <code>managed-sql</code> (SQL warehouse INSERT).</td></tr>
<tr><td><code>tableName</code></td><td>yes</td><td>Managed UC table full name <code>catalog.schema.table</code>.</td></tr>
<tr><td><code>databricksWorkspaceUrl</code></td><td>yes</td><td><code>https://&lt;workspace&gt;.cloud.databricks.com</code>.</td></tr>
<tr><td><code>databricksWorkspaceId</code></td><td>yes</td><td>Numeric workspace id (for Zerobus URL).</td></tr>
<tr><td><code>databricksRegion</code></td><td>yes</td><td>Workspace AWS region.</td></tr>
<tr><td><code>databricksWarehouseId</code></td><td>yes</td><td>SQL warehouse id. Used at setup for schema sync and at finalize for the MERGE.</td></tr>
<tr><td><code>awsRegion</code></td><td>yes</td><td>AWS region of the S3 staging bucket.</td></tr>
<tr><td><code>stagingTablePath</code></td><td>yes</td><td><code>s3://bucket/staging/&lt;table&gt;/</code>. Must start with <code>s3://</code> or <code>s3a://</code>.</td></tr>
<tr><td><code>chunkCount</code></td><td>no</td><td>Positive integer (default 1). Splits the export into N per-chunk staging tables and N concurrent writers. See <a href="#large-scale-and-multi-pod-execution">Large-scale and multi-pod execution</a> for sizing.</td></tr>
</tbody>
</table>

The module reads OAuth M2M credentials from Aidbox-wide settings: the [`BOX_DATABRICKS_DATA_LAKEHOUSE_CLIENT_ID` and `_CLIENT_SECRET`](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md#export-the-service-principal-credentials) env vars or the corresponding settings registry entries. Per-request parameters do NOT accept them. See the [Data Lakehouse tutorial](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) for the full Databricks-side setup.

### Status polling

```http
GET /fhir/ViewDefinition/$viewdefinition-export/status/<export-id>
```

Response codes:

- `202 Accepted`: still in progress. The server returns the same `Content-Location` so the client can keep polling.
- `200 OK`: terminal. Body is a `Parameters` resource with the final shape (`status=completed`, `status=failed`, or `status=cancelled`, plus `output[].location` on success).
- `404 Not Found`: unknown `export-id`.

Completed output for `kind=data-lakehouse`:

```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "exportId", "valueString": "<uuid>" },
    { "name": "status", "valueCode": "completed" },
    { "name": "clientTrackingId", "valueString": "..." },
    { "name": "exportStartTime", "valueInstant": "2026-05-22T00:00:00Z" },
    { "name": "exportEndTime", "valueInstant": "2026-05-22T00:01:30Z" },
    {
      "name": "output",
      "part": [
        { "name": "name", "valueString": "patient_flat" },
        {
          "name": "location",
          "valueUri": "databricks-uc:catalog.schema.patient_flat"
        }
      ]
    }
  ]
}
```

### Cancellation

```http
DELETE /fhir/ViewDefinition/$viewdefinition-export/status/<export-id>
```

Stops an in-flight export and triggers backend cleanup (the data-lakehouse backend drops per-chunk staging tables and recursively deletes the S3 staging prefixes it created, best-effort). Response codes:

- `202 Accepted`: cancel acknowledged, async cleanup running. Body reports `status=canceling`. Subsequent status polls return `200 OK` with `status=cancelled` once cleanup completes.
- `200 OK`: operation already terminal (`completed`, `failed`, or `cancelled`). DELETE is idempotent.
- `404 Not Found`: unknown `export-id`.

What cancellation does **not** do:

- It does not roll back rows already merged into the target managed table. The merge is the last step of finalize-export. If cancel arrives before finalize, no rows have landed; if after finalize, the operation is already terminal.
- It does not delete history rows of chunks that already completed.
- It does not hard-kill a running JVM task. Running chunks stop when they observe the cancel marker.

### Failure model

- **Input validation failures** (missing `view`, missing `kind`, multiple views, `source` set, etc.): synchronous `400 OperationOutcome` from the kick-off `POST`. The server does not allocate an `export-id`.
- **Backend-side failures**: async. Kick-off returns `202` with an `export-id`; status polling later reports `status=failed` with the error in the `error` parameter. Common causes:
  - **No backend registered for `kind`** (typo, module not deployed).
  - **Databricks auth** (bad `client-id` or `client-secret`).
  - **Missing target table** or **missing required parameter** (e.g., no `tableName`).
  - **Schema mismatch** the module can't auto-`ALTER`.

### How it works (`kind=data-lakehouse`)

![Bulk export flow: Aidbox writes per-chunk Delta stagings on S3, then issues one MERGE INTO target via the Databricks SQL warehouse, then drops the stagings.](../../../assets/aidbox-databricks-bulk.svg)

With `chunkCount = N` (default `N=1`), for each chunk the module creates a per-chunk external Delta staging table, fills it from the hash-partitioned `sof.<view>`, then runs a single `MERGE INTO target` to materialize the union into the managed target and drops every staging. Failed chunks retry with backoff; if retries are exhausted the operation reports `status=failed` and runs best-effort cleanup on the stagings.

{% hint style="info" %}
The `MERGE` is idempotent on `id`. A retried export after a lost response inserts nothing instead of duplicating. Your ViewDefinition must select an `id` column.
{% endhint %}

### Staging cleanup on S3

The module treats `stagingTablePath` as reusable scratch space:

- at setup, it recursively deletes the root `stagingTablePath` before chunk fan-out;
- before each chunk creates its staging table, it recursively deletes that chunk's sub-prefix;
- after successful finalize, it drops the per-chunk Unity Catalog staging tables and recursively deletes both the per-chunk prefixes and the root staging prefix;
- on cancellation and failed chunks, the module runs the same cleanup best-effort.

Two consequences worth knowing:

- **If you rotate `stagingTablePath` between runs** (for example, a date-stamped prefix), Aidbox can only clean the prefix used by the current run. Older prefixes are your responsibility.
- **Cleanup is best-effort.** If S3, Databricks credential vending, or grants fail during cleanup, the export still reports according to the data path result and logs the cleanup problem. A later run that reuses the same prefix retries at setup.
- **The auto-cleanup uses Unity Catalog `temporary-path-credentials`**, so the principal needs `EXTERNAL_USE_LOCATION` on the External Location that covers `stagingTablePath`. Without that grant the module skips cleanup and emits a `staging-s3-cleanup-skipped` event; the export itself still runs. See the [Data Lakehouse tutorial, Databricks-side setup](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md#databricks-side-setup) for the grant table.

## \_since (incremental export)

`_since` makes the export incremental. Instead of materializing the full view, the module filters the source query by the view's timestamp column.

**Which column it filters on.** The column in your ViewDefinition whose `path` is `getAidboxTs()` (this FHIRPath returns `meta.lastUpdated`). For example:

```json
{
  "resourceType": "ViewDefinition",
  "name": "patient_flat",
  "select": [
    {
      "column": [
        { "name": "id", "path": "id" },
        { "name": "ts", "path": "getAidboxTs()" },
        { "name": "family", "path": "name.family.first()" }
      ]
    }
  ]
}
```

Here `_since=2026-01-01T00:00:00Z` filters as `WHERE ts >= '2026-01-01T00:00:00Z'`.

**Failure mode.** If the ViewDefinition exposes no column whose path resolves to `getAidboxTs()`, kick-off fails synchronously with `400 OperationOutcome` and reason `:no-timestamp-column`. Either add such a column to the view or omit `_since`.

**Typical use case.** Cron-driven incremental exports. Persist the `exportEndTime` from the completed status response, then pass it as `_since` on the next kick-off. Each run materializes only rows changed since the previous run finished.

## Large-scale and multi-pod execution

Chunks run on **async-api**, so they distribute across every pod in the Aidbox cluster. Status polling and cancellation work from any pod. If a pod fails mid-chunk, another pod picks up the chunk.

### Capacity caps

Effective cluster-wide concurrent chunks is the smallest of three ceilings: the requested `chunkCount`, the total scheduler capacity across pods, and the total DB headroom across pods. The relevant per-pod knobs:

- [`scheduler-executor-threads`](../../reference/all-settings.md#scheduler-executor-threads): hard cap on async-api task execution per pod. Excess chunks wait in the async-api queue until a slot frees up.
- [`db.pool.maximum-pool-size`](../../reference/all-settings.md#db.pool.maximum-pool-size): chunks may claim at most `pool size − 4` slots per pod, because each running chunk holds a long-lived PostgreSQL cursor on `sof.<view>` for its entire lifetime. The other `4` slots stay reserved for normal request traffic, sender workers, status polling, and the async-api coordinator.

The kick-off handler validates only the receiving pod's `pool size − 4` and returns `400 parallelism-exceeds-pool` if `chunkCount` doesn't fit. It does **not** validate the scheduler-thread cap or the cluster-wide DB sum at kick-off; surplus chunks queue and the export runs slower than expected.

**Sizing rule of thumb:** start with `chunkCount = pods × 4`. To go higher, raise `scheduler-executor-threads` and `db.pool.maximum-pool-size` by the same factor on every pod; otherwise kick-off rejects the request or excess chunks queue.

### JVM heap

Each running chunk buffers a Parquet file in memory up to `targetFileSizeMb` (default 128 MiB) before flushing. Peak heap from staging buffers on a pod is roughly that times the number of chunks running on it. The default Aidbox heap fits a single-cursor (`chunkCount=1`) export. For higher parallelism, raise the JVM heap (via [`JAVA_OPTS`](../../reference/all-settings.md#java-opts)) or lower `targetFileSizeMb`.

## Differences vs `AidboxTopicDestination` initial export

Both flows produce the same output (flattened FHIR rows merged into a managed Delta table) and use the same parallelism sizing. They differ in **how you start them** and **where you read progress from**:

|                  | `$viewdefinition-export`                                             | `AidboxTopicDestination` initial export                                           |
| ---------------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| When it runs     | On demand, when you `POST` this operation                            | Once, when you create a destination with `skipInitialExport=false`                |
| Progress polling | `GET /fhir/ViewDefinition/$viewdefinition-export/status/<export-id>` | `GET /fhir/AidboxTopicDestination/<id>/$status`                                   |
| After completion | The operation is done. No follow-up writes.                          | The destination keeps streaming live FHIR changes into the same target table.     |

Use this operation for one-shot snapshots and backfills. Use the destination flow when you want the same initial fill **plus** continuous replication afterwards. For tutorial-specific operational notes on the destination flow, see [Large-scale initial export](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md#large-scale-initial-export).

## Limitations

- The Data Lakehouse backend's staging path supports **AWS S3 only** (`s3://...` and `s3a://...`).
- One `view` per request (spec allows `1..*`).
- `patient` and `group` filters extracted but not yet applied to the SQL.
- `estimatedTimeRemaining` is not computed.
