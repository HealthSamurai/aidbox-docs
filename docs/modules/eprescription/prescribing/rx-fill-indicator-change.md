---
description: Change which fill notifications a pharmacy sends for a delivered prescription with the RxFillIndicatorChange NCPDP SCRIPT message.
---

# RxFillIndicatorChange Message

## Overview

A pharmacy reports fill events for a prescription in `RxFill` messages.
The prescriber's **RxFill preferences** say which fill events the pharmacy should report.
They travel as `RxFillIndicator` values in the [NewRx](newrx-message.md), or in the renewal or change response that created the prescription.

RxFillIndicatorChange sends new RxFill preferences for a prescription the pharmacy already received.
It sends no new prescription and does not change the medication order.

The ePrescription module supports RxFillIndicatorChange for NCPDP SCRIPT 2023011.

## RxFill preferences

RxFill preferences are a list of `RxFillIndicator` values:

* `All`: report every fill event
* `None`: report no fill events. The prescription stays active.
* any combination of `Dispensed`, `PartiallyDispensed`, `NotDispensed`, and `Transferred`

`All` and `None` must be used alone.
A value can appear only once, and the order of values does not matter.

## When you can send a change

The module accepts a change when all of these conditions hold:

1. The `medication-request-new-rx-status` extension of the `MedicationRequest` is not `cancelled`.
2. Surescripts confirmed that the pharmacy received the message that carried the prescription:
   * the NewRx, for a prescription sent with NewRx
   * the approving renewal or change response, for a prescription that response created
3. The pharmacy `Organization` has the Surescripts service level `RxFillIndicatorChange` in `meta.tag`.
4. No [CancelRx](cancelrx-message.md) started, or the pharmacy denied it, or the module proved that no CancelRx message reached the pharmacy.
5. No other change for the prescription is pending.

A pending change does not block CancelRx.

## Check the current state

Call `GET /e-prescription/rx/rx-fill-indicator-change?medicationRequestId=<id>`:

```json
{
  "available": true,
  "unavailableReason": null,
  "confirmedRxFillPreferences": ["Dispensed", "PartiallyDispensed"],
  "pendingSelection": null,
  "lastChange": null
}
```

* `available`: whether you can send a change now
* `unavailableReason`: the `reason` and `message` of the first unmet condition, or `null`
* `confirmedRxFillPreferences`: the RxFill preferences of the latest delivered message that carried them.
  `null` means the module does not know them, which differs from `["None"]`.
* `pendingSelection`: the RxFill preferences of a change that waits for its delivery result, or `null`
* `lastChange`: the latest change, or `null`:
  * `selection`: the RxFill preferences it requested
  * `result`: `pending`, `delivered`, `not-delivered`, or `failed`
  * `failureReason`: the Surescripts error, for `not-delivered` and `failed`
  * `transaction`: the change's transaction

The module reads `confirmedRxFillPreferences` only from the messages it sent and their delivery results.
Your edits of the `RxFillIndicator` extensions on the `MedicationRequest` and an inbound `RxFill` do not change it.

`unavailableReason.reason` names the first unmet condition, in the order of the list above:

1. `prescription-cancelled`
2. `prescription-delivery-not-confirmed`
3. `pharmacy-does-not-support-rx-fill-indicator-change`
4. `cancellation-started`
5. `rx-fill-indicator-change-pending`

## Send a change

Call `POST /e-prescription/rx/rx-fill-indicator-change` with the prescription and the full new RxFill preferences:

```json
POST /e-prescription/rx/rx-fill-indicator-change

{
  "medicationRequestId": "your-medication-request-id",
  "rxFillIndicators": ["All"]
}
```

The module answers in one of these ways:

* `202`: the module sent the change.
  If you repeated the pending change, the module sent nothing new and returns its transaction.
  `transactions[0].attempt.status` shows the delivery:
  * `completed`: the pharmacy received the change
  * `in-progress`: delivery is unresolved, so the change stays pending
  * `on-hold`: the change did not reach the pharmacy. Repeat the same request to resend it.
  * `failed`: Surescripts refused the change, or the resend limit is spent
* `200` with `{"transactions": []}`: the pharmacy already confirmed these RxFill preferences and no change is pending, so the module sent nothing
* `409`: another change is pending, a CancelRx started, or the module cannot resend this change
* `422`: the RxFill preferences are invalid, or the prescription does not meet conditions 1 to 3

Until Surescripts confirms delivery, `confirmedRxFillPreferences` keeps the previous RxFill preferences and `pendingSelection` shows the new ones.
After delivery, the module writes the new RxFill preferences to the `medication-request-rx-fill-indicator` extensions of the `MedicationRequest`.
If delivery fails, the previous RxFill preferences stay confirmed and the extensions keep their values.

If a change response replaces the prescription while a change is pending, the change and its result stay with the original prescription.
The new prescription gets its RxFill preferences only from the change response.

## Example: certification step

The prescriber sent a NewRx with `Dispensed` and `PartiallyDispensed`, and the pharmacy received it.
The certification step switches the RxFill preferences to `All`.

1. Read the state. `available` is `true`, and `confirmedRxFillPreferences` is `["Dispensed", "PartiallyDispensed"]`.
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

4. After Surescripts confirms delivery, the read returns `confirmedRxFillPreferences: ["All"]` and `lastChange.result: "delivered"`.

## Prior authorization approvals

A prior authorization approval answers an [RxChange](pharmacy-initiated-messages/rx-change.md) request with **MessageRequestCode** `P`.
While a change for the prescription is pending, the module sends such an approval without `RxFillIndicator`, so the approval cannot restore older RxFill preferences.
In that case the module does not validate the `RxFillIndicator` values on the response `MedicationRequest`, and invalid values do not block the approval.
