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
The Databricks-side setup (catalog, schema, target table, staging schema, service principal, grants, warehouse) must be in place **before** you kick off an export. It is documented in the [Data Lakehouse tutorial](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) — the same setup is reused here.
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
<tr><td><code>_format</code></td><td>no</td><td><code>ndjson</code>, <code>parquet</code>, <code>json</code>, or omitted. Functionally ignored — the sink format is determined by the backend (Delta for <code>kind=data-lakehouse</code>).</td></tr>
<tr><td><code>header</code></td><td>no</td><td>Echoed; not meaningful for non-CSV sinks.</td></tr>
<tr><td><code>_since</code></td><td>no</td><td>ISO-8601 instant. Filters the source view by its timestamp column (the column whose ViewDefinition path is <code>getAidboxTs()</code>). 400 <code>:no-timestamp-column</code> if <code>_since</code> is set but the view exposes no such column. See <a href="#_since-incremental-export"><code>_since</code> (incremental export)</a>.</td></tr>
<tr><td><code>patient</code> (0..*)</td><td>no</td><td>List of Patient references. Currently accepted but <strong>not yet applied</strong> — the full view is exported.</td></tr>
<tr><td><code>group</code> (0..*)</td><td>no</td><td>List of Group references. Same status as <code>patient</code>.</td></tr>
<tr><td><code>source</code></td><td>no</td><td>External data source URI. <strong>Not supported</strong> — rejected.</td></tr>
</tbody>
</table>

### Data Lakehouse backend parameters

<table>
<thead>
<tr><th width="230">Parameter</th><th width="110">Required</th><th>Notes</th></tr>
</thead>
<tbody>
<tr><td><code>writeMode</code></td><td>yes</td><td><code>managed-zerobus</code> (default — REST row-insert) or <code>managed-sql</code> (SQL warehouse INSERT).</td></tr>
<tr><td><code>tableName</code></td><td>yes</td><td>Managed UC table full name <code>catalog.schema.table</code>.</td></tr>
<tr><td><code>databricksWorkspaceUrl</code></td><td>yes</td><td><code>https://&lt;workspace&gt;.cloud.databricks.com</code>.</td></tr>
<tr><td><code>databricksWorkspaceId</code></td><td>yes</td><td>Numeric workspace id (for Zerobus URL).</td></tr>
<tr><td><code>databricksRegion</code></td><td>yes</td><td>Workspace AWS region.</td></tr>
<tr><td><code>databricksWarehouseId</code></td><td>yes</td><td>SQL warehouse id (used at setup for schema sync + at finalize for the MERGE).</td></tr>
<tr><td><code>awsRegion</code></td><td>yes</td><td>AWS region of the S3 staging bucket.</td></tr>
<tr><td><code>stagingTablePath</code></td><td>yes</td><td><code>s3://bucket/staging/&lt;table&gt;/</code> — must start with <code>s3://</code> or <code>s3a://</code>.</td></tr>
<tr><td><code>chunkCount</code></td><td>no</td><td>Positive integer (default 1). Splits the export into N per-chunk staging tables and N concurrent writers. See <a href="#large-scale-and-multi-pod-execution">Large-scale and multi-pod execution</a> for sizing.</td></tr>
</tbody>
</table>

OAuth M2M credentials are sourced from Aidbox-wide settings — `BOX_DATABRICKS_DATA_LAKEHOUSE_CLIENT_ID` / `_CLIENT_SECRET` env vars or the corresponding settings registry entries. They are NOT accepted as per-request parameters. See the [Data Lakehouse tutorial](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) for the full Databricks-side setup.

### Status polling

```http
GET /fhir/ViewDefinition/$viewdefinition-export/status/<export-id>
```

Response codes:

- `202 Accepted` — still in progress. The same `Content-Location` is returned so the client can keep polling.
- `200 OK` — terminal. Body is a `Parameters` resource with the final shape (`status=completed`, `status=failed`, or `status=cancelled`, plus `output[].location` on success).
- `404 Not Found` — unknown `export-id`.

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

- `202 Accepted` — cancel acknowledged, async cleanup running. Body reports `status=canceling`. Subsequent status polls return `200 OK` with `status=cancelled` once cleanup is done.
- `200 OK` — operation already terminal (`completed` / `failed` / `cancelled`). DELETE is idempotent.
- `404 Not Found` — unknown `export-id`.

