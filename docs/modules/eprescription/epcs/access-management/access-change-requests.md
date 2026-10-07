---
description: Request, approve, cancel, and list grants and revocations of EPCS access manager roles in the Aidbox ePrescription module.
---

# Access-Change Requests

An **access-change request** grants or revokes one [access manager](README.md) role for one Aidbox `User` at one `Location`.
An administrator at the location creates it, and the change takes effect only after the request is approved.
A request that grants a role is a **nomination**, and the user it names is the **nominee**.

An **EPCS approver** approves requests with their two-factor code.
They can approve only while they are [DEA-qualified](#dea-qualification) at the location.

## Request a Change

The caller must be an administrator at the location.

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
* `permission`: `epcs-access-admin` for the administrator role, or `epcs-access-approver` for the approver role.

`201 Created` returns the access-change request with `status: pending`.
Use its `id` to approve or cancel it.

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

An administrator may request changes to their own roles, including removing the last administrator at the location.
To appoint a new administrator after that, use [Bootstrap the First Administrator](bootstrap-the-first-administrator.md).

Errors:

* `400`: a required field is missing or invalid.
* `403`: the request has no [acting user](configure-access-policies.md#acting-user), or the caller is not an administrator at the location.
* `409`: a pending, unexpired request already exists for the same user, role, and location, whether it grants or revokes the role.
* `422`, in any of these cases:
  * A grant names a user who already holds the role, or a revocation names a user who does not.
  * An administrator nomination names a `User` that does not exist.
  * An approver nomination names a user who is not DEA-qualified.
  * The caller nominates themselves as approver while the location has no DEA-qualified approver. Otherwise they could [accept the nomination themselves](#first-approver).

### DEA Qualification

A user is DEA-qualified at a location when:

* `User.fhirUser` references a `Practitioner` whose `active` is not `false`.
* That `Practitioner` has at least one `PractitionerRole` with all of these:
  * A reference to the location.
  * `active` set to `true`.
  * `period.start` in the past and `period.end` in the future. Both dates are required.
  * An `identifier` with the type code `DEA` from `http://terminology.hl7.org/CodeSystem/v2-0203` and a DEA number in `value`, such as `AB1234563`.

## Approve an Access-Change Request

```http
POST /e-prescription/access/epcs/requests/<id>/approve
Content-Type: application/json

{
  "twoFactorCode": "<code>"
}
```

A pending, unexpired request can be approved in one of three ways.

### Second-Person Approval

A DEA-qualified approver at the location approves the request with their two-factor code.
The approver cannot be the requester or the target of the request.
For an approver nomination, the nominee must still be DEA-qualified.

### First Approver

A location with no DEA-qualified approver cannot use second-person approval.
There, the nominee of an approver nomination accepts it with their own two-factor code, unless they requested it themselves.

If several approver nominations are pending, the first nominee to accept becomes the approver.
The other nominations stay pending, and the new approver can approve them.

### Sole Approver Removal

If only one user at the location holds the approver role, an administrator can remove it without a second person or a two-factor code.
See [Remove the Sole Approver](#remove-the-sole-approver).

### Result

`200 OK` returns the access-change request with `status: approved`, `resolvedBy`, and `resolvedAt`.
A grant creates the role, and a revocation removes it.

Errors:

* `400`: `twoFactorCode` is not a string.
* `403`: the request has no [acting user](configure-access-policies.md#acting-user), or the caller may not approve this request in any of the three ways.
* `409`: another call changed the request or the location's roles at the same time. Reload the request and retry.
* `422`: the request does not exist, is resolved or expired, the code is blank, the user already holds the granted role or lacks the revoked one, or the nominee of an approver nomination is not DEA-qualified.

## Remove the Sole Approver

When only one user holds the approver role at a location, DEA-qualified or not, an administrator can remove it at once.
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
A `409` means another call changed the location's roles at the same time. Retry the request.

When two or more users hold the approver role, the call creates a pending request as usual, even if only one of them is DEA-qualified.
If a pending revocation targets the approver who has since become the only one, any administrator at the location can approve it without `twoFactorCode`, including the administrator who requested it.

To appoint the next approver, nominate one. The nominee accepts as the [first approver](#first-approver).

## Cancel an Access-Change Request

The target or any access manager at the location can cancel a pending, unexpired request.
The target of a revocation can cancel it only if they requested it themselves.

```http
POST /e-prescription/access/epcs/requests/<id>/cancel
```

`200 OK` returns the access-change request with `status: cancelled`, `resolvedBy`, and `resolvedAt`.

Errors:

* `403`: the request has no [acting user](configure-access-policies.md#acting-user), the caller is neither the target nor an access manager at the location, or the caller is the target of a revocation someone else requested.
* `409`: another call changed the request or the caller's role at the location at the same time. Reload the request and retry.
* `422`: the request does not exist, or is resolved or expired.

## List Access-Change Requests

```http
GET /e-prescription/access/epcs/requests
GET /e-prescription/access/epcs/requests?location=<Location id>&status=pending
```

`200 OK` returns a searchset `Bundle` with:

* Requests at locations where the [acting user](configure-access-policies.md#acting-user) holds either role.
* Requests that name the acting user as the target.

Optional filters:

* `location`: a `Location` id.
* `status`: `pending`, `approved`, `cancelled`, or `expired`.

Without an acting user, the operation returns `403`.

## Expiration

A request expires 48 hours after `requestedAt`, at the time in `expiresAt`.
After that:

* Approval and cancellation return `422`.
* You can request the same change again.

The `status` of an expired request may still show `pending`, so check `expiresAt` instead.
