---
description: Change which fill notifications a pharmacy sends for a delivered prescription with the RxFillIndicatorChange NCPDP SCRIPT message.
---

# RxFillIndicatorChange Message

A pharmacy reports fill events for a prescription in `RxFill` messages.
The prescriber's **RxFill preferences** say which fill events the pharmacy should report.
The [NewRx](newrx-message.md), or the renewal or change response that created the prescription, carries them to the pharmacy.

RxFillIndicatorChange sends new RxFill preferences for a prescription the pharmacy already received.
The ePrescription module supports it for NCPDP SCRIPT 2023011.

## RxFill Preferences

RxFill preferences are a list of `RxFillIndicator` values:

* `All`: report every fill event.
* `None`: report no fill events.
* Any combination of `Dispensed`, `PartiallyDispensed`, `NotDispensed`, and `Transferred`.

Use `All` or `None` alone, and list each value once.

The EHR stores the RxFill preferences on the `MedicationRequest`, one `medication-request-rx-fill-indicator` extension per value:

```json
{
  "url": "http://aidbox.app/ePrescription/FHIRSchema/medication-request-rx-fill-indicator",
  "valueCode": "Dispensed"
}
```

After the pharmacy received the prescription, editing these extensions sends nothing to the pharmacy.
To change the RxFill preferences, [send a change](#send-a-change).
After the pharmacy receives the change, the module updates the extensions.

## When You Can Send a Change

The module accepts a change when all of these conditions hold:

1. The prescription is not cancelled.
2. Surescripts confirmed that the pharmacy received the prescription.
3. The pharmacy `Organization` has the Surescripts service level `RxFillIndicatorChange` in `meta.tag`.
4. No [CancelRx](cancelrx-message.md) was sent for the prescription, or the pharmacy denied it.
5. No other change for the prescription is pending.

## Check the Current State

```http
GET /e-prescription/rx/rx-fill-indicator-change?medicationRequestId=<MedicationRequest id>
```

Example `200 OK` response:

```json
{
  "available": true,
  "unavailableReason": null,
  "confirmedRxFillPreferences": ["Dispensed", "PartiallyDispensed"],
  "pendingSelection": null,
  "lastChange": null
}
```

* `available`: whether you can send a change now.
  If not, `unavailableReason.reason` names the first failed condition:
  1. `prescription-cancelled`
  2. `prescription-delivery-not-confirmed`
  3. `pharmacy-does-not-support-rx-fill-indicator-change`
  4. `cancellation-started`
  5. `rx-fill-indicator-change-pending`
* `confirmedRxFillPreferences`: the RxFill preferences the pharmacy last received.
  `null` means the module does not know them, and `["None"]` means no fill notifications.
* `pendingSelection`: the RxFill preferences of a change that is not delivered yet, or `null`.
* `lastChange`: the latest change, or `null`.
  Its `result` is one of:
  * `pending`: the module waits for Surescripts to confirm delivery.
  * `delivered`: the pharmacy received the change.
  * `not-delivered`: the change did not reach the pharmacy. Send the same request again to resend it.
  * `failed`: the module cannot deliver the change. `failureReason` holds the Surescripts error.

<details>

<summary>Error Responses</summary>

* `422`: the `MedicationRequest` does not exist.

</details>

## Send a Change

Send the prescription and the full new RxFill preferences:

```http
POST /e-prescription/rx/rx-fill-indicator-change
Content-Type: application/json

{
  "medicationRequestId": "<MedicationRequest id>",
  "rxFillIndicators": ["All"]
}
```

`202 Accepted` means the module accepted the change for delivery.
Follow the delivery in `lastChange.result` of the [current state](#check-the-current-state).
Sending the same request again while the change is pending sends no second message.

If the pharmacy already has these RxFill preferences and no change is pending, the module sends nothing and returns `200 OK` with `{"transactions": []}`.

<details>

<summary>Error Responses</summary>

* `409`, in any of these cases:
  * Another change for the prescription is pending.
  * A CancelRx was sent for the prescription.
  * The same change already failed.
* `422`, in any of these cases:
  * The RxFill preferences are invalid.
  * The `MedicationRequest` does not exist.
  * The prescription does not meet conditions 1 to 3 of [When You Can Send a Change](#when-you-can-send-a-change).

</details>
