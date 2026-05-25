---
description: Async bulk export of a ViewDefinition's materialized rows to a backend-provided sink (Databricks Delta, etc.)
---
# $viewdefinition-export operation

{% hint style="info" %}
Available in Aidbox versions **2605** and later. Requires **fhir-schema mode**. Implements [SQL-on-FHIR v2 `$viewdefinition-export`](https://build.fhir.org/ig/FHIR/sql-on-fhir-v2/OperationDefinition-ViewDefinitionExport.html).
{% endhint %}

Exports a ViewDefinition's flattened rows into a sink (e.g. a Databricks Delta table). The backend is contributed by an Aidbox module; you pick it with the `kind` parameter.

Use this for one-shot snapshots, backfills, or ad-hoc dumps when standing up a streaming `AidboxTopicDestination` is overkill.

{% hint style="warning" %}
The Databricks-side setup (catalog, schema, target table, staging schema, service principal, grants, warehouse) must be in place **before** you kick off an export. It is documented in the [Data Lakehouse tutorial](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) — the same setup is reused here.
{% endhint %}

## Registered backends

| `kind` | Sink | Module |
|---|---|---|
| `data-lakehouse` | Databricks Unity Catalog managed Delta table | [Data Lakehouse module](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) |

## Kick-off

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

The `_since` line above requests an **incremental export**: only rows whose timestamp column changed at or after the given instant are materialized. Omit it for a full snapshot. See [`_since` (incremental export)](#_since-incremental-export) for details.

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

## Parameters

### Spec parameters

| Parameter | Required | Notes |
|---|---|---|
| `view` | yes | Exactly one entry. `viewReference` must point at a server-stored ViewDefinition. Inline `viewResource` is not yet supported. |
| `kind` | yes | Selects the backend (e.g. `data-lakehouse`). |
| `clientTrackingId` | no | Echoed back in the status response. |
| `_format` | no | `ndjson`, `parquet`, `json`, or omitted. Functionally ignored — the sink format is determined by the backend (Delta for `kind=data-lakehouse`). |
| `header` | no | Echoed; not meaningful for non-CSV sinks. |
| `_since` | no | ISO-8601 instant. Filters the source view by its timestamp column (the column whose ViewDefinition path is `getAidboxTs()`). 400 `:no-timestamp-column` if `_since` is set but the view exposes no such column. See [`_since` (incremental export)](#_since-incremental-export). |
| `patient` (0..\*) | no | List of Patient references. Currently accepted but **not yet applied** — the full view is exported. |
| `group` (0..\*) | no | List of Group references. Same status as `patient`. |
| `source` | no | External data source URI. **Not supported** — rejected. |

### Data Lakehouse backend parameters (`kind=data-lakehouse`)

| Parameter | Required | Notes |
|---|---|---|
| `writeMode` | yes | `managed-zerobus` (default — REST row-insert) or `managed-sql` (SQL warehouse INSERT). |
| `tableName` | yes | Managed UC table full name `catalog.schema.table`. |
| `databricksWorkspaceUrl` | yes | `https://<workspace>.cloud.databricks.com`. |
| `databricksWorkspaceId` | yes | Numeric workspace id (for Zerobus URL). |
| `databricksRegion` | yes | Workspace AWS region. |
| `databricksWarehouseId` | yes | SQL warehouse id (used at setup for schema sync + at finalize for the MERGE). |
| `awsRegion` | yes | AWS region of the S3 staging bucket. |
| `stagingTablePath` | yes | `s3://bucket/staging/<table>/` — must start with `s3://` or `s3a://`. |
| `chunkCount` | no | Positive integer (default 1). Splits the export into N per-chunk staging tables and N concurrent writers. See [Large-scale and multi-pod execution](#large-scale-and-multi-pod-execution) for sizing. |

OAuth M2M credentials are sourced from Aidbox-wide settings — `BOX_DATABRICKS_DATA_LAKEHOUSE_CLIENT_ID` / `_CLIENT_SECRET` env vars or the corresponding settings registry entries. They are NOT accepted as per-request parameters. See the [Data Lakehouse tutorial](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) for the full Databricks-side setup.

## Status polling

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
    {"name": "exportId", "valueString": "<uuid>"},
    {"name": "status",   "valueCode":   "completed"},
    {"name": "clientTrackingId", "valueString": "..."},
    {"name": "exportStartTime", "valueInstant": "2026-05-22T00:00:00Z"},
    {"name": "exportEndTime",   "valueInstant": "2026-05-22T00:01:30Z"},
    {"name": "output",
     "part": [{"name": "name",     "valueString": "patient_flat"},
              {"name": "location", "valueUri":    "databricks-uc:catalog.schema.patient_flat"}]}
  ]
}
```

The `output[].location` URI scheme is backend-specific (`databricks-uc:` for the data-lakehouse backend).

## Cancellation

```http
DELETE /fhir/ViewDefinition/$viewdefinition-export/status/<export-id>
```

Stops an in-flight export and triggers backend cleanup (the data-lakehouse backend drops per-chunk staging tables it created). Response codes:

- `202 Accepted` — cancel acknowledged, async cleanup running. Body reports `status=canceling`. Subsequent status polls return `200 OK` with `status=cancelled` once cleanup is done.
- `200 OK` — operation already terminal (`completed` / `failed` / `cancelled`). DELETE is idempotent.
- `404 Not Found` — unknown `export-id`.

What cancellation does **not** do:

- It does not roll back rows already merged into the target managed table. The merge is the last step of finalize-export — if cancel arrives before finalize, no rows have landed; if after finalize, the operation is already terminal.
- It does not delete history rows of chunks that already completed.

## Failure model

- **Input validation failures** (missing `view`, missing `kind`, multiple views, `source` set, etc.) — synchronous `400 OperationOutcome` from the kick-off `POST`. No `export-id` is allocated.
- **Backend-side failures** — async. Kick-off returns `202` with an `export-id`; status polling later reports `status=failed` with the error in the `error` parameter. Common causes:
  - **No backend registered for `kind`** (typo, module not deployed).
  - **Databricks auth** (bad `client-id` / `client-secret`).
  - **Missing target table** / **missing required parameter** (e.g., no `tableName`).
  - **Schema mismatch** the module can't auto-`ALTER`.

## How it works (`kind=data-lakehouse`)

![Bulk export flow: Aidbox writes per-chunk Delta stagings on S3, then issues one MERGE INTO target via the Databricks SQL warehouse, then drops the stagings.](../../../assets/aidbox-databricks-bulk.svg)

With `chunkCount = N` (default `N=1`), for each chunk the module creates a per-chunk external Delta staging table, fills it from the hash-partitioned `sof.<view>`, then a single `MERGE INTO target` materializes the union into the managed target and drops every staging. Failed chunks retry with backoff; if retries are exhausted the export is reported as `failed` and stagings are best-effort cleaned up.

{% hint style="info" %}
The `MERGE` is idempotent on `id` — a retried export after a lost response inserts nothing instead of duplicating. Your ViewDefinition must select an `id` column.
{% endhint %}

## `_since` (incremental export)

`_since` turns the export into an incremental one: instead of materializing the entire view, the source query is filtered by the view's timestamp column.

**Which column it filters on.** The column in your ViewDefinition whose `path` is `getAidboxTs()` (this FHIRPath returns `meta.lastUpdated`). For example:

```json
{
  "resourceType": "ViewDefinition",
  "name": "patient_flat",
  "select": [
    {"column": [
      {"name": "id", "path": "id"},
      {"name": "ts", "path": "getAidboxTs()"},
      {"name": "family", "path": "name.family.first()"}
    ]}
  ]
}
```

Here `_since=2026-01-01T00:00:00Z` filters as `WHERE ts >= '2026-01-01T00:00:00Z'`.

**Failure mode.** If the ViewDefinition exposes no column whose path resolves to `getAidboxTs()`, kick-off fails synchronously with `400 OperationOutcome` and reason `:no-timestamp-column`. Either add such a column to the view or omit `_since`.

**Typical use case.** Cron-driven incremental exports. Persist the `exportEndTime` from the completed status response, then pass it as `_since` on the next kick-off — each run materializes only rows changed since the previous run finished.

## Large-scale and multi-pod execution

Chunks run on **async-api** (Aidbox's db-scheduler-backed task engine), so they distribute across every pod sharing the metastore. Status polling and cancellation answer from any pod — no kick-off-pod affinity, no client-side load-balancer pinning. A pod failure mid-chunk is recovered automatically via the task's heartbeat lapse — another pod re-leases it.

### Capacity caps

Effective cluster-wide concurrent chunks = the smallest of three ceilings:

$$
\text{concurrency} = \min\!\left(\,
  \text{chunkCount},\quad
  \sum_{\text{pods}} S,\quad
  \frac{M - B}{2}
\,\right)
$$

- $$S$$ — **`scheduler-executor-threads`** per pod ([Aidbox setting](../../reference/all-settings.md#scheduler-executor-threads)). This is the **hard per-pod cap** on async-api task execution. Excess chunks queue in `db_scheduler.scheduled_tasks` with `picked=false` and wait. Default is small (≈10); bump it if you plan high `chunkCount`.
- $$M$$ — PostgreSQL `max_connections`.
- $$B$$ — connections Aidbox uses for normal traffic (HikariCP pool size × pod count).
- $$/2$$ — each chunk worker holds up to two PG connections (one cursor + one short-lived).

The kick-off handler returns `400 parallelism-exceeds-pool` if `chunkCount > (M − B) / 2` is obvious from settings, but the scheduler-thread cap is **not validated** at kick-off — the export simply runs slower than expected if you exceed it.

### Differences vs `AidboxTopicDestination` initial export

The continuous-destination init-export uses a **different code path** (raw `(future ...)` + PG advisory locks, not async-api) with `min(N, availableProcessors())` as the per-pod cap. `scheduler-executor-threads` doesn't apply there. See the [tutorial's Large-scale section](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md#large-scale-initial-export) for that path.

## Cloud support

The Data Lakehouse backend's staging path currently supports **AWS S3 only** (`s3://...` / `s3a://...`). 

## Limitations (current)

- One `view` per request (spec allows `1..*`).
- `patient` / `group` filters extracted but not yet applied to the SQL.
- `cancelUrl` (the spec's pointer to a cancel endpoint exposed in the kick-off response) is not yet returned. Cancellation itself works — `DELETE` on the status URL is supported (see [Cancellation](#cancellation) above).
- `estimatedTimeRemaining` is not computed.
