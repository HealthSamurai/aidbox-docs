---
description: Manage access to Electronic Prescribing of Controlled Substances (EPCS) in the Aidbox ePrescription module.
---

# EPCS Access Management

The DEA requires two people to set or change who may prescribe controlled substances: one enters the change, and another approves it with two-factor authentication.
The ePrescription module lets each location appoint its own **access managers** for this job:

* An **administrator access manager** at the location:
  * requests access changes
  * requests the **EPCS prescribing permission** (`epcs-prescribing`) for each practitioner who prescribes controlled substances there, which covers every DEA number the practitioner uses at the location
  * lists access permissions
* An **EPCS approver** approves access changes with two-factor authentication.

Each role and permission applies to an Aidbox `User` at a `Location`.
Neither access manager role lets its holder prescribe controlled substances.

## Operations

The Aidbox App exposes the operations under `/e-prescription/access/epcs`:

* [Configure Access Policies](configure-access-policies.md): decide who may call each operation. Do this first.
* [Bootstrap the First Administrator](bootstrap-the-first-administrator.md): grant a location's first administrator during deployment.
* [Access-Change Requests](access-change-requests.md): change who holds an access manager role or the EPCS prescribing permission at a location.
* [List Permissions](list-permissions.md): list your own permissions and those at the locations you administer.

The operations work whether or not controlled-substance prescribing is enabled, so you can set up access managers and prescribers ahead of time.
