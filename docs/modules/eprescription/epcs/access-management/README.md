---
description: Set up a location's EPCS administrator, nominate its first approver, and list access permissions in the Aidbox ePrescription module.
---

# EPCS Access Management

The DEA requires two people to set or change who may prescribe controlled substances: one enters the change, and another approves it with two-factor authentication.
The ePrescription module lets each location appoint its own **access managers** for this job.
An **access manager** holds one of two roles at a location:

* An **administrator access manager** holds `epcs-access-admin`. They nominate approvers and see every permission at the location.
* An **EPCS approver** holds `epcs-access-approver`. They are the second person who approves access changes.

An **access permission** grants one of these roles to an Aidbox `User` at a `Location`.
The module stores it as an `EPrescriptionAccessPermission`.
An **access-change request** asks to grant an **access permission** to a user, the **nominee**.
A **nomination** is an **access-change request** for `epcs-access-approver`, stored as an `EPrescriptionAccessRequest`.
Acceptance grants the **access permission** and records its link to the **nomination**.

Use these guides to call the operations exposed by the Aidbox App under `/e-prescription/access/epcs`:

* [Bootstrap the First Administrator](bootstrap-the-first-administrator.md) grants the first **administrator access manager** during deployment.
* [Approver Nominations](approver-nominations.md) covers nominating the first **EPCS approver**, accepting or cancelling a **nomination**, and listing **nominations**.
* [List Permissions](list-permissions.md) covers the caller's own **access permissions** and those at locations they administer.

Before you expose any of them, set up the AccessPolicies described in [Who May Call the Operations](who-may-call-the-operations.md).

Change `EPrescriptionAccessPermission` and `EPrescriptionAccessRequest` records only through these operations.
A direct write skips the module's checks and writes no module audit event.

The operations work whether or not controlled-substance prescribing is enabled, so you can set up **access managers** ahead of time.

**LIMITATIONS:** The module supports appointing the first **access managers** only. It cannot add a second **EPCS approver**, revoke an **access permission**, or ask an existing **EPCS approver** to approve access changes. For the two-factor authentication limitation, see [Accept a Nomination](approver-nominations.md#accept-a-nomination).
