---
description: Using the $sqlquery-run operation to execute SQLQuery Libraries over ViewDefinition tables
---
# `$sqlquery-run` operation

{% hint style="warning" %}
Requires **fhir-schema mode**.
{% endhint %}

{% hint style="info" %}
This functionality is available in Aidbox versions 2605 and later.
{% endhint %}

SQL on FHIR provides the `$sqlquery-run` operation to execute a SQLQuery Library synchronously against ViewDefinition tables. The operation resolves dependencies declared in `relatedArtifact` and exposes each one to SQL as a table named after its `label`, binds input parameters to `:name` placeholders in SQL, runs the query, and streams the result in the requested format.

SQL on FHIR specification [defines $sqlquery-run operation](https://build.fhir.org/ig/FHIR/sql-on-fhir-v2/OperationDefinition-SQLQueryRun.html).

## SQLQuery Library

SQLQuery is a profile on `Library` that bundles SQL, dependencies, and parameters for sharing and versioning. Its key elements are:

- **`meta.profile`** — `https://sql-on-fhir.org/ig/StructureDefinition/SQLQuery`.
- **`type`** — fixed coding `https://sql-on-fhir.org/ig/CodeSystem/LibraryTypesCodes#sql-query`.
- **`parameter`** — declared input parameters. Each parameter has `name`, `use = "in"`, and FHIR `type` (`string`, `integer`, `boolean`, `decimal`, `date`, `dateTime`).
- **`relatedArtifact`** — dependencies of `type = "depends-on"`. The `resource` is a canonical URL pointing to a ViewDefinition or another SQLQuery Library; the `label` becomes the table name used in SQL.
- **`content`** — one or more SQL attachments. `content.contentType` starts with `application/sql`; `content.data` is the base64-encoded SQL. The optional [sql-text](https://build.fhir.org/ig/FHIR/sql-on-fhir-v2/StructureDefinition-sql-text.html) extension carries a plain-text copy for human readability. When several attachments are provided, Aidbox prefers `application/sql;dialect=postgresql` and falls back to `application/sql`.

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

