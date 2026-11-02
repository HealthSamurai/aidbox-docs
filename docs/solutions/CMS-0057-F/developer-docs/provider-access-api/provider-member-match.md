---
description: Da Vinci PDex Provider Access $provider-member-match operation — match a batch of members and get a Group for bulk data export.
---

# $provider-member-match

The `$provider-member-match` operation implements the [Da Vinci PDex Provider Access API](https://build.fhir.org/ig/HL7/davinci-epdx/). It lets a provider submit a batch of members (patient demographics, coverage, and a treatment-relationship attestation) and receive one or more `Group` resources whose IDs can then be used with `$davinci-data-export` to pull clinical data in bulk.

The operation follows the [FHIR Bulk Data async pattern](https://hl7.org/fhir/uv/bulkdata/export.html#bulk-data-kick-off-request): the kick-off request `POST [base]/fhir/Group/$provider-member-match` returns `202 Accepted` with a `Content-Location` header, the client polls the status URL, and once processing is complete downloads an ndjson file containing the output `Parameters` resource.

{% hint style="warning" %}
`$provider-member-match` is **not part of Aidbox core**. It is delivered by the [Aidbox PDex / Provider Access interop app](https://github.com/HealthSamurai/interop), which registers itself with Aidbox as a FHIR `App` resource and handles the operation via HTTP-RPC. You must run and register the interop app against your Aidbox instance before these endpoints are available. The PDex 2.1 FHIR package (`hl7.fhir.us.davinci-pdex#2.1.0`) also needs to be loaded in Aidbox so the input/output profiles are known to `$validate`.
{% endhint %}

{% hint style="warning" %}
`$provider-member-match` is **always asynchronous**. Clients must include the `Prefer: respond-async` header on the kick-off request. Requests without this header are rejected with `400 Bad Request`.
{% endhint %}

{% hint style="info" %}
**Spec references** (PDex 2.1):

* [OperationDefinition: PDex Provider-Member-Match Operation](https://build.fhir.org/ig/HL7/davinci-epdx/OperationDefinition-ProviderMemberMatch.html)
* [Input profile: Provider $multi-member-match Request](https://build.fhir.org/ig/HL7/davinci-epdx/StructureDefinition-provider-parameters-multi-member-match-bundle-in.html)
* [Output profile: Provider $multi-member-match Response](https://build.fhir.org/ig/HL7/davinci-epdx/StructureDefinition-provider-parameters-multi-member-match-bundle-out.html)
* Output Group profiles: [pdex-treatment-relationship](https://build.fhir.org/ig/HL7/davinci-epdx/StructureDefinition-pdex-treatment-relationship.html), [pdex-member-no-match-group](https://build.fhir.org/ig/HL7/davinci-epdx/StructureDefinition-pdex-member-no-match-group.html), [pdex-member-opt-out](https://build.fhir.org/ig/HL7/davinci-epdx/StructureDefinition-pdex-member-opt-out.html)
{% endhint %}

## Overview

Each submitted member goes through a deterministic evaluation pipeline and lands in exactly one of three output buckets:

| Bucket | Profile | Code | Meaning |
| --- | --- | --- | --- |
|`MatchedMembers` |`pdex-treatment-relationship` |`match` | Demographics matched a payer member, treatment attestation is valid, and the member has not opted out. The Group ID of this bucket is what the provider feeds into `$davinci-data-export`. |
|`NonMatchedMembers` |`pdex-member-no-match-group` |`nomatch` | No match was found, the match was ambiguous, or the treatment attestation was invalid. |
|`ConsentConstrainedMembers` |`pdex-member-opt-out` |`consentconstraint` | Demographics matched, but the member has an active opt-out `Consent` on file. |

Per-member failures do not fail the whole batch — problematic members are routed to `NonMatchedMembers`.

### Per-member evaluation pipeline

<div align="center">

```mermaid
graph TD
    A(Input member):::blue2 --> B(Validate attestation):::green2
    B -->|valid| C(Match demographics):::green2
    C -->|matched| D(Check opt-out):::green2
    B -->|invalid| N(NonMatchedMembers):::neutral1
    C -->|no match| N
    D -->|opted out| O(ConsentConstrainedMembers):::yellow2
    D -->|not opted out| M(MatchedMembers):::violet2
    N ~~~ O ~~~ M
```

</div>

### Per-member edge cases

The pipeline never rejects an entire batch. Every input member resolves to exactly one bucket, even when the input is malformed:

| Condition | Bucket |
| --- | --- |
| `Consent` part missing or `status` not `active` | `NonMatchedMembers` |
| Submitted Patient missing any of `family`, `given[0]`, `birthDate`, `gender` | `NonMatchedMembers` |
| Demographic search returns zero payer Patients | `NonMatchedMembers` |
| Demographic search returns more than one payer Patient (ambiguous) | `NonMatchedMembers` |
| `Coverage.subscriberId` is present but no payer Patient has a matching Coverage | `NonMatchedMembers` |
| Unhandled exception while evaluating a single member | `NonMatchedMembers` (with reason in `Task` logs) |
| Match succeeds and matched Patient has an active opt-out `Consent` | `ConsentConstrainedMembers` |
| Match succeeds and no opt-out exists | `MatchedMembers` |

## Workflow

{% stepper %}
{% step %}
**Kick-off.** `POST` a `Parameters` resource listing one or more `MemberBundle` entries. Include `Prefer: respond-async`. The server responds with `202 Accepted` and a `Content-Location` header pointing at the status URL.
{% endstep %}

{% step %}
**Poll status.** `GET` the URL from `Content-Location`. While processing is running you get `202 Accepted` with a `Retry-After` header. Once complete you get `200 OK` with a Bulk Data manifest whose `output[].url` points to an ndjson file.
{% endstep %}

{% step %}
**Download output.** `GET` the ndjson URL from the manifest. The body is a single-line `Parameters` resource containing the output `Group` resources inline.
{% endstep %}

{% step %}
**(Optional) Cancel or delete.** `DELETE` the cancel URL to stop a running job or clean up a completed one.
{% endstep %}
{% endstepper %}

### Async sequence

<div align="center">

```mermaid
sequenceDiagram
    participant C as Provider client
    participant A as Aidbox
    participant I as Interop app
    C->>A: POST /fhir/Group/$provider-member-match<br/>Prefer: respond-async
    A->>I: HTTP-RPC kick-off
    I->>A: PUT Task (status=requested)
    I-->>A: 202 + Content-Location
    A-->>C: 202 + Content-Location
    Note over I: background future:<br/>match → opt-out → group build
    loop Poll
        C->>A: GET .../$provider-member-match-status/{id}
        A->>I: HTTP-RPC status
        alt Task in-progress
            I-->>A: 202 + Retry-After
            A-->>C: 202 + Retry-After
        else Task completed
            I-->>A: 200 + Bulk Data manifest
            A-->>C: 200 + manifest
        end
    end
    C->>A: GET /output/{id}.ndjson
    A->>I: HTTP-RPC ndjson
    I-->>A: 200 + Parameters (ndjson)
    A-->>C: 200 + Parameters (ndjson)
```

</div>

## Authorization

`$provider-member-match` is a backend-services API: callers are provider organizations, not end users. The interop app authenticates the request via the OAuth client that Aidbox issues a token to (typically through the SMART [Backend Services / `client_credentials`](https://www.hl7.org/fhir/smart-app-launch/backend-services.html) flow).

| Concern | Requirement |
| --- | --- |
| Auth flow | OAuth 2.0 `client_credentials` (SMART Backend Services). The bearer token is presented to Aidbox; Aidbox forwards the resolved `oauth/client` to the interop app over HTTP-RPC. |
| Provider identity | The OAuth `Client` resource representing the provider organization must carry an NPI in `Client.identifier[*]` with `system = http://hl7.org/fhir/sid/us-npi`. The interop app reads this entry and stamps it on `Task.requester` and on the `MatchedMembers` Group. If no NPI is found the provider is recorded as `"unknown"`. |
| Required Aidbox access | The interop app needs read access to `Patient`, `Coverage`, `Consent`, `Organization` (for payer NPI lookup) and read/write access to `Task`, `Group`, `Binary` in the same Aidbox instance. The app is registered as a FHIR `App` resource on startup; granting the `App` an access policy that allows these resource types is sufficient. |
| App registration | The interop app must be running and registered (its `App` resource present in Aidbox). Without it, `POST /fhir/Group/$provider-member-match` returns Aidbox's default "operation not found" response. |

UDAP B2B token validation, mTLS, and dynamic client registration are **not** implemented today — see [Limitations](#limitations).

## Input

A FHIR `Parameters` resource with one or more `MemberBundle` parameters. Each `MemberBundle` contains:

| Part | Card. | Type | Profile |
| --- | --- | --- | --- |
| `MemberPatient` | 1..1 | Patient | [HRex Patient Demographics](http://hl7.org/fhir/us/davinci-hrex/STU1/StructureDefinition-hrex-patient-demographics.html) |
| `CoverageToMatch` | 1..1 | Coverage | [HRex Coverage](http://hl7.org/fhir/us/davinci-hrex/STU1/StructureDefinition-hrex-coverage.html) |
| `Consent` | 1..1 | Consent | [Provider Treatment Relationship Consent](http://hl7.org/fhir/us/davinci-pdex/STU2.1/StructureDefinition-provider-treatment-relationship-consent.html) |
| `CoverageToLink` | 0..1 | Coverage | HRex Coverage |

The whole `Parameters` body is first validated with Aidbox `$validate` against the `provider-parameters-multi-member-match-bundle-in` profile. If validation fails, the server returns `422 Unprocessable Entity` with the `OperationOutcome` from `$validate` and no background job is created.

### Matching algorithm

Matching is deterministic and exact. The following demographic fields are **all required** on the submitted Patient and must all match a payer-side `Patient`:

| Field | Logic |
| --- | --- |
| `Patient.name[0].family` | Case-insensitive exact |
| `Patient.name[0].given[0]` | Case-insensitive exact |
| `Patient.birthDate` | Exact |
| `Patient.gender` | Exact |

When `CoverageToMatch.subscriberId` is present the matching query additionally requires `_has:Coverage:beneficiary:subscriber-id=<subscriberId>` so only Patients with a matching Coverage subscriber ID are considered.

A member is treated as **unmatched** when the demographic search returns zero entries **or** more than one entry (ambiguous matches are rejected conservatively).

### Treatment attestation

The `Consent` part is the provider's attestation that a treatment relationship exists with the member. The attestation is accepted when the `Consent` resource is present and `Consent.status = "active"`. There is no deeper verification of the attestation claim itself — the attestation **is** the declaration.

### Opt-out check

After a successful demographic match, the server searches for an active opt-out `Consent` on the matched payer-side Patient:

```http
GET /fhir/Consent
  ?patient=<matched-patient-id>
  &status=active
  &category=http://hl7.org/fhir/us/davinci-pdex/CodeSystem/pdex-consent-api-purpose|provider-access
  &provision-type=deny
```

If at least one such `Consent` exists, the member is placed in `ConsentConstrainedMembers`. Revocations (`provision.type = "permit"`) are not returned by this query and therefore do not block the member.

{% hint style="info" %}
All opt-out scopes (`global`, `provider-specific`, `purpose-specific`, `payer-specific`, `provider-category`) are currently treated the same — any active `deny` opts the member out. Scope-aware enforcement is not yet implemented.
{% endhint %}

### Kick-off example

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/Group/$provider-member-match
Content-Type: application/fhir+json
Prefer: respond-async
```

```json
{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "MemberBundle",
      "part": [
        {
          "name": "MemberPatient",
          "resource": {
            "resourceType": "Patient",
            "name": [{"family": "Johnson", "given": ["Robert"]}],
            "gender": "male",
            "birthDate": "1952-07-25",
            "identifier": [
              {"system": "http://example.org/member-id", "value": "M12345"}
            ]
          }
        },
        {
          "name": "CoverageToMatch",
          "resource": {
            "resourceType": "Coverage",
            "status": "active",
            "subscriberId": "SUB-001",
            "beneficiary": {"reference": "Patient/test-member-001"},
            "payor": [{"reference": "Organization/test-payer-001"}]
          }
        },
        {
          "name": "Consent",
          "resource": {
            "resourceType": "Consent",
            "status": "active",
            "scope": {
              "coding": [{
                "system": "http://terminology.hl7.org/CodeSystem/consentscope",
                "code": "treatment"
              }]
            },
            "category": [
              {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IDSCL"}]},
              {"coding": [{"system": "http://loinc.org", "code": "64292-6"}]}
            ],
            "patient": {"reference": "Patient/test-member-001"},
            "dateTime": "2026-01-15T10:00:00Z",
            "performer": [
              {"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "1982947230"}}
            ],
            "policyRule": {
              "coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "OPTIN"}]
            }
          }
        }
      ]
    }
  ]
}
```
{% endtab %}

{% tab title="Response" %}
**Status**

202 Accepted

**Headers**

* `Content-Location` — status URL, e.g. `[base]/fhir/Group/$provider-member-match-status/<task-id>`
{% endtab %}

{% tab title="Response (validation fail)" %}
**Status**

422 Unprocessable Entity

**Body**

```json
{
  "resourceType": "OperationOutcome",
  "id": "validationfail",
  "issue": [
    {
      "severity": "error",
      "code": "invariant",
      "diagnostics": "..."
    }
  ]
}
```
{% endtab %}

{% tab title="Response (missing Prefer)" %}
**Status**

400 Bad Request

**Body**

```json
{
  "resourceType": "OperationOutcome",
  "issue": [
    {
      "severity": "error",
      "code": "processing",
      "diagnostics": "This operation requires Prefer: respond-async header"
    }
  ]
}
```
{% endtab %}
{% endtabs %}

## Status polling

```
GET [base]/fhir/Group/$provider-member-match-status/<task-id>
```

The operation tracks progress with a standard FHIR `Task` resource. Responses map from the Task status as follows:

| Task status | HTTP | Headers | Body |
| --- | --- | --- | --- |
| `requested` | 202 | `Retry-After: 5` | — |
| `in-progress` | 202 | `Retry-After: 5`, `X-Progress: Processing members` | — |
| `completed` | 200 | `Content-Type: application/json` | Bulk Data manifest |
| `failed` | 500 | — | `OperationOutcome` with failure diagnostics |
| not found | 404 | — | `OperationOutcome` |

{% tabs %}
{% tab title="In progress" %}
**Status**

202 Accepted

**Headers**

| Header         | Value                       |
| -------------- | --------------------------- |
| Retry-After    | `5`                         |
| X-Progress     | `Processing members`        |
{% endtab %}

{% tab title="Completed" %}
**Status**

200 OK

**Body**

```json
{
  "transactionTime": "2026-04-20T12:34:56Z",
  "request": "[base]/fhir/Group/$provider-member-match",
  "requiresAccessToken": true,
  "output": [
    {
      "type": "Parameters",
      "url": "[base]/output/<task-id>.ndjson"
    }
  ],
  "error": []
}
```
{% endtab %}

{% tab title="Failed" %}
**Status**

500 Internal Server Error

**Body**

```json
{
  "resourceType": "OperationOutcome",
  "issue": [
    {
      "severity": "error",
      "code": "exception",
      "diagnostics": "<reason from Task.statusReason>"
    }
  ]
}
```
{% endtab %}
{% endtabs %}

## Output

The manifest's `output[0].url` points at an ndjson endpoint served by Aidbox:

```
GET [base]/output/<task-id>.ndjson
```

The body is a single line — a `Parameters` resource conforming to the `provider-parameters-multi-member-match-bundle-out` profile. Each non-empty output bucket appears as one parameter whose `resource` is the full inline `Group`. Empty buckets are omitted.

{% tabs %}
{% tab title="Request" %}
```http
GET /output/<task-id>.ndjson
```
{% endtab %}

{% tab title="Response" %}
**Status**

200 OK

**Headers**

| Header       | Value                       |
| ------------ | --------------------------- |
| Content-Type | `application/fhir+ndjson`   |

**Body** (single ndjson line, formatted for readability)

```json
{
  "resourceType": "Parameters",
  "meta": {
    "profile": [
      "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/provider-parameters-multi-member-match-bundle-out"
    ]
  },
  "parameter": [
    {
      "name": "MatchedMembers",
      "resource": {
        "resourceType": "Group",
        "id": "<task-id>-matched",
        "meta": {
          "profile": [
            "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-treatment-relationship"
          ]
        },
        "active": true,
        "type": "person",
        "actual": true,
        "code": {
          "coding": [{
            "system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS",
            "code": "match"
          }]
        },
        "identifier": [
          {"system": "http://hl7.org/fhir/sid/us-npi", "value": "1982947230"}
        ],
        "managingEntity": {
          "identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"},
          "display": "Payer Organization"
        },
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "match"}]},
          "valueReference": {
            "identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "1982947230"},
            "display": "Provider Organization"
          },
          "exclude": false,
          "period": {"start": "2026-04-20", "end": "2026-05-20"}
        }],
        "quantity": 1,
        "member": [
          {"entity": {"reference": "Patient/test-member-001", "display": "Johnson, Robert"}, "inactive": false}
        ]
      }
    },
    {
      "name": "ConsentConstrainedMembers",
      "resource": {
        "resourceType": "Group",
        "id": "<task-id>-consent",
        "meta": {
          "profile": [
            "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-member-opt-out"
          ]
        },
        "active": true,
        "type": "person",
        "actual": true,
        "code": {
          "coding": [{
            "system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS",
            "code": "consentconstraint"
          }]
        },
        "managingEntity": {
          "identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"},
          "display": "Payer Organization"
        },
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "consentconstraint"}]},
          "valueCodeableConcept": {
            "coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/opt-out-scope", "code": "provider-specific"}]
          },
          "exclude": false,
          "period": {"start": "2026-04-20", "end": "2026-05-20"}
        }],
        "quantity": 1,
        "member": [
          {"entity": {"reference": "Patient/test-member-002", "display": "Williams, Sarah"}, "inactive": false}
        ]
      }
    },
    {
      "name": "NonMatchedMembers",
      "resource": {
        "resourceType": "Group",
        "id": "<task-id>-nomatch",
        "meta": {
          "profile": [
            "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-member-no-match-group"
          ]
        },
        "active": true,
        "type": "person",
        "actual": true,
        "code": {
          "coding": [{
            "system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS",
            "code": "nomatch"
          }]
        },
        "contained": [
          {
            "resourceType": "Patient",
            "id": "1",
            "name": [{"family": "Unknown", "given": ["Nobody"]}],
            "gender": "male",
            "birthDate": "2000-01-01"
          }
        ],
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "nomatch"}]},
          "valueBoolean": true,
          "exclude": false,
          "period": {"start": "2026-04-20", "end": "2026-05-20"}
        }],
        "quantity": 1,
        "member": [
          {
            "entity": {
              "reference": "#1",
              "extension": [{
                "url": "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/base-ext-match-parameters",
                "valueReference": {"reference": "#1"}
              }]
            },
            "inactive": false
          }
        ]
      }
    }
  ]
}
```
{% endtab %}
{% endtabs %}

### Output Group fields

All output Groups share `type = "person"`, `actual = true`, and `active = true`. Additional fields depend on the bucket:

**MatchedMembers and ConsentConstrainedMembers**

* `managingEntity.identifier` — the **payer's** NPI, resolved from the first submitted member's `Coverage.payor[0].reference` (an Organization with an `identifier` of system `http://hl7.org/fhir/sid/us-npi`). If the Organization is missing or has no NPI, this falls back to `"unknown"`.
* `member[].entity.reference` — a literal reference to the payer-side `Patient` that was matched.
* `characteristic[].period` — 30-day validity window, `period.start` is today, `period.end` is 30 days out.

