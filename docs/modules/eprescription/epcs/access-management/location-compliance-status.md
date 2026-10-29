---
description: Check whether a location has an EPCS administrator and an EPCS approver who are different users in the Aidbox ePrescription module.
---

# Location Compliance Status

A **DEA-compliant location** has an administrator and an approver who are different users.
The compliance status operation reports whether a location is DEA-compliant.
The module does not block controlled-substance prescribing at a location that is not DEA-compliant, so use the compliance status to warn your users, for example on the prescribing screen.

```http
GET /e-prescription/access/epcs/locations/<Location id>/status
```

Any [acting user](configure-access-policies.md#acting-user) can call it, including one who holds no EPCS role or permission.

`200 OK` returns the result:

```json
{
  "compliant": false,
  "issues": ["no-approver"]
}
```

* `compliant`: `true` for a DEA-compliant location.
* `issues`: every failed check, empty for a DEA-compliant location:
  * `no-approver`: no user holds the approver role at the location.
  * `no-administrator`: no user holds the administrator role at the location.
  * `same-person`: one user holds both roles, and nobody else holds either.

The module counts every user who holds a role, whether or not they are [DEA-qualified](access-change-requests.md#dea-qualification).

<details>

<summary>Error Responses</summary>

* `403`: the request has no [acting user](configure-access-policies.md#acting-user).
* `422`: the `Location` does not exist or was deleted.

</details>
