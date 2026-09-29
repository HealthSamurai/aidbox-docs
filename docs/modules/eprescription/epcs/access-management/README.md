---
description: Set up a location's EPCS administrator, nominate its first approver, and list access permissions in the Aidbox ePrescription module.
---

# EPCS Access Management

The DEA requires two people to set or change who may prescribe controlled substances: one enters the change, and another approves it with two-factor authentication.
The ePrescription module lets each location appoint its own **access managers** for this job:

* An **administrator** holds the `epcs-access-admin` permission. They nominate approvers and see every permission at the location.
* An **approver** holds the `epcs-access-approver` permission. They are the second person who approves access changes.

An **access permission** grants one of these roles to an Aidbox `User` at a `Location`, and the module stores it as an `EPrescriptionAccessPermission`.
A **nomination** asks to grant the approver role to a user, and the module stores it as an `EPrescriptionAccessRequest`.

The Aidbox App exposes the operations under `/e-prescription/access/epcs`:

* [Configure Access Policies](configure-access-policies.md): decide who may call each operation. Do this first.
* [Bootstrap the First Administrator](bootstrap-the-first-administrator.md): grant a location's first administrator during deployment.
* [Approver Nominations](approver-nominations.md): nominate the first approver, accept or cancel a nomination, and list nominations.
* [List Permissions](list-permissions.md): list your own permissions and those at the locations you administer.

Change `EPrescriptionAccessPermission` and `EPrescriptionAccessRequest` records only through these operations.
A direct write skips the module's checks and audit events.

The operations work whether or not controlled-substance prescribing is enabled, so you can set up access managers ahead of time.

{% hint style="warning" %}
The module can appoint only the first access managers of a location.
It cannot add a second approver, revoke a permission, or send access changes to an existing approver for approval.
{% endhint %}
