---
description: Change which fill notifications a pharmacy sends for a delivered prescription with the RxFillIndicatorChange NCPDP SCRIPT message.
---

# RxFillIndicatorChange Message

A pharmacy reports fill events for a prescription in `RxFill` messages.
The prescriber's **RxFill preferences** say which fill events the pharmacy should report.
They travel as `RxFillIndicator` values in the [NewRx](newrx-message.md), or in the renewal or change response that created the prescription.

RxFillIndicatorChange sends new RxFill preferences for a prescription the pharmacy already received.
The ePrescription module supports it for NCPDP SCRIPT 2023011.

## RxFill Preferences

RxFill preferences are a list of `RxFillIndicator` values:

* `All`: report every fill event.
* `None`: report no fill events.
* Any combination of `Dispensed`, `PartiallyDispensed`, `NotDispensed`, and `Transferred`.

`All` and `None` must be used alone, and a value can appear only once.

The EHR stores the RxFill preferences on the `MedicationRequest`, one `medication-request-rx-fill-indicator` extension per value:

```json
{
  "url": "http://aidbox.app/ePrescription/FHIRSchema/medication-request-rx-fill-indicator",
  "valueCode": "Dispensed"
}
```

## When You Can Send a Change

The module accepts a change when all of these conditions hold:

1. The `medication-request-new-rx-status` extension of the `MedicationRequest` is not `cancelled`.
2. Surescripts confirmed that the pharmacy received the message that carried the prescription:
   * The NewRx, for a prescription sent with NewRx.
   * The approving renewal or change response, for a prescription that response created.
3. The pharmacy `Organization` has the Surescripts service level `RxFillIndicatorChange` in `meta.tag`.
4. No [CancelRx](cancelrx-message.md) started, or the pharmacy denied it, or the module proved that no CancelRx message reached the pharmacy.
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
* `unavailableReason`: the `reason` and `message` of the first unmet condition, or `null`.
* `confirmedRxFillPreferences`: the RxFill preferences of the latest delivered message that carried them.
  `null` means the module does not know them, which differs from `["None"]`.
* `pendingSelection`: the RxFill preferences of a change that waits for its delivery result, or `null`.
* `lastChange`: the latest change, or `null`:
  * `selection`: the RxFill preferences it requested.
  * `result`: `pending`, `delivered`, `not-delivered`, or `failed`. [Send a Change](#send-a-change) explains each value.
  * `failureReason`: the Surescripts error, for `not-delivered` and `failed`.
  * `transaction`: the change's transaction.

Editing the `medication-request-rx-fill-indicator` extensions or receiving an inbound `RxFill` does not change `confirmedRxFillPreferences`.

`unavailableReason.reason` names the first unmet condition, in the order of the [conditions](#when-you-can-send-a-change):

1. `prescription-cancelled`
2. `prescription-delivery-not-confirmed`
3. `pharmacy-does-not-support-rx-fill-indicator-change`
4. `cancellation-started`
5. `rx-fill-indicator-change-pending`

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

`202 Accepted` returns the change's transaction in `transactions[0]`.
Repeating the pending change returns its transaction and sends no second message.

`transactions[0].attempt.status` shows the delivery.
`lastChange.result` in the [current state](#check-the-current-state) names the same outcome as shown in parentheses:

* `completed` (`delivered`): the pharmacy received the change.
* `in-progress` (`pending`): delivery is unresolved, so the change stays pending.
* `on-hold` (`not-delivered`): the change did not reach the pharmacy. Repeat the same request to resend it.
* `failed` (`failed`): Surescripts refused the change, or the resend limit is spent.

If Surescripts accepts the change with Status `000` and never sends the final answer, the change stays pending and blocks every later change for the prescription.
The API cannot resolve such a change.

`200 OK` with `{"transactions": []}` means the pharmacy already confirmed these RxFill preferences and no change is pending, so the module sent nothing.

After delivery, the module writes the new RxFill preferences to the `medication-request-rx-fill-indicator` extensions.

<details>

<summary>Error Responses</summary>

* `400`: `medicationRequestId` or `rxFillIndicators` is missing.
* `409`, in any of these cases:
  * Another change for the prescription is pending.
  * A CancelRx started.
  * Another request is sending the same change.
  * The resend limit for this change is spent.
  * Surescripts refused this change.
* `422`, in any of these cases:
  * The RxFill preferences are invalid.
  * The `MedicationRequest` does not exist.
  * The prescription does not meet conditions 1 to 3 of [When You Can Send a Change](#when-you-can-send-a-change).

</details>
