---
description: >-
  In this tutorial, you will learn how to use Aidbox Init Bundle to run SQL statements.
---

# How to run SQL statements via Init Bundle

## Objectives

* Run SQL statements via [Init Bundle](../../configuration/init-bundle.md)
* Make it safe: don't run it on each Aidbox startup but instead do it **exactly once**.


## Before you begin

* Make sure your Aidbox version is 2607 or newer
* Setup the local Aidbox instance using getting started [guide](../../getting-started/run-aidbox-locally.md)

## Using init bundle to run SQL statements

Init bundle allows you to automatically execute a bundle of resources on Aidbox startup.
The following example shows how to use `AidboxMigration` resource to call an API for executing SQL statements **exactly once**.

The example creates an index with `CREATE INDEX CONCURRENTLY`. A plain `CREATE INDEX` takes a lock that blocks writes to the table until the build finishes, which on a large table means downtime. `CONCURRENTLY` builds the index while writes keep going. PostgreSQL forbids it inside a transaction block, so the bundle type is `batch` and the migration carries `execution-type: not-in-transaction`. See [Run SQL outside a transaction](../../configuration/migrations.md#run-sql-outside-a-transaction) for the details.

1. Create a new file for the Init Bundle.

```bash
touch init-bundle.json
```

paste the following content into the file:
```json
{
  "type": "batch",
  "resourceType": "Bundle",
  "entry": [
    {
      "request": {
        "method": "POST",
        "url": "AidboxMigration",
        "ifNoneExist": "id=create-index-on-encounter-subject-id"
      },
      "resource": {
        "action": "aidbox-migration-run-sql",
        "status": "to-run",
        "params": {
          "parameter": [
            {
              "name": "sql",
              "valueString": "CREATE INDEX CONCURRENTLY IF NOT EXISTS encounter_subject_id ON encounter ((resource #>> '{ subject, id }'));"
            },
            {
              "name": "execution-type",
              "valueCode": "not-in-transaction"
            }
          ],
          "resourceType": "Parameters"
        },
        "resourceType": "AidboxMigration",
        "id": "create-index-on-encounter-subject-id"
      }
    }
  ]
}

```

2. Modify the docker-compose.yml file to set the init bundle.

```yaml
volumes:
  - ./init-bundle.json:/tmp/init-bundle.json
environment:
  BOX_INIT_BUNDLE: file:///tmp/init-bundle.json
```

3. Restart the Aidbox instance.

```bash
docker-compose down
docker-compose up -d
```

4. Navigate to the Aidbox UI -> "DB console" tab and execute the following SQL statement to verify that the index is created.

```sql
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'encounter';
```

5. Check that the index is valid. 

```sql
SELECT c.relname, i.indisvalid
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE c.relname = 'encounter_subject_id';
```


{% hint style="info" %}
A failed entry in a `batch` init bundle logs a warning and Aidbox continues starting, unlike a `transaction` init bundle, which blocks startup. Check the startup log and the index validity above to confirm the migration did what you expected.
{% endhint %}

## Running SQL inside a transaction

Aidbox wraps migration SQL in a transaction unless you set `execution-type` to `not-in-transaction`. Drop that parameter and use `"type": "transaction"` for the bundle when you want the statement rolled back on failure, which suits statements PostgreSQL allows inside a transaction block: `CREATE TABLE`, `INSERT` for seed data.
