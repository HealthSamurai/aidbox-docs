---
description: Async bulk export of a ViewDefinition's materialized rows to a backend-provided sink (Databricks Delta, etc.)
---
# $viewdefinition-export operation

{% hint style="info" %}
Available in Aidbox versions **2605** and later. Requires **fhir-schema mode**. Implements [SQL-on-FHIR v2 `$viewdefinition-export`](https://build.fhir.org/ig/FHIR/sql-on-fhir-v2/OperationDefinition-ViewDefinitionExport.html).
{% endhint %}

Exports a ViewDefinition's flattened rows into a sink (e.g. a Databricks Delta table). The backend is contributed by an Aidbox module; you pick it with the `kind` parameter.

Use this for one-shot snapshots, backfills, or ad-hoc dumps when standing up a streaming `AidboxTopicDestination` is overkill.

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
    {"name": "stagingTablePath",       "valueString": "s3://xxx/staging/patient_flat/"}
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

## Parameters

### Spec parameters

| Parameter | Required | Notes |
|---|---|---|
| `view` | yes | Exactly one entry. `viewReference` must point at a server-stored ViewDefinition. Inline `viewResource` is not yet supported. |
| `kind` | yes | Selects the backend (e.g. `data-lakehouse`). |
| `clientTrackingId` | no | Echoed back in the status response. |
| `_format` | no | `ndjson`, `parquet`, `json`, or omitted. Functionally ignored — the sink format is determined by the backend (Delta for `kind=data-lakehouse`). |
| `header` | no | Echoed; not meaningful for non-CSV sinks. |
| `_since` | no | ISO-8601 instant. Filters rows by the view's timestamp column (`ts` or `last_updated`). 400 if `_since` is set but the view exposes neither column. |
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
| `chunkCount` | no | Positive integer (default 1). Splits the export into N per-chunk staging tables and N concurrent writers. Capped by Aidbox's HikariCP pool size; 400 with `parallelism-exceeds-pool` if exceeded. |

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

With `chunkCount = N` (default `N=1`), the backend hash-partitions `sof.<view>` into `N` chunks, writes each chunk into its own external Delta table under `<stagingTablePath>/chunk-K/`, then materializes the union into the managed target with one `MERGE INTO target USING (SELECT * FROM staging_0 UNION ALL …)` against the SQL warehouse and drops every staging. The `N=1` case is the degenerate path of the same flow.

Steps:

1. `plan-export` decides the chunk count from `chunkCount`. `setup-export` syncs the target schema against `sof.<view>` (auto-`ALTER ADD COLUMNS` if Aidbox added columns) and pre-computes the staging-column spec.
2. Each chunk task creates its own external Delta table at `<stagingTablePath>/chunk-K/`, vends short-lived STS credentials from Unity Catalog for that prefix, and streams its hash-partition of `sof.<view>` as one Delta commit.
3. Once all chunks complete, the coordinator task invokes `finalize-export`: `MERGE INTO target USING (SELECT * FROM staging_0 UNION ALL …) ON t.id = s.id WHEN NOT MATCHED THEN INSERT *`.
4. The module drops every staging table.

On failure the per-chunk stagings are best-effort dropped via `cancel-export`. Chunks retry up to 2 times with a 30-second backoff; if they exhaust retries the export is reported as `failed`.

{% hint style="info" %}
The `MERGE` is idempotent on `id` — a retried export after a lost response inserts nothing instead of duplicating. Your ViewDefinition must select an `id` column.
{% endhint %}

The Databricks-side setup (catalog, schema, target table, staging schema, service principal, grants, warehouse) is documented in the [Data Lakehouse tutorial](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) — the same setup is reused here.

## Multi-pod execution

Chunks run on Aidbox's standard async-task engine, so they distribute across every pod sharing the metastore. Status polling and cancellation answer from any pod — no kick-off-pod affinity, no client-side load-balancer pinning.

A pod failure mid-chunk is recovered automatically: the chunk task's heartbeat lapses and another pod re-leases it.

## Cloud support

The Data Lakehouse backend's staging path currently supports **AWS S3 only** (`s3://...` / `s3a://...`). The Unity Catalog managed target table is unaffected — UC manages its own storage.

{% hint style="info" %}
Need **GCS** (`gs://...`) or **Azure ADLS Gen2** (`abfss://...`) staging? [Contact us](../../overview/contact-us.md) — they're not wired through the backend yet, but the Aidbox-side wiring is cloud-agnostic and we can prioritize.
{% endhint %}

## Limitations (current)

- One `view` per request (spec allows `1..*`).
- `patient` / `group` filters extracted but not yet applied to the SQL. `_since` is applied.
- `cancelUrl` (the spec's pointer to a cancel endpoint exposed in the kick-off response) is not yet returned. Cancellation itself works — `DELETE` on the status URL is supported (see [Cancellation](#cancellation) above).
- `estimatedTimeRemaining` is not computed.
