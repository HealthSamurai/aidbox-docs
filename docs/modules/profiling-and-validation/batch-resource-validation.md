---
description: >-
  Validate resources already stored in the database against their schemas and
  FHIR profiles, at scale, via a resource-level $batch-validate operation,
  synchronously or asynchronously, then drill into the offending resources.
---

# Batch resource validation

{% hint style="info" %}
Available in Aidbox starting from version **2607**.
{% endhint %}

{% hint style="warning" %}
**Breaking change.** `$batch-validate` **replaces** the previous batch-validation API, which is **removed**. The `aidbox.validation/batch-validation`, `aidbox.validation/batch-validation-result`, `aidbox.validation/clear-batch-validation`, and `aidbox.validation/resources-batch-validation-task` RPCs no longer exist, and a run no longer produces `BatchValidationRun` / `BatchValidationError` resources — results now live in the aggregated `aidbox_batch_validation` schema (see [How results are stored](#how-results-are-stored)). Migrate to the `$batch-validate` operation described below.
{% endhint %}

## Overview

Batch validation checks resources **already in the database** against the active FHIR schemas and an optional set of profiles. Use it when you loaded data with validation off, or when you publish a new profile version and want to know **how many existing resources are non-compliant and why**.

`$batch-validate` runs against **one resource type**. Aidbox hash-partitions it into a **fixed number of tasks** (`number-of-chunks`, default `12`), each task validating its `mod(hash(id), N)` slice, and aggregates the results into a compact, offender-indexed form (see [How results are stored](#how-results-are-stored)).

It works two ways, chosen by the `Prefer` header:

| | Trigger | Response |
| --- | --- | --- |
| **Synchronous** (default) | `POST …/$batch-validate` | blocks, returns a `Parameters` summary |
| **Asynchronous** | same + `Prefer: respond-async` | `202` + `Content-Location`; poll for the result |

Both paths produce the same result under a **`task-id`** and persist it the same way, so you drill into a synchronous run the same as an asynchronous one.

{% hint style="info" %}
Synchronous validation blocks the request until it finishes. That suits a type scoped by a narrow `_since`/`_until` window; for a large type, use `Prefer: respond-async`. The synchronous path runs the N tasks on a local pool sized by `scheduler-executors` (`BOX_SCHEDULER_EXECUTORS`, default `4`); the async path schedules them on the task scheduler, which spreads them across nodes.

Each task scans the window once for its hash slice, so total scan work grows with the task count. More chunks means more parallelism (the async path spreads them across nodes) but more scans; fewer chunks means fewer scans but less parallelism. The default of `12` balances the two — raise `number-of-chunks` to parallelize a large type further.
{% endhint %}

{% hint style="warning" %}
**PostgreSQL connections.** Running tasks each use their own PostgreSQL connections, so a run with many parallel tasks (a high `number-of-chunks` together with a high `scheduler-executors`) raises connection use. Make sure PostgreSQL `max_connections` (and any external pooler) has the headroom, or tasks will fail to acquire a connection.
{% endhint %}

## Start a validation

`POST /fhir/<type>/$batch-validate` with a FHIR `Parameters` body:

```yaml
POST /fhir/Observation/$batch-validate
content-type: application/json

resourceType: Parameters
parameter:
  # required: only resources whose meta.lastUpdated >= _since
  - {name: _since, valueInstant: '2025-06-02T00:00:00Z'}
  # optional upper bound (exclusive)
  - {name: _until, valueInstant: '2025-06-09T00:00:00Z'}
  # validate against these profiles (conjunctive, see Profiles)
  - {name: profile, valueCanonical: 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab'}
  # tuning (optional): number of parallel tasks (default 12)
  - {name: number-of-chunks, valuePositiveInt: 24}
  # validator options (optional): override the box's validation settings for this run
  - {name: disable-terminology-validation, valueBoolean: true}
```

| Parameter | Type | Meaning |
| --- | --- | --- |
| `_since` **(required)** | `instant` | Only resources whose `meta.lastUpdated >= _since` (inclusive). Required so that a run declares a window instead of scanning a whole type (see [Filtering by date](#filtering-by-date)). |
| `_until` | `instant` | Upper bound: `meta.lastUpdated < _until` (exclusive). |
| `profile` (repeatable) | `canonical` | Validate every resource against these profile URLs (in addition to its base schema), conjunctively (see [Profiles](#profiles)). |
| `number-of-chunks` (default `12`) | `positiveInt` | Number of hash-partitioned tasks the run is split into. More parallelizes a large type (across nodes when async) at the cost of more scans; each task streams its slice, so heap stays bounded regardless. No fixed maximum: a sync run streams the tasks through a bounded thread pool (heap stays proportional to the executor count, not the task count), and an async run writes one scheduler row per task — so a very large value costs task rows and scans, not memory. |
| `disable-terminology-validation` | `boolean` | Skip coded-binding / terminology checks. |
| `disable-primitive-validation` | `boolean` | Skip primitive type & format checks. |
| `disable-slicing-validation` | `boolean` | Skip slice validation. |
| `disable-constraint-validation` | `boolean` | Blanket switch for FHIRPath invariants: `true` skips **all** of them; `false` checks **all** (see [Validator options](#validator-options)). |
| `disable-constraint` (repeatable) | `string` | Skip specific invariants by key (e.g. `us-core-8`). |
| `strict-profile-resolution` | `boolean` | Treat an unresolved `profile` / `meta.profile` canonical as an error instead of silently skipping it. |
| `strict-extension-resolution` | `boolean` | Treat an unresolved extension as an error. |

{% hint style="warning" %}
The body must be a valid `Parameters` resource. Each parameter must use the **exact** `value[x]` type above (`profile` as `valueCanonical`, `_since`/`_until` as `valueInstant`, `number-of-chunks` as `valuePositiveInt`, the `disable-*`/`strict-*` flags as `valueBoolean`, `disable-constraint` as `valueString`). Aidbox rejects an unknown parameter, a wrong value type, or a missing `_since` with `422` and an `OperationOutcome` that names the offending parameter.
{% endhint %}

## Validator options

The `disable-*` and `strict-*` parameters tune what the validator checks, **for this run only**. Each is three-state: **omit it to keep the box's configured setting**, or pass it to override that setting (`true`/`false`). Use them to trade completeness for speed on a huge type (e.g. skip the terminology and slicing passes for a structural-only sweep), or to tighten a run beyond the box defaults (e.g. `strict-profile-resolution` to surface resources whose declared profiles don't resolve — which otherwise read as compliant).

Constraints (FHIRPath invariants) have two controls that compose:

* `disable-constraint-validation` is the blanket switch — `true` skips **every** invariant, `false` checks **every** invariant (including any the box normally mutes).
* `disable-constraint` names specific invariants to skip (repeat it per key).
* When both are given, the blanket wins: `true` skips everything (the list is moot); with `false`, only the listed keys are skipped and all others are checked. With the blanket omitted, the listed keys are skipped **on top of** the box's defaults.

## Synchronous response

A `Parameters` resource holds the `task-id`, the headline counts, a link to the offending resources, and one `issue` per distinct error (each with its own filtered drill-down link).

```yaml
status: 200

resourceType: Parameters
parameter:
  - {name: task-id,   valueString: '<task-id>'}
  - {name: validated, valueUnsignedInt: 1804646}   # resources validated
  - {name: valid,     valueUnsignedInt: 1317494}    # resources with no issues
  - {name: invalid,   valueUnsignedInt: 487152}     # distinct resources with ≥1 issue
  - {name: bytes,     valueDecimal: 5242880000}     # total bytes of resource JSON processed
  - {name: invalid-resources, valueUrl: '/fhir/$batch-validate/<task-id>/invalid-resources'}
  - name: issue
    part:
      - {name: id,                valueString: '5b4b07e4…'}   # issue-id (for drill-down)
      - {name: invalid-resources, valueUrl: '/fhir/$batch-validate/<task-id>/invalid-resources?_issue=5b4b07e4…'}
      - {name: code,        valueCode: invalid-slice-cardinality}
      - {name: expression,  valueString: category}      # the element
      - {name: profile,     valueString: 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab'}
      - {name: count,       valueUnsignedInt: 486018}   # distinct offending resources
      - {name: constraint,  valueString: us-core-8}      # for invariants
      - {name: diagnostics, valueString: '…human-readable message…'}
```

* **`bytes`** is the total size of the resource JSON the run processed — a `decimal` because the total overflows `unsignedInt` at scale.
* **`count`** is the number of **distinct offending resources** for the issue, derived from the offender index.
* For **invariant** issues, the `constraint` part carries the constraint key. The `diagnostics` part is a **generated** summary keyed off the issue `code` (for an invariant, `<expression>: constraint <key> is not satisfied`) — it is not the validator's original message text, which is not stored (see [How results are stored](#how-results-are-stored)).
* Other issue kinds add a type-specific part: `slice` (the slice name) for slice issues, `binding` (the value-set URL) for terminology-binding issues, and `unknown-profile` (the unresolved canonical) for an unresolved `profile` / `meta.profile`. A part with no value is omitted.
* Each `issue` carries its own `invalid-resources` link, pre-filtered to that issue.
* The summary lists at most **10,000** distinct issues, worst first. If a run produces more, it lists the worst 10,000 and adds `issues-total` (the true count) and `issues-truncated: true`, so a truncated list is not mistaken for the whole.
* On failure the response is an `OperationOutcome`.

## Asynchronous response

```
status: 202 Accepted
Content-Location: /fhir/$batch-validate/<task-id>
```

The endpoints below are **system-level**, keyed by `task-id` alone (no resource type in the path).

Poll the `Content-Location`:

```yaml
GET /fhir/$batch-validate/<task-id>
```

* **In progress** → `202 Accepted` with an `X-Progress` header (percent of tasks completed, e.g. `45%`).
* **Complete** → `200` with the same `Parameters` summary as the synchronous response.
* **Cancelled** → `200`, an informational `OperationOutcome` (issue code `informational`).
* **Failed** → `200` with the partial `Parameters` summary from the tasks that completed, plus a `status: failed` parameter; if no task completed, a `200` `OperationOutcome`.
* **Unknown task** → `404`.

## Drill into the offending resources

The summary tells you which issues occur and how many resources hit each. To get the **offending resources**, each linked to the version that was validated and carrying its full `OperationOutcome`, call `invalid-resources`:

```
GET /fhir/$batch-validate/<task-id>/invalid-resources
    ?_issue=<issue-id>&_issue=<issue-id2>&_count=50&_page=1&_fullurl-only=false
```

| Query parameter | Meaning |
| --- | --- |
| `_issue` (repeatable) | Restrict to offenders of these issue(s). Omit for **all** offending resources. |
| `_count` / `_page` | Page size (default `50`, max `1000`) and 1-based page number. |
| `_fullurl-only` (default `false`) | When `true`, return only the `fullUrl` of each offender (omit the body and outcome). |

The response is a **`Parameters` report** rather than a Bundle (see [Response format](#response-format)): a `total`, flat paging links, and one repeated `resource` parameter per offending resource.

```yaml
resourceType: Parameters
parameter:
  - {name: total, valueUnsignedInt: 1114}
  # paging: flat links. first/previous appear past page 1; next/last before the last page
  - {name: self, valueUrl: '/fhir/$batch-validate/<task-id>/invalid-resources?_count=50&_page=1'}
  - {name: next, valueUrl: '/fhir/$batch-validate/<task-id>/invalid-resources?_count=50&_page=2'}
  - {name: last, valueUrl: '/fhir/$batch-validate/<task-id>/invalid-resources?_count=50&_page=23'}
  - name: resource
    part:
      - {name: fullUrl, valueUrl: '/Observation/<id>/_history/<version>'}
      - name: resource                                  # omitted when _fullurl-only=true
        resource: {resourceType: Observation, meta: {versionId: '<version>'}, …}
      - name: outcome                                   # omitted when _fullurl-only=true
        resource:
          resourceType: OperationOutcome
          issue:
            - {severity: fatal, code: invalid, expression: [Observation.category],
               diagnostics: '…', details: {coding: [{code: invalid-slice-cardinality}]}}
```

* Each `resource` parameter is **one distinct offending resource**: its versioned `fullUrl`, the `resource` body (read from history at the validated version), and its `outcome`, an `OperationOutcome` listing **every** issue that resource has (its full issue set, even when `_issue` narrows which resources come back).
* `_fullurl-only=true` drops the `resource` and `outcome` parts and keeps the `fullUrl`.
* Paging is flat: `self` always; `first` and `previous` once past page 1; `next` and `last` while before the last page.
* An unknown `_issue` on a known task returns an empty report (`total: 0`). An unknown task returns `404`.

{% hint style="info" %}
The `fullUrl` is **version-specific** (`/_history/<version>`), so a vread resolves to the resource version that was validated rather than the current one. (If that version was pruned, the body is absent; the `fullUrl` and `outcome` remain.)
{% endhint %}

## Cancel

```
DELETE /fhir/$batch-validate/<task-id>
```

Responds `202 Accepted`. Cancellation removes the run's **pending** tasks and marks it **cancelled** (a later poll reports `cancelled`). Aidbox does not interrupt a task already running, and keeps partial results.

## Profiles

Pass `profile` (as `valueCanonical`) to validate every resource against those URLs (via `meta.profile`), say to check the impact of a new profile version on existing data. The profiles must be loaded (an installed IG package, or a `StructureDefinition` you created).

{% hint style="info" %}
**Multiple profiles are conjunctive (AND).** A resource is compliant only if it conforms to **every** listed profile, and issues are the union of violations across them (same as FHIR `$validate`).

For **OR** ("valid against US Core 6 **or** 7"), run one validation per profile and intersect the offender sets: a resource is OR-invalid only if it appears in **every** run's offenders.
{% endhint %}

{% hint style="warning" %}
Aidbox skips an unresolvable profile URL when strict profile resolution is off, so a typo yields a "compliant" report that is wrong. Make sure the profile (and its package) is installed and the URL matches.
{% endhint %}

## Filtering by date

`_since` and `_until` are FHIR `instant`s that filter on **`meta.lastUpdated`**, following the bulk-export `_since`/`_until` semantics:

```yaml
parameter:
  - {name: _since, valueInstant: '2025-06-02T00:00:00Z'}   # lastUpdated in [2025-06-02, 2025-06-09)
  - {name: _until, valueInstant: '2025-06-09T00:00:00Z'}
```

* `_since` is an **inclusive** lower bound (`lastUpdated >= _since`); `_until` is an **exclusive** upper bound (`lastUpdated < _until`).
* `_since` is **required**: every run declares a window, so no call scans a whole (possibly huge) type by accident. To validate everything, pass an epoch `_since` (`1970-01-01T00:00:00Z`).
* A narrow window keeps a synchronous run small. Date filters compose with `profile`.

## How results are stored

Aidbox stores results in an **aggregated, compact** form, so validating 100 GB of non-conformant data does **not** add 100 GB to the database. The `aidbox_batch_validation` schema holds:

| Table | Holds |
| --- | --- |
| `issue` | one row per distinct error (no per-resource rows) |
| `invalid_resource` | a tiny `(issue_id, resource_id, version_id)` row per offending resource: ids and versions only |
| `chunk_stat` | one row per task, written once when the task finishes: its `validated`/`invalid`/`bytes` tallies |

The aggregation key is `profile`, `resource_type`, index-normalized `path` (`identifier[2].system` → `identifier.system`), `code`, `constraint_key`, and — where they apply — the slice name, binding value set, and unresolved profile canonical. All occurrences that share these collapse into one issue; the issue's **count is the number of offender rows** (distinct resources).

Aidbox does **not** store the invalid resource bodies, their `OperationOutcome`s, or the validator's original message text. The drill-down re-reads the body from history at the validated version and reconstructs the `OperationOutcome` from the stored machine fields (`code`, `expression`, `constraint`, and the type-specific parts), synthesizing the `diagnostics` message from the `code`.

Both synchronous and asynchronous runs persist these tables under the run's `task-id`, so you poll and drill into either until you cancel it.

## Response format

The `invalid-resources` response is a `Parameters` resource rather than a `Bundle`. A `searchset` or `collection` Bundle cannot carry a `total`, version-specific links, a per-offender `OperationOutcome`, and the invalid resource bodies together while remaining FHIR-valid: Bundle invariants prohibit a version-specific `fullUrl`, permit `total` and `entry.response` only on certain Bundle types, and require each embedded resource to be valid in its own right — which the intentionally invalid bodies are not. A `Parameters` resource is subject to none of these constraints: it preserves the version-specific drill-down links and embeds each `OperationOutcome` beside the resource it describes. The invalid resource bodies are the report's content — the data under review.

## Terminology

Coded-binding and slice validation may call the configured terminology server. Bindings that resolve **locally** (local code systems, or a hybrid engine with local content) validate offline and surface invalid codes as ordinary `terminology-binding-error` issues. But if validation needs the configured terminology server and it is **unreachable or errors**, the validator cannot complete and the **whole run fails**: a synchronous call returns `422` (`OperationOutcome`, "Batch validation failed…"), an asynchronous run reports `failed`. Point `fhir.terminology.service-base-url` at a reachable server (a local or hybrid engine works best) so coded validation is accurate and does not fail the run.
