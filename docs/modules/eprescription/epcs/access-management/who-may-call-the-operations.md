---
description: Configure AccessPolicy resources that control who may call the EPCS access management operations in the Aidbox ePrescription module.
---

# Who May Call the Operations

Every call needs an **Acting User**, the Aidbox `User` your EHR authenticated.
A request authenticated with a `Client` credential alone has no Acting User, and the module refuses it with `403`.

{% hint style="danger" %}
The module does not check whether the Acting User holds any EPCS permission before it runs `bootstrap-admin`.
Any authenticated user your Aidbox lets through can make themselves, or anyone else, the administrator of a location that has none.
Your [AccessPolicy](../../../../access-control/authorization/access-policies.md) is the only thing that decides who may call it.
{% endhint %}

Write a policy for each operation and grant it to the smallest group that needs it:

* `POST /e-prescription/access/epcs/bootstrap-admin`: the operators who set up locations during deployment. Do not expose it to EHR users or to an administration UI.
* `POST /e-prescription/access/epcs/requests`: the users who administer EPCS access.
* `GET /e-prescription/access/epcs/requests` and the `approve` and `cancel` operations: administrators and nominees, with the role checks described in [Approver Nominations](approver-nominations.md).
* `GET /e-prescription/access/epcs/permissions`: the users who administer EPCS access.
* `GET /e-prescription/access/epcs/permissions/mine`: the users who work in the prescribing UI.

Also deny clients direct read and write access to `EPrescriptionAccessPermission` and `EPrescriptionAccessRequest`.

A policy that keys on a field of your `User` resource looks like this.
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
