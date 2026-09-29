---
description: List your own EPCS access permissions and the permissions at the locations you administer in the Aidbox ePrescription module.
---

# List Permissions

Access permissions come from [bootstrapping the first administrator](bootstrap-the-first-administrator.md) and from accepted [approver nominations](approver-nominations.md).
Without an acting user, both listings return `403`.

## List Your Own Permissions

```http
GET /e-prescription/access/epcs/permissions/mine
```

`200 OK` returns a searchset `Bundle` with the acting user's access permissions at every location.

## List Permissions at the Locations You Administer

```http
GET /e-prescription/access/epcs/permissions
GET /e-prescription/access/epcs/permissions?location=<Location id>
```

`200 OK` returns a searchset `Bundle` with the permissions of both roles at the locations the acting user administers.
The optional `location` parameter limits the result to one location.

The approver role alone does not let a user list other users' permissions.
