---
description: Run one-time migrations at startup — install FHIR packages or execute SQL using AidboxMigration and Init Bundle.
---

# Migrations

Aidbox supports one-time migrations that run exactly once during startup. Migrations are useful for:

* Installing FHIR Implementation Guide packages
* Running SQL statements (creating indexes, tables, seed data)

Migrations use the `AidboxMigration` resource combined with [Init Bundle](init-bundle.md) for declarative, idempotent execution.

## How it works

1. You define an `AidboxMigration` resource with an action and parameters
2. You wrap it in an Init Bundle with `ifNoneExist` to ensure it runs only once
3. On startup, Aidbox executes the bundle — if the migration already exists, it is skipped

## Install a FHIR package

Use the `far-migration-fhir-package-install` action to install a FHIR IG package from the registry.

```json
{
  "type": "transaction",
  "resourceType": "Bundle",
  "entry": [
    {
      "request": {
        "method": "POST",
        "url": "AidboxMigration",
        "ifNoneExist": "id=us-core-install"
      },
      "resource": {
        "resourceType": "AidboxMigration",
        "id": "us-core-install",
        "action": "far-migration-fhir-package-install",
        "status": "to-run",
        "params": {
          "resourceType": "Parameters",
          "parameter": [
            {
              "name": "package",
              "valueString": "hl7.fhir.us.core@3.1.1"
            }
          ]
        }
      }
    }
  ]
}
```

The `package` parameter value follows the format `<package-name>@<version>`.

After execution, the migration status changes to `done` and the `result` field contains the number of installed canonicals.

### Uninstall a FHIR package

Use `far-migration-fhir-package-uninstall` to remove a previously installed package:

```json
{
  "resourceType": "AidboxMigration",
  "id": "us-core-uninstall",
  "action": "far-migration-fhir-package-uninstall",
  "status": "to-run",
  "params": {
    "resourceType": "Parameters",
    "parameter": [
      {
        "name": "package",
        "valueString": "hl7.fhir.us.core@3.1.1"
      }
    ]
  }
}
```

## Run a SQL migration

Use the `aidbox-migration-run-sql` action to execute arbitrary SQL statements.

{% hint style="info" %}
Available since the 2602 release.
{% endhint %}

```json
{
  "type": "transaction",
  "resourceType": "Bundle",
  "entry": [
    {
      "request": {
        "method": "POST",
        "url": "AidboxMigration",
        "ifNoneExist": "id=create-encounter-index"
      },
      "resource": {
        "resourceType": "AidboxMigration",
        "id": "create-encounter-index",
        "action": "aidbox-migration-run-sql",
        "status": "to-run",
        "params": {
          "resourceType": "Parameters",
          "parameter": [
            {
              "name": "sql",
              "valueString": "CREATE INDEX IF NOT EXISTS encounter_subject_id ON encounter ((resource #>> '{subject, id}'));"
            }
          ]
        }
      }
    }
  ]
}
```

After execution, the migration status changes to `done` and `result.valueBoolean` is `true`.

{% hint style="warning" %}
Invalid SQL causes the migration to fail with a 422 error. In a transaction bundle, this rolls back the entire transaction and prevents Aidbox from starting.
{% endhint %}

### Run SQL outside a transaction

{% hint style="info" %}
Available since the 2607 release.
{% endhint %}

By default Aidbox wraps the migration SQL in a transaction. PostgreSQL forbids some statements inside a transaction block, among them `CREATE INDEX CONCURRENTLY`, `DROP INDEX CONCURRENTLY`, `REINDEX CONCURRENTLY`, and `VACUUM`. Add the `execution-type` parameter with the value `not-in-transaction` to run the SQL with autocommit on:

```json
{
  "resourceType": "AidboxMigration",
  "id": "create-encounter-index-concurrently",
  "action": "aidbox-migration-run-sql",
  "status": "to-run",
  "params": {
    "resourceType": "Parameters",
    "parameter": [
      {
        "name": "sql",
        "valueString": "CREATE INDEX CONCURRENTLY IF NOT EXISTS encounter_subject_id ON encounter ((resource #>> '{subject, id}'));"
      },
      {
        "name": "execution-type",
        "valueCode": "not-in-transaction"
      }
    ]
  }
}
```

| `execution-type` | Behavior |
|---|---|
| `in-transaction` | Default, also applied when the parameter is absent. Aidbox runs the SQL inside a transaction and rolls it back on failure. |
| `not-in-transaction` | Aidbox runs the SQL with autocommit on, outside any transaction. |

A migration that runs outside a transaction cannot be part of a FHIR **transaction** bundle, because the bundle itself is one atomic transaction. Post it in one of these ways instead:

| How you send it | `execution-type: not-in-transaction` |
|---|---|
| `POST /fhir/AidboxMigration` | Runs outside a transaction |
| `POST /AidboxMigration` (Aidbox format) | Runs outside a transaction |
| Entry in a `batch` bundle | Runs outside a transaction |
| Entry in a `transaction` bundle | Rejected with a 422 error |

Init Bundle examples on this page use `"type": "transaction"`. To run a non-transactional migration on startup, set the bundle type to `batch`:

