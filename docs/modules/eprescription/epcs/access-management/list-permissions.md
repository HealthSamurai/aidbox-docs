---
description: List your own EPCS access permissions and the permissions at the locations you administer in the Aidbox ePrescription module.
---

# List Permissions

Access permissions come from [bootstrapping the first administrator](bootstrap-the-first-administrator.md) and from accepted [approver nominations](approver-nominations.md).
Without an [acting user](configure-access-policies.md#acting-user), both listings return `403`.

## List Your Own Permissions

```http
GET /e-prescription/access/epcs/permissions/mine
```

`200 OK` returns a searchset `Bundle` with the [acting user](configure-access-policies.md#acting-user)'s access permissions at every location.

## List Permissions at the Locations You Administer

```http
GET /e-prescription/access/epcs/permissions
GET /e-prescription/access/epcs/permissions?location=<Location id>
```

Example `200 OK` response for a location the [acting user](configure-access-policies.md#acting-user) administers:

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
        "grantedAt": "2026-09-29T09:00:00Z"
      }
    }
  ]
}
```

The optional `location` parameter limits the result to one location.

Administrators can list other users' permissions at their locations.
