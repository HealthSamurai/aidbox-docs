---
description: Manage Aidbox internal cache including drop cache operation for introspected tokens, FHIR schemas, and FAR-resolved canonicals.
---

# Cache

Aidbox keeps a set of in-memory caches per process: introspected access tokens, [FHIR Artifact Registry](../../artifact-registry/artifact-registry-overview.md) (FAR) resolved canonicals, route definitions, secrets, and a few smaller caches. Most cache invalidations happen automatically — see [Cache replication](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/highly-available-aidbox.md#cache-replication) for how this works in [highly available](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/highly-available-aidbox.md) deployments. The `$drop-cache` operation forces a manual refresh.

## Drop cache operation

Drops every in-memory cache on every replica. Intended for testing and debugging — when you want a known-cold cache, or to check whether behaviour you are seeing comes from a stale entry.

Writes through Aidbox invalidate the caches they affect, so this is not part of normal operation. Reach for it when something changed outside Aidbox — contents edited directly in the database, or a key rotated on an external token introspection endpoint — and you need the caches to forget what they hold.

{% code title="Example request" %}
```http
POST /$drop-cache
```
{% endcode %}

The response is `200 OK` with no body.

### What gets cleared

* Introspected access token cache
* FAR-resolved canonical resources (StructureDefinitions, ValueSets, CodeSystems, ConceptMaps, SearchParameters)
* Compiled FHIR Schemas
* Route definitions and operation handlers
* Secrets resolved from external vaults

### Multi-replica deployments

`$drop-cache` clears the caches of **every** replica, not only the one that receives the request. It publishes the drop over the same PostgreSQL `LISTEN` / `NOTIFY` channel that [cache replication](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/highly-available-aidbox.md#cache-replication) uses, and every replica subscribes to it.

One call is therefore enough: send it through the load balancer and it reaches all pods. There is no need to address each replica directly.

Propagation is asynchronous — a replica drops its caches when it receives the notification, normally within a second.

{% hint style="info" %}
Cross-replica propagation needs cache replication enabled, which is the default. With [`BOX_CACHE_REPLICATION_DISABLE`](../../reference/all-settings.md#cache-replication-disable) set, `$drop-cache` affects only the replica that receives it.
{% endhint %}
