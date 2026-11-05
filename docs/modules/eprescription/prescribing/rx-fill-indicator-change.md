---
description: Change which fill events a pharmacy reports for a delivered prescription with the RxFillIndicatorChange NCPDP SCRIPT message.
---

# RxFillIndicatorChange Message

A pharmacy reports fill events for a prescription in `RxFill` messages.
The prescriber's **RxFill preferences** say which fill events the pharmacy should report.
The [NewRx](newrx-message.md), RxRenewalResponse, or RxChangeResponse that created the prescription carries them to the pharmacy.

RxFillIndicatorChange sends new RxFill preferences for a prescription the pharmacy has already received.
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

After the pharmacy has received the prescription, the pharmacy keeps the RxFill preferences it received, even if you edit these extensions.
To change the RxFill preferences, [send a change](#send-a-change).
After the pharmacy receives the change, the module updates the extensions.

## When You Can Send a Change

The module accepts a change when all of these conditions hold.
If a condition fails, the [current state](#check-the-current-state) returns its code in parentheses as `unavailableReason.reason`:

1. The prescription is not cancelled (`prescription-cancelled`).
2. Surescripts confirmed that the pharmacy received the prescription (`prescription-delivery-not-confirmed`).
3. The pharmacy supports the Surescripts service level `RxFillIndicatorChange` (`pharmacy-does-not-support-rx-fill-indicator-change`).
4. No [CancelRx](cancelrx-message.md) was sent for the prescription, or the pharmacy denied it (`cancellation-started`).
5. No other change for the prescription is pending (`rx-fill-indicator-change-pending`).

## Check the Current State

```http
GET /e-prescription/rx/rx-fill-indicator-change?medicationRequestId=<MedicationRequest id>
```

Example `200 OK` response while a change is pending:

```json
{
  "available": false,
  "unavailableReason": {
    "reason": "rx-fill-indicator-change-pending",
    "message": "Another pharmacy notification change for this prescription is pending"
  },
  "confirmedRxFillPreferences": ["Dispensed", "PartiallyDispensed"],
  "pendingSelection": ["All"],
  "lastChange": {
    "selection": ["All"],
    "result": "pending",
    "failureReason": null
  }
}
```

* `available`: `true` if you can send a change now.
  Otherwise, `unavailableReason` holds a readable `message` and the `reason` code of the first [condition](#when-you-can-send-a-change) that blocks the change.
* `confirmedRxFillPreferences`: the RxFill preferences the pharmacy last received.
  `null` means the module does not know them, and `["None"]` means the pharmacy reports no fill events.
* `pendingSelection`: the RxFill preferences of the pending change, or `null`.
* `lastChange`: the latest change with its `selection` and `result`, or `null`.
  Its `result` is one of:
  * `pending`: the module waits for Surescripts to confirm delivery.
  * `delivered`: the pharmacy received the change.
  * `not-delivered`: the change did not reach the pharmacy. Send the same request again to resend it.
  * `failed`: the module cannot deliver the change. `failureReason` holds the Surescripts error.
    If you send the same change again, the module returns an error.

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

`202 Accepted` means the module accepted the change for delivery; the [current state](#check-the-current-state) shows the result.
If you repeat the request while the change is pending, the module returns `202 Accepted` again without a second message.

If the pharmacy already has these RxFill preferences and no change is pending, the module sends nothing and returns `200 OK`.
