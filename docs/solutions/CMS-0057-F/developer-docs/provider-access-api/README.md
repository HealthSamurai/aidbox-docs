---
description: Da Vinci PDex Provider Access API — backend services auth, member matching, and bulk clinical data export for treating providers.
---

# Provider Access API

The [Da Vinci PDex Provider Access API](https://build.fhir.org/ig/HL7/davinci-epdx/) lets a provider attest to a treatment relationship with a payer's members and pull their clinical data in bulk. The flow has two stages:

1. **Match members.** Submit a batch of patient demographics, coverage, and a treatment-relationship attestation. The payer returns one or more `Group` resources identifying matched members, members the payer could not match, and members who have opted out of provider data sharing.
2. **Export data.** Use the `MatchedMembers` Group ID with `$davinci-data-export` to pull the patients' clinical data as ndjson via FHIR Bulk Data.

## Operations

| Operation | Endpoint | Purpose |
| --- | --- | --- |
| [$provider-member-match](operations/provider-member-match.md) | `POST /fhir/Group/$provider-member-match` | Match a batch of members; emit Groups for export. |

## Explanation

* [Matching logic](matching-logic.md) — algorithm, treatment attestation, opt-out check, output Group shape.
* [Async and authorization](async-and-auth.md) — bulk-data lifecycle, OAuth client setup, tenant isolation.

## Setup prerequisites

`$provider-member-match` is delivered by the [Aidbox PDex / Provider Access interop app](https://github.com/HealthSamurai/interop), not by Aidbox core. Before calling the operation:

* Run the interop app and confirm it has registered itself as a FHIR `App` in Aidbox.
* Load the PDex 2.1 FHIR package (`hl7.fhir.us.davinci-pdex#2.1.0`) so input/output profiles are known to `$validate`.
* Seed a provider `Client` and matching `Organization` carrying an NPI (system `http://hl7.org/fhir/sid/us-npi`).
* Grant the interop app's `App` an `AccessPolicy` over `Patient`, `Coverage`, `Consent`, `Organization`, `Task`, `Group`, and `Binary`.
* Configure SMART [Backend Services / `client_credentials`](https://www.hl7.org/fhir/smart-app-launch/backend-services.html) for the provider client.
