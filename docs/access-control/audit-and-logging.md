---
description: Track access to patient data with FHIR BALP audit events, resource versioning, and OpenTelemetry structured logging.
---

# Audit and Logging

Audit logging is essential in healthcare systems because it:

* **Protects Patient Privacy**: Tracks who accessed sensitive medical records, ensuring compliance with privacy laws like HIPAA
* **Prevents Data Breaches**: Helps detect and investigate unauthorized access to patient data
* **Ensures Accountability**: Records all changes to medical records, creating a clear trail of who modified what and when
* **Supports Legal Requirements**: Provides evidence for compliance audits and legal investigations

Aidbox provides comprehensive audit and logging capabilities:

* FHIR Basic Audit Logging Profile (BALP) implementation
* FHIR Resource versioning
* Logging configuration

## FHIR Basic Audit Logging Profile (BALP) implementation

Aidbox supports the FHIR [BALP](https://profiles.ihe.net/ITI/BALP/index.html) Implementation Guide.

{% hint style="info" %}
Since version 2609, Aidbox publishes audit events to a built-in subscription topic. The `security.audit-log.*` settings are deprecated. For earlier versions, see [How to configure FHIR Audit Log (deprecated)](../deprecated/deprecated/other/security-access-control-deprecated-tutorials/how-to-configure-audit-log.md).
{% endhint %}

### Audit events topic

Aidbox publishes audit events to a built-in [AidboxSubscriptionTopic](../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md):

```
http://health-samurai.io/fhir/core/StructureDefinition/AuditEventsR4BALP
```

Each event is a FHIR R4 AuditEvent resource. To receive events, create an [AidboxTopicDestination](../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md#aidboxtopicdestination) with this URL in the `topic` element. Any destination kind works: webhook, Kafka, GCP Pub/Sub, and the others listed in [supported channels](../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md#currently-supported-channels).

```mermaid
graph LR
    A(API request):::blue2 --> B(Aidbox):::green2
    B --> C(Audit events topic):::violet2
    C --> D(Webhook destination):::neutral2
    C --> E(Kafka destination):::neutral2
    C --> F(Other destinations):::neutral2
```

How the topic behaves:

* Destinations switch audit logging on. With no destination on the topic, Aidbox builds no audit events and requests carry no audit overhead. Delete the last destination to stop audit logging.
* The topic is part of Aidbox. You do not create an `AidboxSubscriptionTopic` resource for it, and Aidbox rejects a stored topic that reuses its URL with `422`.
* Every destination receives its own copy of each event. Delivery guarantees, batching, and retries come from the destination kind.
* Aidbox publishes events produced from the moment a destination exists. A new destination receives no earlier events.
* With [organization-based hierarchical access control](authorization/scoped-api/organization-based-hierarchical-access-control/README.md), the AuditEvent `meta` carries the organization of the request.

For a step-by-step setup, see [How to subscribe to audit events](../tutorials/security-access-control-tutorials/how-to-subscribe-to-audit-events.md).

### Aidbox as a source of audit events

Aidbox produces audit events for significant events:

* FHIR CRUD & Search operations for basic FHIR resources and custom resources (with BALP profiles)
* FHIR CRUD & Search operations for Patient compartment resources (with Patient-specific BALP profiles)
* User login and logout events (custom Aidbox event types, not BALP-conformant)
* Password change events (DICOM subtype `110139`)
* SQL operations via `$psql`/`$sql` (custom `aidbox/sql-interaction` type, not BALP-conformant)
* Bundle transaction entries (each entry audited individually with BALP profiles)

### BALP profile selection

Aidbox assigns a BALP profile to each AuditEvent based on the operation type and whether the operation involves a Patient.

| Operation | Generic Profile | Patient-specific Profile |
|---|---|---|
| Create | `IHE.BasicAudit.Create` | `IHE.BasicAudit.PatientCreate` |
| Read / VRead | `IHE.BasicAudit.Read` | `IHE.BasicAudit.PatientRead` |
| Update / Patch | `IHE.BasicAudit.Update` | `IHE.BasicAudit.PatientUpdate` |
| Delete | `IHE.BasicAudit.Delete` | `IHE.BasicAudit.PatientDelete` |
| Search / Query | `IHE.BasicAudit.Query` | `IHE.BasicAudit.PatientQuery` |

**When Patient-specific profiles are used:**

* The resource **is** a Patient — CRUD operations directly on the Patient resource (e.g. `PUT /fhir/Patient/123`)
* The resource is in the [Patient Compartment](https://www.hl7.org/fhir/compartmentdefinition-patient.html) and references a Patient (e.g. creating an Observation with `subject` pointing to a Patient)

{% hint style="info" %}
Patient **search** (`GET /fhir/Patient?...`) uses the generic `IHE.BasicAudit.Query` profile, not `IHE.BasicAudit.PatientQuery`. This is because a search does not reference a specific Patient. The `PatientQuery` profile is used when searching compartment resources that reference a Patient (e.g. `GET /fhir/Observation?patient=123`).
{% endhint %}

#### Example: AuditEvent for Patient update

When you update a Patient resource, the generated AuditEvent uses the `IHE.BasicAudit.PatientUpdate` profile:

```json
{
  "resourceType": "AuditEvent",
  "meta": {
    "profile": [
      "https://profiles.ihe.net/ITI/BALP/StructureDefinition/IHE.BasicAudit.PatientUpdate"
    ]
  },
  "type": {
    "system": "http://terminology.hl7.org/CodeSystem/audit-event-type",
    "code": "rest",
    "display": "Restful Operation"
  },
  "subtype": [
    {
      "system": "http://hl7.org/fhir/restful-interaction",
      "code": "update",
      "display": "update"
    }
  ],
  "action": "U",
  "recorded": "2026-02-25T12:00:00Z",
  "outcome": "0",
  "agent": [
    {
      "who": {
        "reference": "Client/my-client"
      },
      "requestor": true
    }
  ],
  "source": {
    "observer": {
      "display": "Aidbox"
    }
  },
  "entity": [
    {
      "what": {
        "reference": "Patient/example"
      },
      "role": {
        "system": "http://terminology.hl7.org/CodeSystem/object-role",
        "code": "4",
        "display": "Domain Resource"
      },
      "type": {
        "system": "http://terminology.hl7.org/CodeSystem/audit-entity-type",
        "code": "2",
        "display": "System Object"
      }
    }
  ]
}
```

### Password change AuditEvent

When a user's password is changed (via `PUT /User/:id` or `PATCH /User/:id`), Aidbox generates an AuditEvent with DICOM subtype `110139` ("User password changed").

```json
{
  "resourceType": "AuditEvent",
  "type": {
    "system": "http://terminology.hl7.org/CodeSystem/audit-event-type",
    "code": "rest",
    "display": "Restful Operation"
  },
  "subtype": [
    {
      "system": "http://dicom.nema.org/resources/ontology/DCM",
      "code": "110139",
      "display": "User password changed"
    }
  ],
  "action": "U",
  "outcome": "0",
  "entity": [
    {
      "what": { "reference": "User/example-user" },
      "type": {
        "system": "http://terminology.hl7.org/CodeSystem/audit-entity-type",
        "code": "2"
      },
      "role": {
        "system": "http://terminology.hl7.org/CodeSystem/object-role",
        "code": "4"
      }
    }
  ],
  "agent": [
    {
      "who": { "identifier": { "value": "root" } },
      "requestor": true
    },
    {
      "who": { "display": "Aidbox" },
      "requestor": false
    }
  ]
}
```

Aidbox generates this event regardless of whether the password value changed.

### External Audit record repository support

To send audit events to an external [Audit record repository](https://profiles.ihe.net/ITI/TF/Volume1/ch-9.html#9.1.1.3), create a webhook `AidboxTopicDestination` on the audit events topic with the repository endpoint. Aidbox delivers events as a FHIR Bundle of type `history`, described in [Notification shape](../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md#notification-shape). The first entry of the bundle is an `AidboxSubscriptionStatus`, so check that the repository accepts this shape.

For setup instructions and a payload example, see [How to subscribe to audit events](../tutorials/security-access-control-tutorials/how-to-subscribe-to-audit-events.md).

## FHIR Resource versioning

A separate version is recorded in the history table each time a resource is created, updated, or deleted.

All versions can be accessed using the [\_history](../api/rest-api/history.md) operation.

## Logging configuration

Aidbox automatically logs all auth, API, database, and network events, so in most cases, basic audit logs may be derived from [Aidbox logs](../modules/observability/logs/).

Aidbox also provides ways to [extend](../modules/observability/logs/extending-aidbox-logs.md) Aidbox logs.

## Audit coverage

| Operation | Audited | BALP Profile | Notes |
|---|---|---|---|
| REST Create (POST) | Yes | `IHE.BasicAudit.Create` / `PatientCreate` | |
| REST Read (GET) | Yes | `IHE.BasicAudit.Read` / `PatientRead` | |
| REST Update (PUT/PATCH) | Yes | `IHE.BasicAudit.Update` / `PatientUpdate` | |
| REST Delete | Yes | `IHE.BasicAudit.Delete` / `PatientDelete` | Entity reference includes `/_history/version`, see Known limitations |
| REST Search | Yes | `IHE.BasicAudit.Query` / `PatientQuery` | |
| Bundle transaction | Yes | Per-entry BALP profiles | Each entry gets its own AuditEvent |
| Password change | Yes | No (DICOM `110139`) | See [Password change AuditEvent](#password-change-auditevent) |
| `$psql` / `$sql` | Yes | No (`aidbox/sql-interaction`) | Custom Aidbox type system |
| User login/logout | Yes | No (custom) | Not BALP-conformant |
| GraphQL | Indirect | Via underlying FHIR calls | The GraphQL query text is not captured; only the translated FHIR operations are audited |
| Bulk `$import` / `$load` | **No** | — | Imported resources have no audit trail |
| Bulk `$export` | **No** | — | |
| Auth token issuance | **No** | — | `client_credentials` grant, `/auth/token` not audited |
| `/auth/userinfo` | **No** | — | |
| Configuration changes | **No** | — | |
| AuditEvent search, read, create | Excluded | — | Intentional, prevents infinite audit loops |

## Known limitations

{% hint style="warning" %}
**Delete entity reference includes version**: Delete AuditEvents carry the entity reference as `ResourceType/id/_history/versionId` (e.g. `Patient/123/_history/5`). A consumer that matches events by `Patient/123` misses delete events unless it strips the version suffix.
{% endhint %}

{% hint style="info" %}
**Bulk import has no audit trail**: Resources created via `$import` or `$load` bypass the CRUD pipeline and do not generate AuditEvents. If you need a complete audit trail, use individual FHIR CRUD operations or Bundle transactions instead.
{% endhint %}

{% hint style="info" %}
**GraphQL queries are not directly audited**: GraphQL requests generate AuditEvents only for the underlying FHIR search/read operations, not for the GraphQL query itself. The original query text is not captured in any AuditEvent.
{% endhint %}

## See also:

{% content-ref url="../tutorials/security-access-control-tutorials/how-to-subscribe-to-audit-events.md" %}
[how-to-subscribe-to-audit-events.md](../tutorials/security-access-control-tutorials/how-to-subscribe-to-audit-events.md)
{% endcontent-ref %}
