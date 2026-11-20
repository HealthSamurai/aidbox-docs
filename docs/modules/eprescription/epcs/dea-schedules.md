---
description: Store a DEA schedule on a medication and check how the ePrescription module validates and sends it to the pharmacy.
---

# DEA Schedules

The module treats a prescription as a **controlled prescription** when its medication has a DEA schedule.
The EHR stores the schedule the practitioner reviewed, and the module reads it from the prescription's medication.

## Store a DEA Schedule

Store the schedule in the `http://aidbox.app/ePrescription/FHIRSchema/medication-dea-schedule` extension of the medication code:

* `MedicationRequest.medicationCodeableConcept` for a prescription without a `Medication` resource
* `Medication.code` for a `Medication` that is not a compound

For a compound, store the schedule on each scheduled ingredient as described in [Compound Medications](../prescribing/compound-medications.md#ingredient-schedules).

The extension's `valueCodeableConcept` holds one coding under `http://terminology.hl7.org/CodeSystem/v2-0477` with one of the codes `I`, `II`, `III`, `IV`, or `V`.
Give each medication code at most one schedule extension.
An extension that holds only `text` stores no schedule.

<details>

<summary>Schedule extension</summary>

```json
{
  "url": "http://aidbox.app/ePrescription/FHIRSchema/medication-dea-schedule",
  "valueCodeableConcept": {
    "coding": [
      {
        "system": "http://terminology.hl7.org/CodeSystem/v2-0477",
        "code": "II",
        "display": "Schedule II"
      }
    ]
  }
}
```

</details>

## Schedules in NCPDP Messages

The module sends each schedule in `DEASchedule/Code` as its NCI Thesaurus (NCIt) code:

* `I`: `C48672`
* `II`: `C48675`
* `III`: `C48676`
* `IV`: `C48677`
* `V`: `C48679`

`DrugCoded/DEASchedule` carries the prescription's schedule.

## Schedule Checks

The module checks the schedules when you send a [NewRx](../prescribing/newrx-message.md) or respond to a [renewal](../prescribing/pharmacy-initiated-messages/rx-renewal.md) or [change](../prescribing/pharmacy-initiated-messages/rx-change.md) request.
The checks it runs depend on the request:

* a NewRx, or a response that lets the pharmacy fill the prescription: the medication code checks below and, for compounds, the [compound schedule checks](../prescribing/compound-medications.md#schedule-checks)
* a denied response, a pending response, or an approved prior-authorization change response: only `medication-has-multiple-dea-schedules` and `dea-schedule-coding-system-is-not-supported`

When EPCS is disabled (`EPCS_MODE=disabled`), the module rejects a controlled prescription with `epcs-disabled`.
It does not reject a denied response this way.

A request that fails a check returns `422` with an `OperationOutcome`.

A group submission returns `202` instead when the module sent some prescriptions of the group in an earlier submission.
Its `failures[].reason` holds the error code of each prescription that the module did not send.

<details>

<summary>Error Responses</summary>

* The medication code (`Medication.code` or `MedicationRequest.medicationCodeableConcept`):
  * `medication-has-multiple-dea-schedules`: the code has more than one schedule extension, or more than one coding under `http://terminology.hl7.org/CodeSystem/v2-0477` in one extension.
  * `dea-schedule-coding-system-is-not-supported`: a schedule extension has codings, and none of them is a coding under `http://terminology.hl7.org/CodeSystem/v2-0477` that has a code.
  * `controlled-substance-invalid-dea-schedule`: the schedule is not one of `I` to `V`.

</details>
