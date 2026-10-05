---
description: Grant the first EPCS administrator of a location in the Aidbox ePrescription module.
---

# Bootstrap the First Administrator

Use this operation to appoint an administrator at a location that has none:

* during deployment, for the location's first administrator
* after the location loses its last administrator

The appointment does not require a second person's approval.

## Before You Start

* Create the target Aidbox `User` and `Location` records.
* Confirm that the location has no administrator.
* Restrict the operation to deployment operators, as described in [Configure Access Policies](configure-access-policies.md).

## Appoint the Administrator

Call the operation as the deployment operator:

```http
POST /e-prescription/access/epcs/bootstrap-admin
Content-Type: application/json

{
  "userId": "<Aidbox User id of the first administrator>",
  "locationId": "<Location id>"
}
```

`201 Created` confirms the appointment and returns the administrator's access permission.
The administrator can verify their role with [List Your Own Permissions](list-permissions.md#list-your-own-permissions).

## Handle Errors

Errors return an `OperationOutcome`:

* `400 Bad Request`: invalid request body.
* `403 Forbidden`: the request has no [acting user](configure-access-policies.md#acting-user).
* `422 Unprocessable Entity`: the user or location does not exist, or the location already has an administrator.
