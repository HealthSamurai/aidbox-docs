---
description: Send FHIR resource events to HTTP webhooks using AidboxTopicDestination with retry logic and batch support.
---

# Webhook AidboxTopicDestination

{% hint style="info" %}
This functionality is available starting from version 2410 and requires [FHIR Schema](../../modules/profiling-and-validation/fhir-schema-validator/) validation engine to be [enabled](../../modules/profiling-and-validation/fhir-schema-validator/).
{% endhint %}

{% hint style="warning" %}
**Aidbox version compatibility**

| Aidbox | Profile URL |
| --- | --- |
| ≥ 2604 | `http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-webhookAtLeastOnceProfile` |
| < 2604 | `http://aidbox.app/StructureDefinition/aidboxtopicdestination-webhook-at-least-once` |

Examples below use the ≥ 2604 form. On older Aidbox, swap the `meta.profile` URL. The webhook destination ships with Aidbox core — no separate connector JAR.
{% endhint %}

This page describes an AidboxTopicDestination, which allows sending events described by an AidboxSubscriptionTopic to a specific HTTP endpoint.

The webhook AidboxTopicDestination works in the following way:

* Aidbox stores events in the database within the same transaction as the CRUD operation.
* After the CRUD operation, Aidbox collects unsent messages (refer to the `maxEventNumberInBatch` parameter) from the database and sends them to the specified endpoint via a POST request.
* If an error occurs during sending, Aidbox will continue retrying until the message is successfully delivered.

{% content-ref url="./" %}
[.](./)
{% endcontent-ref %}

## Configuration