**MatchedMembers only**

* `identifier` — array containing the provider's NPI (derived from the authenticated OAuth client's `identifier` entry with system `http://hl7.org/fhir/sid/us-npi`).
* `characteristic[0].valueReference` — a logical reference by NPI to the provider Organization.

**NonMatchedMembers**

* The submitted Patient demographics are **not** persisted as standalone `Patient` resources. Instead, each submitted Patient is carried in `Group.contained[]` with a local id (`"1"`, `"2"`, …).
* `member[].entity.reference` is a fragment reference (`"#1"`, `"#2"`, …) into `contained`, plus a `base-ext-match-parameters` extension carrying the same fragment reference.
* `characteristic[0].valueBoolean = true`.

## Cancellation and deletion

```
DELETE [base]/fhir/Group/$provider-member-match-cancel/<task-id>
```

Cancellation is cooperative. The background worker checks the Task status before starting, after each evaluated member, and again before persisting results — so a cancelled job stops at the next checkpoint without ever writing Groups or the Binary.

| Task status | Action | Response |
| --- | --- | --- |
| `requested` / `in-progress` | Set Task to `cancelled`. The background processor stops at its next checkpoint. | 202 Accepted |
| `completed` / `failed` / `cancelled` | Delete the Task and every resource referenced from `Task.output` (Groups and the Binary). | 202 Accepted |
| not found | — | 404 `OperationOutcome` |

