---
description: Get automatic index suggestions for Aidbox search queries. API supports FHIR search parameters, date ranges, tokens, and dot expressions.
---

# Get Suggested Indexes

Since version 2211, Aidbox can suggest indexes for Search API.&#x20;

{% hint style="warning" %}
Index suggestion API is in the draft stage.
{% endhint %}

Supported FHIR Search parameter types:

* string
* number
* date
* token
* quantity
* reference
* uri

Supported special FHIR parameters:

* \_id
* \_ilike
* \_text
* \_content
* \_lastUpdated

Supported Aidbox search:

* \_createdAt
* [Dot expressions](../../api/rest-api/aidbox-search.md#dot-expressions)

Not supported:

* zen Search Parameters
* \_filter
* _include,_ \_revinclude
* chained Search Parameters

### aidbox.index/suggest-index

Required parameters: `resource-type` and `search-param`.

```yaml
POST /rpc

method: aidbox.index/suggest-index
params:
  resource-type: <resourceType>
  search-param: <searchParameter>
```

Example:

```yaml
POST /rpc

method: aidbox.index/suggest-index
params:
  resource-type: Observation
  search-param: date
```

Result:

```yaml
result:
  - index-name: observation_date_param_knife_date_min_tstz
    name: date
    resource-type: Observation
    statement: >-
      CREATE INDEX CONCURRENTLY IF NOT EXISTS
      "observation_date_param_knife_date_min_tstz" ON "observation" USING btree
      ((knife_extract_min_timestamptz("observation".resource,
      '[["effective","Period","start"],["effective","Period","end"],["effective","dateTime"],["effective","Timing","event"],["effective","instant"]]'))
      )
    subtypes:
      - null
      - eq
      - ne
      - lt
      - le
      - btw
    type: date
  - index-name: observation_date_param_knife_date_max_tstz
    name: date
    resource-type: Observation
    statement: >-
      CREATE INDEX CONCURRENTLY IF NOT EXISTS
      "observation_date_param_knife_date_max_tstz" ON "observation" USING btree
      ((knife_extract_max_timestamptz("observation".resource,
      '[["effective","Period","start"],["effective","Period","end"],["effective","dateTime"],["effective","Timing","event"],["effective","instant"]]'))
      )
    subtypes:
      - null
      - eq
      - ne
      - gt
      - ge
      - btw
    type: date
```

Suggested two indexes: first one to search using `lt`, `le` and `eq` prefixes, second one to search using`gt`, `ge`, `eq` prefixes.&#x20;

### aidbox.index/suggest-index-query

You can get all indexes for specific query using suggest-index-query.

Required parameters: `resource-type` and `query`.

```yaml
POST /rpc

method: aidbox.index/suggest-index-query
params:
  resource-type: <resourceType>
  query: <query>
```

Example:

```yaml
POST /rpc

method: aidbox.index/suggest-index-query
params:
  resource-type: Observation
  query: date=gt2022-01-01&_id=myid
```

Response:

```yaml
result:
  - index-name: observation_date_param_knife_date_min_low_tstz
    name: date
    resource-type: Observation
    statement: >-
      CREATE INDEX CONCURRENTLY IF NOT EXISTS
      "observation_date_param_knife_date_min_low_tstz" ON "observation" USING btree
      ((knife_extract_min_timestamptz("observation".resource,
      '[["effective","dateTime"],["effective","Period","start"],["effective","Timing","event"],["effective","instant"]]'))
      )
    subtypes:
      - null
      - ge
      - eq
      - sa
      - gt
      - ne
      - le
      - lt
    type: date
  - index-name: observation_date_param_knife_date_max_high_tstz
    name: date
    resource-type: Observation
    statement: >-
      CREATE INDEX CONCURRENTLY IF NOT EXISTS
      "observation_date_param_knife_date_max_high_tstz" ON "observation" USING btree
      ((knife_extract_max_timestamptz("observation".resource,
      '[["effective","dateTime"],["effective","Period","end"],["effective","Timing","event"],["effective","instant"]]'))
      )
    subtypes:
      - null
      - ge
      - eq
      - gt
      - ne
      - le
      - lt
      - eb
    type: date
  - index-name: observation_date_param_knife_date_max_tstz
    name: date
    resource-type: Observation
    statement: >-
      CREATE INDEX CONCURRENTLY IF NOT EXISTS
      "observation_date_param_knife_date_max_tstz" ON "observation" USING btree
      ((knife_extract_max_timestamptz("observation".resource,
      '[["effective","dateTime"],["effective","Period","start"],["effective","Period","end"],["effective","Timing","event"],["effective","instant"]]'))
      )
    subtypes:
      - btw
    type: date
  - index-name: observation_date_param_knife_date_min_tstz
    name: date
    resource-type: Observation
    statement: >-
      CREATE INDEX CONCURRENTLY IF NOT EXISTS
      "observation_date_param_knife_date_min_tstz" ON "observation" USING btree
      ((knife_extract_min_timestamptz("observation".resource,
      '[["effective","dateTime"],["effective","Period","start"],["effective","Period","end"],["effective","Timing","event"],["effective","instant"]]'))
      )
    subtypes:
      - btw
    type: date
  - index-name: observation_resource_id
    name: id
    resource-type: Observation
    statement: >-
      CREATE INDEX CONCURRENTLY IF NOT EXISTS "observation_resource_id" ON
      "observation" USING btree (("observation".id) )
    subtypes:
      - in
      - null
    type: id
```

Suggested indexes will increase performance of Observation.date and Observation.\_id. The date parameter now returns 4 indexes: `_min_low_tstz` and `_max_high_tstz` for comparison operators (`ge`, `gt`, `le`, `lt`, `eq`, `ne`, `sa`, `eb`), plus `_min_tstz` and `_max_tstz` for the `btw` (between) operator.

## Index name changes

Some suggested index names changed so the same SearchParameter can coexist across resource types and so two distinct GIN flavors aren't collapsed under one name.

### Full-resource GIN: `resource` → `<rt>_resource_jsonb`

The full-resource fallback GIN (used by token and reference parameters that don't have a dedicated path expression) used to suggest a bare `resource` index. That name collides the moment a second resource type wants the same kind of index. The suggester now scopes it by table:

| Resource | Old name | New name |
|---|---|---|
| Patient | `resource` | `patient_resource_jsonb` |
| Observation | `resource` | `observation_resource_jsonb` |

{% hint style="info" %}
If you've created the old unscoped `resource` index by hand, it still works (Postgres doesn't care what the index is called) — but `aidbox.index/list-search-param-indexes` won't recognize it as a candidate. Drop it manually and let the suggester rebuild under the new name.
{% endhint %}

### String knife: `<sp>_param_knife_string` split into fuzzy and exact

The string knife generators used to suggest a single `<rt>_<sp>_param_knife_string` index for both:

* fuzzy / contains / starts-with matching (`gin_trgm_ops` over `aidbox_text_search(extract_text(...))`), and
* exact equality (`gin_default` over the raw `extract_text(...) text[]`).

Same name, two different `USING gin (…)` bodies — only one could exist at a time. The suggester now emits two distinct names:

| Modifiers covered | Index name |
|---|---|
| default, `:contains`, `:starts`, `:ends`, `:otherwise`, `:co`, `:sw`, `:ew` | `<rt>_<sp>_param_knife_string` |
| `:eq`, `:exact` | `<rt>_<sp>_param_knife_string_exact` |

Creating both gives full-modifier coverage. Existing deployments that ran one or the other under the old name should re-suggest and create whichever variant is missing.
