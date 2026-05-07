---
description: $provider-member-match operation reference — kick-off, polling, output, cancellation, and error responses for the PDex Provider Access member-match endpoint.
---

# $provider-member-match

`$provider-member-match` takes a batch of patient demographics, coverage, and a treatment-relationship attestation, and returns one or more `Group` resources. The provider then feeds the `MatchedMembers` Group ID into `$davinci-data-export` to pull the matched patients' clinical data in bulk.

The operation is always asynchronous. It follows the [FHIR Bulk Data async pattern](https://hl7.org/fhir/uv/bulkdata/export.html#bulk-data-kick-off-request) — see [Async and authorization](../async-and-auth.md) for the shared lifecycle and auth model. Per-member evaluation rules live in [Matching logic](../matching-logic.md).

{% hint style="warning" %}
`$provider-member-match` is **not** part of Aidbox core. It is delivered by the [Aidbox PDex / Provider Access interop app](https://github.com/HealthSamurai/interop), which registers itself as a FHIR `App`. The interop app must be running and the PDex 2.1 FHIR package (`hl7.fhir.us.davinci-pdex#2.1.0`) must be loaded — see [setup prerequisites](../README.md#setup-prerequisites).
{% endhint %}

{% hint style="warning" %}
Clients must include `Prefer: respond-async` on the kick-off request. Requests without it are rejected with `400 Bad Request`.
{% endhint %}

{% hint style="info" %}
**PDex 2.1 spec references**

* [OperationDefinition: PDex Provider-Member-Match](https://build.fhir.org/ig/HL7/davinci-epdx/OperationDefinition-ProviderMemberMatch.html)
* [Input profile](https://build.fhir.org/ig/HL7/davinci-epdx/StructureDefinition-provider-parameters-multi-member-match-bundle-in.html) and [output profile](https://build.fhir.org/ig/HL7/davinci-epdx/StructureDefinition-provider-parameters-multi-member-match-bundle-out.html)
* Output Group profiles: [pdex-treatment-relationship](https://build.fhir.org/ig/HL7/davinci-epdx/StructureDefinition-pdex-treatment-relationship.html), [pdex-member-no-match-group](https://build.fhir.org/ig/HL7/davinci-epdx/StructureDefinition-pdex-member-no-match-group.html), [pdex-member-opt-out](https://build.fhir.org/ig/HL7/davinci-epdx/StructureDefinition-pdex-member-opt-out.html)
{% endhint %}

## Endpoints

| Purpose | Method | URL |
| --- | --- | --- |
| Kick-off | `POST` | `[base]/fhir/Group/$provider-member-match` |
| Status / output | `GET` | `[base]/fhir/Group/$provider-member-match-status/<task-id>` |
| Cancel / delete | `DELETE` | `[base]/fhir/Group/$provider-member-match-cancel/<task-id>` |

## Authorization

Backend-services OAuth (`client_credentials`). The `Client` resource representing the provider must carry an NPI in `Client.identifier[*]` with `system = http://hl7.org/fhir/sid/us-npi`. Without it the provider is recorded as `"unknown"` on the output Group. Status and cancel URLs scope to the requesting client — Tasks created by another client return `404 Not Found`. Full details in [Async and authorization](../async-and-auth.md#authorization).

## Parameters

The request body is a FHIR `Parameters` resource with one or more `MemberBundle` parameters. Each `MemberBundle` carries:

| Part | Card. | Type | Profile |
| --- | --- | --- | --- |
| `MemberPatient` | 1..1 | Patient | [HRex Patient Demographics](http://hl7.org/fhir/us/davinci-hrex/STU1/StructureDefinition-hrex-patient-demographics.html) |
| `CoverageToMatch` | 1..1 | Coverage | [HRex Coverage](http://hl7.org/fhir/us/davinci-hrex/STU1/StructureDefinition-hrex-coverage.html) |
| `Consent` | 1..1 | Consent | [Provider Treatment Relationship Consent](http://hl7.org/fhir/us/davinci-pdex/STU2.1/StructureDefinition-provider-treatment-relationship-consent.html) |
| `CoverageToLink` | 0..1 | Coverage | HRex Coverage |

The body is validated with `$validate` against `provider-parameters-multi-member-match-bundle-in`. Validation failure returns `422 Unprocessable Entity` with the `OperationOutcome` from `$validate`, and no background job is created.

## Kick-off

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
            "birthDate": "1952-07-25"
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

{% tab title="Response (202)" %}
**Status**

202 Accepted

**Headers**

| Header | Value |
| --- | --- |
| Content-Location | `[base]/fhir/Group/$provider-member-match-status/<task-id>` |
{% endtab %}

{% tab title="Response (400)" %}
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

{% tab title="Response (422)" %}
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
{% endtabs %}

## Status polling

```
GET [base]/fhir/Group/$provider-member-match-status/<task-id>
```

| `Task.status` | HTTP | Headers | Body |
| --- | --- | --- | --- |
| `requested` | 202 | `Retry-After: 5` | — |
| `in-progress` | 202 | `Retry-After: 5`, `X-Progress: Processing members` | — |
| `completed` | 200 | `Content-Type: application/json` | Bulk Data manifest |
| `failed` | 500 | — | `OperationOutcome` |
| not found | 404 | — | `OperationOutcome` |

{% tabs %}
{% tab title="In progress" %}
**Status**

202 Accepted

**Headers**

| Header | Value |
| --- | --- |
| Retry-After | `5` |
| X-Progress | `Processing members` |
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

```
GET [base]/output/<task-id>.ndjson
```

The body is a single ndjson line — a `Parameters` resource conforming to `provider-parameters-multi-member-match-bundle-out`. Each non-empty bucket appears as one parameter with the full `Group` inline; empty buckets are omitted.

| Bucket | Code | Profile |
| --- | --- | --- |
| `MatchedMembers` | `match` | `pdex-treatment-relationship` |
| `NonMatchedMembers` | `nomatch` | `pdex-member-no-match-group` |
| `ConsentConstrainedMembers` | `consentconstraint` | `pdex-member-opt-out` |

Group field semantics (managing entity, member references, contained payloads for unmatched submissions, validity period) are documented in [Matching logic — Output Group fields](../matching-logic.md#output-group-fields).

{% tabs %}
{% tab title="Request" %}
```http
GET /output/<task-id>.ndjson
```
{% endtab %}

{% tab title="Response (matched only)" %}
**Status**

200 OK

**Headers**

| Header | Value |
| --- | --- |
| Content-Type | `application/fhir+ndjson` |

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
    }
  ]
}
```
{% endtab %}

{% tab title="Response (no match)" %}
**Status**

200 OK

**Body**

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

{% tab title="Response (opt-out)" %}
**Status**

200 OK

**Body**

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
    }
  ]
}
```
{% endtab %}

{% tab title="Response (full distribution)" %}
**Status**

200 OK

**Body** — one input member per bucket: matched, opted out, no match.

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
        "meta": {"profile": ["http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-treatment-relationship"]},
        "active": true, "type": "person", "actual": true,
        "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "match"}]},
        "identifier": [{"system": "http://hl7.org/fhir/sid/us-npi", "value": "1982947230"}],
        "managingEntity": {"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"}, "display": "Payer Organization"},
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "match"}]},
          "valueReference": {"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "1982947230"}, "display": "Provider Organization"},
          "exclude": false,
          "period": {"start": "2026-04-20", "end": "2026-05-20"}
        }],
        "quantity": 1,
        "member": [{"entity": {"reference": "Patient/test-member-001", "display": "Johnson, Robert"}, "inactive": false}]
      }
    },
    {
      "name": "ConsentConstrainedMembers",
      "resource": {
        "resourceType": "Group",
        "id": "<task-id>-consent",
        "meta": {"profile": ["http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-member-opt-out"]},
        "active": true, "type": "person", "actual": true,
        "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "consentconstraint"}]},
        "managingEntity": {"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"}, "display": "Payer Organization"},
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "consentconstraint"}]},
          "valueCodeableConcept": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/opt-out-scope", "code": "provider-specific"}]},
          "exclude": false,
          "period": {"start": "2026-04-20", "end": "2026-05-20"}
        }],
        "quantity": 1,
        "member": [{"entity": {"reference": "Patient/test-member-002", "display": "Williams, Sarah"}, "inactive": false}]
      }
    },
    {
      "name": "NonMatchedMembers",
      "resource": {
        "resourceType": "Group",
        "id": "<task-id>-nomatch",
        "meta": {"profile": ["http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-member-no-match-group"]},
        "active": true, "type": "person", "actual": true,
        "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "nomatch"}]},
        "contained": [{"resourceType": "Patient", "id": "1", "name": [{"family": "Unknown", "given": ["Nobody"]}], "gender": "male", "birthDate": "2000-01-01"}],
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "nomatch"}]},
          "valueBoolean": true,
          "exclude": false,
          "period": {"start": "2026-04-20", "end": "2026-05-20"}
        }],
        "quantity": 1,
        "member": [{
          "entity": {
            "reference": "#1",
            "extension": [{"url": "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/base-ext-match-parameters", "valueReference": {"reference": "#1"}}]
          },
          "inactive": false
        }]
      }
    }
  ]
}
```
{% endtab %}
{% endtabs %}

## Cancellation

```
DELETE [base]/fhir/Group/$provider-member-match-cancel/<task-id>
```

| `Task.status` | Action | Response |
| --- | --- | --- |
| `requested` / `in-progress` | Set Task to `cancelled`. Background processor stops at next checkpoint. | 202 Accepted |
| `completed` / `failed` / `cancelled` | Delete the Task and every resource referenced from `Task.output`. | 202 Accepted |
| not found | — | 404 `OperationOutcome` |

## Error responses

| Status | Condition |
| --- | --- |
| 400 | `Prefer: respond-async` header missing. |
| 404 | Unknown `<task-id>` on status, output, or cancel — or Task belongs to a different client. |
| 422 | Input `Parameters` failed profile validation. |
| 500 | Background processing failed; `OperationOutcome.diagnostics` reports a generic message. |

Per-member failures (validation issues, exceptions during evaluation) do not fail the whole batch — the affected members are routed to `NonMatchedMembers`.

## Limitations

| Area | Status |
| --- | --- |
| Matching algorithm | Exact match only on `family`, `given[0]`, `birthDate`, `gender`, optional `subscriberId`. No fuzzy or probabilistic matching, no confidence scoring. |
| Opt-out scopes | Every scope (`global`, `provider-specific`, `purpose-specific`, `payer-specific`, `provider-category`) is treated identically — any active `deny` constrains the match. |
| UDAP B2B | Not implemented. The operation relies on whatever OAuth flow Aidbox is configured for. |
| Rate limiting | Not enforced — no throttling, no `429`, no per-client concurrency caps. |
| Treatment-relationship verification | Limited to `Consent.status = "active"` and resource presence. The attestation claim is not cross-checked against external sources. |

## Related

* [Matching logic](../matching-logic.md) — algorithm, attestation, opt-out, output Group fields.
* [Async and authorization](../async-and-auth.md) — lifecycle, NPI client setup, cross-tenant rules.
* [Provider Access API overview](../README.md) — setup prerequisites and sibling operations.
