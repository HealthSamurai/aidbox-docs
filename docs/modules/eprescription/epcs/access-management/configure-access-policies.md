---
description: Configure AccessPolicy resources that control who may call the EPCS access management operations in the Aidbox ePrescription module.
---

# Configure Access Policies

Every call needs an **acting user**: the Aidbox `User` authenticated for the request.
A request made with only a `Client` credential has no [acting user](configure-access-policies.md), and the module returns `403`.

{% hint style="danger" %}
`bootstrap-admin` does not require the caller to be an access manager.
At a location with no administrator, any [acting user](configure-access-policies.md) allowed by your AccessPolicies can grant that role to themselves or to another user.
Restrict this operation to deployment operators. See the [AccessPolicy documentation](../../../../access-control/authorization/access-policies.md) for policy configuration.
Do not expose it to EHR users or to an administration UI.
{% endhint %}

Write a policy for each operation and grant it to the smallest group that needs it:

* `POST /e-prescription/access/epcs/bootstrap-admin`: the operators who set up locations during deployment.
* `GET /e-prescription/access/epcs/permissions`: administrators.
* `GET /e-prescription/access/epcs/permissions/mine`: the users who work in the prescribing UI.
* `GET /e-prescription/access/epcs/requests`: administrators and nominees.
* `POST /e-prescription/access/epcs/requests`: administrators.
* `POST /e-prescription/access/epcs/requests/<id>/approve`: nominees.
* `POST /e-prescription/access/epcs/requests/<id>/cancel`: administrators and nominees.

The module checks each caller's role as described in [Approver Nominations](approver-nominations.md).

This example policy matches a field of your `User` resource.
Replace `data.role` and its value with whatever your EHR stores on its users.

```yaml
resourceType: AccessPolicy
id: erx-epcs-bootstrap-admin
engine: matcho
matcho:
  uri: /e-prescription/access/epcs/bootstrap-admin
  request-method: post
  user:
    data:
      role: deployment-operator
```
