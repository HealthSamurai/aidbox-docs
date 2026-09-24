---
description: Nominate, accept, cancel, and list EPCS approver nominations in the Aidbox ePrescription module.
---

# Approver Nominations

An administrator access manager nominates the first EPCS approver of a location.
The nominee gets the `epcs-access-approver` permission only after they accept the nomination.

## Nominate the First Approver

An administrator access manager may nominate another user at a location that has no EPCS approver.
The module checks the nominee's records:

* The nominee's `User.fhirUser` references a `Practitioner`, and that practitioner's `active` field is not `false`.
* At least one of the practitioner's `PractitionerRole` records at the location has `active: true`, a `period.start` in the past, a `period.end` in the future, and a well-formed DEA identifier.

The module checks only the DEA identifier's format.
Before you nominate someone, verify outside the module that their DEA registration and state authorizations are current.

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
The request records the nominee in `user` and the administrator in `requestedBy`.
Its `expiresAt` deadline is 48 hours after `requestedAt`.

* `400` means a required field is missing or invalid. The operation supports only `action: grant` and `permission: epcs-access-approver`.
* `403` means the caller has no Acting User or does not administer the location.
* `409` means a pending, unexpired nomination exists for the same user and location.
* `422` means the caller nominated themselves, the location already has an approver, or the nominee is missing or ineligible.

You may nominate several people for one location, but only one of them becomes its first approver.
Once one nominee accepts, the module rejects acceptance by the others.

## Accept a Nomination

Only the nominee may accept their nomination.

```http
POST /e-prescription/access/epcs/requests/<id>/approve
Content-Type: application/json

{
  "twoFactorCode": "<nonblank code>"
}
```

The module checks these conditions again on acceptance:

* the request is still pending and unexpired
* the location still has no approver
* the nominee still meets the eligibility rules above

`200 OK` returns the request with `status: approved`, `resolvedBy`, and `resolvedAt`.
The module creates an `EPrescriptionAccessPermission` for the nominee, with a `request` reference to the nomination.
The nominee sees the new permission in [`GET /e-prescription/access/epcs/permissions/mine`](list-permissions.md#list-your-own-permissions).

* `400` means `twoFactorCode` is missing or is not a string.
* `403` means the caller has no Acting User or is not the nominee.
* `409` means another call changed the request or appointed an approver while this call ran.
* `422` means the request is missing, resolved, or expired; the code is blank; the location already has an approver; or the nominee is no longer eligible.

**LIMITATIONS:** The module checks only that `twoFactorCode` is nonblank. It does not verify the code or store it in the permission, the request, or the audit event.

## Cancel a Nomination

The nominee or any administrator access manager of the location may cancel a pending, unexpired nomination:

```http
POST /e-prescription/access/epcs/requests/<id>/cancel
```

`200 OK` returns the request with `status: cancelled`, `resolvedBy`, and `resolvedAt`.

* `403` means the caller has no Acting User or is neither the nominee nor an administrator of the location.
* `409` means another call changed the request while this call ran.
* `422` means the request is missing, resolved, or expired.

## List Nominations

```http
GET /e-prescription/access/epcs/requests
GET /e-prescription/access/epcs/requests?location=<Location id>&status=pending
```

`200 OK` returns a searchset `Bundle` with two kinds of requests: those at the locations the Acting User administers, and those that nominate the Acting User.
The optional `location` and `status` filters narrow that list.
Supported statuses are `pending`, `approved`, `cancelled`, and `expired`.
A caller with no matching requests receives an empty `Bundle`.
A call without an Acting User returns `403`.

## Expiration

The `expire-access-requests` scheduler job runs hourly by default and marks overdue pending requests `expired`.
Acceptance and cancellation reject an overdue request even if the job has not marked it yet.
An expired nomination does not block a new nomination for the same user and location.

## Audit Trail

Nomination, acceptance, and cancellation write `AuditEvent` records with these `type.code` values:

* `epcs-access-request-creation`
* `epcs-access-request-approval`
* `epcs-access-request-cancellation`

The module commits each successful change and its audit event in one transaction.
An acceptance event records `secondPersonApprovalWaiver: no-active-approver`, because the nominee accepts without a second approver.

A rejected call writes an event with the reason in `failureReason`.
A call without an Acting User is audited even when its parameters are invalid.
Otherwise, a `400` for invalid parameters writes no event.
Listing and scheduled expiration write no audit events.