{% hint style="info" %}
Cancellation uses a custom `$provider-member-match-cancel` URL rather than `DELETE` on the status URL, because Aidbox operation dispatch is keyed on HTTP method and distinct method/URL combinations must be registered separately.
{% endhint %}

## Group lifecycle and cleanup

Each output Group carries a 30-day validity window on `Group.characteristic[0].period`:

```json
"period": {"start": "2026-04-20", "end": "2026-05-20"}
```

A background job inside the interop app runs hourly and:

1. **Deactivates expired Groups** — Groups whose `characteristic.period.end` has passed and whose `active = true` are flipped to `active = false`.
2. **Hard-deletes old inactive Groups** — Groups with `active = false` whose `characteristic.period.end` is more than 90 days in the past are removed along with the Task and Binary they belong to.

Cleanup only touches PDex Groups — the scan filters on `_profile=<pdex-treatment-relationship,pdex-member-no-match-group,pdex-member-opt-out>`. Non-PDex Groups in the same Aidbox instance are left alone.

## Error responses

| Status | Condition |
| --- | --- |
| 202 | Async request accepted (kick-off) or cancellation acknowledged. |
| 200 | Polling complete, manifest returned. |
| 400 | `Prefer: respond-async` header is missing. |
| 404 | Unknown `task-id` on status, cancel, or output. |
| 422 | Input `Parameters` failed profile validation. |
| 500 | Background processing failed; see `Task.statusReason`. |

