---
description: The AuditEvent resources the Aidbox ePrescription module records for controlled prescriptions and EPCS access changes.
---

# EPCS Audit Events

The module records an `AuditEvent` for each action it performs on a [controlled prescription](dea-schedules.md) or an [EPCS access permission](access-management/README.md).
Each event holds the data that EPCS compliance requires: when the action happened, what it was, who took it, and whether it succeeded.

This event records a refused signing attempt:

<details>

<summary>AuditEvent Example</summary>

```json
{
  "resourceType": "AuditEvent",
  "type": {
    "system": "urn:app:aidbox:e-prescriptions",
    "code": "epcs-sign",
    "display": "EPCS signing failed"
  },
  "action": "E",
  "recorded": "2026-11-19T14:32:07.512Z",
  "outcome": "4",
  "outcomeDesc": "EPCS signing failed: Controlled substance fillable prescription requires a valid EPCS ready-to-sign proof before transmission",
  "agent": [
    {
      "requestor": true,
      "who": {
        "identifier": {
          "system": "urn:app:aidbox:e-prescriptions:aidbox-user",
          "value": "dr-smith"
        }
      },
      "type": {
        "coding": [
          {
            "system": "http://terminology.hl7.org/CodeSystem/extra-security-role-type",
            "code": "humanuser"
          }
        ]
      }
    },
    {
      "requestor": false,
      "who": { "reference": "Practitioner/pr-12345" }
    }
  ],
  "source": { "observer": { "display": "ePrescription" } },
  "entity": [
    {
      "what": { "reference": "MedicationRequest/mr-67890" },
      "detail": [
        { "type": "medicationRequestId", "valueString": "mr-67890" },
        { "type": "selectedDeaNumber", "valueString": "AS1234563" },
        { "type": "deaSchedule", "valueString": "II" },
        { "type": "surescriptsSpi", "valueString": "1234567890001" },
        { "type": "surescriptsMessageId", "valueString": "b7e0c2a4f1d94c6e8a3b5d7f9e1c2a4b" },
        { "type": "failureReason", "valueString": "epcs-ready-to-sign-required" }
      ]
    },
    { "what": { "reference": "Patient/pt-24680" } },
    { "what": { "reference": "Practitioner/pr-12345" } },
    { "what": { "reference": "PractitionerRole/prr-13579" } },
    { "what": { "reference": "Location/loc-11223" } },
    { "what": { "reference": "Organization/pharmacy-44556" } }
  ]
}
```

</details>

## Search the Events

```http
GET /fhir/AuditEvent?type=urn:app:aidbox:e-prescriptions%7Cepcs-sign&date=ge2026-11-19T00:00:00Z&date=lt2026-11-20T00:00:00Z
```

* `type`: `urn:app:aidbox:e-prescriptions|<code>`, with several codes separated by commas
* `date`: the time the module recorded the event
* `entity`: `MedicationRequest/<id>`, for the events of one prescription

## Event Fields

* `type.code`: the event code from the lists below.
  `type.system` is always `urn:app:aidbox:e-prescriptions`.
* `recorded`: when the event happened.
* `outcome`: `"0"` if the action succeeded, `"4"` if it failed.
  The event lists below call these success and failure.
