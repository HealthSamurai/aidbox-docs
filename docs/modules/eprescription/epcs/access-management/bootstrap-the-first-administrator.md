---
description: Grant the first EPCS administrator access manager of a location in the Aidbox ePrescription module.
---

# Bootstrap the First Administrator

Call the operation once per location after you create the App.
It grants `epcs-access-admin` to the given user without a second person's approval and records the Acting User as the person who performed the setup.

```http
POST /e-prescription/access/epcs/bootstrap-admin
Content-Type: application/json

{
  "userId": "<Aidbox User id of the first administrator>",
  "locationId": "<Location id>"
}
```

Both ids are required.
The module rejects a blank id and an id with leading or trailing whitespace.
It stores the id as given, so a padded id would point at a different resource than the one Aidbox reads.

## Responses

`201 Created` returns the new permission:

```json
{
  "resourceType": "EPrescriptionAccessPermission",
  "id": "9f1c1a2e-4d5b-4b1a-9c1e-2f6d0e7a8b90",
  "permission": "epcs-access-admin",
  "user": { "reference": "User/first-admin" },
  "location": { "reference": "Location/clinic-1" },
  "grantedAt": "2026-09-22T10:15:00Z"
}
```

Errors return an `OperationOutcome`:

* `400 Bad Request` when `userId` or `locationId` is missing, blank, or padded with whitespace, or when the body is not a JSON object.
* `403 Forbidden` when the call has no Acting User.
* `422 Unprocessable Entity` when the `User` or `Location` does not exist, or when the location already has an administrator access manager.

```json
{
  "resourceType": "OperationOutcome",
  "issue": [
    {
      "severity": "error",
      "code": "forbidden",
      "details": { "text": "EPCS access management requires the authenticated Aidbox user" }
    }
  ]
}
```

## Bootstrapping Again

A location can be bootstrapped whenever it has no administrator access manager.
If the only administrator of a location is removed, run the bootstrap again to appoint a new one.
Earlier grants stay in the audit trail and do not block the new one.

Concurrent bootstrap calls for one location grant a single administrator.
The other calls receive `422`.

## Audit Trail

Each bootstrap call, granted or rejected, writes an `AuditEvent` with `type.code` `epcs-access-admin-bootstrap`.
A granted call has `outcome` `0`, a rejected one `4`.

The event names the Acting User as the requesting agent and the target user as a second agent.
A granted event references the created permission and the `Location`, and records `secondPersonApprovalWaiver` = `deployment-setup` as the reason no second person approved the grant.
The module commits the permission and its event in one transaction, so a grant without its event cannot occur.

A rejected event records the reason under `failureReason`: `acting-user-required`, `user-not-found`, `location-not-found`, or `location-already-has-access-admin`.
A call without an Acting User is audited with the requesting agent as `unknown` and without any value from the request body, because the module has not validated the body yet.
A `400` from an authenticated caller writes no event.
The two listing operations write no events either.