Individual member failures (validation issues, exceptions while evaluating one member) do **not** fail the whole batch — the affected members are routed to `NonMatchedMembers` with a reason string.

## End-to-end example

The snippets below reproduce the three-bucket demo used in internal testing. They assume an Aidbox instance with the PDex STU 2.1 package loaded, the interop app registered, and an OAuth client authorized to call it.

### 1. Seed the payer-side test data

Post this `Bundle` once to create the Organization, payer-side Patients, Coverages, and an opt-out `Consent` for `test-member-002`.

```http
POST /fhir
Content-Type: application/fhir+json
```

```json
{
  "resourceType": "Bundle",
  "type": "transaction",
  "entry": [
    {
      "request": {"method": "PUT", "url": "/Organization/test-payer-001"},
      "resource": {
        "resourceType": "Organization", "id": "test-payer-001",
        "name": "Test Payer Organization",
        "identifier": [{"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"}]
      }
    },
    {
      "request": {"method": "PUT", "url": "/Patient/test-member-001"},
      "resource": {
        "resourceType": "Patient", "id": "test-member-001",
        "name": [{"family": "Johnson", "given": ["Robert"]}],
        "gender": "male", "birthDate": "1952-07-25"
      }
    },
    {
      "request": {"method": "PUT", "url": "/Patient/test-member-002"},
      "resource": {
        "resourceType": "Patient", "id": "test-member-002",
        "name": [{"family": "Williams", "given": ["Sarah"]}],
        "gender": "female", "birthDate": "1985-03-12"
      }
    },
    {
      "request": {"method": "PUT", "url": "/Coverage/test-coverage-001"},
      "resource": {
        "resourceType": "Coverage", "id": "test-coverage-001", "status": "active",
        "subscriberId": "SUB-001",
        "beneficiary": {"reference": "Patient/test-member-001"},
        "payor": [{"reference": "Organization/test-payer-001"}]
      }
    },
    {
      "request": {"method": "PUT", "url": "/Coverage/test-coverage-002"},
      "resource": {
        "resourceType": "Coverage", "id": "test-coverage-002", "status": "active",
        "subscriberId": "SUB-002",
        "beneficiary": {"reference": "Patient/test-member-002"},
        "payor": [{"reference": "Organization/test-payer-001"}]
      }
    },
    {
      "request": {"method": "PUT", "url": "/Consent/test-optout-member-002"},
      "resource": {
        "resourceType": "Consent", "id": "test-optout-member-002", "status": "active",
        "scope": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/consentscope", "code": "patient-privacy"}]},
        "patient": {"reference": "Patient/test-member-002"},
        "category": [{"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/pdex-consent-api-purpose", "code": "provider-access"}]}],
        "provision": {"type": "deny"},
        "policyRule": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "OPTIN"}]}
      }
    }
  ]
}
```

