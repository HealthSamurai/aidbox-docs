---
description: List your own EPCS access permissions and the permissions at the locations you administer in the Aidbox ePrescription module.
---

# List Permissions

An **access permission** grants an Aidbox `User` an **access manager** role at one location.
See [EPCS Access Management](README.md) for the roles and [Who May Call the Operations](who-may-call-the-operations.md) for the **acting user** required by these calls.
Permissions come from [bootstrapping the first administrator](bootstrap-the-first-administrator.md) and from accepted [approver nominations](approver-nominations.md).

## List Your Own Permissions

```http
GET /e-prescription/access/epcs/permissions/mine
```

The operation returns `200` with a searchset `Bundle`:

* It contains the **acting user**'s `EPrescriptionAccessPermission` records at every location.
* If the user has no **access permissions**, it is empty.

```json
{
  "resourceType": "Bundle",
  "type": "searchset",
  "total": 1,
  "entry": [
    {
      "resource": {
        "resourceType": "EPrescriptionAccessPermission",
        "id": "9f1c1a2e-4d5b-4b1a-9c1e-2f6d0e7a8b90",
        "permission": "epcs-access-admin",
        "user": { "reference": "User/first-admin" },
        "location": { "reference": "Location/clinic-1" },
        "grantedAt": "2026-09-22T10:15:00Z"
      }
    }
  ]
}
```

## List Permissions at the Locations You Administer

```http
GET /e-prescription/access/epcs/permissions
GET /e-prescription/access/epcs/permissions?location=<Location id>
```

The operation returns `200` with a searchset `Bundle`:

* It contains **access permissions** for both roles at locations where the **acting user** holds `epcs-access-admin`.
* With the optional `location` parameter, it includes only that location's permissions.
* If the user administers no matching location, it is empty.

The `epcs-access-approver` permission alone does not allow the user to list other users' **access permissions**.

## Errors and Audit Trail

Without an **acting user**, both listings return `403`.
Neither listing writes an audit event.
