---
description: Represent compound medications in FHIR and send ingredient schedules and National Drug Codes to the pharmacy.
---

# Compound Medications

The ePrescription module treats a FHIR `Medication` as a compound if either condition holds.

* Its `http://aidbox.app/ePrescription/FHIRSchema/medication-is-compound` extension has `valueBoolean: true`.
* It has `ingredient` entries and no National Drug Code (NDC) in `Medication.code`.

## Ingredient Schedules

Store the [DEA schedule extension](../epcs/dea-schedules.md#store-a-dea-schedule) on `Medication.ingredient.itemCodeableConcept` for each scheduled ingredient.
Omit it for ingredients with `isActive: false`.

If a compound has at least one scheduled ingredient, the module treats its prescription as a **controlled prescription**.
The strictest ingredient schedule determines the prescription's schedule, with I the strictest and V the least strict.
For example, a compound with a Schedule II ingredient and a Schedule IV ingredient has Schedule II.
If you also store a schedule on `Medication.code`, it must match the strictest ingredient schedule.

In the NCPDP message, the module sends the compound's schedule in `DrugCoded/DEASchedule` and each scheduled ingredient's schedule in `CompoundIngredient/DEASchedule`.
Both fields use the [NCI Thesaurus codes for DEA schedules](../epcs/dea-schedules.md#schedules-in-ncpdp-messages).

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

## Ingredient NDCs

Each scheduled ingredient of a compound needs an 11-digit NDC.
Store it as a coding under `http://hl7.org/fhir/sid/ndc` in the ingredient's `itemCodeableConcept`.

The module sends every 11-digit ingredient NDC to the pharmacy in `CompoundIngredient/ItemNumber`, whether or not the ingredient has a schedule.

## Schedule Checks

The module checks compound ingredients for a NewRx or a response that lets the pharmacy fill the prescription.
See [Schedule Checks](../epcs/dea-schedules.md#schedule-checks) for the checks on the medication code, other response types, and group submissions.

For a compound error, the `OperationOutcome.issue.diagnostics` field contains a JSON object.
Its `in` field identifies where to look.

* `["Medication"]` points to the compound.
* `["Medication", "ingredient", <index>]` points to the ingredient at that index.

<details>

<summary>Error Responses</summary>

* The compound's `Medication.code`:
  * `compound-root-dea-schedule-without-ingredient-schedules`: the code of a compound has a schedule, and no ingredient has one.
  * `compound-root-dea-schedule-mismatch`: the code of a compound has a schedule other than the strictest ingredient schedule.
* A compound ingredient:
  * `compound-ingredient-has-multiple-dea-schedules`: the ingredient has more than one schedule extension, or more than one coding under `http://terminology.hl7.org/CodeSystem/v2-0477` in one extension.
  * `compound-ingredient-dea-schedule-coding-system-is-not-supported`: a schedule extension has codings, and none of them is under `http://terminology.hl7.org/CodeSystem/v2-0477`.
  * `compound-ingredient-invalid-dea-schedule`: the schedule is not one of `I` to `V`, or a schedule extension's codings under `http://terminology.hl7.org/CodeSystem/v2-0477` have no code.
  * `compound-inactive-ingredient-has-dea-schedule`: an ingredient with `isActive: false` has a schedule.
* A scheduled ingredient of a compound:
  * `controlled-compound-ingredient-missing-ndc`: the ingredient has no coding under `http://hl7.org/fhir/sid/ndc`.
  * `controlled-compound-ingredient-invalid-ndc`: the ingredient's NDC coding has no code, or its code does not have 11 digits.

</details>
