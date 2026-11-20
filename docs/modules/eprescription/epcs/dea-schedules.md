---
description: Store DEA schedules on FHIR medication and ingredient codes and read the corresponding schedules in NCPDP messages.
---

# DEA Schedules

The EHR records the DEA schedule the practitioner reviewed. The ePrescription module treats a prescription for a scheduled medication as a **controlled prescription**.
For a compound, any scheduled ingredient makes the prescription controlled. The strictest ingredient schedule determines the prescription's schedule.

## Store a DEA Schedule

Store the schedule in the `http://aidbox.app/ePrescription/FHIRSchema/medication-dea-schedule` extension on the appropriate FHIR field.

* If the prescription specifies the drug by code, use `MedicationRequest.medicationCodeableConcept`.
* If the prescription references or contains a `Medication` resource, use `Medication.code` for the medication's schedule. For a compound, omit the schedule here or repeat the strictest ingredient schedule.
* For each scheduled ingredient of a [compound medication](../prescribing/compound-medications.md#ingredient-schedules), use `Medication.ingredient.itemCodeableConcept`.

Use at most one schedule extension on each medication or ingredient code.
In its `valueCodeableConcept.coding`, use the system `http://terminology.hl7.org/CodeSystem/v2-0477` and one code from `I` through `V`.
A `valueCodeableConcept` with only `text` supplies no schedule.

<details>

<summary>Schedule II extension</summary>

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

The module sends the prescription's schedule in `DrugCoded/DEASchedule/Code` and each scheduled compound ingredient's schedule in `CompoundIngredient/DEASchedule/Code`.
Both fields use NCI Thesaurus codes.

* Schedule I maps to `C48672`.
* Schedule II maps to `C48675`.
* Schedule III maps to `C48676`.
* Schedule IV maps to `C48677`.
* Schedule V maps to `C48679`.

## Schedule Checks

When `EPCS_MODE=disabled`, the module rejects a controlled [NewRx](../prescribing/newrx-message.md) with `epcs-disabled`.
It also rejects a [renewal](../prescribing/pharmacy-initiated-messages/rx-renewal.md) or [change](../prescribing/pharmacy-initiated-messages/rx-change.md) response for a controlled prescription unless the prescriber denies the request.

The schedule checks depend on what the prescriber sends.

* For a NewRx or a response that lets the pharmacy fill a prescription, the module validates the medication's schedule. For a compound, it also [checks the ingredient schedules](../prescribing/compound-medications.md#schedule-checks).
* For a denial, a pending response, or approval of a prior-authorization change request, it checks the medication code for duplicate schedules and unsupported schedule codings.

If a schedule check fails, the module returns `422` with the error message in `OperationOutcome.issue[].details.text`.
If a NewRx group includes a prescription the module already sent, it returns `202` and gives the reason for each failure in `failures[].reason`.

<details>

<summary>Medication schedule errors</summary>

* `medication-has-multiple-dea-schedules` means the medication code has multiple schedule extensions, or one extension has multiple codings under the DEA schedule system.
* `dea-schedule-coding-system-is-not-supported` means the extension contains codings but none supplies a `code` under the DEA schedule system.
* `controlled-substance-missing-dea-schedule` means the schedule code for a controlled prescription is blank.
* `controlled-substance-invalid-dea-schedule` means the schedule code falls outside `I` through `V`.

</details>
