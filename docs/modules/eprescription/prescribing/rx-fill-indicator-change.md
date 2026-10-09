---
description: Change which fill notifications a pharmacy sends for a delivered prescription with the RxFillIndicatorChange NCPDP SCRIPT message.
---

# RxFillIndicatorChange Message

## Overview

A prescriber chooses which fill events the pharmacy reports back in `RxFill` messages. The choice travels as `RxFillIndicator` values on [NewRx](newrx-message.md) and on renewal and change responses. RxFillIndicatorChange changes that choice for a prescription the pharmacy already received, without sending a new prescription or changing the medication order.

The ePrescription module supports RxFillIndicatorChange for NCPDP SCRIPT 2023011.

## Notification selection

A selection is a list of `RxFillIndicator` values:

* `All`: report every fill event
* `None`: report no fill events; the prescription stays active
* any combination of `Dispensed`, `PartiallyDispensed`, `NotDispensed`, and `Transferred`

`All` and `None` must be used alone, and a value cannot repeat. The order of values does not matter.

## When you can change notifications

The module accepts a change when all of these conditions hold:

* `MedicationRequest.status` is not `completed` or `cancelled`
* Surescripts gave a final confirmation that the pharmacy received the prescription, sent as a NewRx or as an approved renewal or change response
* the pharmacy `Organization` has the Surescripts service level `RxFillIndicatorChange` in `meta.tag`
* no cancellation started, or the pharmacy denied it, or Surescripts proved that the cancellation was not delivered
* no other notification change of the prescription is pending

A pending notification change does not block [CancelRx](cancelrx-message.md).

## Check the current state

Call `GET /e-prescription/rx/rx-fill-indicator-change?medicationRequestId=<id>`:

```json
{
  "available": true,
  "unavailableReason": null,
  "confirmedSelection": ["Dispensed", "PartiallyDispensed"],
  "pendingSelection": null,
  "lastChange": null
}
```

* `available`: whether you can send a change now
* `unavailableReason`: the `reason` and `message` of the first unmet condition, or `null`
* `confirmedSelection`: the selection of the latest delivered message that carried one. `null` means no delivered message carried a selection, which differs from `["None"]`.
* `pendingSelection`: the selection of a change that waits for its delivery result, or `null`
* `lastChange`: the latest change with its `selection`, its `result` (`pending`, `delivered`, `not-delivered`, or `failed`), the Surescripts error as `failureReason`, and its `transaction`

The module reads `confirmedSelection` from the messages it sent and their delivery results. Editing the `RxFillIndicator` extensions of the `MedicationRequest`, or receiving an `RxFill`, does not change it.

Possible `unavailableReason.reason` values:

* `prescription-completed-or-cancelled`
* `prescription-delivery-not-confirmed`
* `pharmacy-does-not-support-rx-fill-indicator-change`
* `cancellation-started`
* `rx-fill-indicator-change-pending`

## Send a change

Call `POST /e-prescription/rx/rx-fill-indicator-change` with the prescription and the full new selection:

```json
POST /e-prescription/rx/rx-fill-indicator-change

{
  "medicationRequestId": "your-medication-request-id",
  "rxFillIndicators": ["All"]
}
```

The module answers in one of these ways:

* `202`: the module sent the change. `transactions[0].attempt.status` tells what happened to it:
  * `completed`: the pharmacy received the change
  * `in-progress`: delivery is unresolved, so the change stays pending
  * `on-hold`: Surescripts proved the change was not delivered. Repeat the same request to resend it.
  * `failed`: Surescripts refused the change, or the resend limit is spent
* `202` with the same transaction: you repeated the pending change, so the module sent nothing new
* `200` with `{"transactions": []}`: the pharmacy already confirmed this selection, so the module sent nothing
* `409`: another change is pending, a cancellation blocks the change, or the module cannot resend this change
* `422`: the selection is invalid, or the prescription does not meet the conditions above

The pharmacy applies the new selection after the module confirms delivery. Until then, `confirmedSelection` keeps the previous selection and `pendingSelection` shows the new one. If delivery fails, the previous selection stays confirmed.

If a change response replaces the prescription while a notification change is pending, the change and its result stay with the original prescription. The new prescription starts with the selection its response carried.

## Example: certification step

The prescriber sent a NewRx with `Dispensed` and `PartiallyDispensed`, and the pharmacy received it. The certification step switches the selection to `All`.

1. Read the state. `available` is `true`, and `confirmedSelection` is `["Dispensed", "PartiallyDispensed"]`.
2. Send the change:

   ```json
   POST /e-prescription/rx/rx-fill-indicator-change

   {
     "medicationRequestId": "your-medication-request-id",
     "rxFillIndicators": ["All"]
   }
   ```

3. The module sends this message body to the pharmacy:

   ```xml
   <RxFillIndicatorChange>
     <RxFillIndicator>All</RxFillIndicator>
   </RxFillIndicatorChange>
   ```

4. After Surescripts confirms delivery, the read returns `confirmedSelection: ["All"]` and `lastChange.result: "delivered"`.

## Renewal and change responses

An approving renewal or change response sends the `RxFillIndicator` extensions of its `MedicationRequest`. A prior authorization approval sends none while a notification change of the same prescription is pending. See [RxChange Message](pharmacy-initiated-messages/rx-change.md#fill-notifications).
