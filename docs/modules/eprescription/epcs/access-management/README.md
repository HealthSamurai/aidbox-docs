---
description: Set up a location's EPCS administrator, nominate its first approver, and list access permissions in the Aidbox ePrescription module.
---

# EPCS Access Management

Electronic Prescribing of Controlled Substances (EPCS) rules require each location that prescribes controlled substances to designate its own **access managers**, the people who manage the location's EPCS access.
The ePrescription module stores each designation as an `EPrescriptionAccessPermission`: one Aidbox `User`, one role, one `Location`.
Two roles exist.
An **administrator access manager** holds `epcs-access-admin`.
An **EPCS approver** holds `epcs-access-approver`.

The Aidbox App exposes operations to set up administrators, manage approver nominations, and list permissions:

* `POST /e-prescription/access/epcs/bootstrap-admin` grants the first administrator access manager of a location. This is a deployment setup step.
* `POST /e-prescription/access/epcs/requests` nominates the first EPCS approver of a location. The nominee accepts through `POST /e-prescription/access/epcs/requests/<id>/approve`.
* `GET /e-prescription/access/epcs/requests` lists nominations visible to the caller. `POST /e-prescription/access/epcs/requests/<id>/cancel` cancels a nomination.
* `GET /e-prescription/access/epcs/permissions/mine` lists the caller's own permissions.
* `GET /e-prescription/access/epcs/permissions` lists every permission at the locations the caller administers.

Use these operations to read and change `EPrescriptionAccessPermission` and `EPrescriptionAccessRequest` records.
Direct writes skip the module's checks and leave no audit record.

The operations do not depend on `EPCS_MODE`.
They work on every deployment that installs the App, including one that keeps controlled-substance prescribing disabled.

**LIMITATIONS:** The module cannot add another approver to a location that already has one or revoke a permission. Acceptance requires a nonblank two-factor code, but the module does not verify it.

## Pages

* [Who May Call the Operations](who-may-call-the-operations.md)
* [Bootstrap the First Administrator](bootstrap-the-first-administrator.md)
* [List Permissions](list-permissions.md)
* [Approver Nominations](approver-nominations.md)
