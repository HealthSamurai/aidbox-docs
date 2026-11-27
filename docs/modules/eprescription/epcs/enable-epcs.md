---
description: Configure the Aidbox ePrescription module and your EHR so that prescribers can sign controlled prescriptions.
---

# Enable EPCS

After this setup, a prescriber can mark a controlled prescription ready to sign and sign it only while they hold the EPCS prescribing permission at the prescription's location.
[Prescribing Controlled Substances](access-management/README.md#prescribing-controlled-substances) lists every check the module runs for these two steps.

## Configure the Module

1. Set `EPCS_MODE` to `full`.
   With the default `disabled`, the module refuses controlled prescriptions.
2. Set `EPCS_PROOF_SECRET` to a random 64-character string (for example, the output of `openssl rand -hex 32`).
   The module uses it to detect a change to a controlled prescription between marking it ready to sign and signing it. Changing the secret invalidates existing ready-to-sign proofs.
3. Open `App/ePrescription-app` in the Aidbox console (`/ui/console#/entities/App`) and check `endpoint.secret`.
   If it is empty or still `PUT_ENDPOINT_SECRET_HERE`, set it to a separate random 64-character string (for example, the output of `openssl rand -hex 32`) and save the App.
4. Copy the current value of `endpoint.secret` and set `AIDBOX_RPC_CREDENTIALS` to the Base64 encoding of `ePrescription-app:<endpoint.secret>`, substituting the copied value for `<endpoint.secret>`.
   The module uses this credential to authenticate every call from Aidbox.
5. Restart the module.

## Configure User Authentication and Access Policies

1. Configure your EHR to use the signed-in user's Aidbox credentials for the operations listed below.
   The module requires an [acting user](access-management/configure-access-policies.md#acting-user) for these operations. A `Client` credential alone does not identify one.
2. Write [AccessPolicies](../../../access-control/authorization/access-policies.md) that let your users call these operations:
   * `POST /e-prescription/rx/ready-to-sign`, which marks a prescription ready to sign
   * `POST /e-prescription/rx/new`, `POST /e-prescription/rx/respond-to-renewal`, and `POST /e-prescription/rx/respond-to-change`, which sign prescriptions
   * the EPCS access operations that [Configure Access Policies](access-management/configure-access-policies.md#access-policies) lists

## Protect the EPCS Records

The module stores the evidence for controlled prescriptions as Aidbox resources:

* `Provenance`: signing records, ready-to-sign proofs, and Surescripts message history
* `Binary`: ready-to-sign proof payloads, archived Surescripts messages, and [practitioner log](practitioner-log.md#archives) payloads
* `DocumentReference`: practitioner log archives
* `AuditEvent`: the EPCS audit trail

To support compliance with DEA requirements, we recommend configuring your Aidbox access policies to prevent users and clients from changing or deleting these evidence resources.

Check every policy that applies to your users and clients.

* Don't grant `PUT`, `PATCH`, or `DELETE` on these four resource types.
* Grant `$sql`, `$load`, and `$import` only to operators.

### If Your EHR Updates Its Own Records

Your EHR can create its own `Provenance`, `Binary`, and `DocumentReference` records with `POST` without touching the module's records.
To let it update or delete its own records, keep the grant away from the module's records:

* `DocumentReference`: the id of every module record starts with `practitioner-log-`.
  Grant writes only for other ids, as in the example below.
* `Provenance` and `Binary`: the module's records carry no marker that a policy can match.
  Any grant that lets your EHR update or delete its records of these types also lets it change the module's records.
  For these two resource types, we recommend allowing only `POST` for writes so your EHR can create records.

<details>
<summary>Policy example</summary>

Replace `Client/my-ehr` with your client.

```yaml
resourceType: AccessPolicy
id: ehr-epcs-record-writes
engine: complex
link:
  - reference: Client/my-ehr
or:
  - engine: matcho
    matcho:
      request-method: post
      uri: '#^/(fhir/)?(Provenance|Binary)$'
  - engine: complex
    and:
      - engine: matcho
        matcho:
          request-method:
            $enum: [put, patch, delete]
          params:
            resource/type: DocumentReference
      - engine: sql
        sql:
          query: SELECT COALESCE({{params.resource/id}} NOT LIKE 'practitioner-log-%', false)
```

</details>

## Appoint the Access Managers

Each location where practitioners prescribe controlled substances needs an administrator and an approver who are different users:

1. Appoint the administrator with [Bootstrap the First Administrator](access-management/bootstrap-the-first-administrator.md).
2. Ask the administrator to nominate the approver with an [access-change request](access-management/access-change-requests.md#request-a-change).
   The nominee must be [DEA-qualified](access-management/access-change-requests.md#dea-qualification) at the location.
3. Ask the nominee to accept the request as the [first approver](access-management/access-change-requests.md#first-approver).
4. Check that [Location Compliance Status](access-management/location-compliance-status.md) returns `compliant: true` for the location.

## Grant the Prescribing Permission

For each practitioner who prescribes controlled substances, at each location where they do:

1. Prepare their `User`, `Practitioner`, `PractitionerRole`, and `Location` as [Prescribing Controlled Substances](access-management/README.md#prescribing-controlled-substances) describes.
2. Add a DEA number to the `PractitionerRole`, as [DEA Qualification](access-management/access-change-requests.md#dea-qualification) describes.
3. Ask the administrator to create a [prescribing nomination](access-management/access-change-requests.md#prescribing-nomination) for the practitioner.
4. Ask an approver other than the nominating administrator to give [second-person approval](access-management/access-change-requests.md#second-person-approval) before it [expires](access-management/access-change-requests.md#expiration).
5. Signed in as the practitioner, check that [`GET /e-prescription/access/epcs/permissions/mine`](access-management/list-permissions.md#list-your-own-permissions) returns `epcs-prescribing` at the location.

## Register the Prescriber for Controlled Prescriptions

For each `PractitionerRole` that prescribes controlled substances:

1. Add the `ControlledSubstance` service level to the `PractitionerRole`:

   ```json
   {
     "meta": {
       "tag": [
         {
           "system": "urn:app:aidbox:e-prescriptions:surescripts:serviceLevel",
           "code": "ControlledSubstance"
         }
       ]
     }
   }
   ```

   Keep the service levels the role already has.
2. Send the updated role to the Surescripts directory with an [UpdateProviderLocation message](../directory/updateproviderlocation-message.md).

## Verify the Setup

Sign in as a practitioner who holds the permission, mark one of their controlled prescriptions ready to sign, and sign it.
If the module rejects a step:

* `401`: check that the EHR uses the signed-in user's credentials. If every call from Aidbox returns `401`, check `AIDBOX_RPC_CREDENTIALS` in [Configure the Module](#configure-the-module).
* `403`: the call failed another check in [Prescribing Controlled Substances](access-management/README.md#prescribing-controlled-substances).
