---
description: Manage access to Electronic Prescribing of Controlled Substances (EPCS) in the Aidbox ePrescription module.
---

# EPCS Access Management

The DEA requires two people to set or change who may prescribe controlled substances: one enters the change, and another approves it with two-factor authentication.
The ePrescription module lets each location appoint its own **access managers** for this job:

* An **administrator access manager** requests access changes and lists access permissions at the location.
* An **EPCS approver** approves access changes with two-factor authentication.

Each role applies to an Aidbox `User` at a `Location`.
Neither role lets its holder prescribe controlled substances.

## Operations

The Aidbox App exposes the operations under `/e-prescription/access/epcs`:

* [Configure Access Policies](configure-access-policies.md): decide who may call each operation. Do this first.
* [Bootstrap the First Administrator](bootstrap-the-first-administrator.md): grant a location's first administrator during deployment.
* [Access-Change Requests](access-change-requests.md): change who holds an access manager role at a location, with the approval of a second person.
* [List Permissions](list-permissions.md): list your own permissions and those at the locations you administer.

The operations work whether or not controlled-substance prescribing is enabled, so you can set up access managers ahead of time.
