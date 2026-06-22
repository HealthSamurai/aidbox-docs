---
description: ETag HTTP caching support in Aidbox for efficient resource validation and bandwidth optimization.
---

# ETAG support

The `ETag` HTTP response header is a unique identifier assigned to a specific version of a resource on a server. When a resource, like a web page or an API endpoint, changes, its `ETag` also changes. This mechanism allows client-side caching and efficient revalidation.

When a client requests a resource, it may include the `ETag` it has in an `If-None-Match` request header. If the server's current version of the resource has a matching `ETag`, it means the content hasn't changed, and the server can send back a `304 Not Modified` response without the actual resource data.

This saves bandwidth and speeds up the loading process, as the client can use its cached version. When the `ETags` don't match, it indicates the resource has changed, prompting the server to send the new version of the resource with its updated `ETag`.

{% hint style="warning" %}
Aidbox **ETags** mechanism is based on the **txid** column of the resource table in the database. If you update resources directly in the database, don't forget to update the **txid** column: `UPDATE resource SET txid = nextval('transaction_id_seq')`
{% endhint %}

### ETag Cache

{% hint style="danger" %}
**The ETag cache described in this section was removed in Aidbox 2208 (August 2022).**

ETag / `txid` values are now read directly from the database per request, so there is no cache to maintain, build, or reset. The `DELETE /$etags-cache` and `DELETE /<ResourceType>/$etags-cache` endpoints are deprecated and only return a `Deprecated!` message. A plain `GET` with `If-None-Match` always reads the resource from the database before returning `304 Not Modified` — the saving is network bandwidth, not database load.

This section is kept for historical reference only.
{% endhint %}

Historically, all ETag values were cached to make ETag queries efficient. If the cache became invalid, it could be reset with `DELETE /$etags-cache` or `DELETE /Patient/$etags-cache`.

To build the cache for a specific resourceType, Aidbox ran a query to get the `max` value of the `txid` column. To make this operation efficient, it was recommended to build an index on the `txid` column for tables where **ETag** was used:

```sql
CREATE INDEX IF NOT EXISTS <resourceType>_txid_btree ON <resourceType> using btree(txid);

CREATE INDEX IF NOT EXISTS <resourceType>_history_txid_btree ON <resourceType>_history using btree(txid);
```

{% hint style="info" %}
replace with table name, for example `CREATE INDEX IF NOT EXISTS patient_txid_btree ON patient using btree(txid); CREATE INDEX IF NOT EXISTS patient_history_txid_btree ON patient_history using btree(txid);`
{% endhint %}
