---
description: Retrieve the log of controlled prescriptions a practitioner signed in a period, as JSON or CSV, in the Aidbox ePrescription module.
---

# Practitioner Log

The practitioner log lists the controlled prescriptions one practitioner signed during a period, with the [NewRx](../prescribing/newrx-message.md) and [CancelRx](../prescribing/cancelrx-message.md) outcome of each one.
It provides the log of a requested period that [21 CFR 1311.120(b)(27)](https://www.ecfr.gov/current/title-21/section-1311.120) describes.

```http
GET /e-prescription/audit/practitioner-log/<Practitioner id>?from=2026-05-01&to=2026-05-31
```

Query parameters:

* `from` and `to` (required): the first and the last day of the period, as ISO dates. The period includes both days.
* `format=csv`: returns the log as CSV instead of JSON.
* `refresh=true`: builds the log again, see [Archives and Refresh](#archives-and-refresh).

The log has one entry for each controlled prescription the practitioner signed in the period.
The module places a prescription in the period by its signing date in UTC, so a prescription written in April and signed in May belongs to May.

## Values From Signing Time

Each entry shows these values as the practitioner signed them:

* patient name
* drug name
* dispense quantity
* location address
* dispensing pharmacy name

The module saves these values when the practitioner signs the prescription, and the log reads them from that record.
A later change to the `Patient`, `MedicationRequest`, `Location`, or pharmacy `Organization` does not change the log.

The transmission, callback, timeout, and cancellation statuses come from the prescription's activity after signing, so a [refreshed](#archives-and-refresh) log can show newer statuses.

## JSON Response

`200 OK` returns the log:

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

`metadata` describes the log: when the module built it, for which practitioner and period, and the fingerprints it compares on [refresh](#archives-and-refresh).

The module sorts `entries` by patient name, then drug name, then issue date. Each entry holds:

* `medicationRequestId`: the signed `MedicationRequest`.
* `patient`: the `Patient` id and the signed patient name, as "Family Given".
* `medication.name`: the signed drug name.
* `quantity`: the signed dispense quantity.
* `deaSchedule`: the DEA schedule of the signed prescription.
* `issueDate`: the signing date in UTC.
* `signedAt`: the signing time.
* `selectedDeaNumber`: the DEA number the practitioner signed under.
* `practitioner` and `practitionerRole`: the ids of the signing `Practitioner` and `PractitionerRole`.
* `location`: the `Location` id and the signed location address.
* `pharmacy`: the pharmacy `Organization` id and the signed pharmacy name.
* `transmissionStatus`, `callbackStatus`, and `timeoutStatus`: the latest NewRx statuses.
* `cancellationStatus`: the latest CancelRx status.
* `reconciliationIdentifiers`: the `prescriberOrderNumber` and `surescriptsMessageId` of the NewRx, to match the entry with Surescripts records.

The module leaves out empty fields, so an entry without a cancellation has no `cancellationStatus`.

## CSV Response

With `format=csv`, `200 OK` returns `text/csv` with a header row and one row per entry, in the order of the JSON entries:

```csv
Patient,Drug Name,Issue Date,Signed Time,DEA Schedule,Quantity,Selected DEA Number,Practitioner Role,Location,Pharmacy,Transmission Status,Callback Status,Timeout Status,Cancellation Status,Prescriber Order Number,Surescripts Message ID,MedicationRequest ID
Carter Alice,Adderall 10 MG Oral Tablet,2026-05-08,2026-05-08T16:42:03Z,II,60 Tablet C48542,BJ1234563,prole-987,loc-55,Springfield Community Pharmacy,active,completed,,,PON-2026-000812,f47ac10b-58cc-4372-a567-0e02b2c3d479,med-req-7a1c
```

`Practitioner Role` and `Location` hold ids, and `Pharmacy` holds the signed pharmacy name.

The `metadata` comes in response headers:

* `X-Practitioner-Log-Generated-At`: `generatedAt`
* `X-Practitioner-Log-Generator-Version`: `generatorVersion`
* `X-Practitioner-Log-Practitioner-Id`: `practitionerId`
* `X-Practitioner-Log-Period-From` and `X-Practitioner-Log-Period-To`: `period`
* `X-Practitioner-Log-Report-Kind`: `reportKind`
* `X-Practitioner-Log-Generation-Mode`: `generationMode`
* `X-Practitioner-Log-Audit-Events-Count` and `X-Practitioner-Log-Audit-Events-Fingerprint`: `auditEvents`
* `X-Practitioner-Log-Snapshot-Data-Fingerprint`: `snapshotDataFingerprint`

## Archives and Refresh

The first request for a practitioner and period builds the log and archives it.
Later requests for the same practitioner and period return the archived log unchanged, in JSON or CSV.

An archive is a `DocumentReference` with the type code `practitioner-log`, whose attachment points to a `Binary` that holds the log JSON.
The module keeps every archive and never changes one.

With `refresh=true`, the module builds the log again and compares it with the newest archive:

* when the module recorded a new `AuditEvent` for a prescription in the log, or the practitioner signed another prescription in the period, it archives the new log and returns it
* otherwise, it returns the newest archive

A change to a `Patient`, `MedicationRequest`, `Location`, or pharmacy `Organization` after signing does not add an archive, because the log shows the [values from signing time](#values-from-signing-time).

<details>

<summary>Error Responses</summary>

* `422` when any of these is true:
  * `from` or `to` is missing
  * `from` or `to` is not an ISO date
  * `from` is after `to`
  * `format` has a value other than `csv`

</details>
