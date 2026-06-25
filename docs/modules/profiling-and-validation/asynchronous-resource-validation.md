---
description: >-
  Validate resources already stored in the database against their schemas and
  FHIR profiles, asynchronously and at scale, and analyze the results.
---

# Asynchronous resource validation

{% hint style="danger" %}
**Breaking change since version 2607.** Batch validation was reworked onto the asynchronous engine and a new API. If you used it before 2607:

* The RPC procedures (`aidbox.validation/batch-validation`, `resources-batch-validation-task`, `batch-validation-result`, `clear-batch-validation`) are **removed**. Use the FHIR operations on `BatchValidationRun` described below.
* `BatchValidationError` resources are **no longer produced**. Results are stored in an aggregated form and read via `$result` / `$offenders` (see [How results are stored](#how-results-are-stored)).
* The deprecated AWF/legacy engine and the `batch-validation-legacy-engine` (`BOX_BATCH_VALIDATION_LEGACY_ENGINE`) setting are **removed**; an asynchronous task scheduler is now required.
* The `filter`, `limit`, and `async` parameters are **no longer supported**.
{% endhint %}

## Overview

Batch validation checks resources that are **already in the database** against the active FHIR schemas and, optionally, against a set of profiles. Use it when you loaded data with validation off, or when you publish a new version of a profile and want to know **how many existing resources are non-compliant and why**.

A run validates one or more resource types. Each table is split into id-range **chunks** that are executed in parallel by the asynchronous task scheduler, so a single large table fans out across workers. Results are persisted in a compact, aggregated form (see [How results are stored](#how-results-are-stored)) and survive Aidbox restarts.

The API is a set of FHIR operations on the `BatchValidationRun` resource:

| Operation | Purpose |
| --- | --- |
| `POST /fhir/BatchValidationRun/$run` | Start a run |
| `GET /fhir/BatchValidationRun/{id}/$result` | Status, compliance summary, findings, per‑resource problems |
| `GET /fhir/BatchValidationRun/{id}/$offenders` | All resource ids hitting one finding pattern |
| `POST /fhir/BatchValidationRun/{id}/$clear` | Delete a run and its results |

{% hint style="info" %}
An asynchronous task scheduler is required. The number of executor threads is controlled by the `scheduler-executors` setting (`BOX_SCHEDULER_EXECUTORS`, default `4`) — raise it to validate large datasets faster. Chunks are also distributed across nodes in a clustered deployment.
{% endhint %}

## Start a run

`POST /fhir/BatchValidationRun/$run` starts a run and returns immediately with a run id; validation proceeds in the background.

The body can be either a FHIR **`Parameters`** resource (the canonical operation-input form) or a **plain JSON** object with the same fields (an accepted shorthand). The examples below use the plain JSON shorthand; the equivalent `Parameters` form is shown under [Body shapes](#body-shapes).

```yaml
POST /fhir/BatchValidationRun/$run
content-type: text/yaml

# What to validate — choose one of:
resource: Patient            # a single resource type
# include: [Patient, Observation]   # several types
# exclude: [Provenance]             # all types except these
# (omit all three to validate every persistable resource type)

# Optional:
# id: my-run                  # client-supplied run id (rejected if it already exists)
# profiles: ['http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient']
# errorsThreshold: 10000      # cancel the run once this many violations are recorded
# chunkSize: 1000             # max rows per chunk task (byte-bounded, see note)
# incremental: true           # only validate resources changed since the last run of this stream
# configId: nightly-uscore    # incremental stream id

# response
status: 202
Content-Location: /fhir/BatchValidationRun/my-run/$result
result:
  run-id: my-run
  operation-id: my-run
  status: in-progress
```

{% hint style="info" %}
`include` and `exclude` are mutually exclusive. With none of `resource`/`include`/`exclude`, every persistable resource type is validated.
{% endhint %}

`errorsThreshold` (alias `error-threshold`) cancels the whole operation once that many violations are recorded — remaining chunks are stopped and the run status becomes `cancelled`.

`chunkSize` is an **upper bound**, not a fixed size. The planner caps each chunk by stored bytes (~8 MB), so heavy resource types (e.g. Provenance) get fewer rows per chunk than requested while light types use the full `chunkSize`. This keeps a single chunk's in-memory footprint bounded regardless of resource size.

### Body shapes

`$run` accepts the spec in two shapes, both producing the same run:

* **FHIR `Parameters`** (canonical). Multi-valued fields (`include`, `exclude`, `profiles`) and date ranges repeat the parameter; this is the form to use for the prefixed date filters (see [Filtering by date range](#filtering-by-date-range)).

  ```yaml
  POST /fhir/BatchValidationRun/$run
  content-type: application/json

  resourceType: Parameters
  parameter:
    - {name: include, valueString: Patient}
    - {name: include, valueString: Observation}
    - {name: profiles, valueString: 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient'}
    - {name: id, valueString: my-run}
  ```

* **Plain JSON** (shorthand). Terser for the common case:

  ```yaml
  POST /fhir/BatchValidationRun/$run
  content-type: text/yaml

  include: [Patient, Observation]
  profiles: ['http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient']
  id: my-run
  ```

## Get results

`GET /fhir/BatchValidationRun/{id}/$result` returns the run state and three views of the results. Poll it until `status` is terminal (`complete`, `failed`, or `cancelled`).

```yaml
GET /fhir/BatchValidationRun/my-run/$result?pageSize=50
# optional query params: page (0-based), pageSize, severity (e.g. "error")

# response
status: 200
result:
  run:
    id: my-run
    resourceType: BatchValidationRun
    status: complete           # in-progress | complete | cancelled | failed
    invalid: 14                # total violation occurrences (see note below)
  status: complete
  compliance:
    scanned: 1127              # resources validated
    compliant: 1115            # resources with no violations
    non-compliant: 12          # distinct resources with at least one violation (14 occurrences across them)
    percent: 98.94
  findings:                    # aggregate, worst (highest count) first
    - path: bogusKey
      code: unknown-key
      resource_type: Patient
      profile_url: ''
      constraint_key: ''
      severity: error
      count: 3
      pattern_hash: 5b4b07e46a65a5f0
      message: 'Patient.bogusKey: element is not allowed by the profile'
  problems:                    # per-resource view (paged by page/pageSize)
    - resource:
        id: p-1
        resourceType: Patient
        gender: 5
      errors:
        - path: gender
          type: invalid-type
          severity: error
          diagnostics: 'Patient.gender: value has the wrong type'
```

The result has three parts:

* **`compliance`** — the headline rollup: how many resources were `scanned`, how many are `compliant` vs `non-compliant` (distinct resources), and the `percent` compliant.
* **`findings`** — the aggregate "which paths fail and how often" view, worst-first. Each finding is one error **pattern** with a `count`, a reconstructed human `message`, and a `pattern_hash` for drill-down (the resource ids hitting the pattern are fetched separately via `$offenders`). Pass `severity=error` to see only errors.
* **`problems`** — the per-resource view (the offending resource plus its reconstructed errors), paged by `page`/`pageSize`. The `resource` body is **re-read live from the primary table** at read time (it is not stored by the run), so it reflects the resource's **current** state — if it was edited after the run it may no longer match the errors, and if it was deleted the body collapses to an `{id, resourceType}` stub.

{% hint style="warning" %}
`run.invalid` and the sum of finding `count`s are **violation occurrences** — one resource that breaks three rules contributes three. `compliance.non-compliant` is the number of **distinct resources** with at least one violation. They are different numbers; use `compliance` for "how many of my resources are bad".

If chunks fail or vanish, the run also records synthetic `chunk-validation-failed` / `chunk-incomplete` findings (so a partially-covered run can't read as clean — see [Run status](#run-status-as-a-resource)). These count toward `run.invalid` and appear in `findings`, but are **excluded** from `compliance.non-compliant`. So on a healthy run `run.invalid` is pure violation occurrences; on a degraded run it is inflated by the failure markers — another reason to read `compliance` for the real picture.
{% endhint %}

## Drill into a finding

A finding tells you *which* pattern fails and *how many* resources hit it, but not *which* resources. To get the resource ids, take the finding's `pattern_hash` and call `$offenders`:

```yaml
GET /fhir/BatchValidationRun/my-run/$offenders?pattern=5b4b07e46a65a5f0&pageSize=1000
# optional: page (0-based), pageSize

# response
result:
  run-id: my-run
  pattern-hash: 5b4b07e46a65a5f0
  resource-ids: [p-4, p-8, p-12]
```

## Clear a run

```yaml
POST /fhir/BatchValidationRun/my-run/$clear

# response
result:
  message: "Batch validation results for run.id='my-run' are cleared"
```

This deletes the `BatchValidationRun`, all of its stored findings, offenders, and scanned counter, and the scheduler bookkeeping for the operation. (The incremental `watermark` is keyed by `configId`, not by run id, so it is left intact.)

## Run status as a resource

`BatchValidationRun` is a regular resource; you can read or search it through the standard API to list runs and check status:

```yaml
GET /fhir/BatchValidationRun/my-run
```

## Validating against profiles

Pass `profiles` to validate every resource against those profile URLs in addition to its base schema — this is how you check the impact of a new profile version on existing data. The profiles must be loaded (e.g. an installed IG package, or a `StructureDefinition` you created).

```yaml
POST /fhir/BatchValidationRun/$run
content-type: text/yaml

resource: Patient
profiles:
  - http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient
```

{% hint style="info" %}
**Multiple profiles are conjunctive (AND).** All listed profiles are applied together (via `meta.profile`), exactly like the FHIR `$validate` operation: a resource is compliant only if it conforms to **every** profile, and the findings are the union of violations across them.

To express **OR** ("valid against US Core 6 **or** 7"), run one validation per profile and intersect the offender sets: a resource is OR‑invalid only if it appears in **every** run's offenders (i.e. it failed all of them).
{% endhint %}

{% hint style="warning" %}
If a profile URL cannot be resolved and strict profile resolution is disabled, it is silently skipped — so a typo yields a falsely "compliant" report. Make sure the profile (and its package) is installed and the URL matches.
{% endhint %}

## Filtering by date range

To validate only resources loaded (or modified) in a time window, use the FHIR date search parameters with a prefix (`ge`, `gt`, `le`, `lt`) — `createdAt` filters by load time (`cts`), `_lastUpdated` by modification time (`ts`). A closed range is the same parameter twice. These are most naturally supplied in a `Parameters` body:

```yaml
POST /fhir/BatchValidationRun/$run
content-type: application/json

resourceType: Parameters
parameter:
  - name: resource
    valueString: Patient
  # loaded in the week before last: createdAt in [now-14d, now-7d)
  - name: createdAt
    valueString: 'ge2025-06-02'
  - name: createdAt
    valueString: 'lt2025-06-09'
```

- *Loaded over the last week*: a single `createdAt` = `ge<now-7d>`.
- *Modified in a range*: use `_lastUpdated` with the same prefix grammar.

{% hint style="info" %}
`createdAt` (load time) is usually what you want for "newly loaded data"; `_lastUpdated` is the FHIR-standard parameter and reflects the last modification. Date filters compose with `profiles`, `include`/`exclude`, and `incremental` — they are all additional conditions on the same scan.
{% endhint %}

## Incremental validation

For recurring runs, set `incremental: true` and a stable `configId`. The first run validates everything; each subsequent run validates only resources written since the previous run of that `configId` (tracked by a transaction-id watermark). This makes nightly "re-check what changed" runs cheap. The watermark only advances when a run completes with full coverage.

```yaml
POST /fhir/BatchValidationRun/$run
content-type: text/yaml

include: [Patient, Observation]
profiles: ['http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient']
incremental: true
configId: nightly-uscore
```

{% hint style="warning" %}
**Incremental tracks writes, so it can miss newly-invalid references.** A resource is re-validated only when **its own** transaction id changes (a create or update). But a reference becomes dangling when its **target** is deleted — with no write to the referencing resource, so its txid does not move and an incremental run will **not** re-check it. Incremental mode is for "validate freshly loaded or modified data"; to re-verify referential integrity across data that didn't change, run a full (non-incremental) validation.
{% endhint %}

{% hint style="warning" %}
**One `configId` ⇄ one fixed scope and profile set.** The watermark is keyed by `configId` alone — not by the `include`/`exclude`/`profiles` of the run. If you reuse a `configId` for a different scope (e.g. Patients one night, Observations the next), the second run starts from the first run's watermark and **silently skips** everything written before it that the new scope never validated. Use a distinct `configId` per recurring stream.
{% endhint %}

## How results are stored

Results are stored in an **aggregated, compact** form rather than as one record per violation. The goal is that validating 100 GB of non-conformant data does **not** add 100 GB to the database. The `aidbox_batch_validation` schema holds four tables:

| Table | Keyed by | Holds |
| --- | --- | --- |
| `finding` | run id | one row per error **pattern** + its `count` |
| `offender` | run id | full `(pattern, resource_id)` index — ids only |
| `run_stat` | run id | the `scanned` counter for the run |
| `watermark` | `configId` | incremental cursor: last validated transaction id per stream |

### Findings — aggregate by error pattern

A **finding** is one row per distinct **error pattern**, with a count. Patterns are bounded by profile structure (a few thousand at most), not by data volume, so the findings table stays small regardless of how many resources are invalid.

The aggregation key — what defines a "pattern" — is:

| Field | Meaning | Example |
| --- | --- | --- |
| `profile_url` | which schema/profile raised the error | `us-core-patient` |
| `resource_type` | the resource type | `Patient` |
| `norm_path` | element path with **array indices stripped** | `identifier[2].system` → `identifier.system` |
| `code` | the kind of error | `unknown-key`, `cardinality`, `required`, `invalid-type`, `binding`, `reference` |
| `constraint_key` | the constraint / slice / binding id, when applicable | `us-core-8` |

All occurrences sharing these fields collapse into one finding. Index normalization is key: every array element of the same element (`identifier[0]`, `identifier[1]`, …) folds into one `identifier.system` pattern, giving the clean "this path is the problem on N resources" view. Each finding keeps only a running `count` — no resource ids are stored on the finding itself.

### Offenders — the full pattern → resource index

The **offender** index is where resource ids live: one tiny row per `(pattern, resource_id)` pair — ids only, no resource bodies. This is what `$offenders` reads to return every resource hitting a pattern. Storage is ids-only (tens of bytes per row), so the full drill-down list is available without storing copies of the invalid resources.

### Scanned counter and incremental watermark

`run_stat` keeps the per-run `scanned` total (resources examined), incremented additively as chunks complete; it feeds `compliance.scanned`. `watermark` is unrelated to results — it is the incremental cursor: one row per `configId` recording the last transaction id validated by that stream, advanced only when a run completes with full chunk coverage (see [Incremental validation](#incremental-validation)).

### What is not stored

The invalid resources themselves, their OperationOutcomes, and the human-readable messages are **not** stored. The finding `message` and the per-resource `errors` are **reconstructed at read time** from the stored machine fields (`code`, `path`, `constraint_key`, …). As a result the reconstructed errors are approximate: the path is index-normalized and the offending value is not named in the diagnostics.

The `problems` view's `resource` body is the one exception — it is not stored either, but it is **re-read live from the primary resource table** when you call `$result` (so the actual offending value *is* visible there, just sourced from the current resource, not the validated snapshot; deleted resources fall back to an `{id, resourceType}` stub).

Writes are batched per chunk and merge with `INSERT … ON CONFLICT DO UPDATE SET count = count + …`, so chunks running concurrently across workers and nodes accumulate into the same findings without coordination.

## Terminology

Coded-binding and slice validation may call the configured terminology server. If the server is unreachable or returns an error, the affected resource is recorded as invalid with a `terminology-unavailable` finding (naming the server), and the run still completes — it is not aborted. Point `fhir.terminology.service-base-url` at a reachable server (ideally with a local/hybrid engine) for accurate coded validation.
