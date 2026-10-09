---
description: Cancel electronic prescriptions using CancelRx NCPDP SCRIPT message in Surescripts workflow.
---

# CancelRx Message

### Overview

CancelRx is a message type used to discontinue a previously sent prescription electronically through the Surescripts network. It allows prescribers to request cancellation of a [NewRx](newrx-message.md) that was previously sent to a pharmacy.

### How to Send CancelRx Message

To send a CancelRx message, follow these steps:

1. Find the MedicationRequest you want to cancel.
2. Call the CancelRx API endpoint: `POST /e-prescription/rx/cancel`\
   Expected payload is a medication request identifier. Unlike [NewRx](newrx-message.md) which accepts a group identifier to send multiple prescriptions at once, CancelRx operates on a single MedicationRequest since cancellations are handled individually per prescription. This allows for more granular control when discontinuing specific medications.
3. Monitor the status of the cancellation using the status fields.

#### Required FHIR Resources

CancelRx requires the same FHIR resources as [NewRx](newrx-message.md) message, with identical validation rules and required fields. In addition, the `medication-request-new-rx-status` extension of the MedicationRequest **must be "active" or "completed"**.

### Cancel or Discontinue

The ePrescription module sends each CancelRx message to Surescripts with a code that tells the pharmacy if the prescription was already dispensed. It chooses the code from RxFill messages, so you don't pass it yourself:

* Discontinue (`D`): the pharmacy reported in an RxFill message that it dispensed this prescription fully or partially.
* Cancel (`C`): no RxFill message reports dispensing.

Dispense records created by your EHR and the patient's medication history do not affect this choice.

The module cannot choose between Cancel and Discontinue if both are true:

* No RxFill message confirms dispensing of this prescription.
* An RxFill message may refer to this prescription or to another one.

In this case, it returns `422 ambiguous-dispensing-history` and sends nothing. Contact the pharmacy to cancel the prescription.

### Status Management

The cancellation status is tracked via two extensions on MedicationRequest:

* `medication-request-cancellation-status`: Tracks the cancellation workflow status
* `medication-request-cancellation-status-reason`: Contains details about the current status

Main MedicationRequest status values remain same as for [NewRx](newrx-message.md). The system will track cancellation workflow via status extensions until we receive a final response from the pharmacy. Only upon receiving a positive cancellation acknowledgment, the MedicationRequest status will be updated to `cancelled`. This helps maintain clear audit trail of prescription state transitions.

It's expected to get a response from pharmacy within 48 hours. If no response is received within this time frame, status will be updated to `unknown` <sub>_(since 2.0)_</sub>.

#### Status flow

<figure><img src="../../../../assets/image (1) (1).avif" alt="CancelRx message status flow diagram"><figcaption></figcaption></figure>