### 2. Kick off

Submit three members: one will match, one will hit the opt-out, one has no match.

```http
POST /fhir/Group/$provider-member-match
Content-Type: application/fhir+json
Prefer: respond-async
```

```json
{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "MemberBundle",
      "part": [
        {"name": "MemberPatient", "resource": {"resourceType": "Patient", "name": [{"family": "Johnson", "given": ["Robert"]}], "gender": "male", "birthDate": "1952-07-25"}},
        {"name": "CoverageToMatch", "resource": {"resourceType": "Coverage", "status": "active", "subscriberId": "SUB-001", "beneficiary": {"reference": "Patient/test-member-001"}, "payor": [{"reference": "Organization/test-payer-001"}]}},
        {"name": "Consent", "resource": {"resourceType": "Consent", "status": "active", "scope": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/consentscope", "code": "treatment"}]}, "category": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IDSCL"}]}, {"coding": [{"system": "http://loinc.org", "code": "64292-6"}]}], "patient": {"reference": "Patient/test-member-001"}, "dateTime": "2026-01-15T10:00:00Z", "performer": [{"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "1982947230"}}], "policyRule": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "OPTIN"}]}}}
      ]
    },
    {
      "name": "MemberBundle",
      "part": [
        {"name": "MemberPatient", "resource": {"resourceType": "Patient", "name": [{"family": "Williams", "given": ["Sarah"]}], "gender": "female", "birthDate": "1985-03-12"}},
        {"name": "CoverageToMatch", "resource": {"resourceType": "Coverage", "status": "active", "subscriberId": "SUB-002", "beneficiary": {"reference": "Patient/test-member-002"}, "payor": [{"reference": "Organization/test-payer-001"}]}},
        {"name": "Consent", "resource": {"resourceType": "Consent", "status": "active", "scope": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/consentscope", "code": "treatment"}]}, "category": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IDSCL"}]}, {"coding": [{"system": "http://loinc.org", "code": "64292-6"}]}], "patient": {"reference": "Patient/test-member-002"}, "dateTime": "2026-01-15T10:00:00Z", "performer": [{"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "1982947230"}}], "policyRule": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "OPTIN"}]}}}
      ]
    },
    {
      "name": "MemberBundle",
      "part": [
        {"name": "MemberPatient", "resource": {"resourceType": "Patient", "name": [{"family": "Unknown", "given": ["Nobody"]}], "gender": "male", "birthDate": "2000-01-01"}},
        {"name": "CoverageToMatch", "resource": {"resourceType": "Coverage", "status": "active", "subscriberId": "SUB-999", "beneficiary": {"reference": "Patient/test-member-001"}, "payor": [{"reference": "Organization/test-payer-001"}]}},
        {"name": "Consent", "resource": {"resourceType": "Consent", "status": "active", "scope": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/consentscope", "code": "treatment"}]}, "category": [{"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IDSCL"}]}, {"coding": [{"system": "http://loinc.org", "code": "64292-6"}]}], "patient": {"reference": "Patient/test-member-001"}, "dateTime": "2026-01-15T10:00:00Z", "performer": [{"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "1982947230"}}], "policyRule": {"coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "OPTIN"}]}}}
      ]
    }
  ]
}
```