What cancellation does **not** do:

- It does not roll back rows already merged into the target managed table. The merge is the last step of finalize-export — if cancel arrives before finalize, no rows have landed; if after finalize, the operation is already terminal.
- It does not delete history rows of chunks that already completed.
- It does not hard-kill an already executing JVM task. Running chunks stop cooperatively when they observe the cancel marker.

### Failure model

- **Input validation failures** (missing `view`, missing `kind`, multiple views, `source` set, etc.) — synchronous `400 OperationOutcome` from the kick-off `POST`. No `export-id` is allocated.
- **Backend-side failures** — async. Kick-off returns `202` with an `export-id`; status polling later reports `status=failed` with the error in the `error` parameter. Common causes:
  - **No backend registered for `kind`** (typo, module not deployed).
  - **Databricks auth** (bad `client-id` / `client-secret`).
  - **Missing target table** / **missing required parameter** (e.g., no `tableName`).
  - **Schema mismatch** the module can't auto-`ALTER`.

### How it works (`kind=data-lakehouse`)

![Bulk export flow: Aidbox writes per-chunk Delta stagings on S3, then issues one MERGE INTO target via the Databricks SQL warehouse, then drops the stagings.](../../../assets/aidbox-databricks-bulk.svg)

With `chunkCount = N` (default `N=1`), for each chunk the module creates a per-chunk external Delta staging table, fills it from the hash-partitioned `sof.<view>`, then a single `MERGE INTO target` materializes the union into the managed target and drops every staging. Failed chunks retry with backoff; if retries are exhausted the export is reported as `failed` and stagings are best-effort cleaned up.

{% hint style="info" %}
The `MERGE` is idempotent on `id` — a retried export after a lost response inserts nothing instead of duplicating. Your ViewDefinition must select an `id` column.
{% endhint %}

### Staging cleanup on S3

The module treats `stagingTablePath` as reusable scratch space:

- at setup, it recursively deletes the root `stagingTablePath` before chunk fan-out;
- before each chunk creates its staging table, it recursively deletes that chunk's sub-prefix;
- after successful finalize, it drops the per-chunk Unity Catalog staging tables and recursively deletes both the per-chunk prefixes and the root staging prefix;
- on cancellation and failed chunks, the same cleanup is attempted best-effort.

Two consequences worth knowing:

