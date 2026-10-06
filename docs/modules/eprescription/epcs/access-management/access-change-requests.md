---
description: Request, approve, cancel, and list grants and revocations of EPCS access manager roles in the Aidbox ePrescription module.
---

# Access-Change Requests

An administrator requests a change of who manages EPCS access at a location, and a second person approves it.
Each **access-change request** grants or revokes one role for one Aidbox `User` at one `Location`.

## Request a Change

The module allows an access-change request when:

* The caller is an administrator at the location.
* A grant names a user who does not hold the role there, and a revocation names one who does.
* No pending, unexpired access-change request exists for that user, role, and location, whether it grants or revokes the role.
* An administrator nomination names an existing `User`.
* An approver nomination names a DEA-qualified user, as described below.

An administrator may request changes to their own roles, including the removal of the last administrator at the location.
The one exception is a self-nomination: an administrator cannot request the approver role for themselves while the location has no DEA-qualified approver, because they could then accept it themselves.

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

`201 Created` returns the access-change request with `status: pending`.

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

Use the access-change request's `id` to approve or cancel it.

* `400` means a required field is missing or invalid.
* `403` means the request has no [acting user](configure-access-policies.md#acting-user), or the caller does not administer the location.
* `409` means a pending, unexpired access-change request exists for the same user, role, and location.
* `422` means the caller nominated themselves without a DEA-qualified approver, the user already holds the granted role or lacks the revoked one, the user does not exist, or the nominee is not DEA-qualified.

### DEA Qualification

A user is DEA-qualified for the approver role, and DEA-qualified to approve as one, when their EHR records meet these rules:

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

The module checks DEA qualification when you request an approver nomination and again on approval.
It keeps the approver role of a user whose records stop meeting the rules; that user only loses the ability to approve until the records qualify again.

## Approve an Access-Change Request

```http
POST /e-prescription/access/epcs/requests/<id>/approve
Content-Type: application/json

{
  "twoFactorCode": "<code>"
}
```

Three kinds of caller may approve a pending, unexpired access-change request.

### An EPCS approver

Any DEA-qualified approver at the location approves an access-change request with their two-factor authentication code, sent in `twoFactorCode`.
The approver must be neither the requester nor the target of the access-change request.
For an approver nomination, the target must still be DEA-qualified.

### The first approver

While no approver at the location is DEA-qualified, the nominee of an approver nomination accepts it themselves with their two-factor code, unless they requested it.
Approver roles held by users who are not DEA-qualified stay in place and do not block this.
When several nominations are pending, the first nominee to accept becomes the approver; the other nominations stay pending, and the new approver may approve them.

### An administrator removing the sole approver

If the target of a pending approver revocation is now the only approver at the location, any administrator at the location, including the one who requested it, may approve it alone, without `twoFactorCode`.
See [Remove the Sole Approver](#remove-the-sole-approver).

### Result

`200 OK` returns the access-change request with `status: approved`, `resolvedBy`, and `resolvedAt`.
A grant creates the role, and a revocation removes it.

* `400` means `twoFactorCode` is not a string.
* `403` means the request has no [acting user](configure-access-policies.md#acting-user), or the caller is none of the three callers above.
* `409` means another call changed the access-change request or the location's roles at the same time. Reload the access-change request and retry.
* `422` means the access-change request does not exist, is resolved or expired, the code is blank, the user already holds the granted role or lacks the revoked one, or the target of an approver nomination is not DEA-qualified.

## Remove the Sole Approver

When only one user holds the approver role at a location, DEA-qualified or not, an administrator can remove it at once, without a second person's approval or a two-factor code.
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

`201 Created` returns the access-change request already `approved`, and the role is gone.
When two or more users hold the approver role, the call creates a pending access-change request as usual, even if only one of them is DEA-qualified.
A `409` means another call changed the location's roles at the same time; retry the request.

To appoint the next approver, nominate one; the nominee accepts as the [first approver](#the-first-approver).

## Cancel an Access-Change Request

The target or any access manager at the location may cancel a pending, unexpired access-change request.
The target of a revocation cannot cancel it, even as an access manager, unless they requested it themselves.

```http
POST /e-prescription/access/epcs/requests/<id>/cancel
```

`200 OK` returns the access-change request with `status: cancelled`, `resolvedBy`, and `resolvedAt`.

* `403` means the request has no [acting user](configure-access-policies.md#acting-user), or the caller is neither the target nor an access manager at the location, or is the target of another person's revocation.
* `409` means another call changed the access-change request or the caller's role at the location at the same time. Reload the access-change request and retry.
* `422` means the access-change request does not exist, or is resolved or expired.

## List Access-Change Requests

```http
GET /e-prescription/access/epcs/requests
GET /e-prescription/access/epcs/requests?location=<Location id>&status=pending
```

`200 OK` returns a searchset `Bundle` with:

* Access-change requests at locations where the [acting user](configure-access-policies.md#acting-user) holds either role.
* Access-change requests naming the [acting user](configure-access-policies.md#acting-user) as target.

Optional filters:

* `location`: a `Location` id.
* `status`: `pending`, `approved`, `cancelled`, or `expired`.

Without an [acting user](configure-access-policies.md#acting-user), the operation returns `403`.

## Expiration

An access-change request expires 48 hours after `requestedAt`, at the time in `expiresAt`.

After an access-change request passes its `expiresAt` time:

* Approval and cancellation return `422`.
* You can request the same change again.

Use `expiresAt` to determine whether an access-change request has expired, even if its `status` still shows `pending`.
