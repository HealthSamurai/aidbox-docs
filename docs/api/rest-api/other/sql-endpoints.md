---
description: Execute raw SQL queries directly in Aidbox via $sql, $psql, and $psql-cancel endpoints.
---

# SQL endpoints

## $sql
Execute SQL in Aidbox.

Supported params:
- SQL string 
- jdbc friendly array [SQL, param, param]

Example request:

{% tabs %}
{% tab title="Without jdbc params" %}
```yaml
POST /$sql?_format=yaml

SELECT count(*) FROM patient

# Response 
#
# - {count: 7}
```
{% endtab %}

{% tab title="With jdbc params" %}
```yaml
POST /$sql?_format=yaml

["SELECT count(*) FROM patient where resource->'status' = ?", true]

# Response 
#
# - {count: 2}
```
{% endtab %}
{% endtabs %}

## $psql

Run a raw multi-statement SQL script in a single request. The endpoint is what the Aidbox UI SQL Console uses; `/$notebook-psql` is an alias with identical behavior.

Request body:

```yaml
POST /$psql

{ "query": "SELECT 1; SELECT 2", "limit": 1000 }
```

- `query` — the SQL text. Sent verbatim to PostgreSQL; Aidbox does not split, trim, or rewrite it.
- `limit` (optional) — applied via JDBC `setMaxRows` to cap each result set.

Response (success):

```yaml
{ "status":  "success",
  "duration": 12,
  "query":   "SELECT 1; SELECT 2",
  "result": [
    { "type": "rset",  "data":  [{ "?column?": 1 }] },
    { "type": "rset",  "data":  [{ "?column?": 2 }] }
  ] }
```

`result` is an array of one entry per statement. `:type` is `rset` for queries that return rows (`SELECT`, `INSERT … RETURNING`, `EXPLAIN`, …) and `count` for statements that report a row count (`UPDATE`, `DELETE`, `INSERT` without `RETURNING`).

Response (error):

```yaml
{ "status":   "error",
  "error":    "ERROR: syntax error at or near \"SELEC\"\n  Position: 1",
  "duration": 4,
  "query":    "SELEC 1",
  "position": 1 }
```

### Execution headers

Every header below is optional. Defaults match a single-transaction read-write run.

| Header | Value | Effect |
|---|---|---|
| `X-Aidbox-Sql-Autocommit` | `true` | Run outside a transaction. Required for `VACUUM`, `CREATE INDEX CONCURRENTLY`, `REINDEX CONCURRENTLY`. Rejected when [`db.pass-auth-vars`](../../../reference/all-settings.md#db.pass-auth-vars) is on **and** the request carries a resolvable identity — autocommit would drop the SQL identity injection that RLS relies on. |
| `X-Aidbox-Sql-Timeout` | seconds, 1..86400 | Per-query `statement_timeout`. Empty / non-numeric / negative / out-of-range values are ignored. |
| `X-Aidbox-Sql-Read-Only` | `true` | Run as read-only. Writes raise `ERROR: cannot execute … in a read-only transaction`. |
| `X-Aidbox-Sql-Query-Id` | UUID | Tags the PG session via `application_name = aidbox-psql:<uuid>`. The same UUID is used to cancel via `/$psql-cancel`. |
| `X-Aidbox-Sql-Async` | `true` | Fire-and-forget background execution. Returns `202 { "operation-id": "<uuid>" }` immediately. The query runs server-side; result rows are not retained — only `status` / `duration` / `query` / `error` are kept in `db_scheduler.scheduled_tasks_history`. The same handler accepts the operation-id as a `query-id` for cancellation. |

### Breaking change in 2604

Prior versions returned a vector of per-statement debug objects and accepted an `execute=true` query parameter to switch between two execution paths; multi-statement scripts were split on `\n----\n`. All three behaviours were removed. Old clients that posted to `/$psql` without `execute=true` and parsed `[{:result …}, …]` need to be updated to the shape above. The endpoint URL is unchanged.

## $psql-cancel

Cancel an in-flight query (sync or async) by its tag UUID.

```yaml
POST /$psql-cancel

{ "query-id": "<uuid sent in X-Aidbox-Sql-Query-Id, or operation-id from async kick-off>" }
```

The handler runs `pg_cancel_backend(pid)` on rows in `pg_stat_activity` whose `application_name` matches `aidbox-psql:<uuid>` and returns the matched backends:

```yaml
{ "cancelled": [ true ] }
```

The same endpoint covers sync and async runs because both tag the session with the same prefix.

## SQL migrations

Aidbox provides `POST and GET /db/migrations` operations to enable SQL migrations, which can be used to migrate/transform data, create helper functions, views etc.

`POST /db/migrations` accepts array of `{id,sql}` objects. If the migration with such id wasn't executed, execute it. Execution will be stopped on the first exception. This operation returns only freshly executed migrations. It means that if there are no pending migrations, you will get an empty array in the response body.

```yaml
POST /db/migrations

- id: remove-extensions-from-patients
  sql: |
    update patient set resource = resource - 'extension'
- id: create-policy-helper
  sql: |
    create function patient_for_user(u jsonb) returns jsonb 
    as $$
        select resource || jsonb_build_object('id', id)
           from patient
           where id = u#>>'{data,patient_id}'
    $$ language sql

-- first run response
- id: remove-extensions-from-patients
  sql: ...
- id: create-policy-helper
  sql: ...
  
-- second run response
[]
```

For your application you can keep `migrations.yaml` file under source control. Add new migrations to the end of this file when this is required. With each deployment you can ensure migrations are applied on your server using a simple script like this:

```bash
curl -X POST \
  --data-binary @migrations.yaml \
  -H "Content-type: text/yaml" \
  -u $client_id:$client_secret \
  $box_url/db/migrations
```

By `GET /db/migrations`  you can introspect which migrations were already applied on the server:

```yaml
GET /db/migrations

-- resp
- id: remove-extensions-from-patients
  ts: <timestamp>
  sql: ...
- id: create-policy-helper
  ts: <timestamp>
  sql: ...

```
