---
description: Change who holds an EPCS access manager role or the EPCS prescribing permission at a location in the Aidbox ePrescription module.
---

# Access-Change Requests

An **access-change request** grants or revokes one [access manager](README.md) role or the [EPCS prescribing permission](README.md) for one Aidbox `User` at one `Location`.
An administrator at the location creates it, and the change takes effect when the request is approved.
An administrator completes an [immediate revocation](#immediate-revocation) without a second person's approval.
The user whose role or permission a request changes is its **target**.
A request that grants a role or permission is a **nomination**, and its target is the **nominee**.

An **EPCS approver** approves requests with their two-factor code.
They can approve only while they are [DEA-qualified](#dea-qualification) at the location.

## Request a Change

The caller must be an administrator at the location.

```http
POST /e-prescription/access/epcs/requests
Content-Type: application/json

{
  "action": "grant",
  "permissionCode": "epcs-access-approver",
  "userId": "<target's Aidbox User id>",
  "locationId": "<Location id>"
}
```

* `action`: `grant` or `revoke`.
* `permissionCode`, one of:
  * `epcs-access-admin` for the administrator role
  * `epcs-access-approver` for the approver role
  * `epcs-prescribing` for the EPCS prescribing permission

<details>

<summary>Response</summary>

`201 Created` returns the access-change request with `status: pending`, or `status: approved` for an [immediate revocation](#immediate-revocation).
Use the `id` of a pending request to approve or cancel it.

```json
{
  "resourceType": "EPrescriptionAccessRequest",
  "id": "72bfe69d-0bf7-4691-8b0a-d40ad8624d51",
  "action": "grant",
  "permissionCode": "epcs-access-approver",
  "user": { "reference": "User/nominee" },
  "location": { "reference": "Location/clinic-1" },
  "status": "pending",
  "requestedBy": { "reference": "User/first-admin" },
  "requestedAt": "2026-09-29T10:00:00Z",
  "expiresAt": "2026-10-01T10:00:00Z"
}
```

</details>

An administrator may request changes to their own roles, including removing the last administrator at the location.
To appoint a new administrator after that, use [Bootstrap the First Administrator](bootstrap-the-first-administrator.md).

<details>

<summary>Error Responses</summary>

* `400`: a required field is missing or invalid.
* `403`: the request has no [acting user](configure-access-policies.md#acting-user), or the caller is not an administrator at the location.
* `409`, in either of these cases:
  * A pending, unexpired request already exists for the same user, permission, and location, whether it grants or revokes the permission.
  * During an [immediate revocation](#immediate-revocation), another call changed the location's roles or the revoked permission at the same time. Retry the call.
* `422`, in any of these cases:
  * A grant names a user who already holds the permission, or a revocation names a user who does not.
  * An administrator nomination names a `User` that does not exist.
  * An approver or prescribing nomination names a user who is not DEA-qualified.
  * The caller nominates themselves as approver while the location has no DEA-qualified approver. Otherwise they could [accept the nomination themselves](#first-approver).

</details>

### Prescribing Nomination

A request that grants `epcs-prescribing` is a **prescribing nomination**.
Its nominee must be [DEA-qualified](#dea-qualification) at the location.
An administrator may nominate themselves.

Any approver at the location other than the requester can approve it through [second-person approval](#second-person-approval), including the nominee.

### Prescribing Revocation

A request that revokes `epcs-prescribing` is a **prescribing revocation**.
Its target does not need to be DEA-qualified.
An administrator may revoke their own prescribing permission.

When a practitioner must lose the permission, for example after a lost authentication factor or an expired DEA registration, an administrator requests the revocation.
The module does not detect these events.

Any approver at the location other than the requester can approve it through [second-person approval](#second-person-approval), including the target.
At a location where no user holds the approver role, the revocation is an [immediate revocation](#immediate-revocation) and completes when it is created.

### Immediate Revocation

An **immediate revocation** is a revocation that an administrator completes without a second person's approval or a two-factor code.
A revocation is immediate in either of these cases:

* It revokes the approver role while only one user holds that role at the location, DEA-qualified or not.
* It revokes `epcs-prescribing` (the administrator's own included) while no user holds the approver role at the location.

When a case holds as the administrator creates the request, the module removes the role or permission and returns the request with `status: approved`.
A pending revocation that matches a case later needs [Administrator Approval](#administrator-approval).

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

A pending, unexpired request can be approved in one of the three ways below.

### First Approver

A location with no DEA-qualified approver cannot use [second-person approval](#second-person-approval).
There, the nominee of an approver nomination accepts it with their own two-factor code.

### Second-Person Approval

A DEA-qualified approver at the location approves the request with their two-factor code.
The approver cannot be the requester.
They cannot be the target either, unless the request is a [prescribing nomination](#prescribing-nomination) or a [prescribing revocation](#prescribing-revocation).

### Administrator Approval

After the location's approvers change, a pending revocation can become an [immediate revocation](#immediate-revocation):

* It revokes the approver role, and its target is now the only user who holds that role at the location.
* It revokes `epcs-prescribing`, and no user holds the approver role at the location.

Any administrator at the location can then approve it without `twoFactorCode`, including the administrator who requested it.

<details>

<summary>Result</summary>

`200 OK` returns the access-change request with `status: approved`, `resolvedBy`, and `resolvedAt`.

Errors:

* `400`: `twoFactorCode` is not a string.
* `403`: the request has no [acting user](configure-access-policies.md#acting-user), or the caller may not approve this request in any of the three ways.
* `409`: another call changed the request or the location's roles at the same time. Reload the request and retry.
* `422`: the request does not exist, is resolved or expired, the two-factor code is missing, the user already holds the granted permission or lacks the revoked one, or the nominee of an approver or prescribing nomination is not DEA-qualified.

</details>

## Cancel an Access-Change Request

These users can cancel a pending, unexpired request:

* Any access manager at the location.
* The target of a request that changes their access manager role, such as a nominee who declines an administrator or approver nomination.

The target of a revocation that someone else requested cannot cancel it.

```http
POST /e-prescription/access/epcs/requests/<id>/cancel
```

`200 OK` returns the access-change request with `status: cancelled`, `resolvedBy`, and `resolvedAt`.

<details>

<summary>Error Responses</summary>

* `403`, in any of these cases:
  * The request has no [acting user](configure-access-policies.md#acting-user).
  * The caller is neither an access manager at the location nor the target of a request that changes their access manager role.
  * The caller is the target of a revocation that someone else requested.
* `409`: another call changed the request or the caller's role at the location at the same time. Reload the request and retry.
* `422`: the request does not exist, or is resolved or expired.

</details>

## List Access-Change Requests

```http
GET /e-prescription/access/epcs/requests
GET /e-prescription/access/epcs/requests?location=<Location id>&status=pending
```

`200 OK` returns a searchset `Bundle` with:

* Requests at locations where the [acting user](configure-access-policies.md#acting-user) is an access manager.
* Requests that name the acting user as the target and change an access manager role.

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