Response: `202 Accepted`, `Content-Location: [base]/fhir/Group/$provider-member-match-status/<task-id>`.

### 3. Poll

Call the status URL until it returns `200 OK`.

```http
GET /fhir/Group/$provider-member-match-status/<task-id>
```

### 4. Download

Use the `output[0].url` from the manifest to fetch the ndjson.

```http
GET /output/<task-id>.ndjson
```

Expected result distribution:

| Member | Match | Opt-out | Bucket |
| --- | --- | --- | --- |
| Johnson, Robert | Yes (`test-member-001`) | No | `MatchedMembers` |
| Williams, Sarah | Yes (`test-member-002`) | Yes | `ConsentConstrainedMembers` |
| Unknown, Nobody | No | — | `NonMatchedMembers` |

## Limitations

The current implementation is intentionally MVP-scoped. The following items are recognized gaps versus the PDex 2.1 spec / production expectations:

| Area | Status |
| --- | --- |
| Matching algorithm | Deterministic exact match only (`family`, `given[0]`, `birthDate`, `gender`, optional `subscriberId`). No fuzzy / probabilistic matching, no confidence scoring, no multi-tier fall-through. |
| Opt-out scope enforcement | All opt-out scopes (`global`, `provider-specific`, `purpose-specific`, `payer-specific`, `provider-category`) are treated identically — any active `deny` constrains the match. Targeting the requesting provider's NPI for `provider-specific` opt-outs is not yet enforced. |
| Authentication hardening | UDAP B2B token validation, mTLS, and dynamic client registration are not implemented. The operation relies on whatever OAuth flow Aidbox is configured for. |
| Rate limiting | No throttling, no `429 Too Many Requests`, no per-client concurrency caps. |
| Treatment-relationship verification | Limited to `Consent.status = "active"` and presence of the resource. The attestation claim itself is not cross-checked against external sources. |
| Sandbox / interactive console | None — all examples are run against a real Aidbox instance. |

## What's next

After receiving a `MatchedMembers` Group, the provider uses its ID to call `$davinci-data-export` (FHIR Bulk Data group export) on the same Aidbox instance to retrieve the matched patients' clinical data as ndjson. Documentation for that operation will live alongside this page in the [Provider Access API](README.md) section.
