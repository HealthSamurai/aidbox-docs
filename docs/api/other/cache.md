---
description: Manage Aidbox internal cache including drop cache operation for introspected tokens, FHIR schemas, and FAR-resolved canonicals.
---

# Cache

Aidbox keeps a set of in-memory caches per process: introspected access tokens, [FHIR Artifact Registry](../../artifact-registry/artifact-registry-overview.md) (FAR) resolved canonicals, route definitions, secrets, and a few smaller caches. Most cache invalidations happen automatically — see [Cache replication](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/highly-available-aidbox.md#cache-replication) for how this works in [highly available](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/highly-available-aidbox.md) deployments. The `$drop-cache` operation forces a manual refresh.

## Drop cache operation

Drops every in-memory cache on the receiving replica. Most useful right after an out-of-band change to FAR contents (an Implementation Guide loaded via init bundle, an external token introspection rotation, etc.) when you don't want to wait for the next automatic invalidation tick.

{% code title="Example request" %}
```http
POST /$drop-cache
```
{% endcode %}

The response is `200 OK` with no body. The operation is local to the replica that receives the request.

### What gets cleared

* Introspected access token cache
* FAR-resolved canonical resources (StructureDefinitions, ValueSets, CodeSystems, ConceptMaps, SearchParameters)
* Compiled FHIR Schemas
* Route definitions and operation handlers
* Secrets resolved from external vaults

### Multi-replica deployments

`$drop-cache` only affects the replica that receives the request. Two consequences:

* Calls through a load balancer hit one replica per request — they will not clear caches on the other pods.
* For an HA-wide refresh (for example after loading an IG that other replicas haven't observed yet), call `$drop-cache` against each replica's pod address directly. See the [HA cache invalidation guidance](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/highly-available-aidbox.md#cache-invalidation-after-ig-loading) for an example loop.

Under normal operation the cross-replica cache propagation runs automatically over PostgreSQL `LISTEN` / `NOTIFY` — `$drop-cache` is an emergency lever, not the routine path.
