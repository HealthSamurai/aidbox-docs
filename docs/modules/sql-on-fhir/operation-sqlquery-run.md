---
description: Using the $sqlquery-run operation to execute SQLQuery Libraries over ViewDefinition tables
---
# $sqlquery-run operation

{% hint style="warning" %}
Requires **fhir-schema mode**.
{% endhint %}

{% hint style="info" %}
This functionality is available in Aidbox versions 2605 and later.
{% endhint %}

SQL on FHIR provides the `$sqlquery-run` operation to execute a SQLQuery Library synchronously against ViewDefinition tables. The operation resolves dependencies declared in `relatedArtifact` and exposes each one to SQL as a table named after its `label`, binds input parameters to `:name` placeholders in SQL, runs the query, and streams the result in the requested format.

SQL on FHIR specification [defines $sqlquery-run operation](https://build.fhir.org/ig/HL7/sql-on-fhir/OperationDefinition-SQLQueryRun.html).

## SQLQuery Library

SQLQuery is a profile on `Library` that bundles SQL, dependencies, and parameters for sharing and versioning. Its key elements are:

- **`meta.profile`**: `https://sql-on-fhir.org/ig/StructureDefinition/SQLQuery`.
- **`type`**: fixed coding `https://sql-on-fhir.org/ig/CodeSystem/LibraryTypesCodes#sql-query`.
- **`parameter`**: declared input parameters. Each parameter has `name`, `use = "in"`, and FHIR `type` (`string`, `integer`, `boolean`, `decimal`, `date`, `dateTime`).
- **`relatedArtifact`**: dependencies of `type = "depends-on"`. The `resource` is the canonical URL of a ViewDefinition, another SQLQuery or SQLView Library, a ValueSet, or a ConceptMap, and may carry a `|version` suffix. The `label` becomes the table name used in SQL. See [ValueSet and ConceptMap dependencies](#valueset-and-conceptmap-dependencies).
- **`content`**: one or more SQL attachments. `content.contentType` starts with `application/sql`; `content.data` is the base64-encoded SQL. The optional [sql-text](https://build.fhir.org/ig/HL7/sql-on-fhir/StructureDefinition-sql-text.html) extension carries a plain-text copy for human readability. When several attachments are provided, Aidbox prefers `application/sql;dialect=postgresql` and falls back to `application/sql`.

A dependency declared with an [AidboxMaterialization](aidbox-materialization.md) reads its database object: `$sqlquery-run` compiles it to `SELECT * FROM <schema>.<name>` instead of inlining its SQL. See [How dependents read a materialized object](aidbox-materialization.md#how-dependents-read-a-materialized-object).

A minimal SQLQuery Library looks like this:

```json
{
  "resourceType": "Library",
  "id": "active-patient-count",
  "url": "https://example.org/Library/active-patient-count",
  "meta": {
    "profile": ["https://sql-on-fhir.org/ig/StructureDefinition/SQLQuery"]
  },
  "status": "active",
  "type": {
    "coding": [{
      "system": "https://sql-on-fhir.org/ig/CodeSystem/LibraryTypesCodes",
      "code": "sql-query"
    }]
  },
  "relatedArtifact": [{
    "type": "depends-on",
    "resource": "https://example.org/ViewDefinition/patient_view",
    "label": "patient"
  }],
  "content": [{
    "contentType": "application/sql",
    "extension": [{
      "url": "https://sql-on-fhir.org/ig/StructureDefinition/sql-text",
      "valueString": "select count(*) as total from patient"
    }],
    "data": "c2VsZWN0IGNvdW50KCopIGFzIHRvdGFsIGZyb20gcGF0aWVudA=="
  }]
}
```

## General syntax

The operation is exposed at three levels:

| Level    | Endpoint                                 | Library source                                 |
|----------|------------------------------------------|------------------------------------------------|
| System   | `POST [base]/$sqlquery-run`              | `queryReference` or `queryResource` (required) |
| Type     | `POST [base]/Library/$sqlquery-run`      | `queryReference` or `queryResource` (required) |
| Instance | `POST [base]/Library/[id]/$sqlquery-run` | The Library identified by `[id]`               |

The body is a `Parameters` resource:

```http
POST /fhir/Library/[<resource-id>/]$sqlquery-run
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "_format", "valueCode": "fhir"},
    ...
  ]
}
```

At the system and type level, the SQLQuery Library must be supplied via either `queryReference` (a stored Library) or `queryResource` (an inline Library) — these two parameters are mutually exclusive. At the instance level, the Library is identified by the URL, and neither `queryReference` nor `queryResource` is allowed.

## Parameters

* **\_format** (required): output format. Allowed values: `csv`, `json`, `ndjson`, `fhir`.

    Example:

    ```json
    {
      "name": "_format",
      "valueCode": "fhir"
    }
    ```

* **queryReference**: reference to a stored SQLQuery Library.

    This parameter is mutually exclusive with `queryResource` and is not allowed at the instance level.

    Example:

    ```json
    {
      "name": "queryReference",
      "valueReference": {
        "reference": "Library/active-patient-count"
      }
    }
    ```

* **queryResource**: inline SQLQuery Library to execute.

    This parameter is mutually exclusive with `queryReference` and is not allowed at the instance level. The inline resource must conform to the SQLQuery profile.

    Example:

    ```json
    {
      "name": "queryResource",
      "resource": {
        "resourceType": "Library",
        "meta": {"profile": ["https://sql-on-fhir.org/ig/StructureDefinition/SQLQuery"]},
        "status": "active",
        "type": {"coding": [{
          "system": "https://sql-on-fhir.org/ig/CodeSystem/LibraryTypesCodes",
          "code": "sql-query"
        }]},
        "relatedArtifact": [{
          "type": "depends-on",
          "resource": "https://example.org/ViewDefinition/patient_view",
          "label": "patient"
        }],
        "content": [{
          "contentType": "application/sql",
          "data": "c2VsZWN0IGNvdW50KCopIGFzIHRvdGFsIGZyb20gcGF0aWVudA=="
        }]
      }
    }
    ```

* **parameters**: nested `Parameters` resource binding values to the SQL `:name` placeholders.

    Each entry's `name` matches a `Library.parameter.name` declared in the SQLQuery Library; the `value[x]` type must match the declared parameter `type` (`valueString`, `valueInteger`, `valueBoolean`, `valueDecimal`, `valueDate`, `valueDateTime`). Parameters that are passed but not declared in the Library are ignored. Repeating a parameter name binds it as a SQL array, usable with `ANY(:name)`.

    Example:

    ```json
    {
      "name": "parameters",
      "resource": {
        "resourceType": "Parameters",
        "parameter": [
          {"name": "from_date", "valueDate": "2024-01-01"},
          {"name": "gender",    "valueString": "female"}
        ]
      }
    }
    ```

* **header**: include the CSV header row. Defaults to `true`. Only applies when `_format` is `csv`.

    Example:

    ```json
    {
      "name": "header",
      "valueBoolean": false
    }
    ```

## Output format

| `_format` | Response media type     | Body                                                                    |
|-----------|-------------------------|-------------------------------------------------------------------------|
| `json`    | `application/json`      | JSON array of row objects                                               |
| `ndjson`  | `application/x-ndjson`  | One JSON object per line                                                |
| `csv`     | `text/csv`              | CSV with optional header row controlled by `header`                     |
| `fhir`    | `application/fhir+json` | `Parameters` resource with one repeating `row` parameter per result row |

`_format` overrides the `Accept` header — for example, `Accept: text/csv` together with `_format: json` returns JSON.

When `_format=fhir`, each result column is rendered using a FHIR `value[x]` type derived from the SQL column type. SQL `NULL` values are omitted from the row part list. An empty result set is returned as a `Parameters` resource without any `parameter` element.

| SQL type                                 | FHIR value type    |
|------------------------------------------|--------------------|
| `BOOLEAN`                                | `valueBoolean`     |
| `SMALLINT`, `INTEGER`                    | `valueInteger`     |
| `BIGINT`                                 | `valueInteger64`   |
| `DECIMAL`, `NUMERIC`, `REAL`, `DOUBLE`   | `valueDecimal`     |
| `CHARACTER`, `CHARACTER VARYING`, `TEXT` | `valueString`      |
| `DATE`                                   | `valueDate`        |
| `TIME`, `TIME WITH TIME ZONE`            | `valueTime`        |
| `TIMESTAMP`                              | `valueDateTime`    |
| `TIMESTAMP WITH TIME ZONE`               | `valueInstant`     |

If a result column has a SQL type not listed above (for example `jsonb`, `interval`, `array`, `xml`), the operation returns `422 Unprocessable Entity`. Cast the column to a supported type inside the SQL query to work around this.

## SQL execution

Aidbox runs the Library's SQL in a read-only transaction. SQL that changes data fails with 422 and leaves the database as it was. This covers `INSERT`, `UPDATE`, `DELETE`, `MERGE`, a `WITH` query that modifies data, a function that writes, `nextval()` and `SELECT … FOR UPDATE`.

The SQL must be a single statement. A trailing semicolon is fine, but Aidbox counts any text after it as another statement, even a comment, and refuses SQL with more than one statement with 422.

Aidbox fetches the whole result before it sends the response, so an error in the SQL returns an error status with an `OperationOutcome` in every `_format`.

| Status | Condition                                                                                                                          |
|--------|------------------------------------------------------------------------------------------------------------------------------------|
| 422    | The SQL has more than one statement                                                                                                |
| 422    | The SQL changes data                                                                                                               |
| 422    | Postgres rejects the SQL: a syntax error, an unknown table or column, a missing privilege, or a data error such as division by zero or an invalid cast |
| 422    | With `_format=fhir`, a result column has a SQL type that [Output format](#output-format) doesn't list                              |
| 500    | Any other database failure, such as a lost connection                                                                              |

The `diagnostics` of the `OperationOutcome` carries the reason, for example:

```text
SQL on FHIR runs queries read-only: ERROR: cannot execute INSERT in a read-only transaction
The SQL has 2 statements; SQL on FHIR runs a single one
ERROR: division by zero
```

{% hint style="warning" %}
The read-only transaction protects the data. The SQL still runs as Aidbox's database user, so it can read every table that user can read, Aidbox's own tables included. When that user is a Postgres superuser, a read-only transaction also lets the SQL read files and run programs on the database server. Grant `$sqlquery-run` to clients you would trust with read access to the whole database, and restrict it with an [AccessPolicy](../../access-control/authorization/access-policies.md).
{% endhint %}

## Examples

The examples below assume the following ViewDefinitions and supporting resources exist on the server:

```json
{
  "resourceType": "ViewDefinition",
  "id": "patient_view",
  "url": "https://example.org/ViewDefinition/patient_view",
  "status": "active",
  "resource": "Patient",
  "select": [{"column": [
    {"name": "id",         "path": "getResourceKey()"},
    {"name": "gender",     "path": "gender",    "type": "string"},
    {"name": "birth_date", "path": "birthDate", "type": "date"}
  ]}]
}
```

```json
{
  "resourceType": "ViewDefinition",
  "id": "bp_view",
  "url": "https://example.org/ViewDefinition/bp_view",
  "status": "active",
  "resource": "Observation",
  "select": [{"column": [
    {"name": "id",             "path": "getResourceKey()"},
    {"name": "patient_id",     "path": "subject.getReferenceKey(Patient)"},
    {"name": "systolic",       "path": "value.ofType(Quantity).value", "type": "decimal"},
    {"name": "effective_date", "path": "effective.ofType(dateTime)",   "type": "dateTime"}
  ]}]
}
```

### SQLQuery Library over multiple ViewDefinitions with a parameter

The Library below declares two ViewDefinition dependencies (`patient_view` mounted as `pt` and `bp_view` mounted as `bp`) and a `from_date` parameter. The SQL aggregates blood-pressure observations from `from_date` onward, grouped by patient gender.

```json
{
  "resourceType": "Library",
  "id": "bp-summary-by-gender",
  "url": "https://example.org/Library/bp-summary-by-gender",
  "meta": {
    "profile": ["https://sql-on-fhir.org/ig/StructureDefinition/SQLQuery"]
  },
  "status": "active",
  "type": {
    "coding": [{
      "system": "https://sql-on-fhir.org/ig/CodeSystem/LibraryTypesCodes",
      "code": "sql-query"
    }]
  },
  "parameter": [
    {"name": "from_date", "use": "in", "type": "date"}
  ],
  "relatedArtifact": [
    {"type": "depends-on", "resource": "https://example.org/ViewDefinition/patient_view", "label": "pt"},
    {"type": "depends-on", "resource": "https://example.org/ViewDefinition/bp_view",      "label": "bp"}
  ],
  "content": [{
    "contentType": "application/sql",
    "extension": [{
      "url": "https://sql-on-fhir.org/ig/StructureDefinition/sql-text",
      "valueString": "select pt.gender as gender, count(distinct pt.id) as pt_count, avg(bp.systolic)::numeric(5,1) as avg_systolic from pt join bp on bp.patient_id = pt.id where bp.effective_date >= :from_date group by pt.gender order by pt.gender"
    }],
    "data": "c2VsZWN0CiAgcHQuZ2VuZGVyIGFzIGdlbmRlciwKICBjb3VudChkaXN0aW5jdCBwdC5pZCkgYXMgcHRfY291bnQsCiAgYXZnKGJwLnN5c3RvbGljKTo6bnVtZXJpYyg1LDEpIGFzIGF2Z19zeXN0b2xpYwpmcm9tIHB0CmpvaW4gYnAgb24gYnAucGF0aWVudF9pZCA9IHB0LmlkCndoZXJlIGJwLmVmZmVjdGl2ZV9kYXRlID49IDpmcm9tX2RhdGUKZ3JvdXAgYnkgcHQuZ2VuZGVyCm9yZGVyIGJ5IHB0LmdlbmRlcg=="
  }]
}
```

Run the Library by reference and bind `from_date`:

```http
POST /fhir/Library/$sqlquery-run
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "_format", "valueCode": "fhir"},
    {"name": "queryReference", "valueReference": {"reference": "Library/bp-summary-by-gender"}},
    {"name": "parameters", "resource": {
      "resourceType": "Parameters",
      "parameter": [
        {"name": "from_date", "valueDate": "2024-06-01"}
      ]
    }}
  ]
}
```

Response:

```json
{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "row", "part": [
      {"name": "gender",       "valueString":    "female"},
      {"name": "pt_count",     "valueInteger64": "1"},
      {"name": "avg_systolic", "valueDecimal":   135.0}
    ]},
    {"name": "row", "part": [
      {"name": "gender",       "valueString":    "male"},
      {"name": "pt_count",     "valueInteger64": "1"},
      {"name": "avg_systolic", "valueDecimal":   125.0}
    ]}
  ]
}
```

The same Library can be invoked at the instance level — in that case `queryReference` and `queryResource` must be omitted:

```http
POST /fhir/Library/bp-summary-by-gender/$sqlquery-run
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "_format", "valueCode": "fhir"},
    {"name": "parameters", "resource": {
      "resourceType": "Parameters",
      "parameter": [
        {"name": "from_date", "valueDate": "2024-06-01"}
      ]
    }}
  ]
}
```

### SQLQuery Library composing a ViewDefinition with another Library and parameters

A SQLQuery Library can depend on another SQLQuery Library — Aidbox compiles the dependency Library into a CTE, mounts it under the declared `label`, and passes the input `parameters` down the dependency chain. This makes it possible to share intermediate results across queries.

The inner Library `recent-bp` exposes blood-pressure observations from `:since_date` onward:

```json
{
  "resourceType": "Library",
  "id": "recent-bp",
  "url": "https://example.org/Library/recent-bp",
  "meta": {
    "profile": ["https://sql-on-fhir.org/ig/StructureDefinition/SQLQuery"]
  },
  "status": "active",
  "type": {
    "coding": [{
      "system": "https://sql-on-fhir.org/ig/CodeSystem/LibraryTypesCodes",
      "code": "sql-query"
    }]
  },
  "parameter": [
    {"name": "since_date", "use": "in", "type": "date"}
  ],
  "relatedArtifact": [
    {"type": "depends-on", "resource": "https://example.org/ViewDefinition/bp_view", "label": "bp"}
  ],
  "content": [{
    "contentType": "application/sql",
    "extension": [{
      "url": "https://sql-on-fhir.org/ig/StructureDefinition/sql-text",
      "valueString": "select id, patient_id, systolic, effective_date from bp where effective_date >= :since_date"
    }],
    "data": "c2VsZWN0IGlkLCBwYXRpZW50X2lkLCBzeXN0b2xpYywgZWZmZWN0aXZlX2RhdGUKZnJvbSBicAp3aGVyZSBlZmZlY3RpdmVfZGF0ZSA+PSA6c2luY2VfZGF0ZQ=="
  }]
}
```

The outer Library `recent-bp-by-gender` joins `patient_view` (label `pt`) with the inner Library `recent-bp` (label `rbp`) and filters by gender. Both `:gender` and `:since_date` are declared at the outer level — `:since_date` is forwarded to the inner Library when its body is compiled:

```json
{
  "resourceType": "Library",
  "id": "recent-bp-by-gender",
  "url": "https://example.org/Library/recent-bp-by-gender",
  "meta": {
    "profile": ["https://sql-on-fhir.org/ig/StructureDefinition/SQLQuery"]
  },
  "status": "active",
  "type": {
    "coding": [{
      "system": "https://sql-on-fhir.org/ig/CodeSystem/LibraryTypesCodes",
      "code": "sql-query"
    }]
  },
  "parameter": [
    {"name": "gender",     "use": "in", "type": "string"},
    {"name": "since_date", "use": "in", "type": "date"}
  ],
  "relatedArtifact": [
    {"type": "depends-on", "resource": "https://example.org/ViewDefinition/patient_view", "label": "pt"},
    {"type": "depends-on", "resource": "https://example.org/Library/recent-bp",            "label": "rbp"}
  ],
  "content": [{
    "contentType": "application/sql",
    "extension": [{
      "url": "https://sql-on-fhir.org/ig/StructureDefinition/sql-text",
      "valueString": "select pt.id as patient_id, pt.gender, rbp.systolic, rbp.effective_date from pt join rbp on rbp.patient_id = pt.id where pt.gender = :gender order by rbp.effective_date"
    }],
    "data": "c2VsZWN0IHB0LmlkIGFzIHBhdGllbnRfaWQsIHB0LmdlbmRlciwgcmJwLnN5c3RvbGljLCByYnAuZWZmZWN0aXZlX2RhdGUKZnJvbSBwdApqb2luIHJicCBvbiByYnAucGF0aWVudF9pZCA9IHB0LmlkCndoZXJlIHB0LmdlbmRlciA9IDpnZW5kZXIKb3JkZXIgYnkgcmJwLmVmZmVjdGl2ZV9kYXRl"
  }]
}
```

Run the outer Library, passing both parameters:

```http
POST /fhir/Library/$sqlquery-run
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "_format", "valueCode": "fhir"},
    {"name": "queryReference", "valueReference": {"reference": "Library/recent-bp-by-gender"}},
    {"name": "parameters", "resource": {
      "resourceType": "Parameters",
      "parameter": [
        {"name": "gender",     "valueString": "female"},
        {"name": "since_date", "valueDate":   "2024-01-01"}
      ]
    }}
  ]
}
```

Response:

```json
{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "row", "part": [
      {"name": "patient_id",     "valueString":  "pt-1"},
      {"name": "gender",         "valueString":  "female"},
      {"name": "systolic",       "valueDecimal": 140.0},
      {"name": "effective_date", "valueString":  "2024-02-01T08:00:00Z"}
    ]},
    {"name": "row", "part": [
      {"name": "patient_id",     "valueString":  "pt-3"},
      {"name": "gender",         "valueString":  "female"},
      {"name": "systolic",       "valueDecimal": 150.0},
      {"name": "effective_date", "valueString":  "2024-05-05T08:00:00Z"}
    ]},
    {"name": "row", "part": [
      {"name": "patient_id",     "valueString":  "pt-1"},
      {"name": "gender",         "valueString":  "female"},
      {"name": "systolic",       "valueDecimal": 135.0},
      {"name": "effective_date", "valueString":  "2024-08-15T08:00:00Z"}
    ]}
  ]
}
```

## ValueSet and ConceptMap dependencies

{% hint style="info" %}
This functionality is available in Aidbox versions 2610 and later.
{% endhint %}

A SQLQuery or SQLView can depend on a ValueSet or a ConceptMap, as the SQL on FHIR [Terminology in SQL](https://build.fhir.org/ig/HL7/sql-on-fhir/terminology-in-sql.html) page defines. You declare it in `relatedArtifact` like any other dependency, and the SQL reads it as a table named after its `label`:

```json
"relatedArtifact": [
  {"type": "depends-on", "resource": "https://example.org/ViewDefinition/condition_view",         "label": "conditions"},
  {"type": "depends-on", "resource": "http://example.org/ValueSet/cardiovascular-disease|2026", "label": "cvd_codes"},
  {"type": "depends-on", "resource": "http://example.org/ConceptMap/sct-to-icd10|2026",         "label": "sct_to_icd10"}
]
```

Before any SQL runs, Aidbox expands each ValueSet with `$expand`, turns each ConceptMap into rows, and stores both in the database. The query reads the stored rows.

### Terminology engine

ValueSet dependencies need [`fhir.terminology.engine`](../../reference/all-settings.md#fhir.terminology.engine) set to `local` or `hybrid`. On `legacy`, a query with a ValueSet dependency fails with 422.

A ConceptMap dependency doesn't use the engine: Aidbox takes the rows from the ConceptMap resource. Aidbox resolves both kinds of dependency in the FHIR Artifact Registry (FAR). On `legacy`, ConceptMaps you create through the API live outside FAR, and a dependency on one returns 404.

### ValueSet relation

A ValueSet dependency reads as a table with these columns:

| Column     | SQL type  | Content                                                       |
|------------|-----------|---------------------------------------------------------------|
| `system`   | `text`    | Code system URL. Never null                                   |
| `version`  | `text`    | Code system version. Null when the expansion records none     |
| `code`     | `text`    | The code. Never null                                          |
| `display`  | `text`    | Display text                                                  |
| `inactive` | `boolean` | `true` for an inactive code, null for an active one           |

Each row is a member of the expansion: a non-abstract `expansion.contains` entry at any depth of nesting. The table holds one row per (`system`, `version`, `code`). An abstract entry adds no row.

Aidbox takes `version` from the entry or from the expansion's `used-codesystem` parameter. When the expansion uses two versions of one code system, Aidbox can't tell which version a code came from and leaves `version` null.

`$expand` leaves out a code that `compose.include.concept` lists but its code system doesn't define. Aidbox adds such a code to the table when the ValueSet definition takes it in, with the version of its `include`.

`inactive` is null for an active code, so a filter on it must admit null:

```sql
SELECT system, code FROM cvd_codes WHERE inactive IS NULL OR inactive = FALSE
```

### ConceptMap relation

A ConceptMap dependency reads as a table with these columns, all of type `text`. Aidbox splits the canonicals in `group.source` and `group.target` at `|` into a system and a version:

| Column           | Content                                                                    |
|------------------|----------------------------------------------------------------------------|
| `source_system`  | `group.source` without its version suffix. Never null                      |
| `source_version` | The version suffix of `group.source`, or `group.sourceVersion` in R4       |
| `source_code`    | `group.element.code`. Never null                                           |
| `source_display` | `group.element.display`                                                    |
| `target_system`  | `group.target` without its version suffix                                  |
| `target_version` | The version suffix of `group.target`, or `group.targetVersion` in R4       |
| `target_code`    | `group.element.target.code`. Null on a noMap row                           |
| `target_display` | `group.element.target.display`                                             |
| `relationship`   | `group.element.target.relationship`. Null on a noMap row                   |

The table holds one row per `group.element.target`, and one noMap row per `group.element` with `noMap: true`. A noMap row keeps the group's `target_system`, so test for it with `target_code IS NULL`. `group.unmapped` adds no rows, and Aidbox drops duplicate rows.

For an R4 ConceptMap, Aidbox converts `target.equivalence` to an R5 `relationship`:

| R4 `equivalence`          | `relationship`                   |
|---------------------------|----------------------------------|
| `relatedto`, `inexact`    | `related-to`                     |
| `equivalent`, `equal`     | `equivalent`                     |
| `wider`, `subsumes`       | `source-is-narrower-than-target` |
| `narrower`, `specializes` | `source-is-broader-than-target`  |
| `disjoint`                | `not-related-to`                 |
| `unmatched`               | noMap row                        |

### Filter by a ValueSet

The examples below read Conditions through this ViewDefinition, one row per coding:

```json
{
  "resourceType": "ViewDefinition",
  "id": "condition_view",
  "url": "https://example.org/ViewDefinition/condition_view",
  "status": "active",
  "resource": "Condition",
  "select": [
    {"column": [
      {"name": "patient_id", "path": "subject.getReferenceKey(Patient)"}
    ]},
    {"forEach": "code.coding", "column": [
      {"name": "system", "path": "system", "type": "uri"},
      {"name": "code",   "path": "code",   "type": "code"}
    ]}
  ]
}
```

The Library below returns the conditions whose code belongs to the `cardiovascular-disease` ValueSet:

```json
{
  "resourceType": "Library",
  "id": "cvd-conditions",
  "url": "https://example.org/Library/cvd-conditions",
  "meta": {
    "profile": ["https://sql-on-fhir.org/ig/StructureDefinition/SQLQuery"]
  },
  "status": "active",
  "type": {
    "coding": [{
      "system": "https://sql-on-fhir.org/ig/CodeSystem/LibraryTypesCodes",
      "code": "sql-query"
    }]
  },
  "relatedArtifact": [
    {"type": "depends-on", "resource": "https://example.org/ViewDefinition/condition_view",         "label": "conditions"},
    {"type": "depends-on", "resource": "http://example.org/ValueSet/cardiovascular-disease|2026", "label": "cvd_codes"}
  ],
  "content": [{
    "contentType": "application/sql",
    "extension": [{
      "url": "https://sql-on-fhir.org/ig/StructureDefinition/sql-text",
      "valueString": "select conditions.patient_id, conditions.code from conditions where exists (select 1 from cvd_codes where cvd_codes.system = conditions.system and cvd_codes.code = conditions.code)"
    }],
    "data": "U0VMRUNUIGNvbmRpdGlvbnMucGF0aWVudF9pZCwgY29uZGl0aW9ucy5jb2RlCkZST00gY29uZGl0aW9ucwpXSEVSRSBFWElTVFMgKAogIFNFTEVDVCAxCiAgRlJPTSBjdmRfY29kZXMKICBXSEVSRSBjdmRfY29kZXMuc3lzdGVtID0gY29uZGl0aW9ucy5zeXN0ZW0KICAgIEFORCBjdmRfY29kZXMuY29kZSA9IGNvbmRpdGlvbnMuY29kZQop"
  }]
}
```

The SQL tests membership with `EXISTS`:

```sql
SELECT conditions.patient_id, conditions.code
FROM conditions
WHERE EXISTS (
  SELECT 1
  FROM cvd_codes
  WHERE cvd_codes.system = conditions.system
    AND cvd_codes.code = conditions.code
)
```

Use `EXISTS` rather than `JOIN` for a membership test. The table can hold one code under two versions of its code system, and a `JOIN` on `system` and `code` would then return the condition twice. `NOT EXISTS` excludes the members of a ValueSet.

### Translate with a ConceptMap

A Library that declares `sct_to_icd10` the same way translates SNOMED CT codes to ICD-10. A `LEFT JOIN` keeps the conditions the map doesn't translate:

```sql
SELECT conditions.patient_id,
       conditions.code,
       sct_to_icd10.target_code,
       sct_to_icd10.relationship
FROM conditions
LEFT JOIN sct_to_icd10
  ON sct_to_icd10.source_system = conditions.system
 AND sct_to_icd10.source_code = conditions.code
 AND (sct_to_icd10.relationship IS NULL
      OR sct_to_icd10.relationship <> 'not-related-to')
```

A `not-related-to` row states that the target is not a translation of the source, yet it carries a target code. Exclude it in the `ON` clause: in `WHERE`, the filter would also drop the conditions the `LEFT JOIN` keeps. The filter admits null because a noMap row has no `relationship`.

The result has three kinds of rows:

- a translated condition has a `target_code`;
- a condition the map marks as noMap has a `source_code` in the map and a null `target_code`;
- a condition the map doesn't mention has every column of `sct_to_icd10` null.

### Versions

- A canonical without `|version` resolves to the latest version of the ValueSet or ConceptMap in FAR.
- Aidbox stores the content under the canonical as written in `relatedArtifact`. `url`, `url|2025` and `url|2026` are three separate entries.
- An unversioned dependency picks up a new version on the first run after you publish it. A pinned one stays on its version.

### Storage and freshness

Aidbox keeps the content in the `aidbox_sof` schema:

| Table                             | Content                                                                         |
|-----------------------------------|---------------------------------------------------------------------------------|
| `aidbox_sof.valueset_expansion`   | One row per ValueSet dependency, keyed by the canonical as written (`key`)     |
| `aidbox_sof.valueset_member`      | The ValueSet members                                                            |
| `aidbox_sof.conceptmap_snapshot`  | One row per ConceptMap dependency, keyed by the canonical as written (`key`)   |
| `aidbox_sof.conceptmap_mapping`   | The ConceptMap rows                                                             |

For each expansion, Aidbox records:

- `url` and `version` of the ValueSet the canonical resolved to;
- `sources`: the FAR resources the expansion came from with their timestamps, the terminology engine, and the external server;
- `expansion`: the expansion without `contains`, with its `identifier`, `timestamp`, `total` and `parameter`.

On each `$sqlquery-run` and [`$materialize`](aidbox-materialization.md#valueset-and-conceptmap-dependencies), Aidbox checks the stored content against its sources. It expands a ValueSet again after a change in FAR to the ValueSet, to a CodeSystem it uses, or to a ValueSet it includes, and after a change of the terminology engine or the external server. It rebuilds the rows of a ConceptMap after a change to the ConceptMap.

Aidbox doesn't detect changes on the external terminology server. To drop a stored expansion, delete its row, and the members go with it:

```sql
DELETE FROM aidbox_sof.valueset_expansion
WHERE key = 'http://example.org/ValueSet/cardiovascular-disease|2026';
```

The next run expands the ValueSet again.

### Errors

Aidbox checks every ValueSet and ConceptMap dependency before any SQL runs, so a dependency it can't resolve fails the request instead of matching nothing.

| Status | Condition                                                                                                                         |
|--------|-----------------------------------------------------------------------------------------------------------------------------------|
| 404    | The canonical doesn't resolve in FAR                                                                                              |
| 422    | The dependency is another resource type, such as a CodeSystem                                                                     |
| 422    | The dependency is a ValueSet and `fhir.terminology.engine` is `legacy`                                                            |
| 422    | `$expand` returns an error, or the expansion lists fewer codes than its `total`                                                   |
| 422    | The ValueSet lists a code its code system doesn't define, and a filter in its definition leaves open whether the code is a member |
| 422    | The ConceptMap has a group without `source`, an element without `code`, a `valueSet` on an element or a target, or a target with `dependsOn` or `product` |

{% hint style="warning" %}
On `hybrid`, a failed request to the external server doesn't fail the query. When the external server returns an error for the first page of the expansion, Aidbox treats its part of the expansion as empty, and the query returns 200. For example, a ValueSet that includes all of a code system neither Aidbox nor the external server knows returns 422 on `local` and an empty table on `hybrid`. Aidbox stores that result like any other, so it stays until you [delete the stored expansion](#storage-and-freshness).
{% endhint %}

### Limitations

- **ValueSets outside FAR.** A ValueSet that the external terminology server knows and FAR doesn't returns 404.
- **No inline artifacts.** You can't send a ValueSet or ConceptMap with the request, as the `context` parameter of the specification's `$sql-run` allows. Store it in Aidbox first.
- **`ValueSet.expansion` is ignored.** `$expand` evaluates `compose` and ignores `ValueSet.expansion`, so a ValueSet with an `expansion` and no `compose` reads as an empty table.
- **No API for stored content.** No operation refreshes or deletes what Aidbox keeps in `aidbox_sof`, and rows for canonicals that no query uses anymore stay there. Use SQL.

