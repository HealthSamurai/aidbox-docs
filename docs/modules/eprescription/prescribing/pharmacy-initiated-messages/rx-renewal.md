---
description: Manage pharmacy-initiated prescription renewal requests using RxRenewalRequest NCPDP SCRIPT message.
---

# RxRenewal Message

## Overview

RxRenewal is a type of message sent by pharmacy to subscriber when the medication should be renewed.
It is required that RxRenewal is preceded by NewRx.

## Responding to RxRenewalRequest

### Decisions use cases

{% hint style="info" %}

**MedicationRequest.extension.where(url = "http://aidbox.app/ePrescription/FHIRSchema/medication-request-pharmacy-request-refills")** referred as **PharmacyRequestedRefills** for simplicity

{% endhint %}

*Example 1:* Prescriber wishes to deny the request because the patient must be re-examined.
Response must be `denied`

*Example 2:* Pharmacy has not requested a specific number of refills (**PharmacyRequestedRefills** not sent); prescriber wishes to approve the request, specifying 3 additional dispensings. Since the pharmacy did not request a specific number of refills **PharmacyRequestedRefills** and the **MedicationRequest.dispenseRequest.numberOfRepeatsAllowed** contains a value greater than zero, the response must be `approved`.

*Example 3:* Pharmacy requests 5 refills **PharmacyRequestedRefills**; prescriber approves 3 refills **MedicationRequest.dispenseRequest.numberOfRepeatsAllowed** Since this is a change in **MedicationRequest.dispenseRequest.numberOfRepeatsAllowed** versus **PharmacyRequestedRefills**, the response must be `approved-with-changes`.

*Example 4:* Prescriber changes **MedicationRequest.dosageInstruction.\*.text** from “Take one tablet daily” to “Take one tablet morning and evening.” (**MedicationRequest.dispenseRequest.quantity** and other fields may change as well).
Response must be `replace`.

*Example 5:* Pharmacy has not requested a specific number of refills (**PharmacyRequestedRefills** not sent); prescriber wishes to approve the request,
specifying 3 additional dispensings. In addition, the prescriber changes **MedicationRequest.dosageInstruction.\*.text** from “Take one tablet daily” to “Take one tablet morning and evening.” (<Quantity> and other fields may change as well).
Response must be `replace`.

*Example 6:*
If the prescriber wishes to send a new prescription to a different pharmacy (other than the one who made the RxRenewalRequest), the `replace` is an inappropriate response. A `denied` should be sent to the pharmacy that made the RxRenewalRequest, and a new prescription should be sent to the new pharmacy.

*Example 7:* The pharmacy sent an RxRenewal request proposing to renew Lipitor 20 mg. The prescriber responded with an RxRenewalResponse of type `pending`, indicating that a decision could not yet be made and that further review was required. The prescriber must wait for subsequent RxRenewalRequest messages from the pharmacy, as once a request has been answered with `pending`, it cannot later be responded to again with `approved` or `denied` for the same transaction.


### Denied

