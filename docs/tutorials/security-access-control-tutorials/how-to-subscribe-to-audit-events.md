---
description: >-
  Receive Aidbox audit events as FHIR AuditEvent resources by subscribing an
  AidboxTopicDestination to the built-in audit events topic, or store them in
  the AuditEvent table
---

# How to subscribe to audit events

{% hint style="info" %}
This functionality is available starting from version 2609. If you used the `security.audit-log.*` settings before 2609, see [Migrate from the security.audit-log settings](#migrate-from-the-security-audit-log-settings).
{% endhint %}

Aidbox publishes audit events to a built-in [AidboxSubscriptionTopic](../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md). You receive them by creating an `AidboxTopicDestination` on that topic. This tutorial uses a webhook destination; Kafka, GCP Pub/Sub, and the other [destination kinds](../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md#currently-supported-channels) work the same way.

Objectives

* Subscribe a webhook to the audit events topic.
* Produce an audit event and inspect the notification.
* Check delivery status and stop audit logging.
* Filter audit events.
* Store audit events in the `AuditEvent` table and search them.

{% hint style="info" %}
Not all operations generate AuditEvents. See [Audit coverage](../../access-control/audit-and-logging.md#audit-coverage) and [Known limitations](../../access-control/audit-and-logging.md#known-limitations) for details.
{% endhint %}

## The audit events topic

| Property | Value |
|---|---|
| Topic URL | `http://health-samurai.io/fhir/core/StructureDefinition/AuditEventsR4BALP` |
| Event format | FHIR R4 AuditEvent with [IHE BALP](https://profiles.ihe.net/ITI/BALP/index.html) profiles |

The topic ships with Aidbox, so there is no `AidboxSubscriptionTopic` resource to create. Aidbox produces audit events while at least one destination is subscribed to the topic. To keep the events in Aidbox, see [Store audit events in the AuditEvent table](#store-audit-events-in-the-auditevent-table).

## Create a destination

Create an `AidboxTopicDestination` with the audit topic URL in the `topic` element. Replace the `endpoint` value with the URL of your receiver.

```http
POST /fhir/AidboxTopicDestination
content-type: application/json
accept: application/json

{
  "resourceType": "AidboxTopicDestination",
  "id": "audit-log-webhook",
  "meta": {
    "profile": [
      "http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-webhookAtLeastOnceProfile"
    ]
  },
  "kind": "webhook-at-least-once",
  "topic": "http://health-samurai.io/fhir/core/StructureDefinition/AuditEventsR4BALP",
  "content": "full-resource",
  "parameter": [
    {
      "name": "endpoint",
      "valueUrl": "https://audit.example.com/events"
    }
  ]
}
```

Aidbox responds with `201 Created` and starts producing audit events. See [Webhook AidboxTopicDestination](../subscriptions-tutorials/webhook-aidboxtopicdestination.md) for the full parameter list, including custom headers, batch size, and timeouts.

## Produce an audit event

Run any audited operation, for example create a patient:

```http
PUT /fhir/Patient/pt-1
content-type: application/json
accept: application/json

{
  "name": [{"given": ["John"], "family": "Smith"}]
}
```

## Inspect the notification

Aidbox sends a `POST` request to the endpoint. The body is a FHIR Bundle of type `history`. The first entry is an `AidboxSubscriptionStatus`, and every other entry carries one AuditEvent. The example below shortens the AuditEvent:

```json
{
  "resourceType": "Bundle",
  "type": "history",
  "timestamp": "2026-09-30T10:07:55Z",
  "entry": [
    {
      "resource": {
        "resourceType": "AidboxSubscriptionStatus",
        "status": "active",
        "type": "event-notification",
        "notificationEvent": [
          {
            "eventNumber": 1,
            "focus": {
              "reference": "AuditEvent/0199bf3c-8a2e-7c41-9d3e-5b7a0a1d2c3e"
            }
          }
        ],
        "topic": "http://health-samurai.io/fhir/core/StructureDefinition/AuditEventsR4BALP",
        "topic-destination": {
          "reference": "AidboxTopicDestination/audit-log-webhook"
        }
      }
    },
    {
      "fullUrl": "https://aidbox.example.com/fhir/AuditEvent/0199bf3c-8a2e-7c41-9d3e-5b7a0a1d2c3e",
      "request": {
        "method": "POST",
        "url": "/fhir/AuditEvent"
      },
      "resource": {
        "resourceType": "AuditEvent",
        "id": "0199bf3c-8a2e-7c41-9d3e-5b7a0a1d2c3e",
        "meta": {
          "profile": [
            "https://profiles.ihe.net/ITI/BALP/StructureDefinition/IHE.BasicAudit.PatientCreate"
          ]
        },
        "type": {
          "system": "http://terminology.hl7.org/CodeSystem/audit-event-type",
          "code": "rest",
          "display": "RESTful Operation"
        },
        "subtype": [
          {
            "system": "http://hl7.org/fhir/restful-interaction",
            "code": "create",
            "display": "create"
          }
        ],
        "action": "C",
        "outcome": "0",
        "entity": [
          {
            "what": {
              "reference": "Patient/pt-1"
            }
          }
        ]
      }
    }
  ]
}
```

Aidbox assigns a UUIDv7 to each AuditEvent `id`, and every destination receives the event with the same `id`. Use it to deduplicate events on the receiver, because an at-least-once destination can deliver the same event twice.

An operation that touches several patients produces one AuditEvent per patient reference. A search yields one AuditEvent for every patient that each returned resource references: 100 Observations of 100 patients yield 100 events, and 100 Observations of one patient yield 100 events too.

See [Notification shape](../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md#notification-shape) for the `id-only` and `empty` content modes.

## Check delivery status

Use the `$status` operation to see how many events Aidbox delivered and how many wait in the queue:

```http
GET /fhir/AidboxTopicDestination/audit-log-webhook/$status
```

If the endpoint is unavailable, the webhook destination keeps events in the queue and retries until delivery succeeds.

## Stop audit logging

Delete the destination:

```http
DELETE /fhir/AidboxTopicDestination/audit-log-webhook
```

Aidbox drops the undelivered events of a deleted destination. Wait until `messagesQueued` in `$status` reaches zero before the `DELETE` if you need them. Once the topic has no destinations, Aidbox stops producing audit events.

## Filter audit events

A destination receives every audit event unless you add `filterBy`. This destination forwards create, update, and delete events and drops reads, searches, and the rest:

```http
POST /fhir/AidboxTopicDestination
content-type: application/json
accept: application/json

{
  "resourceType": "AidboxTopicDestination",
  "id": "audit-log-changes-webhook",
  "meta": {
    "profile": [
      "http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-webhookAtLeastOnceProfile"
    ]
  },
  "kind": "webhook-at-least-once",
  "topic": "http://health-samurai.io/fhir/core/StructureDefinition/AuditEventsR4BALP",
  "content": "full-resource",
  "filterBy": [
    {
      "filterParameter": "action",
      "comparator": "eq",
      "value": "C,U,D"
    }
  ],
  "parameter": [
    {
      "name": "endpoint",
      "valueUrl": "https://audit.example.com/events"
    }
  ]
}
```

The audit events topic defines three filter parameters: `type`, `subtype`, and `action`. See [Filter audit events](../../access-control/audit-and-logging.md#filter-audit-events) for their values.

* Comma-separated values in one filter match when any of them matches.
* Several filters match when all of them match. For example, `type` = `rest` and `subtype` = `delete` select REST delete events.
* Aidbox checks the filters before it builds an event and does not build an event that no destination accepts.
* You cannot change `filterBy` on an existing destination. To change filters, delete the destination and create it again.

## Store audit events in the AuditEvent table

Aidbox can keep audit events in its own `AuditEvent` table, where you search them with the FHIR API and browse them in Aidbox UI. You turn this on with an `audit-events-recorder` destination or with the `security.audit-log.enabled` setting. Both require Aidbox to run FHIR R4 or R4B.

Aidbox stores the events without validation, so you do not need to install the BALP package. The recorder writes each event before the operation that produced it completes. If the write fails, the operation fails.

### Create a recorder destination

Create an `AidboxTopicDestination` of kind `audit-events-recorder` on the audit events topic. The recorder takes no parameters and accepts [`filterBy`](#filter-audit-events) to store part of the events.

```http
POST /fhir/AidboxTopicDestination
content-type: application/json
accept: application/json

{
  "resourceType": "AidboxTopicDestination",
  "id": "audit-events-recorder",
  "meta": {
    "profile": [
      "http://health-samurai.io/fhir/core/StructureDefinition/aidboxtopicdestination-auditEventsRecorderProfile"
    ]
  },
  "kind": "audit-events-recorder",
  "topic": "http://health-samurai.io/fhir/core/StructureDefinition/AuditEventsR4BALP"
}
```

Aidbox rejects the destination with `422` when:

* the `topic` is not the audit events topic;
* Aidbox runs a FHIR version other than R4 or R4B;
* another `audit-events-recorder` destination exists or `security.audit-log.enabled` is on. Aidbox runs one recorder at a time.

The recorder works alongside destinations of other kinds, so you can store events in Aidbox and forward them to a webhook at once. Delete the recorder to stop storing events.

### Use the security.audit-log.enabled setting

Set [`security.audit-log.enabled`](../../reference/all-settings.md#security.audit-log.enabled) to `true` and restart Aidbox:

```yaml
BOX_SECURITY_AUDIT_LOG_ENABLED: true
```

At startup, Aidbox runs a built-in recorder destination with id `security-audit-log-enabled`. The built-in recorder stores every event. Aidbox keeps it in memory, so `GET /fhir/AidboxTopicDestination` does not list it. To stop it, disable the setting and restart Aidbox. With a FHIR version other than R4 or R4B, Aidbox starts, logs an error, and stores no events. In Multibox, the setting defaults to `true` for every box.

To manage the recorder through the API or to filter what it stores, disable the setting, restart Aidbox, and [create a recorder destination](#create-a-recorder-destination).

### Search stored events

Read the latest events with the FHIR API:

```http
GET /fhir/AuditEvent?_sort=-date
```

Password change events carry DICOM subtype `110139`:

```http
GET /fhir/AuditEvent?subtype=110139
```

To browse events in the UI, open the [Audit Events](../../overview/aidbox-ui/README.md#audit-events) page of Aidbox UI.

{% hint style="warning" %}
Delete AuditEvents store the reference to the deleted resource as `ResourceType/id/_history/versionId`, for example `Observation/obs-1/_history/2`. A search by `entity=Observation/obs-1` does not return delete events.
{% endhint %}

### Record events from other systems

Aidbox works as an [Audit record repository](https://profiles.ihe.net/ITI/TF/Volume1/ch-9.html#9.1.1.3) (ARR) for FHIR AuditEvent resources:

* `POST /fhir/AuditEvent` records an event;
* `GET /fhir/AuditEvent` returns stored events.

Aidbox stores the AuditEvent resources that clients create next to the events of the recorder. It does not publish them to the audit events topic.

## Performance considerations

Audit logging costs nothing while the topic has no destinations. With a destination, the cost grows with the number of events per request. Aidbox skips the events that no destination accepts, so [filters](#filter-audit-events) cut this cost.

The `webhook-at-least-once` and `audit-events-recorder` destinations write every event to the Aidbox database before the request returns:

* Create, update, and delete operations store the event in the same transaction as the resource change.
* Read and search operations add one database write per event. A search that returns resources of many patients pays for each of them.

## Migrate from the security.audit-log settings

Since 2609, Aidbox treats the `security.audit-log.*` settings as follows:

| Setting | Since 2609 |
|---|---|
| `security.audit-log.enabled` | Stores audit events in the `AuditEvent` table through a built-in recorder, see [Use the security.audit-log.enabled setting](#use-the-security-audit-log-enabled-setting). |
| `security.audit-log.repository-url`, `security.audit-log.flush-interval`, `security.audit-log.max-flush-interval`, `security.audit-log.batch-count`, `security.audit-log.request-headers` | Deprecated and ignored. Aidbox logs a warning at startup when any of them is set. |

Before 2609, with `repository-url` set, Aidbox sent events to the external repository and kept none in its database. Since 2609, `security.audit-log.enabled` stores every event in the database and sends nothing outside. To keep forwarding events to the repository, create a webhook destination with the same endpoint. If you do not need a copy in Aidbox, disable `security.audit-log.enabled`.

Move custom headers from `security.audit-log.request-headers` to `header` parameters of the destination, and the batch size from `security.audit-log.batch-count` to `maxMessagesInBatch`. The webhook destination retries until delivery succeeds, so `flush-interval` and `max-flush-interval` have no counterpart.

{% hint style="warning" %}
The payload changed. The deprecated sender posted a Bundle of type `collection` that contained AuditEvent resources only. A topic destination posts a Bundle of type `history` with an `AidboxSubscriptionStatus` in the first entry. Check that your repository accepts this shape before you switch.
{% endhint %}
