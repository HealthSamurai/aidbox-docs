---
description: >-
  Receive Aidbox audit events as FHIR AuditEvent resources by subscribing an
  AidboxTopicDestination to the built-in audit events topic
---

# How to subscribe to audit events

{% hint style="info" %}
This functionality is available starting from version 2609. For earlier versions, see [How to configure FHIR Audit Log (deprecated)](../../deprecated/deprecated/other/security-access-control-deprecated-tutorials/how-to-configure-audit-log.md).
{% endhint %}

Aidbox publishes audit events to a built-in [AidboxSubscriptionTopic](../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md). You receive them by creating an `AidboxTopicDestination` on that topic. This tutorial uses a webhook destination; Kafka, GCP Pub/Sub, and the other [destination kinds](../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md#currently-supported-channels) work the same way.

Objectives

* Subscribe a webhook to the audit events topic.
* Produce an audit event and inspect the notification.
* Check delivery status and stop audit logging.

{% hint style="info" %}
Not all operations generate AuditEvents. See [Audit coverage](../../access-control/audit-and-logging.md#audit-coverage) and [Known limitations](../../access-control/audit-and-logging.md#known-limitations) for details.
{% endhint %}

## The audit events topic

| Property | Value |
|---|---|
| Topic URL | `http://health-samurai.io/fhir/core/StructureDefinition/AuditEventsR4BALP` |
| Event format | FHIR R4 AuditEvent with [IHE BALP](https://profiles.ihe.net/ITI/BALP/index.html) profiles |

The topic ships with Aidbox, so there is no `AidboxSubscriptionTopic` resource to create. No setting turns audit logging on or off: Aidbox produces audit events while at least one destination is subscribed to the topic.

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
              "reference": "AuditEvent/1f6f7a5e-2f0f-4f0b-9a3c-0b7a0a1d2c3e"
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
      "fullUrl": "https://aidbox.example.com/fhir/AuditEvent/1f6f7a5e-2f0f-4f0b-9a3c-0b7a0a1d2c3e",
      "request": {
        "method": "POST",
        "url": "/fhir/AuditEvent"
      },
      "resource": {
        "resourceType": "AuditEvent",
        "id": "1f6f7a5e-2f0f-4f0b-9a3c-0b7a0a1d2c3e",
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

Aidbox assigns a random UUID to each AuditEvent `id`. Use it to deduplicate events on the receiver, because an at-least-once destination can deliver the same event twice.

An operation that touches several patients produces one AuditEvent per patient. A search that returns resources of 100 patients yields 100 events.

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

## Performance considerations

Audit logging costs nothing while the topic has no destinations. With a destination, the cost grows with the number of events per request.

The `webhook-at-least-once` destination writes every event to the Aidbox database before the request returns:

* Create, update, and delete operations store the event in the same transaction as the resource change.
* Read and search operations add one database write per event. A search that returns resources of many patients pays for each of them.

## Migrate from the security.audit-log settings

Before 2609, the `security.audit-log.enabled` setting turned audit logging on, and `security.audit-log.repository-url` forwarded events to an external repository. Since 2609 these settings are deprecated and no longer control event production.

If you forwarded events to an external repository, create a webhook destination with the same endpoint. Move custom headers from `security.audit-log.request-headers` to `header` parameters of the destination, and the batch size from `security.audit-log.batch-count` to `maxMessagesInBatch`.

{% hint style="warning" %}
The payload changed. The deprecated sender posted a Bundle of type `collection` that contained AuditEvent resources only. A topic destination posts a Bundle of type `history` with an `AidboxSubscriptionStatus` in the first entry. Check that your repository accepts this shape before you switch.
{% endhint %}

See [How to configure FHIR Audit Log (deprecated)](../../deprecated/deprecated/other/security-access-control-deprecated-tutorials/how-to-configure-audit-log.md) for the previous behavior.
