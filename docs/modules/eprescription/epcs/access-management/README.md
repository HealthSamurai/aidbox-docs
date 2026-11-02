---
description: Manage access to Electronic Prescribing of Controlled Substances (EPCS) in the Aidbox ePrescription module.
---

# EPCS Access Management

The DEA requires two people to set or change who may prescribe controlled substances: one enters the change, and another approves it with two-factor authentication.
The ePrescription module lets each location appoint its own **access managers** for this job:

* An **administrator access manager** at the location:
  * requests access changes
  * requests grants and revocations of the **EPCS prescribing permission** `epcs-prescribing` for practitioners (it covers all their DEA numbers at the location)
  * lists access permissions
* An **EPCS approver** approves access changes with two-factor authentication.

Each role and permission applies to an Aidbox `User` at a `Location`.

## Prescribing Controlled Substances

A practitioner marks a controlled prescription ready to sign, and signs it, only while they hold the EPCS prescribing permission at the prescription's location.
That location is the `Location` of the prescriber's `PractitionerRole` that has:

* `status` set to `active`, or no `status`
* a tag with the system `urn:app:aidbox:e-prescriptions:surescripts:providerDirectory`

For both steps, the module checks that:

* the prescriber's `PractitionerRole` has such a `Location`
* the [acting user](configure-access-policies.md#acting-user) is the prescriber: their `User.fhirUser` references the `Practitioner` of that `PractitionerRole`
* the acting user is [DEA-qualified](access-change-requests.md#dea-qualification) at that `Location`
* the acting user holds the EPCS prescribing permission at that `Location`

The module checks the permission again at signing, so a revocation stops signing even after the practitioner marked the prescription ready.

## Operations

The Aidbox App exposes the operations under `/e-prescription/access/epcs`:

* [Configure Access Policies](configure-access-policies.md): decide who may call each operation. Do this first.
* [Bootstrap the First Administrator](bootstrap-the-first-administrator.md): grant a location's first administrator during deployment.
* [Access-Change Requests](access-change-requests.md): change who holds an access manager role or the EPCS prescribing permission at a location.
* [List Permissions](list-permissions.md): list your own permissions and those at the locations you administer.
* [Location Compliance Status](location-compliance-status.md): check whether a location has an administrator and an approver who are different users.

The operations work whether or not controlled-substance prescribing is enabled, so you can set up access managers and prescribers ahead of time.
