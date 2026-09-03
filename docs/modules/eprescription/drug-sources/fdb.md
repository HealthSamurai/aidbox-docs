---
description: Integrate FirstDataBank FDB medication database for drug information and clinical decision support.
---

# FDB

## Supported interaction code systems

For drugs:

* `urn:app:aidbox:e-prescriptions:fdb:DispensableDrugID` - FDB dispensable drug id
* `urn:app:aidbox:e-prescriptions:fdb:DrugNameID` - FDB drug name id
* [`http://www.nlm.nih.gov/research/umls/rxnorm`](http://www.nlm.nih.gov/research/umls/rxnorm) - RxNorm

For allergies:

* [`http://snomed.info/sct`](http://snomed.info/sct) - SNOMED
* `urn:app:aidbox:e-prescriptions:fdb:AllergenGroupID` - FDB allergen group id
* `urn:app:aidbox:e-prescriptions:fdb:DrugNameID` - FDB drug name id
* `urn:app:aidbox:e-prescriptions:fdb:IngredientID` - FDB ingredient id

Example request body for `POST /api/drug-sources/fdb/interactions`:

```json
{
  "medications": [
    {
      "system": "http://www.nlm.nih.gov/research/umls/rxnorm",
      "code": "167"
    }
  ],
  "allergies": [
    {
      "system": "urn:app:aidbox:e-prescriptions:fdb:IngredientID",
      "code": "2432"
    }
  ]
}
```

## Identify Rx and OTC products

`GET /api/drug-sources/fdb/medications` returns a FHIR `Bundle` of `MedicationKnowledge` resources. Each result can include an FDB Federal Legend Code at `regulatory[0].schedule[0].schedule`. Its `text` describes the class, and `coding[0].code` contains the FDB code.

The endpoint returns these FDB codes:

| Code | Description | Meaning |
| --- | --- | --- |
| 1 | Prescription Required | The product requires a prescription under the Food, Drug, and Cosmetic Act. |
| 2 | No Prescription Required | The product does not require a prescription under the Food, Drug, and Cosmetic Act. |
| 3 | Available in Multiple Classes | The packaged drugs associated with the medication have different values. |
| 4 | Non-drug, Non-device | The product is not a drug or device under the Food, Drug, and Cosmetic Act. |
| 9 | No Value | FDB has no packaged drug record associated with the medication. |

For a drug, code `1` means Rx and code `2` means OTC. Codes `3`, `4` and `9` do not establish an Rx or OTC class.

Example medication search result:

```json
{
  "resourceType": "MedicationKnowledge",
  "code": {
    "text": "Example medication"
  },
  "regulatory": [
    {
      "regulatoryAuthority": {
        "display": "FDCA"
      },
      "schedule": [
        {
          "schedule": {
            "text": "Prescription Required",
            "coding": [
              {
                "code": "1",
                "system": "urn:app:aidbox:e-prescriptions:fdb:FederalLegendCode"
              }
            ]
          }
        }
      ]
    }
  ]
}
```