* `outcomeDesc`: the result in words.
* `agent[]` with `requestor: true`: who took the action, one of:
  * an [acting user](access-management/configure-access-policies.md#acting-user): `who.identifier.value` is the `User` id, as in the example
  * a request without an acting user: `who.display` is `unknown`
  * Surescripts: `who.display` is `Surescripts`
  * the module's scheduler: `who.identifier.system` is `urn:app:aidbox:e-prescriptions:component` and `who.identifier.value` is `scheduler`
* `agent[]` with `requestor: false`: other people the event involves, such as the prescriber's `Practitioner` in the example.
* `entity[]`: the resources the event concerns.
  In a prescription or transmission event, the first entity references the `MedicationRequest`, and its `detail[]` holds values such as the DEA schedule and `failureReason`.

## Prescription Events

* `epcs-create`: the module creates a controlled prescription from a prescriber's answer to a renewal or change request.
  Always a success.
* `epcs-alter`: the module updates such a prescription, and the prescription is controlled before or after the update.
  Always a success.
* `epcs-ready-to-sign`: the prescriber marks the prescription ready to sign.
  * Success: the module saved the proof of readiness.
  * Failure:
    * the prescriber failed the [prescribing checks](access-management/README.md#prescribing-controlled-substances)
    * the prescription failed validation
    * Aidbox rejected the save
* `epcs-sign`: the prescriber signs the prescription.
  * Success: the module saved the legal authentication record and the prescription's [issued values](practitioner-log.md#issued-values).
  * Failure:
    * the prescriber failed the prescribing checks
    * the prescription was not marked ready to sign, or changed after it was
    * the two-factor code is missing
    * the prescription failed validation
    * the module could not start sending the message to Surescripts
    * Aidbox rejected the save
* `epcs-cancel`: a cancellation of the prescription reaches the step in the `cancellationStep` detail:
  * `delivered`: the pharmacy received the cancellation request. Success.
  * `approved`: the pharmacy approved the cancellation. Success.
  * `replaced`: a delivered replacement prescription cancelled this one. Success.
  * `denied`: the pharmacy denied the cancellation, and the prescription stays active. Failure.

On failure, the `failureReason` detail names the error, as in the example.

## Transmission Events

* `epcs-transmission-attempt`: the module starts a call to Surescripts, a retry included.
  Always a success.
* `epcs-transmission`: the call to Surescripts ends.
  * Success: Surescripts confirmed delivery, or the [message status](../prescribing/newrx-message.md#statuses-description) after the call is `active`, `completed`, or `on-hold`.
    For an RxFillIndicatorChange, success means Surescripts accepted the message for processing.
  * Failure: any other result.
* `epcs-callback`: Surescripts reports the result of an earlier message.
  Success or failure follows the reported result.
* `epcs-timeout`: always a failure, recorded by the scheduler when:
  * a sent message gets no final answer in time
  * an incoming renewal or change request expires before the prescriber answers it

These details of the `MedicationRequest` entity describe the message:

* `messageType`: the Surescripts message, such as `NewRx`
* `surescriptsMessageId`: the outgoing message
* `transportCallNumber`: the number of the call for that message
* `transmissionStatus`: the message status after the call
* `deliveryResult`: the result Surescripts reported

<details>

<summary>Transmission Entity Example</summary>

```json
{
  "what": { "reference": "MedicationRequest/mr-67890" },
  "detail": [
    { "type": "medicationRequestId", "valueString": "mr-67890" },
    { "type": "selectedDeaNumber", "valueString": "AS1234563" },
    { "type": "deaSchedule", "valueString": "II" },
    { "type": "surescriptsSpi", "valueString": "1234567890001" },
    { "type": "messageType", "valueString": "NewRx" },
    { "type": "surescriptsMessageId", "valueString": "b7e0c2a4f1d94c6e8a3b5d7f9e1c2a4b" },
    { "type": "prescriberOrderNumber", "valueString": "ORD-2026-0042" },
    { "type": "transportCallNumber", "valueString": "1" },
    { "type": "surescriptsResponseMessageId", "valueString": "5f3e9a1c7b2d4e6f8a0b1c2d3e4f5a6b" },
    { "type": "surescriptsRelatesToMessageId", "valueString": "b7e0c2a4f1d94c6e8a3b5d7f9e1c2a4b" },
    { "type": "transmissionStatus", "valueString": "completed" },
    { "type": "deliveryResult", "valueString": "delivered" }
  ]
}
```

</details>

## EPCS Access Events

* `epcs-access-admin-bootstrap`: a user [bootstraps the first administrator](access-management/bootstrap-the-first-administrator.md) at a location.
* `epcs-access-change-request-creation`: an administrator [requests a change](access-management/access-change-requests.md#request-a-change).
* `epcs-access-change-request-approval`: a user [approves an access-change request](access-management/access-change-requests.md#approve-an-access-change-request), and the module grants or revokes the permission.
* `epcs-access-change-request-cancellation`: a user [cancels an access-change request](access-management/access-change-requests.md#cancel-an-access-change-request).
* `epcs-access-immediate-revocation`: the module completes an [immediate revocation](access-management/access-change-requests.md#immediate-revocation).
  Always a success: when the module refuses an immediate revocation, it records a failed `epcs-access-change-request-creation`.

An access event is a success when the operation completes and a failure when the module refuses it.

The `requestor: false` agents carry their part in `role[].coding[].code`:

* `target`: the `User` whose access changes, and their `Practitioner`
* `requester`: the `User` who requested the change
* `approver`: the `Practitioner` who approved it

The entities reference the access-change request, the permission, and the location.
On failure, and for a permission the operation deleted, an entity names the resource in `what.display` instead of `what.reference`.
The last entity's `detail[]` holds:

* `permissionCode`: the permission the change concerns
* `action`: `grant` or `revoke`
* `failureReason`: on failure, the error, such as `not-location-admin`

<details>

<summary>Access Event Example</summary>

```json
{
  "resourceType": "AuditEvent",
  "type": {
    "system": "urn:app:aidbox:e-prescriptions",
    "code": "epcs-access-change-request-approval",
    "display": "EPCS access-change request was approved by an EPCS approver"
  },
  "action": "C",
  "recorded": "2026-11-19T10:05:44.021Z",
  "outcome": "0",
  "outcomeDesc": "EPCS access-change request was approved by an EPCS approver",
  "agent": [
    {
      "requestor": true,
      "who": {
        "identifier": {
          "system": "urn:app:aidbox:e-prescriptions:aidbox-user",
          "value": "approver-jones"
        }
      },
      "type": {
        "coding": [
          {
            "system": "http://terminology.hl7.org/CodeSystem/extra-security-role-type",
            "code": "humanuser"
          }
        ]
      }
    },
    {
      "requestor": false,
      "who": {
        "identifier": {
          "system": "urn:app:aidbox:e-prescriptions:aidbox-user",
          "value": "dr-smith"
        }
      },
      "role": [{ "coding": [{ "system": "urn:app:aidbox:e-prescriptions", "code": "target" }] }]
    },
    {
      "requestor": false,
      "who": { "reference": "Practitioner/pr-12345" },
      "role": [{ "coding": [{ "system": "urn:app:aidbox:e-prescriptions", "code": "target" }] }]
    },
    {
      "requestor": false,
      "who": {
        "identifier": {
          "system": "urn:app:aidbox:e-prescriptions:aidbox-user",
          "value": "admin-lee"
        }
      },
      "role": [{ "coding": [{ "system": "urn:app:aidbox:e-prescriptions", "code": "requester" }] }]
    },
    {
      "requestor": false,
      "who": { "reference": "Practitioner/pr-67890" },
      "role": [{ "coding": [{ "system": "urn:app:aidbox:e-prescriptions", "code": "approver" }] }]
    }
  ],
  "source": { "observer": { "display": "ePrescription" } },
  "entity": [
    { "what": { "reference": "EPrescriptionAccessRequest/acr-33445" } },
    { "what": { "reference": "EPrescriptionAccessPermission/perm-55667" } },
    {
      "what": { "reference": "Location/loc-11223" },
      "detail": [
        { "type": "permissionCode", "valueString": "epcs-prescribing" },
        { "type": "action", "valueString": "grant" }
      ]
    }
  ]
}
```

</details>
