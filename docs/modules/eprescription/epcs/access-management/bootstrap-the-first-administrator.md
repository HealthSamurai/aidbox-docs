---
description: Grant the first EPCS administrator access manager of a location in the Aidbox ePrescription module.
---

# Bootstrap the First Administrator

Use this operation during deployment to appoint a location's first **administrator access manager**.
It grants the `epcs-access-admin` **access permission** without a second person's approval.
See [EPCS Access Management](README.md) for the roles.

## Before You Start

* Create the target Aidbox `User` and `Location` records.
* Confirm that the location has no **administrator access manager**.
* Restrict the operation to deployment operators with an AccessPolicy. Follow [Who May Call the Operations](who-may-call-the-operations.md), which also defines the **acting user** required for the call.

## Grant the Permission

Call the operation as the deployment operator, using the target user's and location's ids:

```http
POST /e-prescription/access/epcs/bootstrap-admin
Content-Type: application/json

{
  "userId": "<Aidbox User id of the first administrator>",
  "locationId": "<Location id>"
}
```

Both ids must be:

* Present and nonblank.
* Free of leading or trailing whitespace.

## Verify the Grant

Check for `201 Created` and an **access permission** with the requested user and location:

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

As the new **administrator access manager**, call [`GET /e-prescription/access/epcs/permissions/mine`](list-permissions.md#list-your-own-permissions) and confirm that the grant appears.

## Handle Errors

Errors return an `OperationOutcome`:

* `400 Bad Request`: check that the body is a JSON object and both ids meet the requirements above.
* `403 Forbidden`: authenticate with an **acting user** allowed by your AccessPolicy.
* `422 Unprocessable Entity`: check that both target records exist and the location has no **administrator access manager**.

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

If several bootstrap calls for one location run at the same time:

* One call grants the **access permission**.
* The others receive `422` because the location now has an **administrator access manager**.

**LIMITATIONS:** The module has no operation to revoke the grant. Do not delete the permission directly to retry setup; direct writes bypass the module's checks and audit events.

## Audit Trail

To trace a setup attempt, look for an `AuditEvent` with `type.code` `epcs-access-admin-bootstrap`:

* A granted call has `outcome` `0` and references the created **access permission** and `Location`.
* A rejected call has `outcome` `4` and a reason in `failureReason`.
* A parameter-validation `400` from a call with an **acting user** writes no event.

The event names the **acting user** as the requesting agent and the target user as a second agent.
It records `secondPersonApprovalSkipReason` = `deployment-setup` as the reason no second person approved the grant.

Common `failureReason` values are:

* `acting-user-required`
* `user-not-found`
* `location-not-found`
* `location-already-has-access-admin`

Without an **acting user**, the event records the requesting agent as `unknown` and omits values from the unvalidated request body.
