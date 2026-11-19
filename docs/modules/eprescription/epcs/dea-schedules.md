---
description: Store DEA schedules on medications and compound ingredients, and see how the Aidbox ePrescription module classifies a controlled prescription from them.
---

# DEA Schedules

The module treats a prescription as a **controlled prescription** when its medication has a DEA schedule.
The EHR stores the schedule the practitioner reviewed, and the module reads it from the prescription's medication.

## Store a DEA Schedule

Store the schedule in the `http://aidbox.app/ePrescription/FHIRSchema/medication-dea-schedule` extension of the medication code:

* `MedicationRequest.medicationCodeableConcept` for a prescription without a `Medication` resource
* `Medication.code` for a `Medication` that is not a [compound](#compound-medications)
* `Medication.ingredient.itemCodeableConcept` for each scheduled ingredient of a compound

The extension's `valueCodeableConcept` holds one coding under `http://terminology.hl7.org/CodeSystem/v2-0477` with one of the codes `I`, `II`, `III`, `IV`, or `V`.
Give each code at most one schedule extension, with one coding under that system.
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

## Compound Medications

The module treats a `Medication` as a compound when either is true:

* its `http://aidbox.app/ePrescription/FHIRSchema/medication-is-compound` extension has `valueBoolean: true`
* it has `ingredient` entries and `Medication.code` has no NDC coding

The ingredients decide the schedule of a compound.
A prescription whose compound has at least one scheduled ingredient is a **controlled prescription**, and the strictest ingredient schedule is its schedule.
`I` is the strictest and `V` the least strict, so a compound with a Schedule II and a Schedule IV ingredient follows the rules of Schedule II.

A schedule on `Medication.code` of a compound is optional.
When you store one, it must equal the strictest ingredient schedule.
The module never classifies a compound by that schedule.

Only an active ingredient can have a schedule, so leave the extension out of an ingredient with `isActive: false`.

<details>

<summary>Compound with a scheduled ingredient</summary>

```json
{
  "resourceType": "Medication",
  "id": "compound-example",
  "code": {
    "text": "Hydrocodone 1 mg/mL in oral suspension base"
  },
  "extension": [
    {
      "url": "http://aidbox.app/ePrescription/FHIRSchema/medication-is-compound",
      "valueBoolean": true
    }
  ],
  "ingredient": [
    {
      "itemCodeableConcept": {
        "text": "Hydrocodone bitartrate powder",
        "coding": [
          {
            "system": "http://hl7.org/fhir/sid/ndc",
            "code": "38779052405"
          }
        ],
        "extension": [
          {
            "url": "http://aidbox.app/ePrescription/FHIRSchema/medication-dea-schedule",
            "valueCodeableConcept": {
              "coding": [
                {
                  "system": "http://terminology.hl7.org/CodeSystem/v2-0477",
                  "code": "II"
                }
              ]
            }
          }
        ]
      },
      "isActive": true
    },
    {
      "itemCodeableConcept": {
        "text": "Oral suspension base"
      },
      "isActive": false
    }
  ]
}
```

</details>

### Ingredient NDCs

When EPCS is enabled (`EPCS_MODE=full`), each scheduled ingredient of a compound needs an 11-digit NDC.
Store it as a coding under `http://hl7.org/fhir/sid/ndc` in the ingredient's `itemCodeableConcept`.

The module sends every 11-digit ingredient NDC to the pharmacy in `CompoundIngredient/ItemNumber`, whether or not the ingredient has a schedule.

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

The module checks the schedules when you send a [NewRx](../prescribing/newrx-message.md) or respond to a [renewal](../prescribing/pharmacy-initiated-messages/rx-renewal.md) or [change](../prescribing/pharmacy-initiated-messages/rx-change.md) request.
It runs every check below for a NewRx and for a response that lets the pharmacy fill the prescription.
For these responses, the module runs only `medication-has-multiple-dea-schedules` and `dea-schedule-coding-system-is-not-supported`:

* a denied response
* a pending response
* an approved prior-authorization change response

When EPCS is disabled (`EPCS_MODE=disabled`), the module rejects a controlled prescription with `epcs-disabled`, including a compound with a scheduled ingredient.

A request that fails a check returns `422` with an `OperationOutcome`.
For an error about a compound, the issue's `diagnostics` holds a JSON object whose `in` field points to the root medication (`["Medication"]`) or to the ingredient (`["Medication", "ingredient", <index>]`).

When the module sent other prescriptions of a group earlier, a group submission that fails a check returns `202` instead, and `failures[].reason` holds the error code of each prescription it did not send.

<details>

<summary>Error Responses</summary>

* The root medication code, `Medication.code` or `MedicationRequest.medicationCodeableConcept`:
  * `medication-has-multiple-dea-schedules`: the code has more than one schedule extension, or more than one coding under `http://terminology.hl7.org/CodeSystem/v2-0477` in one extension.
  * `dea-schedule-coding-system-is-not-supported`: a schedule extension has codings, and none of them holds a code under `http://terminology.hl7.org/CodeSystem/v2-0477`.
  * `controlled-substance-invalid-dea-schedule`: the schedule is not one of `I` to `V`.
  * `compound-root-dea-schedule-without-ingredient-schedules`: the code of a compound has a schedule, and no ingredient has one.
  * `compound-root-dea-schedule-mismatch`: the code of a compound has a schedule other than the strictest ingredient schedule.
* A compound ingredient:
  * `compound-ingredient-has-multiple-dea-schedules`: the ingredient has more than one schedule extension, or more than one coding under `http://terminology.hl7.org/CodeSystem/v2-0477` in one extension.
  * `compound-ingredient-dea-schedule-coding-system-is-not-supported`: a schedule extension has codings, and none of them is under `http://terminology.hl7.org/CodeSystem/v2-0477`.
  * `compound-ingredient-invalid-dea-schedule`: the schedule is not one of `I` to `V`, or a schedule extension's codings under `http://terminology.hl7.org/CodeSystem/v2-0477` have no code.
  * `compound-inactive-ingredient-has-dea-schedule`: an ingredient with `isActive: false` has a schedule.
* A scheduled ingredient of a compound, when EPCS is enabled:
  * `controlled-compound-ingredient-missing-ndc`: the ingredient has no coding under `http://hl7.org/fhir/sid/ndc`.
  * `controlled-compound-ingredient-invalid-ndc`: the ingredient's NDC coding has no code, or its code does not have 11 digits.

</details>
