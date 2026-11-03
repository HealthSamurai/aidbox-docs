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

A practitioner can mark a controlled prescription ready to sign and sign it only while they hold the EPCS prescribing permission at the prescription's location.
That location is the `Location` that the prescriber's `PractitionerRole` references and that has:

* `status` set to `active`, or no `status`
* a tag with the system `urn:app:aidbox:e-prescriptions:surescripts:providerDirectory`

For both steps, the module checks that:

* the prescriber's `PractitionerRole` has such a `Location`
* `User.fhirUser` of the [acting user](configure-access-policies.md#acting-user) references the `Practitioner` of that `PractitionerRole`
* that `Practitioner` does not have `active` set to `false`
* the `PractitionerRole` has `active` set to `true` and a `period` that covers the current date
* the acting user holds the EPCS prescribing permission at that `Location`

A request without an acting user gets `401`, and a request that fails another check gets `403`.

Because signing repeats these checks, revoking the permission after the practitioner marks the prescription ready stops signing.

## Operations

The Aidbox App exposes the operations under `/e-prescription/access/epcs`:

* [Configure Access Policies](configure-access-policies.md): decide who may call each operation. Do this first.
* [Bootstrap the First Administrator](bootstrap-the-first-administrator.md): grant a location's first administrator during deployment.
* [Access-Change Requests](access-change-requests.md): change who holds an access manager role or the EPCS prescribing permission at a location.
* [List Permissions](list-permissions.md): list your own permissions and those at the locations you administer.
* [Location Compliance Status](location-compliance-status.md): check whether a location has an administrator and an approver who are different users.

The operations work whether or not controlled-substance prescribing is enabled, so you can set up access managers and prescribers ahead of time.
