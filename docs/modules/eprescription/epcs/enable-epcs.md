---
description: Configure the Aidbox ePrescription module and your EHR so that prescribers can sign controlled prescriptions.
---

# Enable EPCS

After this setup, a prescriber can mark a controlled prescription ready to sign and sign it only while they hold the EPCS prescribing permission at the prescription's location.
[Prescribing Controlled Substances](access-management/README.md#prescribing-controlled-substances) lists every check the module runs for these two steps.

## Configure the Module

1. Set `EPCS_MODE` to `full`.
   With the default `disabled`, the module refuses controlled prescriptions.
2. Set `EPCS_PROOF_SECRET` to the output of `openssl rand -hex 32`, a random 64-character string.
   The module uses it to detect a change to a controlled prescription between marking it ready to sign and signing it.
   If you change the secret later, mark the prescriptions that are already ready to sign again before signing them.
3. Open `App/ePrescription-app` in the Aidbox console (`/ui/console#/entities/App`) and copy the value of `endpoint.secret`.
   Aidbox authenticates every call it forwards to the module with this secret.
   If it is empty or still `PUT_ENDPOINT_SECRET_HERE`, set it to the output of `openssl rand -hex 32` and save the App.
4. Set `AIDBOX_RPC_CREDENTIALS` to `base64("ePrescription-app:<endpoint.secret>")`.
   While it does not match `endpoint.secret`, the module answers every call from Aidbox with `401`, not only the EPCS calls.
5. Restart the module.

## Call the Module as the Signed-In User

1. Send each call that marks a prescription ready to sign, signs it, or manages EPCS access with the signed-in person's Aidbox authentication.
   The module then gets an [acting user](access-management/configure-access-policies.md#acting-user) for the call.
   A call made with only a `Client` credential has no acting user, and the module rejects it.
2. Write AccessPolicies that let your users call these operations:
   * `POST /e-prescription/rx/ready-to-sign`, which marks a prescription ready to sign
   * `POST /e-prescription/rx/new`, `POST /e-prescription/rx/respond-to-renewal`, and `POST /e-prescription/rx/respond-to-change`, which sign prescriptions
   * the EPCS access operations that [Configure Access Policies](access-management/configure-access-policies.md#access-policies) lists

## Appoint the Access Managers

Each location where practitioners prescribe controlled substances needs an administrator and an approver who are different users:

1. Appoint the administrator with [Bootstrap the First Administrator](access-management/bootstrap-the-first-administrator.md).
2. The administrator nominates the approver with an [access-change request](access-management/access-change-requests.md#request-a-change), and the nominee accepts it as the [first approver](access-management/access-change-requests.md#first-approver).
3. Check that [Location Compliance Status](access-management/location-compliance-status.md) returns `compliant: true` for the location.

## Grant the Prescribing Permission

For each practitioner who prescribes controlled substances, at each location where they do:

1. Prepare their `User`, `Practitioner`, `PractitionerRole`, and `Location` as [Prescribing Controlled Substances](access-management/README.md#prescribing-controlled-substances) describes.
2. Add a DEA number to the `PractitionerRole`, as [DEA Qualification](access-management/access-change-requests.md#dea-qualification) describes.
3. The administrator creates a [prescribing nomination](access-management/access-change-requests.md#prescribing-nomination) for the practitioner.
4. An approver other than that administrator approves it through [second-person approval](access-management/access-change-requests.md#second-person-approval) before it [expires](access-management/access-change-requests.md#expiration).
5. Signed in as the practitioner, check that [`GET /e-prescription/access/epcs/permissions/mine`](access-management/list-permissions.md#list-your-own-permissions) returns `epcs-prescribing` at the location.

## Verify the Setup

Sign in as a practitioner who holds the permission, mark one of their controlled prescriptions ready to sign, and sign it.
If the module rejects a step:

* `401`: the call had no acting user. Check [Call the Module as the Signed-In User](#call-the-module-as-the-signed-in-user).
* `403`: the call failed another check in [Prescribing Controlled Substances](access-management/README.md#prescribing-controlled-substances).
