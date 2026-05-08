---
description: Da Vinci PDex Payer-to-Payer Access API — backend services auth, opt-in member matching with persisted consent, and bulk historical data export between payers.
---

# Payer-to-Payer API

The [Da Vinci PDex Payer-to-Payer Bulk Exchange](https://hl7.org/fhir/us/davinci-pdex/payertopayerbulkexchange.html) lets a payer onboarding a new member request that member's clinical history from their prior payer. The flow has two stages:

1. **Match members.** Submit a batch of patient demographics, coverage, and an HRex `Consent` proving member opt-in. The prior payer matches each member, evaluates the consent, persists the consent record, and returns three `Group` resources covering matched members, members the payer could not match, and members whose consent did not authorize the share.
2. **Export data.** Use the `MatchedMembers` Group ID with `$davinci-data-export` to pull the patients' clinical data as ndjson via FHIR Bulk Data.

## Operations

| Operation | Endpoint | Purpose |
| --- | --- | --- |
| [$bulk-member-match](operations/bulk-member-match.md) | `POST /fhir/Group/$bulk-member-match` | Match members under opt-in consent; persist consent; emit Groups for export. |

## Explanation

* [Matching logic](matching-logic.md) — algorithm, opt-in consent evaluation, consent persistence, output Group shape.
* [Async and authorization](async-and-auth.md) — bulk-data lifecycle, OAuth client setup, tenant isolation.

## Setup prerequisites

`$bulk-member-match` is delivered by the [Aidbox PDex / Provider Access interop app](https://github.com/HealthSamurai/interop), not by Aidbox core. Before calling the operation:

* Run the interop app and confirm it has registered itself as a FHIR `App` in Aidbox.
* Load the PDex 2.2 FHIR package (`hl7.fhir.us.davinci-pdex#2.2.0`) so input/output profiles are known to `$validate`. The version Aidbox bootstraps by default predates `$bulk-member-match` — bump `BOX_BOOTSTRAP_FHIR_PACKAGES` first.
* Seed a requesting-payer `Client` carrying an NPI under `Client.details.identifier` (system `http://hl7.org/fhir/sid/us-npi`). Aidbox rejects a top-level `Client.identifier`.
* Seed an `Organization` for the requesting payer with the same NPI so `Coverage.payor` references resolve and the Consent persistence layer has a join key.
* Grant the interop app's `App` an `AccessPolicy` over `Patient`, `Coverage`, `Consent`, `Organization`, `Task`, `Group`, and `Binary`.
* Configure SMART [Backend Services / `client_credentials`](https://www.hl7.org/fhir/smart-app-launch/backend-services.html) for the requesting payer client.

## Sibling API

[Provider Access API](../provider-access-api/README.md) shares the matching algorithm and async lifecycle. Differences: provider attestation (opt-out) instead of member opt-in consent, no consent persistence, distinct output Group profiles, single token for match plus export. See [Differences from $provider-member-match](matching-logic.md#differences-from-provider-member-match) for the full list.
