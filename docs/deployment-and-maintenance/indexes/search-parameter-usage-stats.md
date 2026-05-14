---
description: Collect, inspect and reset per-search-parameter usage statistics. Aidbox records every search call so you can rank "hot" SearchParameters and decide which indexes to create.
---

# Search Parameter Usage Statistics

Aidbox records every FHIR search request into a Postgres table and exposes it via RPC. The numbers let you rank hot search parameters, decide which suggested indexes are worth creating, and verify after the fact that the right index ended up doing the work.

## What is collected

A row exists in `_aidbox_search_param_stats` per unique `(resource_type, search_params)` — what we call a **shape**. The `search_params` column is a `text[]` of `<sp-name>[:modifier]` keys, sorted and deduplicated, so:

- `GET /Patient?name=John&gender=male` → shape `["gender", "name"]`
- `GET /Patient?gender:in=…` → shape `["gender:in"]` (a different row from `gender`)
- `GET /Patient?name=X&name=Y` → same row as one `name=X` (per-key dedupe)

Chained and `_has` queries emit one shape per touched resource type — `GET /Observation?subject:Patient.name=John` produces an `Observation [subject]` shape and a `Patient [name]` shape.

Each row stores:

| Column | Meaning |
|---|---|
| `calls` | Number of completed searches that touched this shape |
| `total_time_ms` | Sum of measured response durations |
| `min_time_ms` / `max_time_ms` / `mean_time_ms` | Distribution over `calls` |
| `last_used_at` | `timestamptz` of the most recent matching request |

Recording happens on the search hot path after the response is built. It's non-blocking — samples land in an in-memory buffer; a background worker UPSERTs the buffer into Postgres on a fixed interval. Failed searches are not recorded.

## Reading the stats

### `aidbox.index/get-search-param-stats`

```yaml
POST /rpc

method: aidbox.index/get-search-param-stats
params:
  resource-type: Patient        # optional; or :resource-types ["Patient" "Practitioner"]
  search-param: name            # optional; filters to shapes containing this SP
  by: shape                     # default; or :param to aggregate across shapes
  order-by: calls               # default; or :mean-time-ms, :total-time-ms, :last-used
  limit: 100                    # default
  offset: 0                     # default
  flush-first: true             # drain the in-memory buffer first so the read is fresh
```

`:by :shape` returns one row per `(resource_type, search_params)`:

```yaml
result:
  - resource_type: Patient
    search_params: [gender, name]
    calls: 423
    total_time_ms: 12480.0
    min_time_ms: 4.2
    max_time_ms: 287.6
    mean_time_ms: 29.5
    last_used_at: 2026-05-13T12:04:18.227Z
```

