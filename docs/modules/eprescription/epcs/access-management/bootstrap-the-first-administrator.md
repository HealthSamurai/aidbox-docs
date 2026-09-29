---
description: Grant the first EPCS administrator of a location in the Aidbox ePrescription module.
---

# Bootstrap the First Administrator

Use this operation during deployment to appoint a location's first administrator.
It grants the `epcs-access-admin` permission without a second person's approval.

## Before You Start

* Create the target Aidbox `User` and `Location` records.
* Confirm that the location has no administrator.
* Restrict the operation to deployment operators, as described in [Configure Access Policies](configure-access-policies.md).

## Grant the Permission

Call the operation as the deployment operator:

```http
POST /e-prescription/access/epcs/bootstrap-admin
Content-Type: application/json

{
  "userId": "<Aidbox User id of the first administrator>",
  "locationId": "<Location id>"
}
```

`201 Created` returns the new access permission:

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

## Handle Errors

Errors return an `OperationOutcome`:

* `400 Bad Request`: the body is not a JSON object, or `userId` or `locationId` is missing or invalid.
* `403 Forbidden`: the request has no acting user.
* `422 Unprocessable Entity`: the user or location does not exist, or the location already has an administrator.

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

{% hint style="warning" %}
The module has no operation to revoke the grant.
Do not delete the permission directly to retry setup: a direct write skips the module's checks and audit events.
{% endhint %}

## Audit Trail

The operation writes an `AuditEvent` with `type.code` `epcs-access-admin-bootstrap`:

* A granted call has `outcome` `0` and references the new access permission and the `Location`.
* A rejected call has `outcome` `4` and the reason in `failureReason`, for example `user-not-found` or `location-already-has-access-admin`.

The event lists the acting user and the target user as agents.
It records `secondPersonApprovalSkipReason` = `deployment-setup` to explain why no second person approved the grant.
