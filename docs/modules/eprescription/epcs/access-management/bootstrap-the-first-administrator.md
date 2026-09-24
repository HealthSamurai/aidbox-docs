---
description: Grant the first EPCS administrator access manager of a location in the Aidbox ePrescription module.
---

# Bootstrap the First Administrator

Call this operation once per location during deployment.
It grants `epcs-access-admin` to the given user without a second person's approval.
The module records the Acting User as the operator who performed the setup.
The module lets any Acting User call this operation, so restrict it with an AccessPolicy as described in [Who May Call the Operations](who-may-call-the-operations.md).

```http
POST /e-prescription/access/epcs/bootstrap-admin
Content-Type: application/json

{
  "userId": "<Aidbox User id of the first administrator>",
  "locationId": "<Location id>"
}
```

Both ids are required, and neither may be blank or have leading or trailing whitespace.

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

The operation succeeds whenever the location has no administrator access manager.
The module cannot revoke a permission, so this happens again only if someone deletes the location's administrator permission directly.
Earlier grants stay in the audit trail and do not block the new one.

If several bootstrap calls for one location run at the same time, only one grants an administrator.
The others receive `422`.

## Audit Trail

Each bootstrap call, granted or rejected, writes an `AuditEvent` with `type.code` `epcs-access-admin-bootstrap`.
A granted call has `outcome` `0`, and a rejected one has `4`.

The event names the Acting User as the requesting agent and the target user as a second agent.
A granted event references the created permission and the `Location`.
It records `secondPersonApprovalWaiver` = `deployment-setup` as the reason no second person approved the grant.
The module commits the permission and its event in one transaction, so every grant has its event.

A rejected event records the reason under `failureReason`: `acting-user-required`, `user-not-found`, `location-not-found`, or `location-already-has-access-admin`.
A call without an Acting User is audited with the requesting agent as `unknown`.
That event holds no value from the request body, because the module has not validated the body yet.
A `400` for a call that has an Acting User writes no event.