- **If you rotate `stagingTablePath` between runs** (for example, a date-stamped prefix), Aidbox can only clean the prefix used by the current run. Older prefixes are your responsibility.
- **Cleanup is best-effort.** If S3, Databricks credential vending, or grants fail during cleanup, the export still reports according to the data path result and logs the cleanup problem. A later run that reuses the same prefix will try again at setup.
- **The auto-cleanup uses Unity Catalog `temporary-path-credentials`**, so the principal needs `EXTERNAL_USE_LOCATION` on the External Location that covers `stagingTablePath`. Without that grant the cleanup is skipped and a `staging-s3-cleanup-skipped` event is logged; the export itself still runs. The same grant table is documented in the [Data Lakehouse tutorial — Databricks-side setup](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md#databricks-side-setup).

## \_since (incremental export)

`_since` turns the export into an incremental one: instead of materializing the entire view, the source query is filtered by the view's timestamp column.

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

**Typical use case.** Cron-driven incremental exports. Persist the `exportEndTime` from the completed status response, then pass it as `_since` on the next kick-off — each run materializes only rows changed since the previous run finished.

## Large-scale and multi-pod execution

Chunks run on **async-api**, so they distribute across every pod sharing the metastore. Status polling and cancellation answer from any pod — no kick-off-pod affinity, no client-side load-balancer pinning. A pod failure mid-chunk is recovered automatically via the task's heartbeat lapse — another pod re-leases it.

### Capacity caps

Effective cluster-wide concurrent chunks is bounded by the smallest of three ceilings:

$$
\text{concurrency} = \min\!\left(\,
  \text{chunkCount},\quad
  \sum_{\text{pods}} S,\quad
  \sum_{\text{pods}} \max(0, H - R)
\,\right)
$$

- $$S$$ — **[`scheduler-executor-threads`](../../reference/all-settings.md#scheduler-executor-threads)** per pod. This is the **hard per-pod cap** on async-api task execution. Excess chunks queue in `db_scheduler.scheduled_tasks` with `picked=false` and wait.
- $$H$$ — Aidbox DB pool size per pod: [`db.pool.maximum-pool-size`](../../reference/all-settings.md#db.pool.maximum-pool-size) (`BOX_DB_POOL_MAXIMUM_POOL_SIZE` / HikariCP `maximumPoolSize`).
- $$R$$ — DB connections reserved for normal Aidbox traffic, sender workers, status polling, and coordinator work. The current kick-off guard uses `R = 4`.

Each running chunk holds a long-lived PostgreSQL cursor connection while reading `sof.<view>`. It may also need short-lived DB work around task execution and status/cancel checks, so do not size chunk parallelism up to the full pool.

Treat this as a capacity upper bound, not a scheduling guarantee. It assumes the pods that share the metastore are equally eligible to run async-api tasks and have comparable DB pools.

The kick-off handler returns `400 parallelism-exceeds-pool` if the requested `chunkCount` exceeds the receiving pod's obvious DB-pool headroom (`H - 4`). The scheduler-thread cap and the summed cluster capacity are **not validated** at kick-off — if you exceed them, surplus chunks simply queue and the export runs slower than expected.

Concrete starting points:

| Cluster shape | Suggested `chunkCount` | Notes                                    |
| ------------- | ---------------------- | ---------------------------------------- |
| 1 pod         | `1` (default)          | Single-cursor sequential.                |
| 1 pod         | `4`                    | ~3-4x speedup vs single-cursor.          |
| 1 pod         | `8`                    | Watch PG read capacity and heap.         |
| 2-4 pods (HA) | `16`                   | Survives a pod restart mid-export.       |
| 4+ pods       | `32`                   | Cap by scheduler threads and DB pool.    |

Raise [`scheduler-executor-threads`](../../reference/all-settings.md#scheduler-executor-threads) in step with `chunkCount` if you want a single pod to run more than ~10 chunks in parallel — otherwise the surplus chunks just queue. Also raise [`db.pool.maximum-pool-size`](../../reference/all-settings.md#db.pool.maximum-pool-size) if the kick-off guard rejects the requested value.

### JVM heap

Each chunk worker holds a Kernel Parquet buffer in memory until it reaches `targetFileSizeMb` (default 128 MiB) and flushes a file. With `N` chunks running concurrently per pod, peak heap from staging buffers alone is roughly:

$$
\min(N, \text{scheduler-executor-threads}) \times \text{targetFileSizeMb}
$$

If you raise `chunkCount` beyond a few chunks per pod, bump JVM `-Xmx` proportionally (via [`JAVA_OPTS`](../../reference/all-settings.md#java-opts)) or lower `targetFileSizeMb`. The default Aidbox heap fits a single-cursor (`chunkCount=1`) export comfortably but is the first thing to OOM under aggressive parallelism. There is no warning at kick-off — the symptom is `java.lang.OutOfMemoryError: Java heap space` mid-export.

## Differences vs `AidboxTopicDestination` initial export

Both flows produce the same kind of output — flattened FHIR rows merged into a managed Delta table — and parallelism is sized the same way. They differ in **how you start them** and **where you read progress from**:

|                  | `$viewdefinition-export`                                             | `AidboxTopicDestination` initial export                                           |
| ---------------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| When it runs     | On demand — when you `POST` this operation                           | Automatically, once, when you create a destination with `skipInitialExport=false` |
| Progress polling | `GET /fhir/ViewDefinition/$viewdefinition-export/status/<export-id>` | `GET /fhir/AidboxTopicDestination/<id>/$status`                                   |
| After completion | The operation is done. No follow-up writes.                          | The destination keeps streaming live FHIR changes into the same target table.     |

Use this operation for one-shot snapshots and backfills. Use the destination flow when you want the same initial fill **plus** continuous replication afterwards. For tutorial-specific operational notes on the destination flow, see [Large-scale initial export](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md#large-scale-initial-export).

## Limitations

- The Data Lakehouse backend's staging path currently supports **AWS S3 only** (`s3://...` / `s3a://...`).
- One `view` per request (spec allows `1..*`).
- `patient` / `group` filters extracted but not yet applied to the SQL.
- `cancelUrl` (the spec's pointer to a cancel endpoint exposed in the kick-off response) is not yet returned. Cancellation itself works — `DELETE` on the status URL is supported (see [Cancellation](#cancellation) above).
- `estimatedTimeRemaining` is not computed.
