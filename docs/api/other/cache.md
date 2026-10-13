---
description: Manage Aidbox internal cache including drop cache operation for introspected tokens, FHIR schemas, and FAR-resolved canonicals.
---

# Cache

Aidbox keeps a set of in-memory caches per process: introspected access tokens, [FHIR Artifact Registry](../../artifact-registry/artifact-registry-overview.md) (FAR) resolved canonicals, route definitions, secrets, and a few smaller caches. Most cache invalidations happen automatically — see [Cache replication](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/highly-available-aidbox.md#cache-replication) for how this works in [highly available](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/highly-available-aidbox.md) deployments. The `$drop-cache` operation forces a manual refresh.

## Drop cache operation

Drops every in-memory cache on every replica. Most useful right after an out-of-band change to FAR contents (an Implementation Guide loaded via init bundle, an external token introspection rotation, etc.) when you don't want to wait for the next automatic invalidation tick.

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
Cross-replica propagation needs cache replication enabled, which is the default. With `BOX_CACHE_REPLICATION_DISABLE` set, `$drop-cache` affects only the replica that receives it.
{% endhint %}

Under normal operation cache invalidation happens on its own — `$drop-cache` is an emergency lever, not the routine path.
