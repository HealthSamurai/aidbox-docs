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

## Your Obligation

[21 CFR 1311.125(a)](https://www.ecfr.gov/current/title-21/chapter-II/part-1311/subpart-C#p-1311.125\(a\)) requires the registrant to designate at least two individuals to manage access control at each registered location where practitioners issue controlled-substance prescriptions.
At least one of them must be a registrant authorized to issue controlled-substance prescriptions who holds a two-factor authentication credential.

Give each location at least one administrator and one approver, and verify DEA registrations and state authorizations outside the module before you request a change.
The module checks only the records in Aidbox.

## Operations

The Aidbox App exposes the operations under `/e-prescription/access/epcs`:

* [Configure Access Policies](configure-access-policies.md): decide who may call each operation. Do this first.
* [Bootstrap the First Administrator](bootstrap-the-first-administrator.md): grant a location's first administrator during deployment, or a new one after it loses its last.
* [Access-Change Requests](access-change-requests.md): request, approve, cancel, and list grants and revocations of both roles.
* [List Permissions](list-permissions.md): list your own permissions and those at the locations you administer.

The operations work whether or not controlled-substance prescribing is enabled, so you can set up access managers ahead of time.
