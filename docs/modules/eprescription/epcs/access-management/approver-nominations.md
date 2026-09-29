---
description: Nominate, accept, cancel, and list EPCS approver nominations in the Aidbox ePrescription module.
---

# Approver Nominations

An administrator nominates the first approver of a location.
The **nominee** is the Aidbox `User` who becomes the location's EPCS approver when they accept the nomination.

## Nominate the First Approver

The module allows a nomination when:

* The caller is an administrator at the location.
* The nominee is a different user from the caller.
* The location has no approver.
* No pending, unexpired nomination exists for that user at that location.

The nominee's EHR records must also meet these rules:

* `User.fhirUser` references a `Practitioner` whose `active` is not `false`.
* That `Practitioner` has at least one `PractitionerRole` with all of these:
  * A link to the nomination location.
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

`201 Created` returns the nomination with `status: pending`.

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

Use the nomination's `id` to accept or cancel it.

* `400` means a required field is missing or invalid. Use the `action` and `permission` values shown above to nominate an EPCS approver.
* `403` means the request has no [acting user](configure-access-policies.md), or the caller does not administer the location.
* `409` means a pending, unexpired nomination exists for the same user and location.
* `422` means the caller nominated themselves, the location already has an approver, or the nominee does not exist or does not meet the rules above.

You may nominate several people for one location.
The first nominee to accept becomes its approver, and the others can no longer accept.

## Accept a Nomination

Only the nominee may accept their nomination.
Send their two-factor authentication code as a nonblank string in `twoFactorCode`.

```http
POST /e-prescription/access/epcs/requests/<id>/approve
Content-Type: application/json

{
  "twoFactorCode": "<code>"
}
```

On acceptance, the module checks again that:

* The request is still pending and unexpired.
* The location still has no approver.
* The nominee still meets the rules above.

`200 OK` returns the nomination with `status: approved`, `resolvedBy`, and `resolvedAt`.
The nominee becomes the location's EPCS approver.

* `400` means `twoFactorCode` is missing or is not a string.
* `403` means the request has no [acting user](configure-access-policies.md), or the caller is not the nominee.
* `409` means another call changed the request or appointed an approver at the same time.
* `422` means the request does not exist, is resolved or expired, the code is blank, the location already has an approver, or the nominee no longer meets the rules.

## Cancel a Nomination

The nominee or an administrator of the location may cancel a pending, unexpired nomination.

```http
POST /e-prescription/access/epcs/requests/<id>/cancel
```

`200 OK` returns the nomination with `status: cancelled`, `resolvedBy`, and `resolvedAt`.

* `403` means the request has no [acting user](configure-access-policies.md), or the caller is neither the nominee nor an administrator of the location.
* `409` means another call changed the request at the same time.
* `422` means the request does not exist, or is resolved or expired.

## List Nominations

```http
GET /e-prescription/access/epcs/requests
GET /e-prescription/access/epcs/requests?location=<Location id>&status=pending
```

`200 OK` returns a searchset `Bundle` with:

* Nominations at locations the [acting user](configure-access-policies.md) administers.
* Nominations of the [acting user](configure-access-policies.md).

Optional filters:

* `location`: a `Location` id.
* `status`: `pending`, `approved`, `cancelled`, or `expired`.

Without an [acting user](configure-access-policies.md), the operation returns `403`.

## Expiration

The nomination expires 48 hours after `requestedAt`, at the time in `expiresAt`.

After a nomination passes its `expiresAt` time:

* Acceptance and cancellation return `422`.
* You can nominate the same user at the same location again.

Use `expiresAt` to determine whether a nomination has expired, even if its `status` still shows `pending`.
