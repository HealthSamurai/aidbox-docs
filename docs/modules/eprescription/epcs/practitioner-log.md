---
description: Retrieve the log of controlled prescriptions a practitioner signed in a period, as JSON or CSV, in the Aidbox ePrescription module.
---

# Practitioner Log

The **practitioner log** lists the controlled prescriptions one practitioner signed during a period, one entry per prescription.
[21 CFR 1311.120(b)(27)](https://www.ecfr.gov/current/title-21/section-1311.120) requires an EPCS application to generate this log for a period the practitioner requests.

```http
GET /e-prescription/audit/practitioner-log/<Practitioner id>?from=2026-05-01&to=2026-05-31
```

Query parameters:

* `from` and `to` (required): the first and the last day of the period, as ISO dates.
* `format=csv`: returns the log as CSV instead of JSON.
* `refresh=true`: builds the log again (see [Refresh](#refresh)).

The module places a prescription in the period by its signing date in UTC, so a prescription written in April and signed in May belongs to May.

## Access Policy

The module returns any practitioner's log to any request your AccessPolicies allow, so write a policy that allows this route only to the users who may read the log.
[Configure Access Policies](access-management/configure-access-policies.md) shows how to write policies for the EPCS routes.

## Issued Values

When the practitioner signs a controlled prescription, the module saves its **issued values**, and the log shows them:

* patient name
* drug name
* dispense quantity
* address of the prescribing location
* dispensing pharmacy name

A later change to the `Patient`, `Medication`, `MedicationRequest`, `Location`, or pharmacy `Organization` does not change the log.

The transmission, callback, timeout, and cancellation statuses come from the prescription's [NewRx](../prescribing/newrx-message.md) and [CancelRx](../prescribing/cancelrx-message.md) messages after signing, so a [refreshed](#refresh) log can show newer statuses.

## JSON Response

Without `format`, `200 OK` returns the log as JSON.

<details>

<summary>Response</summary>

```json
{
  "metadata": {
    "generatedAt": "2026-06-01T09:15:42.317Z",
    "generatorVersion": "v1",
    "practitionerId": "pr-12345",
    "period": { "from": "2026-05-01", "to": "2026-05-31" },
    "reportKind": "practitioner-log",
    "generationMode": "on-demand",
    "auditEvents": { "count": 4, "fingerprint": "3a7bd3e2360a3d29eea436fcfb7e44c735d117c42d1c1835420b6b9942dd4f1b" },
    "snapshotDataFingerprint": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
  },
  "entries": [
    {
      "medicationRequestId": "med-req-7a1c",
      "patient": { "id": "pat-3310", "name": "Carter Alice" },
      "medication": { "name": "Adderall 10 MG Oral Tablet" },
      "deaSchedule": "II",
      "quantity": {
        "value": 60,
        "unit": "Tablet",
        "code": "C48542",
        "system": "urn:app:aidbox:e-prescriptions:ncpdp:QuantityUnitOfMeasure"
      },
      "issueDate": "2026-05-08",
      "signedAt": "2026-05-08T16:42:03Z",
      "selectedDeaNumber": "BJ1234563",
      "practitioner": { "id": "pr-12345" },
      "practitionerRole": { "id": "prole-987" },
      "location": {
        "id": "loc-55",
        "address": { "line": ["123 Main St"], "city": "Springfield", "state": "IL", "postalCode": "62701" }
      },
      "pharmacy": { "id": "org-7788", "name": "Springfield Community Pharmacy" },
      "transmissionStatus": "active",
      "callbackStatus": "completed",
      "reconciliationIdentifiers": {
        "prescriberOrderNumber": "PON-2026-000812",
        "surescriptsMessageId": "f47ac10b-58cc-4372-a567-0e02b2c3d479"
      }
    }
  ]
}
```

</details>

`metadata` says when the module built the log and for which practitioner and period.
`auditEvents` counts and fingerprints the `AuditEvent` resources the log reads.
`snapshotDataFingerprint` fingerprints those events together with the issued values.

The module sorts `entries` by patient name, then drug name, then issue date.
The module leaves out empty fields, so an entry without a cancellation has no `cancellationStatus`.

## CSV Response

With `format=csv`, `200 OK` returns `text/csv` with a header row and one row per entry, in the order of the JSON entries.

<details>

<summary>Response</summary>

```csv
Patient,Drug Name,Issue Date,Signed Time,DEA Schedule,Quantity,Selected DEA Number,Practitioner Role,Location,Pharmacy,Transmission Status,Callback Status,Timeout Status,Cancellation Status,Prescriber Order Number,Surescripts Message ID,MedicationRequest ID
Carter Alice,Adderall 10 MG Oral Tablet,2026-05-08,2026-05-08T16:42:03Z,II,60 Tablet C48542,BJ1234563,prole-987,loc-55,Springfield Community Pharmacy,active,completed,,,PON-2026-000812,f47ac10b-58cc-4372-a567-0e02b2c3d479,med-req-7a1c
```

</details>

The response headers carry the `metadata` fields:

* `X-Practitioner-Log-Generated-At`: `generatedAt`
* `X-Practitioner-Log-Generator-Version`: `generatorVersion`
* `X-Practitioner-Log-Practitioner-Id`: `practitionerId`
* `X-Practitioner-Log-Period-From` and `X-Practitioner-Log-Period-To`: `period`
* `X-Practitioner-Log-Report-Kind`: `reportKind`
* `X-Practitioner-Log-Generation-Mode`: `generationMode`
* `X-Practitioner-Log-Audit-Events-Count` and `X-Practitioner-Log-Audit-Events-Fingerprint`: `auditEvents`
* `X-Practitioner-Log-Snapshot-Data-Fingerprint`: `snapshotDataFingerprint`

## Archives

The first request for a practitioner and period builds the log and archives it.
Later requests for the same practitioner and period return the log from the newest archive unchanged, in JSON or CSV.

The module keeps every archive and never changes one.

<details>

<summary>Archive DocumentReference</summary>

The attachment points to the `Binary` that holds the log JSON.

```json
{
  "resourceType": "DocumentReference",
  "id": "practitioner-log-1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed",
  "status": "current",
  "docStatus": "final",
  "type": {
    "coding": [{ "system": "urn:app:aidbox:e-prescriptions", "code": "practitioner-log" }]
  },
  "subject": { "reference": "Practitioner/pr-12345" },
  "date": "2026-06-01T09:15:42.317Z",
  "context": { "period": { "start": "2026-05-01", "end": "2026-05-31" } },
  "identifier": [
    {
      "system": "urn:app:aidbox:e-prescriptions:practitioner-log:archive-key",
      "value": "practitioner-log|on-demand|pr-12345|2026-05-01|2026-05-31"
    },
    {
      "system": "urn:app:aidbox:e-prescriptions:practitioner-log:generator-version",
      "value": "v1"
    },
    {
      "system": "urn:app:aidbox:e-prescriptions:practitioner-log:audit-events-fingerprint",
      "value": "3a7bd3e2360a3d29eea436fcfb7e44c735d117c42d1c1835420b6b9942dd4f1b"
    },
    {
      "system": "urn:app:aidbox:e-prescriptions:practitioner-log:snapshot-data-fingerprint",
      "value": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
    }
  ],
  "content": [
    {
      "attachment": {
        "contentType": "application/json",
        "url": "Binary/practitioner-log-payload-6f1c2a9e-3d4b-4e8f-9a1b-2c3d4e5f6a7b"
      }
    }
  ]
}
```

</details>

### Refresh

With `refresh=true`, the module builds the log again and compares its `snapshotDataFingerprint` with the newest archive's:

* The fingerprints differ: the module archives the new log and returns it.
* The fingerprints match: the module returns the log from the newest archive.

The fingerprint changes when either is true:

* the practitioner signed another controlled prescription in the period
* the module recorded a new `AuditEvent` for a prescription in the log

An edit to the prescription's resources after signing does not change the fingerprint, because the log shows the [issued values](#issued-values).

<details>

<summary>Error Responses</summary>

* `400`: `from` or `to` is missing.
* `422`: any of these is true:
  * `from` or `to` is not an ISO date
  * `from` is after `to`
  * `format` has a value other than `csv`

</details>
