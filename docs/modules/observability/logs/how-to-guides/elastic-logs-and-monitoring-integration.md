---
description: Configure and manage Aidbox logging with Elastic Logs and Monitoring Integration for observability and monitoring.
---

# Elastic Logs and Monitoring Integration

Aidbox can ship its logs to Elasticsearch as JSON documents. Each day Aidbox creates a new index following the `BOX_OBSERVABILITY_ELASTICSEARCH_INDEX_PATTERN` template (default `'aidbox-logs'-yyyy-MM-dd`) and appends log batches to it. Aidbox does **not** delete old indices — without an [Index Lifecycle Management](#elasticsearch-retention-and-maintenance) (ILM) policy your cluster will eventually run out of disk.

## Enable Elasticsearch logging

Set the Elasticsearch URL — that alone enables the appender. Authentication, batch tuning, and the index template are optional.

```yaml
BOX_OBSERVABILITY_ELASTICSEARCH_URL: https://elastic.example.com:9200
# Required. Elasticsearch endpoint Aidbox writes log documents to.

BOX_OBSERVABILITY_ELASTICSEARCH_AUTH: <user>:<password>
# Optional. Basic auth credentials, if the cluster requires them.

BOX_OBSERVABILITY_ELASTICSEARCH_BATCH_SIZE: 200
# Optional. Default 200. Number of log entries per HTTP POST to Elasticsearch.

BOX_OBSERVABILITY_ELASTICSEARCH_BATCH_TIMEOUT: 60000
# Optional. Default 60000 (60s). Flush a partial batch after this many milliseconds.

BOX_OBSERVABILITY_ELASTICSEARCH_INDEX_PATTERN: "'aidbox-logs'-yyyy-MM-dd"
# Optional. Default 'aidbox-logs'-yyyy-MM-dd — one index per day.
# Examples:
#   'aidbox-logs'-yyyy-MM    — one index per month
#   'aidbox-logs'-yyyy-'W'ww — one index per ISO week

BOX_OBSERVABILITY_LOG_FILE_PATH: /var/log/aidbox/fallback.log
# Optional. If Elasticsearch is unreachable, Aidbox writes logs to this file
# instead of dropping them. Without this setting Aidbox prints fallback logs
# to stdout.
```

The pattern uses [Java `DateTimeFormatter`](https://docs.oracle.com/javase/8/docs/api/java/time/format/DateTimeFormatter.html) syntax. See the full Elasticsearch-related entries in the [settings reference](../../../../reference/all-settings.md#observability.elasticsearch.url).

{% hint style="info" %}
**Deprecated env names** — `AIDBOX_ES_URL`, `AIDBOX_ES_AUTH`, `AIDBOX_ES_BATCH_SIZE`, `AIDBOX_ES_BATCH_TIMEOUT`, `AIDBOX_ES_INDEX_PAT`, and `AIDBOX_LOGS` still work as aliases but are deprecated. Migrate to `BOX_OBSERVABILITY_*` for new deployments.
{% endhint %}

{% hint style="warning" %}
If Elasticsearch was down and logs accumulated in the fallback file (`BOX_OBSERVABILITY_LOG_FILE_PATH`), Aidbox does **not** replay them once the cluster is back. Treat the fallback file as a forensic record, not a buffer.
{% endhint %}

## Elasticsearch retention and maintenance

{% hint style="danger" %}
Aidbox creates a new index every day and never deletes old ones. Without an ILM policy in Elasticsearch the data volume grows unbounded — at typical Aidbox traffic an index is hundreds of MB to several GB per day, and a 200 GiB volume fills in roughly 6–12 months. When the disk fills, Elasticsearch flips to read-only and stops accepting log writes.
{% endhint %}

Configure ILM **on the Elasticsearch side** — Aidbox has no built-in retention. The recommended setup is a rollover-then-delete policy applied via an index template that matches the `aidbox-logs-*` pattern.

### 1. Create the ILM policy

Roll over to a fresh backing index when the current one reaches 5 GB or 7 days, and delete each backing index 30 days after rollover. Adjust `min_age`, `max_size`, and `max_age` to your retention requirements (30 / 60 / 90 days are common targets).

```http
PUT _ilm/policy/aidbox-logs-retention
Content-Type: application/json

{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "5gb",
            "max_age":  "7d"
          }
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": {
          "delete": {}
        }
      }
    }
  }
}
```

### 2. Apply the policy via an index template

```http
PUT _index_template/aidbox-logs
Content-Type: application/json

{
  "index_patterns": ["aidbox-logs-*"],
  "template": {
    "settings": {
      "index.lifecycle.name":           "aidbox-logs-retention",
      "index.lifecycle.rollover_alias": "aidbox-logs"
    }
  }
}
```

New indices created by Aidbox after this point pick up the policy automatically. Existing indices keep their previous settings — apply the policy to them explicitly if you want them rolled into the lifecycle:

```http
PUT aidbox-logs-*/_settings
{ "index.lifecycle.name": "aidbox-logs-retention" }
```

### 3. Clean up legacy indices once

If your cluster has been running without retention for a while, do a one-time cleanup of indices that pre-date the policy. **Verify the list first** — this is a destructive operation.

```bash
# List indices and their sizes
curl -s "$ES/_cat/indices/aidbox-logs-*?h=index,store.size,creation.date.string&s=index"

# Delete everything older than a specific date
curl -X DELETE "$ES/aidbox-logs-2025-*"
```

For ongoing operational cleanup prefer the ILM policy above — it is idempotent and safe under restarts.

## Capacity planning

Use these as starting points and adjust to observed usage:

| Resource | Starting value | Notes |
| --- | --- | --- |
| Disk for `aidbox-logs-*` | 30 days × peak daily index size (typically 30–100 GB) | Daily index size scales with HTTP and SQL traffic. Measure the first week before sizing the volume. |
| JVM heap | `-Xms2g -Xmx2g` for single-node, scale up to `-Xmx8g` for high write throughput | Never above 50 % of node RAM and never above ~31 GB (compressed-oops boundary). |
| Shards per index | 1 primary, 0 replicas (single-node) / 1 replica (multi-node) | Aidbox index volumes are small — extra shards add overhead without parallelism. |
| Index pattern granularity | Daily (default) | Switch to weekly (`yyyy-'W'ww`) for low-traffic deployments — fewer indices, less ILM bookkeeping. |

Single-node Elasticsearch is acceptable for log ingestion if you are willing to lose recent logs on node failure. For production, run at least three master-eligible nodes and set `index.number_of_replicas` to `1`.

## Monitoring

Watch these signals — they catch retention regressions before the cluster goes read-only:

* **Cluster health** — `GET /_cluster/health` should return `green` (or `yellow` on single-node). Page on `red` and on `status != green` for more than a few minutes.
* **Disk usage** — alert when any data node exceeds **80 %** disk usage. Elasticsearch's [low watermark](https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-cluster.html#disk-based-shard-allocation) defaults to 85 % and the flood-stage watermark to 95 %, at which point indices are marked read-only.
* **Index count and size** — `GET /_cat/indices/aidbox-logs-*?h=index,store.size,docs.count&s=index` should show the rolling window matching your retention policy. A growing list means ILM is not applied to those indices.
* **ILM status** — `GET /aidbox-logs-*/_ilm/explain` shows which indices are managed and where they are in the lifecycle. Look for `managed: false` or `step: ERROR`.
* **Aidbox fallback file** — non-empty `BOX_OBSERVABILITY_LOG_FILE_PATH` means Aidbox has been unable to reach Elasticsearch. Check it from your platform monitoring or via a sidecar.

## See also

* [Log appenders reference](../technical-reference/log-appenders.md)
* [Settings reference — Elasticsearch](../../../../reference/all-settings.md#observability.elasticsearch.url)
* [Elasticsearch ILM documentation](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html)
