---
description: Inspect tables, observe active queries, and run maintenance operations (VACUUM, ANALYZE, REINDEX, TRUNCATE) against the Aidbox Postgres database via the aidbox.pg/* RPCs.
---

# Database maintenance RPCs

The `aidbox.pg/*` RPC family exposes a thin layer over Postgres' introspection (`pg_stat_*`, `pg_indexes`) and maintenance DDL (`VACUUM`, `ANALYZE`, `REINDEX`, `TRUNCATE`). The same RPCs power the [Database tab in Aidbox UI](../overview/aidbox-ui/README.md#database) — reach for them when scripting backups, building dashboards, or running ad-hoc maintenance.

{% hint style="success" %}
For interactive use, open the **Database** page in Aidbox UI. It calls the RPCs below and renders the results as a sortable, paginated table per section.
{% endhint %}

`aidbox.pg/reindex-table`, `aidbox.pg/truncate-table`, and the `:schema` / `:schemas` / `:all-schemas` parameters on `aidbox.pg/tables` (plus the `:schema` parameter on `get-table` / `vacuum-table` / `analyze-table`) are available since Aidbox 2605. Earlier versions only see the `public` schema and lack the new RPCs.

## Listing tables: `aidbox.pg/tables`

Returns one row per table with size, row-count estimate, index/toast share, and recency of vacuum/analyze.

```yaml
POST /rpc

method: aidbox.pg/tables
params:
  all-schemas: true        # see all user schemas; omit for public-only (legacy default)
  q: pat                   # ILIKE '<q>%' against table name
  limit: 100               # default 100
```

| Parameter | Behavior |
|---|---|
| `q` | `ILIKE '<q>%'` filter on the table name. Optional. |
| `limit` | Max rows. Default `100`. |
| `schema` | Restrict to one schema. Optional. |
| `schemas` | Array of schemas. Optional. |
| `all-schemas` | `true` lists tables across every user schema. Without any of `schema`/`schemas`/`all-schemas`, only `public` is returned — this preserves the legacy default so existing callers (old admin console) keep working. `pg_catalog`, `information_schema`, and `pgagent` are always excluded. |

Each row carries `table_schema`, the table name, an estimated row count from `pg_class.reltuples`, total / index / toast sizes in both pretty (`text`) and bytes (`bigint`) forms, plus minutes since the last manual or autonomous vacuum/analyze.

```yaml
result:
  - table_schema: public
    table_name: patient
    num_rows: 4231
    total: 28 MB
    total_size: 29360128
    index: 6256 kB
    index_size: 6406144
    index_part: 21
    toast: 8192 bytes
    toast_size: 8192
    toast_part: 0
    options: null
    last_autovacuum: 12         # minutes ago; null if never
    last_vacuum: null
    last_analyze: null
    last_autoanalyze: 12
```

## Inspecting a table: `aidbox.pg/get-table`

One-shot detail view: the same row `aidbox.pg/tables` would return, plus a per-index breakdown from `pg_indexes` + `pg_stat_all_indexes` and a single sample row.

```yaml
POST /rpc

method: aidbox.pg/get-table
params:
  schema: public           # optional; defaults to "public"
  table: patient
```

```yaml
result:
  table:
    table_schema: public
    table_name: patient
    num_rows: 4231
    # ... same shape as aidbox.pg/tables
  indexes:
    - index_name: patient_pkey
      index_size: 152 kB
      unique: Y
      number_of_scans: 18221
      tuples_read: 18221
      tuples_fetched: 18221
  row:                             # first row of the table; full resource JSON
    id: pat-1
    resource: { ... }
  offset: 0
```

For backwards compatibility, `table` may also be passed as a `<schema>.<name>` string; the leading segment overrides `schema`.

## Maintenance operations

All four maintenance RPCs accept the same shape: `{:table "<name>" :schema "<schema>"}`. `schema` is optional; identifiers are validated against `[A-Za-z0-9_]` and quoted before being spliced into the DDL.

### `aidbox.pg/vacuum-table`

Runs `VACUUM` on the table. Pass `analyze: true` to run `VACUUM ANALYZE`. Reclaims dead-tuple space and (optionally) refreshes planner statistics. Concurrent with reads and writes.

```yaml
POST /rpc

method: aidbox.pg/vacuum-table
params:
  schema: public
  table: patient
  analyze: true            # optional — runs VACUUM ANALYZE
```

### `aidbox.pg/analyze-table`

Runs `ANALYZE` on the table to refresh planner statistics. Use after bulk loads or whenever query plans look stale.

```yaml
POST /rpc

method: aidbox.pg/analyze-table
params:
  schema: public
  table: patient
```

### `aidbox.pg/reindex-table`

Runs `REINDEX TABLE` to rebuild every index on the table. Locks the table for writes until completion — prefer running it during a maintenance window.

```yaml
POST /rpc

method: aidbox.pg/reindex-table
params:
  schema: public
  table: patient
```

### `aidbox.pg/truncate-table`

Runs `TRUNCATE TABLE` — **permanently deletes every row in the table**. There is no `WHERE` clause and the operation is not undoable. The Aidbox UI requires a confirmation dialog before issuing this RPC; treat it the same way in scripts.

```yaml
POST /rpc

method: aidbox.pg/truncate-table
params:
  schema: public
  table: patient
```

{% hint style="danger" %}
`TRUNCATE` removes all rows without producing history entries. To delete resources with full audit/history tracking, use the FHIR API or `aidbox.bulk/*` operations instead.
{% endhint %}

## Observing running queries

Backs the **Running Queries** subpage. Reads `pg_stat_activity` and lets you cancel or terminate individual backends.

### `aidbox.pg/active-queries`

Returns one row per active backend (excluding the caller's own), sorted by `query_start` so the longest-running shows first.

```yaml
POST /rpc

method: aidbox.pg/active-queries
params: {}
```

```yaml
result:
  - pid: 2391
    usename: postgres
    application_name: aidbox
    state: active
    query_start: 2026-05-12T09:14:21.117Z
    duration: 32            # seconds since query_start
    wait_event_type: Lock
    wait_event: relation
    query: SELECT * FROM patient WHERE …
```

### `aidbox.pg/cancel-query` and `aidbox.pg/terminate-query`

`cancel-query` asks Postgres to abort the currently running statement (`pg_cancel_backend`); the connection stays open. `terminate-query` kills the whole connection (`pg_terminate_backend`) — clients see a "terminating connection due to administrator command" error. Prefer cancel over terminate when possible.

```yaml
POST /rpc

method: aidbox.pg/cancel-query    # or aidbox.pg/terminate-query
params:
  pid: 2391
```

Both return `{result: {pid: <pid>, result: <pg-message>}}`.

## See also

* [Aidbox UI — Database](../overview/aidbox-ui/README.md#database) — the page that ties these RPCs together.
* [Search Parameters Usage Statistics](../deployment-and-maintenance/indexes/search-parameter-usage-stats.md) — `aidbox.index/get-search-param-stats` and related RPCs.
* [SQL endpoints](../api/rest-api/other/sql-endpoints.md) — the `$psql` endpoint for arbitrary SQL.
