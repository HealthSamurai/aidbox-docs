---
description: Store DEA schedules on medications and compound ingredients, and see how the Aidbox ePrescription module classifies a controlled prescription from them.
---

# DEA Schedules

The module treats a prescription as a **controlled prescription** when its medication has a DEA schedule.
The EHR stores the schedule the practitioner reviewed, and the module reads it from the prescription's medication.
For a [compound medication](../prescribing/compound-medications.md), the module reads the schedules of its ingredients instead.

## Store a DEA Schedule

Store the schedule in the `http://aidbox.app/ePrescription/FHIRSchema/medication-dea-schedule` extension of the medication code:

* `MedicationRequest.medicationCodeableConcept` for a prescription without a `Medication` resource
* `Medication.code`
* `Medication.ingredient.itemCodeableConcept` for each scheduled ingredient of a compound (see [Ingredient Schedules](../prescribing/compound-medications.md#ingredient-schedules))

<details>

<summary>Schedule extension example</summary>

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

`DrugCoded/DEASchedule` carries the schedule of the prescription:

* for a compound, the strictest ingredient schedule
* for any other medication, the schedule stored on its code

`CompoundIngredient/DEASchedule` carries the schedule of each ingredient.

## Schedule Checks

The module checks the schedules when you send these requests:

* a [NewRx](../prescribing/newrx-message.md), or a [renewal](../prescribing/pharmacy-initiated-messages/rx-renewal.md) or [change](../prescribing/pharmacy-initiated-messages/rx-change.md) response that lets the pharmacy fill the prescription: every check in the Error Responses list below
* a denied response, a pending response, or an approved prior-authorization change response: only `medication-has-multiple-dea-schedules` and `dea-schedule-coding-system-is-not-supported`

When EPCS is disabled (`EPCS_MODE=disabled`), the module rejects a controlled prescription with `epcs-disabled`, including a compound with a scheduled ingredient.

A request that fails a check returns `422` with an `OperationOutcome`.

<details>

<summary>Error Responses</summary>

* The medication code (`Medication.code` or `MedicationRequest.medicationCodeableConcept`):
  * `medication-has-multiple-dea-schedules`: the code has more than one schedule extension, or more than one coding under `http://terminology.hl7.org/CodeSystem/v2-0477` in one extension.
  * `dea-schedule-coding-system-is-not-supported`: a schedule extension has codings, and none of them is a coding under `http://terminology.hl7.org/CodeSystem/v2-0477` that has a code.
  * `controlled-substance-invalid-dea-schedule`: the schedule is not one of `I` to `V`.

</details>