`:by :param` aggregates across shapes — one row per `(resource_type, single SP)`. Modifiers roll up under the bare SP (`name:contains` adds to `name`'s totals). The result includes a `has_index` boolean computed from `pg_indexes`:

```yaml
result:
  - resource_type: Patient
    search_param: name
    calls: 781
    total_time_ms: 19_200.4
    mean_time_ms: 24.6
    last_used_at: 2026-05-13T12:04:18.227Z
    has_index: true
```

#### Filtering

| Parameter | Behavior |
|---|---|
| `resource-type` | Single base. |
| `resource-types` | Array — for multi-base SearchParameters. |
| `search-param` | Limit to shapes containing this SP under any modifier. |
| `flush-first` | Force a synchronous drain of the in-memory buffer before reading. |

### `aidbox.index/reset-search-param-stats`

Wipe collected stats. The scope mirrors `get-search-param-stats`:

```yaml
POST /rpc

method: aidbox.index/reset-search-param-stats
params:
  # All four params are optional. Combinations:
  #
  #   {}                                            -> wipe everything
  #   {resource-type: Patient}                      -> wipe one rt
  #   {resource-type: Patient, search-param: name}  -> wipe any shape on Patient containing 'name'
  #                                                    (including :contains, :exact, etc)
  #   {resource-type: Patient, search-params: [gender, name]}
  #                                                 -> wipe exactly that one shape
  resource-type: Patient
  search-param: name
```

A scoped reset preserves the in-memory buffer for any resource type, search parameter, or shape outside the scope — unflushed samples for other entities survive.

## Listing indexes for a SearchParameter

`aidbox.index/list-search-param-indexes` ties together three sources: the index-suggestion engine (what indexes *should* exist), `pg_indexes` (what *does* exist), and `_aidbox_search_param_stats` (what callers are actually doing).

```yaml
POST /rpc

method: aidbox.index/list-search-param-indexes
params:
  resource-types: [Patient]    # or :resource-type Patient for single-base SPs
  search-param: name
  flush-first: true            # so :hit_calls reflects the latest samples
```

Each result row covers one `(base, candidate-index)` pair. Multi-base SPs return one row per base.

```yaml
result:
  - base: Patient
    name: patient_name_param_knife_string
    definition: >-
      CREATE INDEX CONCURRENTLY IF NOT EXISTS
      "patient_name_param_knife_string" ON "patient" USING gin
      ((aidbox_text_search(knife_extract_text(...))) gin_trgm_ops)
    subtypes: [null, contains, ew, starts, sw, ends, otherwise, co]
    exists: true
    building: false
    scans: 4221
    tuples_read: 17_330
    tuples_fetched: 1_287
    size_bytes: 327_680
    hit_calls: 781
    hit_shapes: 3
    hit_last_used_at: 2026-05-13T12:04:18.227Z
```

| Field | Source | Meaning |
|---|---|---|
| `name` / `definition` | suggest-index | Candidate index name + the `CREATE INDEX CONCURRENTLY` statement |
| `subtypes` | suggest-index | Which modifiers this index covers (`null` = default, the rest are FHIR modifier codes) |
| `exists` | `pg_indexes` | The index already exists |
| `building` | `pg_stat_progress_create_index` | A `CREATE INDEX` is in flight against this name |
| `scans` / `tuples_read` / `tuples_fetched` | `pg_stat_user_indexes` | Postgres-side counters since index creation. `0` for non-existing indexes. |
| `size_bytes` | `pg_relation_size` | On-disk size in bytes. `0` for non-existing indexes. |
| `hit_calls` / `hit_shapes` | `_aidbox_search_param_stats` | How many recorded calls would have used this index, across how many shapes |
| `hit_last_used_at` | `_aidbox_search_param_stats` | Most recent matching call |

Rows are sorted hottest-first (`hit_calls` desc). A high `hit_calls` on a row where `exists: false` is the textbook "create this index" signal.

## Dropping indexes

`aidbox.index/drop-search-param-index` issues `DROP INDEX CONCURRENTLY` and refuses to drop anything outside the suggester's candidate set for the given `(resource-type, search-param)` pair — so the RPC can't be misused to drop unrelated indexes.

```yaml
POST /rpc

method: aidbox.index/drop-search-param-index
params:
  resource-type: Patient
  search-param: name
  index-name: patient_name_param_knife_string
```

A successful response is `{result: {dropped: "<index-name>"}}`. The index name must be one of those returned by `aidbox.index/list-search-param-indexes` for the same `(rt, sp)`.

## Usage: deciding which indexes to create

A typical workflow:

{% stepper %}
{% step %}
**Let the box serve real traffic.** Stats only accumulate on completed searches; nothing useful comes from an empty `_aidbox_search_param_stats` table. Generate synthetic load if needed.
{% endstep %}

{% step %}
**Find the slowest unindexed parameters.** Call `aidbox.index/get-search-param-stats` with `:by :param`, sort by `mean_time_ms` desc, filter to `has_index: false`. The top of the list is the worst offender.
{% endstep %}

{% step %}
**Inspect the candidates.** Call `aidbox.index/list-search-param-indexes` for that `(resource-type, search-param)` pair. Find the row with the highest `hit_calls` where `exists: false`.
{% endstep %}

{% step %}
**Create the index in the background.** Issue `POST /$psql` with the row's `definition` (the `CREATE INDEX CONCURRENTLY …` statement). Use `Aidbox-Sql-Async: true` so the HTTP request returns immediately while Postgres keeps building.
{% endstep %}

{% step %}
**Watch for completion.** Refresh `aidbox.index/list-search-param-indexes` periodically. The row's `building` flag stays `true` until Postgres finishes, then flips to `exists: true`. After a few subsequent searches the `scans` column climbs — confirmation that Postgres actually used the new index.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
The Aidbox UI's **SearchParameter → Indexes** tab does all of this for you — same RPCs, formatted as a sortable table with one-click create/drop.
{% endhint %}

## See also

* [Get Suggested Indexes](get-suggested-indexes.md) — the underlying `aidbox.index/suggest-index` and `…/suggest-index-query` RPCs.
* [Create Indexes Manually](create-indexes-manually.md) — DDL recipes for raw `CREATE INDEX` statements.
