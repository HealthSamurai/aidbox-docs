---
description: Async bulk export of a ViewDefinition's materialized rows to a backend-provided sink (Databricks Delta, etc.)
---
# `$viewdefinition-export` operation

{% hint style="info" %}
Available in Aidbox versions **2605** and later.
{% endhint %}

{% hint style="info" %}
Implements [SQL-on-FHIR v2 `$viewdefinition-export`](https://build.fhir.org/ig/FHIR/sql-on-fhir-v2/OperationDefinition-ViewDefinitionExport.html). Async pattern follows the FHIR async-request convention (HTTP `202` + `Content-Location` → polling URL).
{% endhint %}

{% hint style="warning" %}
Requires **fhir-schema mode** (same as the other ViewDefinition operations).
{% endhint %}

A one-shot ad-hoc export of a ViewDefinition's materialized rows into a backend-provided sink. Aidbox owns the FHIR-side wiring (route, Parameters parsing, async kick-off, status polling); the sink is contributed by an external Aidbox module that registers itself as a **backend** keyed by the `kind` input parameter.

Use this when you need a periodic snapshot / backfill / ad-hoc dump and don't want to stand up an `AidboxTopicDestination` with its continuous-streaming worker.

## Relationship to AidboxTopicDestination's initial export

For `kind=data-lakehouse`, this operation reuses **the exact same flow** that the [Data Lakehouse Topic Destination](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) runs on its first start as the "initial export": read `sof.<view>` rows → stage Parquet to an external Delta via Unity Catalog credential vending → `MERGE INTO target USING staging ON t.id = s.id WHEN NOT MATCHED THEN INSERT *` → drop staging. The difference is what surrounds that flow:

| | Topic destination initial export | `$viewdefinition-export` |
|---|---|---|
| Triggered by | `POST /AidboxTopicDestination` (once, on resource creation) | `POST /fhir/ViewDefinition/\$viewdefinition-export` (any time, repeatable) |
| Followed by | Continuous streaming worker that ingests new resource changes | Nothing — one-shot |
| Status surface | `$status` on the destination resource | This op's poll URL |
| `AidboxTopicDestination` row in PG | Yes — owns the destination's lifecycle | No — purely ad-hoc, no resource created |

So if all you need is a periodic snapshot of a view and not continuous streaming, this operation gives you the same write path without the topic-destination plumbing.

## Registered backends

| `kind` | Sink | Module |
|---|---|---|
| `data-lakehouse` | Databricks Unity Catalog managed Delta table | [`topic-destination-deltalake`](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md) |

Future BigQuery / ClickHouse backends would plug in with their own `kind`. Customers see "no backend registered for kind=X" if they invoke with an unsupported value.

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
    {"name": "databricksWorkspaceUrl", "valueString": "https://workspace.cloud.databricks.com"},
    {"name": "databricksWorkspaceId",  "valueString": "1234567890123456"},
    {"name": "databricksRegion",       "valueString": "us-east-1"},
    {"name": "tableName",              "valueString": "catalog.schema.patient_flat"},
    {"name": "databricksWarehouseId",  "valueString": "wh-abc"},
    {"name": "awsRegion",              "valueString": "us-east-1"},
    {"name": "stagingTablePath",       "valueString": "s3://bucket/staging/patient_flat/"}
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

## Spec-defined parameters

| Parameter | Required | Notes |
|---|---|---|
| `view` | yes | Exactly one entry. `viewReference` must point at a server-stored ViewDefinition. Inline `viewResource` is not yet supported. |
| `kind` | yes | Selects the backend (e.g. `data-lakehouse`). |
| `clientTrackingId` | no | Echoed back in the status response. |
| `_format` | no | `ndjson`, `parquet`, `json`, or omitted. Functionally ignored — the sink format is determined by the backend (Delta for `kind=data-lakehouse`). |
| `header` | no | Echoed; not meaningful for non-CSV sinks. |
| `patient` (0..\*) | no | List of Patient references. Currently accepted but **not yet applied** to the underlying SQL — the full view is exported. |
| `group` (0..\*) | no | List of Group references. Same status as `patient` — accepted, not yet applied. |
| `_since` | no | Same — accepted, not yet applied. |
| `source` | no | External data source URI. **Not supported** — rejected. |

Backend-specific parameters live alongside the spec ones in the same `Parameters` body. See the backend's docs for the full list. For `kind=data-lakehouse` see the [Data Lakehouse Topic Destination tutorial](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md).

## Status polling

```http
GET /fhir/ViewDefinition/$viewdefinition-export/status/<export-id>
```

Response codes:

- `202 Accepted` — still in progress. The same `Content-Location` is returned so the client can keep polling.
- `200 OK` — terminal. Body is a `Parameters` resource with the final shape (`status=completed` or `status=failed`, plus `output[].location` on success).
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

## Failure model

- **Input validation failures** (missing `view`, missing `kind`, multiple views, `source` set, etc.) — synchronous `400 OperationOutcome` returned from the kick-off `POST`. No `export-id` is allocated.
- **Backend-side failures** — async. The kick-off returns `202` with an `export-id`; status polling later reports `status=failed` with the error in the `error` parameter. Includes:
  - **No backend registered for `kind`** (e.g., typo, module not deployed) — the defmulti's `:default` method raises a clear `ex-info`, so the polling output's `error` field reads `"No backend registered for $viewdefinition-export kind=..."`.
  - **Databricks auth** (bad `client-id` / `client-secret`).
  - **Missing target table** / **missing required Databricks parameter** (e.g., no `tableName`).
  - **Schema mismatch** the module can't auto-`ALTER`.

## Cloud support

The Aidbox-side wiring is cloud-agnostic, but **the first-party backend (`kind=data-lakehouse`, [`topic-destination-deltalake`](../../tutorials/subscriptions-tutorials/data-lakehouse-aidboxtopicdestination.md)) currently supports AWS only**. The initial-export staging Delta is written via Unity Catalog credential vending and the module only consumes the `aws_temp_credentials` response (S3 / `s3a://` staging buckets). GCS and Azure ADLS Gen2 staging are tracked as follow-ups.

## Limitations (current)

- One `view` per request (spec allows `1..*`).
- `patient` / `group` / `_since` filters extracted but not yet applied to the SQL.
- Status registry is in-process — restarting the Aidbox node loses pending export status. Long-running exports across restarts will be tracked via a FHIR custom resource in a follow-up.
- Cancellation (`cancelUrl`) and `estimatedTimeRemaining` are not implemented.
