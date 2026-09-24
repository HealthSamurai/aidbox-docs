---
description: Nominate, accept, cancel, and list EPCS approver nominations in the Aidbox ePrescription module.
---

# Approver Nominations

## Nominate the First Approver

An administrator access manager may nominate another user at a location that has no EPCS approver.
The nominee's `User.fhirUser` must reference a `Practitioner` whose `active` field is not `false`.
At least one of that practitioner's `PractitionerRole` records at the location must have `active: true`, a `period.start` in the past, a `period.end` in the future, and a well-formed DEA identifier.
The module checks the identifier's format, not whether the registration or the practitioner's state authorizations are current.
Verify those outside the module before nominating.

```http
POST /e-prescription/access/epcs/requests
Content-Type: application/json

{
  "action": "grant",
  "permission": "epcs-access-approver",
  "userId": "<nominee's Aidbox User id>",
  "locationId": "<Location id>"
}
```

`201 Created` returns an `EPrescriptionAccessRequest` with `status: pending`.
It records the nominee in `user`, the administrator in `requestedBy`, and a deadline in `expiresAt` 48 hours after `requestedAt`.

* `400` means a required field is missing or invalid. The operation supports only `action: grant` and `permission: epcs-access-approver`.
* `403` means the caller has no Acting User or does not administer the location.
* `409` means a pending, unexpired nomination exists for the same user and location.
* `422` means the caller nominated themselves, the location already has an approver, or the nominee is missing or ineligible.

You may nominate several people for one location, but only one can become its first approver.
Once one nominee accepts, the module rejects the others' acceptance attempts.

## Accept a Nomination

Only the nominee may accept their nomination.

```http
POST /e-prescription/access/epcs/requests/<id>/approve
Content-Type: application/json

{
  "twoFactorCode": "<nonblank code>"
}
```

`200 OK` returns the request with `status: approved`, `resolvedBy`, and `resolvedAt`.
The module creates an `EPrescriptionAccessPermission` for the nominee with a `request` reference to the nomination.
The nominee can retrieve that permission through `permissions/mine`.

The request must still be pending and unexpired, the location must still have no approver, and the nominee must still meet the eligibility rules above.
The module checks these conditions again on acceptance.

* `400` means `twoFactorCode` is missing or is not a string.
* `403` means the caller has no Acting User or is not the nominee.
* `409` means another call changed the request or appointed an approver during acceptance.
* `422` means the request is missing, resolved, or expired; the code is blank; the location has an approver; or the nominee is no longer eligible.

**LIMITATIONS:** The module checks only that `twoFactorCode` is nonblank. It does not verify the code or include it in the permission, request, or audit event.

## Cancel or List Nominations

The nominee or any current administrator access manager of the location may cancel a pending, unexpired nomination:

```http
POST /e-prescription/access/epcs/requests/<id>/cancel
```

`200 OK` returns the request with `status: cancelled`, `resolvedBy`, and `resolvedAt`.
A missing or resolved request, or one past its deadline, returns `422`.
An unauthorized caller receives `403`; a concurrent change to the request returns `409`.

To list nominations, call:

```http
GET /e-prescription/access/epcs/requests
GET /e-prescription/access/epcs/requests?location=<Location id>&status=pending
```

`200 OK` returns a searchset `Bundle` containing requests at the locations the Acting User administers, plus requests that nominate the Acting User.
The optional `location` and `status` filters narrow that list.
Supported statuses are `pending`, `approved`, `cancelled`, and `expired`.
A caller with no matching requests receives an empty `Bundle`; a call without an Acting User returns `403`.

## Expiration and Audit Trail

The `expire-access-requests` scheduler job runs hourly by default and marks overdue pending requests `expired`.
Acceptance and cancellation check `expiresAt` even before that job runs.
An expired nomination does not prevent a new nomination for the same user and location.

Nomination, acceptance, and cancellation write `AuditEvent` records with these `type.code` values:

* `epcs-access-request-creation`
* `epcs-access-request-approval`
* `epcs-access-request-cancellation`

The module commits each successful change and its audit event in one transaction.
Acceptance records `secondPersonApprovalWaiver: no-active-approver`, because the nominee accepts without a second approver.
Rejected operations record `failureReason`; parameter validation errors that return `400` do not create an event.
A call without an Acting User records the rejection before parameter validation.
Listing and scheduled expiration create no audit events.
