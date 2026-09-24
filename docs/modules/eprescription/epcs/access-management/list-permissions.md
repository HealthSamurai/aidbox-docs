---
description: List your own EPCS access permissions and the permissions at the locations you administer in the Aidbox ePrescription module.
---

# List Permissions

## List Your Own Permissions

```http
GET /e-prescription/access/epcs/permissions/mine
```

Returns `200` with a searchset `Bundle` of the Acting User's `EPrescriptionAccessPermission` records at every location.
A user with no permissions receives an empty `Bundle`.

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

Returns `200` with a searchset `Bundle` of every permission, in both roles, at each location where the Acting User holds `epcs-access-admin`.
The optional `location` query parameter narrows the result to one of those locations.
A filter on a location the user does not administer returns an empty `Bundle`, and holding `epcs-access-approver` there does not count as administering it.
A user who administers no location receives an empty `Bundle` as well.

Both listings return `403` when the call has no Acting User.
