---
description: Nominate, accept, cancel, and list EPCS approver nominations in the Aidbox ePrescription module.
---

# Approver Nominations

An **administrator access manager** nominates the first **EPCS approver** of a location.
The **nominee** is the Aidbox `User` who will receive the `epcs-access-approver` **access permission**.
The **nomination** records the proposed grant; accepting it creates the **access permission**.
See [EPCS Access Management](README.md) for the roles and resources.
Each call requires an **acting user** as described in [Who May Call the Operations](who-may-call-the-operations.md).

## Nominate the First Approver

The module allows a **nomination** when:

* The caller is an **administrator access manager** at the location.
* The **nominee** is a different user from the caller.
* The location has no **EPCS approver**.
* No pending, unexpired **nomination** exists for that user at that location.

The module checks the **nominee**'s EHR records:

* `User.fhirUser` references a `Practitioner` with `active` != `false`.
* That `Practitioner` has at least one `PractitionerRole` with all of these:
  * A link to the nomination location.
  * `active` == `true`, required.
  * `period.start` < now < `period.end`, both dates required.
  * A DEA identifier in the correct format.

Before you nominate someone, verify outside the module that their DEA registration and state authorizations are current.

**LIMITATIONS:** The module checks only the DEA identifier's format, not the registration or state authorizations.

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
The request records the **nominee** in `user` and the **administrator access manager** in `requestedBy`.
Its `expiresAt` deadline is 48 hours after `requestedAt`.

* `400` means a required field is missing or invalid. The operation supports only `action: grant` and `permission: epcs-access-approver`.
* `403` means the caller has no **acting user** or does not administer the location.
* `409` means a pending, unexpired **nomination** exists for the same user and location.
* `422` means the caller nominated themselves, the location already has an **EPCS approver**, or the **nominee** is missing or ineligible.

You may nominate several people for one location:

* The first **nominee** to accept becomes its **EPCS approver**.
* After that acceptance, the module rejects acceptance by the others.

## Accept a Nomination

Only the **nominee** may accept their **nomination**.
Acceptance requires their two-factor authentication code.

**LIMITATIONS:** The module checks only that `twoFactorCode` is nonblank. It does not verify the code or store it in the permission, the request, or the audit event.

```http
POST /e-prescription/access/epcs/requests/<id>/approve
Content-Type: application/json

{
  "twoFactorCode": "<nonblank code>"
}
```

The module checks these conditions again on acceptance:

* The request is still pending and unexpired.
* The location still has no **EPCS approver**.
* The **nominee** still meets the eligibility rules above.

`200 OK` returns the request with `status: approved`, `resolvedBy`, and `resolvedAt`.
The module creates an `EPrescriptionAccessPermission` for the **nominee**, with a `request` reference to the **nomination**.
The **nominee** sees the new **access permission** in [`GET /e-prescription/access/epcs/permissions/mine`](list-permissions.md#list-your-own-permissions).

* `400` means `twoFactorCode` is missing or is not a string.
* `403` means the caller has no **acting user** or is not the **nominee**.
* `409` means another call changed the request or appointed an **EPCS approver** while this call ran.
* `422` means the request is missing, resolved, or expired; the code is blank; the location already has an **EPCS approver**; or the **nominee** is no longer eligible.

## Cancel a Nomination

Cancellation requires:

* A pending, unexpired **nomination**.
* A caller who is the **nominee** or an **administrator access manager** of the location.

```http
POST /e-prescription/access/epcs/requests/<id>/cancel
```

`200 OK` returns the request with `status: cancelled`, `resolvedBy`, and `resolvedAt`.

* `403` means the caller has no **acting user** or is neither the **nominee** nor an **administrator access manager** of the location.
* `409` means another call changed the request while this call ran.
* `422` means the request is missing, resolved, or expired.

## List Nominations

```http
GET /e-prescription/access/epcs/requests
GET /e-prescription/access/epcs/requests?location=<Location id>&status=pending
```

`200 OK` returns a searchset `Bundle` containing:

* Requests at locations the **acting user** administers.
* Requests that nominate the **acting user**.

Filters narrow that list:

* `location`: a `Location` id.
* `status`: `pending`, `approved`, `cancelled`, or `expired`.

If no requests match, the operation returns an empty `Bundle`.
Without an **acting user**, it returns `403`.

## Expiration

After a pending **nomination** passes its `expiresAt` deadline:

* Acceptance and cancellation return `422`, even while its stored status is still `pending`.
* A new **nomination** for the same user and location is allowed.
* The `expire-access-requests` scheduler job marks it `expired` on its next run, hourly by default.

## Audit Trail

Nomination, acceptance, and cancellation write `AuditEvent` records with these `type.code` values:

* `epcs-access-request-creation`
* `epcs-access-request-approval`
* `epcs-access-request-cancellation`

The module commits each successful change and its audit event in one transaction.
An acceptance event records `secondPersonApprovalWaiver: no-active-approver`, because the **nominee** accepts without a second **EPCS approver**.

For rejected calls:

* Without an **acting user**, the module writes an event even when the parameters are invalid.
* With an **acting user**, a `400` for invalid parameters writes no event.
* Other rejections write an event with the reason in `failureReason`.

Listing and scheduled expiration write no audit events.
