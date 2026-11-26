---
description: Store DEA schedules on medications and compound ingredients, and see how the Aidbox ePrescription module classifies a controlled prescription from them and which limits each schedule sets.
---

# DEA Schedules

The module treats a prescription as a **controlled prescription** when its medication has a DEA schedule.

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

When EPCS is disabled (`EPCS_MODE=disabled`), the module rejects a controlled prescription with `epcs-disabled`, including a compound with a scheduled ingredient.

The schedule of a controlled prescription sets these limits on it and on its refill count, `MedicationRequest.dispenseRequest.numberOfRepeatsAllowed`:

* Schedule I: the module rejects the prescription.
* Schedule II: the refill count must be 0.
* Schedule III and IV: the refill count must be at most 5.
* Schedule V: no limit beyond the refill range of the message.

The module checks these limits on every message that lets the pharmacy fill the prescription:

* a [NewRx](../prescribing/newrx-message.md)
* an [RxRenewal response](../prescribing/pharmacy-initiated-messages/rx-renewal.md#refill-count) with decision `replace`
* an [RxChange response](../prescribing/pharmacy-initiated-messages/rx-change.md#refill-count) with decision `approved`, `approved-with-changes` or `validated`

You can still deny a renewal or change request for a prescription that breaks a limit.

The schedule limits on the refill count apply only when the prescription sets one.
Each message page states the refill range it accepts and what the module sends without a count.

When the module reports a DEA schedule error for a prescription, it skips the schedule limits and the refill range check of that prescription, because the schedule they depend on is unknown.
After you fix the schedule, the module checks them.

A request that fails a check returns `422` with an `OperationOutcome`.

<details>

<summary>Error Responses</summary>

* The medication code (`Medication.code` or `MedicationRequest.medicationCodeableConcept`):
  * `medication-has-multiple-dea-schedules`: the code has more than one schedule extension, or more than one coding under `http://terminology.hl7.org/CodeSystem/v2-0477` in one extension.
  * `dea-schedule-coding-system-is-not-supported`: a schedule extension has codings, and none of them is a coding under `http://terminology.hl7.org/CodeSystem/v2-0477` that has a code.
  * `controlled-substance-invalid-dea-schedule`: the schedule is not one of `I` to `V`.
* The schedule limits:
  * `schedule-i-medication-is-not-prescribable`: the prescription has Schedule I.
  * `schedule-ii-refills-must-be-zero`: a Schedule II prescription has a refill count other than 0.
  * `schedule-iii-iv-refills-exceed-limit`: a Schedule III or IV prescription has a refill count above 5.

Example response for `controlled-substance-invalid-dea-schedule`:

```json
{
  "resourceType": "OperationOutcome",
  "issue": [
    {
      "severity": "error",
      "code": "invalid",
      "details": {
        "text": "Controlled substance DEASchedule must be one of I, II, III, IV, V"
      },
      "diagnostics": "null"
    }
  ]
}
```

</details>