To use Webhook with [#aidboxsubscriptiontopic](webhook-aidboxtopicdestination.md#aidboxsubscriptiontopic) you have to create [#aidboxtopicdestination](webhook-aidboxtopicdestination.md#aidboxtopicdestination) resource.

You need to specify the following profile:

```
http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-webhookAtLeastOnceProfile
```

### Available Parameters

<table data-full-width="false"><thead><tr><th width="204">Parameter name</th><th width="192">Value type</th><th>Description</th></tr></thead><tbody><tr><td><code>endpoint</code> *</td><td>valueUrl</td><td>Webhook URL.</td></tr><tr><td><code>timeout</code></td><td>valueUnsignedInt</td><td>Timeout in seconds to attempt notification delivery (default: 30).</td></tr><tr><td><code>keepAlive</code></td><td>valueInteger</td><td>The time in seconds that the host will allow an idle connection to remain open before it is closed (default: 120, <code>-1</code> - disable).</td></tr><tr><td><code>maxMessagesInBatch</code></td><td>valueUnsignedInt</td><td>Maximum number of events that can be combined in a single notification (default: 20).</td></tr><tr><td><code>header</code></td><td>valueString</td><td>HTTP header for webhook request in the following format: <code>&#x3C;Name>: &#x3C;Value></code>. Zero or many.</td></tr></tbody></table>

\* required parameter.

## Examples

<pre class="language-json"><code class="lang-json"><strong>POST /fhir/AidboxTopicDestination
</strong>content-type: application/json
accept: application/json

{
  "resourceType": "AidboxTopicDestination",
  "meta": {
    "profile": [
      "http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-webhookAtLeastOnceProfile"
    ]
  },
  "kind": "webhook-at-least-once",
  "id": "webhook-destination",
  "topic": "http://example.org/FHIR/R5/SubscriptionTopic/QuestionnaireResponse-topic",
  "parameter": [
    {
      "name": "endpoint",
      "valueUrl": "https://aidbox.requestcatcher.com/test"
    },
    {
      "name": "timeout",
      "valueUnsignedInt": 30
    },
    {
      "name": "maxMessagesInBatch",
      "valueUnsignedInt": 20
    },
    {
      "name": "header",
      "valueString": "User-Agent: Aidbox Server"
    }
  ]
}
</code></pre>

## **Status Introspection**

Aidbox provides `$status` operation which provides short status information of the integration status:

{% tabs %}
{% tab title="Request" %}
```yaml
GET /fhir/AidboxTopicDestination/<topic-destination-id>/$status
content-type: application/json
accept: application/json
```
{% endtab %}

{% tab title="Response" %}
{% code title="200 OK" %}
```json
{
 "resourceType": "Parameters",
 "parameter": [
  {
   "valueDecimal": 2,
   "name": "messageBatchesDelivered"
  },
  {
   "valueDecimal": 0,
   "name": "messageBatchesDeliveryAttempts"
  },
  {
   "valueDecimal": 2,
   "name": "messagesDelivered"
  },
  {
   "valueDecimal": 0,
   "name": "messagesDeliveryAttempts"
  },
  {
   "valueDecimal": 0,
   "name": "messagesInProcess"
  },
  {
   "valueDecimal": 0,
   "name": "messagesQueued"
  },
  {
   "valueDateTime": "2024-10-03T07:23:00Z",
   "name": "startTimestamp"
  },
  {
   "valueString": "active",
   "name": "status"
  },
  {
   "name": "lastErrorDetail",
   "part": [
    {
     "valueString": "Connection refused",
     "name": "message"
    },
    {
     "valueDateTime": "2024-10-03T08:44:09Z",
     "name": "timestamp"
    }
   ]
  }
 ]
}
```
{% endcode %}
{% endtab %}
{% endtabs %}

Response format:

<table data-full-width="false"><thead><tr><th width="243">Property</th><th width="151">Type</th><th>Description</th></tr></thead><tbody><tr><td><code>messageBatchesDelivered</code></td><td>valueDecimal</td><td>Total number of batches that have been successfully delivered.</td></tr><tr><td><code>messageBatchesDeliveryAttempts</code></td><td>valueDecimal</td><td><p>Number of batch delivery attempts that failed.</p><p>It represents the overall failed delivery attempts.</p></td></tr><tr><td><code>messagesDelivered</code></td><td>valueDecimal</td><td>Total number of events that have been successfully delivered.</td></tr><tr><td><code>messagesDeliveryAttempts</code></td><td>valueDecimal</td><td><p>Number of delivery attempts that failed.</p><p>It represents the overall failed delivery attempts.</p></td></tr><tr><td><code>messagesInProcess</code></td><td>valueDecimal</td><td>Current number of events in the buffer being processed for delivery.</td></tr><tr><td><code>messagesQueued</code></td><td>valueDecimal</td><td>Number of events pending in the queue for send.</td></tr><tr><td><code>startTimestamp</code></td><td>valueDateTime</td><td><code>AidboxTopicDestination</code> start time in UTC.</td></tr><tr><td><code>status</code></td><td>valueString</td><td><code>AidboxTopicDestination</code> status is always <code>active</code>, which means that <code>AidboxTopicDestination</code> will try to send all received notifications.</td></tr><tr><td><code>lastErrorDetail</code></td><td>part</td><td>Information about errors of the latest failed attempt to send an event. This parameter can be repeated up to 5 times. Includes the following parameters.</td></tr><tr><td><p><code>lastErrorDetail</code></p><p><code>.message</code></p></td><td>valueString</td><td>Error message of the given error.</td></tr><tr><td><p><code>lastErrorDetail</code></p><p><code>.timestamp</code></p></td><td>valueDateTime</td><td>Timestamp of the given error.</td></tr></tbody></table>

### Counter semantics

`$status` counters and `startTimestamp` live in memory on the Aidbox instance that handled the request — they are **not** persisted to the database.

* All counters reset to `0` and `startTimestamp` is updated on Aidbox restart. This is expected, not an error.
* In a [highly available](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/highly-available-aidbox.md) deployment each instance keeps its own counters. `$status` against instance A may show `messagesDelivered=6` while the same call to instance B shows `messagesDelivered=0` — both are correct: each instance reports the deliveries it performed.
* The `AidboxTopicDestination` resource itself (and the underlying sender lifecycle) is synchronized across instances via PostgreSQL `LISTEN`/`NOTIFY`. Since 2603 the notification is sent on the same transaction as the create / update / delete, so non-creator instances see the new state once the transaction commits.

If you need a global view of delivery activity, scrape `$status` from each instance and aggregate, or rely on the receiver-side metrics.

## fhirPathCriteria examples

`fhirPathCriteria` is evaluated for every CRUD operation that matches the topic's `resource` and `supportedInteraction`. The expression has access to:

* `%current` — the resource as it will be after the operation. `null` for delete.
* `%previous` — the resource as it was before the operation. `null` for create.

Both bindings are available for `update`. Use them to encode "transition" rules — fire only when something specific changed.

**Detect that a specific identifier was just added:**

```text
%current.identifier.where(type.coding.code = 'LUMID.PROD').exists()
  and %previous.identifier.where(type.coding.code = 'LUMID.PROD').exists().not()
```

**Detect a status change to `final`:**

```text
%current.status = 'final' and %previous.status != 'final'
```

**Detect a value transition (any change to `birthDate`):**

```text
%current.birthDate != %previous.birthDate
```

**Defensive form that also fires on create** (treat absent `%previous` as "no value"):

```text
%current.status = 'final'
  and (%previous.empty() or %previous.status != 'final')
```

If `fhirPathCriteria` is left empty, every matching CRUD operation fires the trigger.

## Troubleshooting

`Internal server error: AidboxTopicDestination ... has no sender associated with it.`

The destination resource exists in the database but the in-memory **sender** (the component that actually pushes events to the webhook) is not running on the instance that served the `$status` call. Possible causes:

| Cause | Diagnosis | Fix |
| --- | --- | --- |
| Sender failed to initialize at startup | Aidbox logs contain `aidbox.topics/init-topic-service-exception` or a stack trace from `aidbox.topics.core/start-topic-service` | Restart Aidbox after fixing the underlying issue (most often a malformed `AidboxSubscriptionTopic.fhirPathCriteria` or unreachable secrets) |
| `AidboxSubscriptionTopic` referenced by `topic` cannot be resolved | Check the `topic` value matches an existing `AidboxSubscriptionTopic.url` exactly (canonical match — see the canonical matching rules in the [validator docs](../../modules/profiling-and-validation/fhir-schema-validator/README.md#canonical-matching-rules)) | Fix the URL or create the missing `AidboxSubscriptionTopic` |
| `fhirPathCriteria` fails to compile | Aidbox logs contain a FHIRPath parse error referring to the topic | Validate the expression — see [examples above](#fhirpathcriteria-examples) |
| Multi-instance: destination created on another instance very recently | Wait one second and retry — the `LISTEN`/`NOTIFY` propagation is sub-second on a healthy cluster | If the error persists across retries, treat it as a sender-init failure on the local instance and check logs. Pre-2603 builds had a known race here — upgrade if you are on an older version |

### Webhook is not firing

Walk through these checks in order — most "missing webhook" reports are `fhirPathCriteria` mismatches, not transport problems.

1. **Confirm events are being enqueued.** `GET $status` on the destination — `messagesQueued` or `messagesDelivered` should increase after a CRUD operation that should match. If neither moves, the trigger did not fire and the rest of the chain is irrelevant.
2. **Verify the topic wiring.** `AidboxTopicDestination.topic` must equal `AidboxSubscriptionTopic.url`, and the topic's `trigger.resource` and `trigger.supportedInteraction` must include the resource type and interaction (`create` / `update` / `delete`) you are testing. Recall that [PATCH maps to `update`](../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md#aidboxsubscriptiontopic).
3. **Test the FHIRPath expression in isolation.** Run the same `fhirPathCriteria` against the resource using `POST /$fhirpath` (or any FHIRPath playground) with `%current` and `%previous` bound to representative resources. A common trap: forgetting `%previous.empty()` for the `create` case.
4. **Check delivery errors.** If `messagesDelivered` is stuck below `messagesQueued`, look at `lastErrorDetail` in `$status` for the HTTP-level reason (TLS, DNS, 4xx / 5xx from the receiver). Aidbox retries indefinitely — a misconfigured endpoint produces a steadily growing `messagesDeliveryAttempts`.
5. **Verify endpoint reachability from Aidbox.** From inside the Aidbox container: `curl -v <endpoint>`. Webhook URLs that work from your laptop may be unreachable from a Kubernetes pod (private DNS, network policies, egress proxy — see [proxy configuration](../other-tutorials/how-to-configure-aidbox-to-use-proxy.md) if Aidbox is behind a corporate proxy).
6. **In multi-instance deployments, query `$status` on each instance.** A working delivery on one instance and a stuck queue on another indicates a sender that never initialized on that instance — see the table above.

For richer per-event logs, set `enableLogging: true` on the destination — Aidbox writes one [`AidboxSubscriptionStatus`](../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md) record per delivery attempt (success or failure) to stdout.
