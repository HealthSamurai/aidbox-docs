---
description: Request, approve, cancel, and list grants and revocations of EPCS access manager roles in the Aidbox ePrescription module.
---

# Access-Change Requests

An administrator requests a change of who manages EPCS access at a location, and a second person approves it.
Each request grants or revokes one role for one Aidbox `User` at one `Location`.

## Request a Change

The module allows a request when:

* The caller is an administrator at the location.
* A grant names a user who does not hold the role there, and a revocation names one who does.
* No pending, unexpired request exists for that user, role, and location, whether it grants or revokes the role.
* An `epcs-access-admin` grant names an existing `User`.
* An `epcs-access-approver` grant names an eligible user, as described below.

An administrator may request changes to their own roles, including the removal of the last administrator at the location.
The one exception is a self-nomination: an administrator cannot request the approver role for themselves while the location has no eligible approver, because they could then accept it themselves.

```http
POST /e-prescription/access/epcs/requests
Content-Type: application/json

{
  "action": "grant",
  "permission": "epcs-access-approver",
  "userId": "<target's Aidbox User id>",
  "locationId": "<Location id>"
}
```

* `action`: `grant` or `revoke`.
* `permission`: `epcs-access-admin` or `epcs-access-approver`.

`201 Created` returns the request with `status: pending`.

```json
{
  "resourceType": "EPrescriptionAccessRequest",
  "id": "72bfe69d-0bf7-4691-8b0a-d40ad8624d51",
  "action": "grant",
  "permission": "epcs-access-approver",
  "user": { "reference": "User/nominee" },
  "location": { "reference": "Location/clinic-1" },
  "status": "pending",
  "requestedBy": { "reference": "User/first-admin" },
  "requestedAt": "2026-09-29T10:00:00Z",
  "expiresAt": "2026-10-01T10:00:00Z"
}
```

Use the request's `id` to approve or cancel it.

* `400` means a required field is missing or invalid.
* `403` means the request has no [acting user](configure-access-policies.md#acting-user), or the caller does not administer the location.
* `409` means a pending, unexpired request exists for the same user, role, and location.
* `422` means the caller nominated themselves without an eligible approver, the user already holds the granted role or lacks the revoked one, the user does not exist, or the nominee is not eligible.

### Eligibility

A user is eligible for the approver role, and eligible to approve as one, when their EHR records meet these rules:

* `User.fhirUser` references a `Practitioner` whose `active` is not `false`.
* That `Practitioner` has at least one `PractitionerRole` with all of these:
  * A link to the location.
  * `active` set to `true`.
  * `period.start` in the past and `period.end` in the future. Both dates are required.
  * A DEA identifier in the format below.

The DEA identifier must have this shape:

```json
{
  "type": {
    "coding": [
      { "system": "http://terminology.hl7.org/CodeSystem/v2-0203", "code": "DEA" }
    ]
  },
  "value": "AB1234563"
}
```

The module checks eligibility when you request an approver grant and again on approval.
It keeps the approver role of a user whose records stop meeting the rules; that user only loses the ability to approve until the records qualify again.

## Approve a Request

```http
POST /e-prescription/access/epcs/requests/<id>/approve
Content-Type: application/json

{
  "twoFactorCode": "<code>"
}
```

Three kinds of caller may approve a pending, unexpired request.

### An EPCS approver

Any eligible approver at the location approves a request with their two-factor authentication code, sent as a nonblank string in `twoFactorCode`.
The approver must be neither the requester nor the target of the request.
For an approver grant, the target must still be eligible.

### The first approver

While no approver at the location is eligible, the nominee of an approver grant accepts it themselves with their two-factor code, unless they requested it.
Approver roles held by ineligible users stay in place and do not block this.
When several nominations are pending, the first nominee to accept becomes the approver; the other nominations stay pending, and the new approver may approve them.

### An administrator removing the sole approver

If the target of a pending approver revocation is now the only approver at the location, an administrator at the location may approve it alone, without `twoFactorCode`.
See [Remove the Sole Approver](#remove-the-sole-approver).

### Result

`200 OK` returns the request with `status: approved`, `resolvedBy`, and `resolvedAt`.
A grant creates the role, and a revocation removes it.

* `400` means `twoFactorCode` is not a string.
* `403` means the request has no [acting user](configure-access-policies.md#acting-user), or the caller may not approve it: the requester (except an administrator removing the sole approver), the target outside the first-approver case, a user who is not an approver at the location, or an approver who is not eligible.
* `409` means another call changed the request or the location's roles at the same time. Reload the request and retry.
* `422` means the request does not exist, is resolved or expired, the code is blank, the user already holds the granted role or lacks the revoked one, or the target of an approver grant is not eligible.

## Remove the Sole Approver

When only one user holds the approver role at a location, eligible or not, an administrator can remove it at once, without a second person's approval or a two-factor code.
Request the revocation as usual:

```http
POST /e-prescription/access/epcs/requests
Content-Type: application/json

{
  "action": "revoke",
  "permission": "epcs-access-approver",
  "userId": "<approver's Aidbox User id>",
  "locationId": "<Location id>"
}
```

`201 Created` returns the request already `approved`, and the role is gone.
When two or more users hold the approver role, the call creates a pending request as usual, even if only one of them is eligible.

To appoint the next approver, nominate one; the nominee accepts as the [first approver](#the-first-approver).

## Cancel a Request

The target or any access manager at the location may cancel a pending, unexpired request.
The target of a revocation cannot cancel it, even as an access manager, unless they requested it themselves.

```http
POST /e-prescription/access/epcs/requests/<id>/cancel
```

`200 OK` returns the request with `status: cancelled`, `resolvedBy`, and `resolvedAt`.

* `403` means the request has no [acting user](configure-access-policies.md#acting-user), or the caller is neither the target nor an access manager at the location, or is the target of another person's revocation.
* `409` means another call changed the request or your role at the location at the same time. Reload the request and retry.
* `422` means the request does not exist, or is resolved or expired.

## List Requests

```http
GET /e-prescription/access/epcs/requests
GET /e-prescription/access/epcs/requests?location=<Location id>&status=pending
```

`200 OK` returns a searchset `Bundle` with:

* Requests at locations where the [acting user](configure-access-policies.md#acting-user) holds either role.
* Requests naming the [acting user](configure-access-policies.md#acting-user) as target.

Optional filters:

* `location`: a `Location` id.
* `status`: `pending`, `approved`, `cancelled`, or `expired`.

Without an [acting user](configure-access-policies.md#acting-user), the operation returns `403`.

## Expiration

A request expires 48 hours after `requestedAt`, at the time in `expiresAt`.

After a request passes its `expiresAt` time:

* Approval and cancellation return `422`.
* You can request the same change again.

Use `expiresAt` to determine whether a request has expired, even if its `status` still shows `pending`.
