---
description: Da Vinci PDex Provider Access API — backend services auth, member matching, and bulk clinical data export for treating providers.
---

# Provider Access API

The [Da Vinci PDex Provider Access API](https://build.fhir.org/ig/HL7/davinci-epdx/) lets a provider attest to a treatment relationship with a payer's members and pull their clinical data in bulk. The flow has two stages:

1. **Match members.** Submit a batch of patient demographics + coverage + treatment-relationship attestation. The payer returns one or more `Group` resources identifying matched members, members the payer could not match, and members who have opted out of provider data sharing.
2. **Export data.** Use the `MatchedMembers` Group ID with `$davinci-data-export` to retrieve the patients' clinical data as ndjson via the FHIR Bulk Data async pattern.

{% content-ref url="provider-member-match.md" %}
[provider-member-match.md](provider-member-match.md)
{% endcontent-ref %}
