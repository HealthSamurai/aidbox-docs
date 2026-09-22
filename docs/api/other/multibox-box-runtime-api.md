---
description: Stop and start the runtime of a single Multibox box without deleting its database, metadata, or ownership, using the multibox/unload-box, multibox/reload-box, and status RPCs.
---

# Multibox box runtime API

Multibox keeps every box that has served a request resident in memory, holding its connection pools, caches, and background workers. A box that nobody uses keeps those resources until the process restarts.

These RPCs let you release one box's runtime and bring it back later. Unloading touches no persistent state: the box's database, its `Box` resource, and its participants stay as they were, and the next request to that box starts it again with the same configuration and data.

For how to run Multibox, see [Run Multibox locally](../../tutorials/security-access-control-tutorials/run-multibox-locally.md). For the RPC transport these methods use, see the [RPC API](rpc-api.md).

{% hint style="warning" %}
These RPCs exist on the Multibox manager, not inside a box. Send them to the bare cluster domain, without the `x-box` header and without a box subdomain. A request that carries a box identifier lands inside that box, where these methods are undefined.
{% endhint %}

## Permissions

A caller must authenticate as the Multibox superuser (`AIDBOX_SUPERUSER`) or as a participant of the box in question. Anonymous callers get `No user session`.

## Unload a box: `multibox/unload-box`

Stops the box runtime and releases its resources.

```http
POST /rpc
Content-Type: application/json
```

```yaml
method: multibox/unload-box
params:
  id: acme
```

```yaml
result:
  id: acme
  loaded: false
  exists: true
  database: true
  changed: true
```

| Field | Meaning |
|---|---|
| `loaded` | Whether a runtime is resident after the call |
| `exists` | Whether the `Box` resource exists |
| `database` | Whether the box's Postgres database exists |
| `changed` | Whether this call stopped a runtime |

The call is idempotent. Unloading a box that is already unloaded answers `changed: false` and stops nothing.

## Start a box again: `multibox/reload-box`

Stops the runtime if one is resident, then starts the box again.

```yaml
method: multibox/reload-box
params:
  id: acme
```

```yaml
result:
  id: acme
  loaded: true
  exists: true
  database: true
  changed: true
  unloaded: true
```

`unloaded` reports whether a runtime was stopped before the start. For a box that was already unloaded, it is `false` and the call starts the box.

The next request to an unloaded box starts it, so this method earns its place elsewhere: restarting a resident box without a deploy, or warming a box before traffic arrives.

## Read one box: `multibox/get-box-status`

```yaml
method: multibox/get-box-status
params:
  id: acme
```

```yaml
result:
  id: acme
  loaded: false
  exists: true
  database: true
```

`exists` and `database` answer separate questions. `multibox/create-box` writes the `Box` resource before it creates the database, and `multibox/delete-box` drops the database before it deletes the resource, so the two can disagree while either operation is in flight.

## Read every box: `multibox/list-box-statuses`

```yaml
method: multibox/list-box-statuses
```

```yaml
result:
  list:
    - id: acme
      loaded: true
      exists: true
      database: true
    - id: beta
      loaded: false
      exists: true
      database: true
  constraints:
    max-boxes: 10
    cur-boxes: 2
```

The superuser sees every box. A participant sees the boxes they participate in.

Use this method rather than `multibox/list-boxes` when you authenticate as the superuser: `multibox/list-boxes` filters by participant, and the superuser participates in no box, so it answers an empty list.

## Behavior to plan for

**Unloading is not sticky.** Any request routed to an unloaded box starts it again, including a health check or a probe from a load balancer. To keep a box unloaded, stop sending it traffic.

**A cold start costs seconds.** The first request after an unload waits for the box to start. Requests that arrive during that start wait for the same runtime rather than starting a second one.

**In-flight requests are not drained.** A request already running inside the box fails when its connection pools close. Unload a box when it is idle.

**Repeat calls are safe.** Concurrent unload and reload calls for one box run one at a time, and concurrent requests to an unloaded box produce a single runtime.

## Errors

Every failure answers HTTP 422 with a message:

```yaml
error:
  message: No box with id - acme
```

| Message | Cause |
|---|---|
| `No user session` | The caller did not authenticate |
| `No box with id - <id>` | No `Box` resource with that identifier |
| `You do not have access to this box` | The caller is neither the superuser nor a participant |
| `The legacy job scheduler is running; stopping a box would stop it for every box in this instance` | See below |

The job scheduler behind `AidboxJob` keeps one registry for the whole process, shared by every box in the instance. Stopping one box would stop that scheduler for all of them, so `multibox/unload-box` and `multibox/reload-box` refuse while it runs. Multibox does not start this scheduler, so you will not meet this error in a default deployment.

## Example: release an idle box

```shell
curl -u admin:secret -X POST https://my.multibox.example/rpc \
  -H 'content-type: application/json' \
  -d '{"method": "multibox/unload-box", "params": {"id": "acme"}}'
```

Read the result before you act on it. A `changed: false` answer means the box was already unloaded.
