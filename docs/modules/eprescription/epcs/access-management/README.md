---
description: Set up a location's EPCS administrator, nominate its first approver, and list access permissions in the Aidbox ePrescription module.
---

# EPCS Access Management

The DEA requires two people to set or change who may prescribe controlled substances: one enters the change, and another approves it with two-factor authentication.
The ePrescription module lets each location appoint its own **access managers** for this job.
An access manager holds one of two roles at a location:

* An **administrator access manager** holds `epcs-access-admin`. They nominate approvers and see every permission at the location.
* An **EPCS approver** holds `epcs-access-approver`. They are the second person who approves access changes.

The module stores each role assignment as an `EPrescriptionAccessPermission` that links one Aidbox `User`, one role, and one `Location`.
A nomination is an `EPrescriptionAccessRequest`.

The Aidbox App exposes these operations:

* `POST /e-prescription/access/epcs/bootstrap-admin` grants the first administrator access manager of a location during deployment. See [Bootstrap the First Administrator](bootstrap-the-first-administrator.md).
* `POST /e-prescription/access/epcs/requests` nominates the first EPCS approver of a location, and `POST /e-prescription/access/epcs/requests/<id>/approve` lets the nominee accept. `GET /e-prescription/access/epcs/requests` lists nominations, and `POST /e-prescription/access/epcs/requests/<id>/cancel` cancels one. See [Approver Nominations](approver-nominations.md).
* `GET /e-prescription/access/epcs/permissions/mine` lists the caller's own permissions, and `GET /e-prescription/access/epcs/permissions` lists every permission at the locations the caller administers. See [List Permissions](list-permissions.md).

Before you expose any of them, set up the AccessPolicies described in [Who May Call the Operations](who-may-call-the-operations.md).

Change `EPrescriptionAccessPermission` and `EPrescriptionAccessRequest` records only through these operations.
A direct write skips the module's checks and leaves no audit record.

The operations work whether or not controlled-substance prescribing is enabled, so you can set up access managers ahead of time.

**LIMITATIONS:** No operation asks an EPCS approver to approve anything yet. The module cannot add a second approver to a location or revoke a permission. Acceptance of a nomination requires a nonblank two-factor code, but the module does not verify it.
