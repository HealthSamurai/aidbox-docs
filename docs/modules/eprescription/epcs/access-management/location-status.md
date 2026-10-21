---
description: Check whether a location's EPCS access managers meet the two-person rule in the Aidbox ePrescription module.
---

# Location Status

A location meets the module's two-person rule when it has an administrator and an approver who are different users.
The status operation reports whether a location meets it.
The module does not block controlled-substance prescribing at a location that fails the rule, so use the status to warn your users, for example on the prescribing screen.

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

* `compliant`: `true` when the location meets the rule.
* `issues`: every failed check, empty for a compliant location:
  * `no-approver`: no user holds the approver role at the location.
  * `no-administrator`: no user holds the administrator role at the location.
  * `same-person`: one user holds both roles, and nobody else holds either.

The module counts every user who holds a role, whether or not they are [DEA-qualified](access-change-requests.md#dea-qualification).

<details>

<summary>Error Responses</summary>

* `403`: the request has no [acting user](configure-access-policies.md#acting-user).
* `422`: the `Location` does not exist or was deleted.

</details>
