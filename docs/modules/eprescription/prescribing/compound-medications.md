---
description: Represent a compound medication in FHIR, store the DEA schedules and NDCs of its ingredients, and see the checks the Aidbox ePrescription module runs on it.
---

# Compound Medications

The module treats a `Medication` as a compound when either of these is true:

* its `http://aidbox.app/ePrescription/FHIRSchema/medication-is-compound` extension has `valueBoolean: true`
* it has `ingredient` entries and `Medication.code` has no National Drug Code (NDC) coding

## Required Fields

A compound `Medication` needs:

* `code.text`: the compound description
* in each `ingredient`:
  * `itemCodeableConcept.text`: the ingredient description
  * a `http://aidbox.app/ePrescription/FHIRSchema/medication-ingredient-quantity` extension with a `valueQuantity`
  * for a scheduled ingredient, an 11-digit NDC as a coding under `http://hl7.org/fhir/sid/ndc` in `itemCodeableConcept`

## Ingredient Schedules

Store the schedule of each scheduled ingredient in the [DEA schedule extension](../epcs/dea-schedules.md#store-a-dea-schedule) of its `Medication.ingredient.itemCodeableConcept`.

A prescription whose compound has at least one scheduled ingredient is a [controlled prescription](../epcs/dea-schedules.md).
Its schedule is the strictest ingredient schedule.
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
      "extension": [
        {
          "url": "http://aidbox.app/ePrescription/FHIRSchema/medication-ingredient-quantity",
          "valueQuantity": {
            "value": 0.12,
            "code": "C48155",
            "system": "urn:app:aidbox:e-prescriptions:ncpdp:QuantityUnitOfMeasure"
          }
        }
      ],
      "isActive": true
    },
    {
      "itemCodeableConcept": {
        "text": "Oral suspension base"
      },
      "extension": [
        {
          "url": "http://aidbox.app/ePrescription/FHIRSchema/medication-ingredient-quantity",
          "valueQuantity": {
            "value": 120,
            "code": "C28254",
            "system": "urn:app:aidbox:e-prescriptions:ncpdp:QuantityUnitOfMeasure"
          }
        }
      ],
      "isActive": false
    }
  ]
}
```

</details>

## Compound Checks

<details>

<summary>Error Responses</summary>

* The compound's `Medication.code`:
  * `compound-stored-dea-schedule-without-ingredient-schedules`: the code of a compound has a schedule, and no ingredient has one.
  * `compound-stored-dea-schedule-mismatch`: the code of a compound has a schedule other than the strictest ingredient schedule.
* A compound ingredient:
  * `compound-ingredient-missing-description`: the ingredient has no `itemCodeableConcept.text`.
  * `compound-medication-ingredients-missing-quantity`: an ingredient has no `http://aidbox.app/ePrescription/FHIRSchema/medication-ingredient-quantity` extension.
  * `compound-ingredient-has-multiple-dea-schedules`: the ingredient has more than one schedule extension, or more than one coding under `http://terminology.hl7.org/CodeSystem/v2-0477` in one extension.
  * `compound-ingredient-dea-schedule-coding-system-is-not-supported`: a schedule extension has codings, and none of them is under `http://terminology.hl7.org/CodeSystem/v2-0477`.
  * `compound-ingredient-invalid-dea-schedule`: the schedule is not one of `I` to `V`, or a schedule extension's codings under `http://terminology.hl7.org/CodeSystem/v2-0477` have no code.
  * `compound-inactive-ingredient-has-dea-schedule`: an ingredient with `isActive: false` has a schedule.
* A scheduled ingredient of a compound:
  * `controlled-compound-ingredient-missing-ndc`: the ingredient has no coding under `http://hl7.org/fhir/sid/ndc`.
  * `controlled-compound-ingredient-invalid-ndc`: the ingredient's NDC coding has no code, or its code does not have 11 digits.
* A compound with a scheduled ingredient:
  * `controlled-compound-medication-missing-active-ingredients`: every ingredient has `isActive: false`.

Example response for `controlled-compound-ingredient-missing-ndc` on the first ingredient of the compound above:

```json
{
  "resourceType": "OperationOutcome",
  "issue": [
    {
      "severity": "error",
      "code": "invalid",
      "details": {
        "text": "Compound ingredient with a DEASchedule must include an NDC",
        "coding": [
          {
            "system": "http://aidbox.app/ePrescription/CodeSystem/error-reason",
            "code": "controlled-compound-ingredient-missing-ndc"
          }
        ]
      },
      "diagnostics": "{\"in\":[\"Medication\",\"ingredient\",0],\"resourceType\":\"Medication\",\"id\":\"compound-example\"}"
    }
  ]
}
```

</details>