<sub>Same as for [RxChange](rx-change.md#denied).</sub>

A `denied` decision needs a reason in `reasonCode`, `note`, or both.
The `note` of a `denied` decision has no length limit.

```http
POST /e-prescription/rx/respond-to-renewal
Content-Type: application/json

{
  "medicationRequestId": "<MedicationRequest id>",
  "responseType": "denied",
  "note": "Patient must be re-examined"
}
```

### Pending

<sub>Same as for [RxChange](rx-change.md#pending).</sub>

A `pending` decision requires `reasonCode`, `note` (up to 70 characters), and `expectedPendedResponseDate`:

```http
POST /e-prescription/rx/respond-to-renewal
Content-Type: application/json

{
  "medicationRequestId": "<MedicationRequest id>",
  "responseType": "pending",
  "reasonCode": "HR",
  "note": "Provider is on vacation",
  "expectedPendedResponseDate": "2025-12-12"
}
```

`reasonCode` accepts these codes for `pending`, the same as in RxChange:

| reason code | meaning                                                                         |
|-------------|---------------------------------------------------------------------------------|
| **HP**      | Patient has an appointment scheduled                                            |
| **HQ**      | Patient has labs/tests pending                                                  |
| **HR**      | Provider is unavailable and no one is available to make a decision              |
| **HS**      | Patient is currently undergoing acute care and a decision is pending resolution |
| **HT**      | Provider wishes to delay for reasons not otherwise indicated                    |

### Approved, ApprovedWithChanges

Use `approved` or `approved-with-changes` when the prescriber approves the renewal.
Both decisions require [`prescription`](README.md#prescription-fields).

<details>

<summary>Decisions differ by the approved number of refills</summary>

The pharmacy's requested number of refills is in this extension of the `MedicationRequest`:

```yaml
extension:
  - url: >-
      http://aidbox.app/ePrescription/FHIRSchema/medication-request-pharmacy-request-refills
    valueInteger: 1
```

The prescriber's approved number of refills is `prescription.dispenseRequest.numberOfRepeatsAllowed`.
Choose the decision by comparing the two:
* `approved`: the numbers are equal, or the pharmacy sent no number of refills.
* `approved-with-changes`: the numbers differ.

</details>

If the module created a `DetectedIssue` (the incoming data did not match existing records), replace these contained resources with existing references before you respond:
* `Patient`: `MedicationRequest.subject`
* `PractitionerRole`: `MedicationRequest.performer`
* `Practitioner`: `PractitionerRole.practitioner`
* `Location`: `PractitionerRole.location` or `PractitionerRole.organization`
* `Organization` (the pharmacy): `MedicationRequest.requester`
* `Medication`: `MedicationRequest.medication`.
  The module also accepts a contained `Medication`, so resolving it is optional.

Send `dispenseRequest` and `dosageInstruction` in `prescription`.
In most renewals, these match the [NewRx](../newrx-message.md) message.

```http
POST /e-prescription/rx/respond-to-renewal
Content-Type: application/json

{
  "medicationRequestId": "<MedicationRequest id>",
  "responseType": "approved",
  "prescription": {
    "dispenseRequest": {
      "quantity": {
        "code": "C48542",
        "unit": "Tablet",
        "value": 60,
        "system": "urn:app:aidbox:e-prescriptions:ncpdp:QuantityUnitOfMeasure"
      },
      "expectedSupplyDuration": {
        "code": "d",
        "unit": "days",
        "value": 30,
        "system": "http://unitsofmeasure.org"
      },
      "numberOfRepeatsAllowed": 1
    },
    "dosageInstruction": [
      {"text": "TAKE ONE TABLET TWO TIMES A DAY UNTIL GONE"}
    ]
  }
}
```

### Replace

Use `replace` when the new prescription changes data from the RxRenewalRequest that `approved` and `approved-with-changes` do not allow.

Rules for a `replace` response:
* The patient data can differ from the RxRenewalRequest as long as it identifies the same patient.
  For example, a corrected birth date, or `Robert` in `name.given` where the request has `Bob`.
* You cannot change the pharmacy.
* `prescription.authoredOn` is the date of the replacement prescription.
* `performer` can name a different prescriber than the one the pharmacy addressed.

Send the replacement prescription fields in [`prescription`](README.md#prescription-fields).
A `note` (up to 70 characters) is optional.
Add one to tell the pharmacy why the prescriber replaced the prescription.

```http
POST /e-prescription/rx/respond-to-renewal
Content-Type: application/json

{
  "medicationRequestId": "<MedicationRequest id>",
  "responseType": "replace",
  "note": "Changed course of therapy, so different medication is required",
  "prescription": {
    "authoredOn": "2025-12-12",
    "dosageInstruction": [
      {"text": "Take one tablet morning and evening"}
    ]
  }
}
```