```json
{
  "type": "batch",
  "resourceType": "Bundle",
  "entry": [
    {
      "request": {
        "method": "POST",
        "url": "AidboxMigration",
        "ifNoneExist": "id=create-encounter-index-concurrently"
      },
      "resource": {
        "resourceType": "AidboxMigration",
        "id": "create-encounter-index-concurrently",
        "action": "aidbox-migration-run-sql",
        "status": "to-run",
        "params": {
          "resourceType": "Parameters",
          "parameter": [
            {
              "name": "sql",
              "valueString": "CREATE INDEX CONCURRENTLY IF NOT EXISTS encounter_subject_id ON encounter ((resource #>> '{subject, id}'));"
            },
            {
              "name": "execution-type",
              "valueCode": "not-in-transaction"
            }
          ]
        }
      }
    }
  ]
}
```

{% hint style="warning" %}
Aidbox does not roll back a migration that runs outside a transaction. A failed `CREATE INDEX CONCURRENTLY` leaves an invalid index behind, and PostgreSQL does not use it for queries. Write the statement with `IF NOT EXISTS`, drop the invalid index, and run the migration again.

Find invalid indexes with:

```sql
SELECT c.relname
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE NOT i.indisvalid;
```
{% endhint %}

## Using with Init Bundle

Set the `BOX_INIT_BUNDLE` environment variable to load migrations on startup:

```yaml
volumes:
  - ./init-bundle.json:/tmp/init-bundle.json
environment:
  BOX_INIT_BUNDLE: file:///tmp/init-bundle.json
```

{% hint style="info" %}
The `ifNoneExist` parameter in the bundle entry ensures idempotency — if a migration with the same `id` already exists, it is skipped. Without `ifNoneExist`, a repeated POST returns a 409 duplicate key error.
{% endhint %}

## Combining multiple migrations

You can include multiple migrations in a single Init Bundle:

```json
{
  "type": "transaction",
  "resourceType": "Bundle",
  "entry": [
    {
      "request": {
        "method": "POST",
        "url": "AidboxMigration",
        "ifNoneExist": "id=install-us-core"
      },
      "resource": {
        "resourceType": "AidboxMigration",
        "id": "install-us-core",
        "action": "far-migration-fhir-package-install",
        "status": "to-run",
        "params": {
          "resourceType": "Parameters",
          "parameter": [
            { "name": "package", "valueString": "hl7.fhir.us.core@3.1.1" }
          ]
        }
      }
    },
    {
      "request": {
        "method": "POST",
        "url": "AidboxMigration",
        "ifNoneExist": "id=create-custom-index"
      },
      "resource": {
        "resourceType": "AidboxMigration",
        "id": "create-custom-index",
        "action": "aidbox-migration-run-sql",
        "status": "to-run",
        "params": {
          "resourceType": "Parameters",
          "parameter": [
            {
              "name": "sql",
              "valueString": "CREATE INDEX IF NOT EXISTS patient_birthdate ON patient ((resource #>> '{birthDate}'));"
            }
          ]
        }
      }
    }
  ]
}
```

## Checking migration status

List all migrations:

```http
GET /fhir/AidboxMigration
```

Each migration has a `status` field:

| Status | Description |
|--------|-------------|
| `to-run` | Migration is queued for execution |
| `done` | Migration completed successfully |

## Comparison with POST /db/migrations

Aidbox also exposes a [`POST /db/migrations`](../api/rest-api/other/sql-endpoints.md#sql-migrations) endpoint that accepts a plain `[{id, sql}]` array. The two approaches serve different use cases:

| | `AidboxMigration` + Init Bundle | `POST /db/migrations` |
|---|---|---|
| When it runs | At Aidbox startup, before serving traffic | Any time, called by an external client |
| External client required | No | Yes (needs credentials and a healthy Aidbox) |
| Idempotency | Built-in via `ifNoneExist` | Built-in via migration id tracking |
| FHIR package installs | Yes | No |
| SQL outside a transaction | Yes, via [`execution-type`](#run-sql-outside-a-transaction) in a batch bundle or a direct POST | No, use [`$psql`](../api/rest-api/other/sql-endpoints.md#execution-headers) with `Aidbox-Sql-Autocommit: true` |

Use `AidboxMigration` when you want zero-touch migrations on boot. Use `POST /db/migrations` when you need to apply migrations on demand from deployment scripts.

## See also

{% content-ref url="init-bundle.md" %}
[init-bundle.md](init-bundle.md)
{% endcontent-ref %}

{% content-ref url="../reference/system-resources-reference/core-module-resources.md" %}
[AidboxMigration resource reference](../reference/system-resources-reference/core-module-resources.md)
{% endcontent-ref %}

{% content-ref url="../tutorials/artifact-registry-tutorials/upload-fhir-implementation-guide/how-to-load-fhir-ig-with-init-bundle.md" %}
[Tutorial: Load FHIR IG with Init Bundle](../tutorials/artifact-registry-tutorials/upload-fhir-implementation-guide/how-to-load-fhir-ig-with-init-bundle.md)
{% endcontent-ref %}

{% content-ref url="../tutorials/other-tutorials/how-to-run-sql-via-init-bundle.md" %}
[Tutorial: Run SQL statements via Init Bundle](../tutorials/other-tutorials/how-to-run-sql-via-init-bundle.md)
{% endcontent-ref %}
