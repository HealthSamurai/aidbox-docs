---
description: $bulk-member-match operation reference — kick-off, polling, output, cancellation, and error responses for the PDex Payer-to-Payer bulk member-match endpoint.
---

# $bulk-member-match

`$bulk-member-match` takes a batch of patient demographics, coverage, and an HRex `Consent` proving member opt-in, then returns three `Group` resources covering matched members, members the prior payer could not match, and members whose consent did not authorize the share. The requesting payer feeds the `MatchedMembers` Group ID into `$davinci-data-export` to pull the matched patients' clinical history in bulk.

The operation is always asynchronous. It follows the [FHIR Bulk Data async pattern](https://hl7.org/fhir/uv/bulkdata/export.html#bulk-data-kick-off-request) — see [Async and authorization](../async-and-auth.md) for the shared lifecycle and auth model. Per-member evaluation rules, opt-in consent decision tree, and consent persistence semantics live in [Matching logic](../matching-logic.md).

`$bulk-member-match` is the **Payer-to-Payer** counterpart of [`$provider-member-match`](../../provider-access-api/operations/provider-member-match.md). They share the matching algorithm and async lifecycle. Key differences: opt-in member consent vs provider attestation, mandatory consent persistence, distinct output Group profiles. See [Differences from $provider-member-match](../matching-logic.md#differences-from-provider-member-match) for the full list.

{% hint style="warning" %}
`$bulk-member-match` is **not** part of Aidbox core. It is delivered by the [Aidbox PDex / Provider Access interop app](https://github.com/HealthSamurai/interop), which registers itself as a FHIR `App`. The interop app must be running and the PDex 2.2 FHIR package (`hl7.fhir.us.davinci-pdex#2.2.0`) must be loaded — see [setup prerequisites](../README.md#setup-prerequisites). Aidbox's default bootstrap predates this operation; bump `BOX_BOOTSTRAP_FHIR_PACKAGES` first.
{% endhint %}

{% hint style="warning" %}
Clients must include `Prefer: respond-async` on the kick-off request. Requests without it are rejected with `400 Bad Request`.
{% endhint %}

{% hint style="info" %}
**PDex P2P spec references**

* [OperationDefinition: PDex Bulk Member Match](https://hl7.org/fhir/us/davinci-pdex/OperationDefinition-BulkMemberMatch.html)
* [Input profile](https://hl7.org/fhir/us/davinci-pdex/StructureDefinition-pdex-parameters-multi-member-match-bundle-in.html) and [output profile](https://hl7.org/fhir/us/davinci-pdex/StructureDefinition-pdex-parameters-multi-member-match-bundle-out.html)
* Output Group profiles: [pdex-member-match-group](https://hl7.org/fhir/us/davinci-pdex/StructureDefinition-pdex-member-match-group.html), [pdex-member-no-match-group](https://hl7.org/fhir/us/davinci-pdex/StructureDefinition-pdex-member-no-match-group.html)
* Narrative: [Payer-to-Payer Bulk Exchange](https://hl7.org/fhir/us/davinci-pdex/payertopayerbulkexchange.html)
* Consent profile: [HRex Consent](https://hl7.org/fhir/us/davinci-hrex/StructureDefinition-hrex-consent.html)
{% endhint %}

## Endpoints

| Purpose | Method | URL |
| --- | --- | --- |
| Kick-off | `POST` | `[base]/fhir/Group/$bulk-member-match` |
| Status / output | `GET` | `[base]/fhir/Group/$bulk-member-match-status/<task-id>` |
| Cancel / delete | `DELETE` | `[base]/fhir/Group/$bulk-member-match-cancel/<task-id>` |

## Authorization

Backend-services OAuth (`client_credentials`). The `Client` representing the requesting payer must carry an NPI under `Client.details.identifier` with `system = http://hl7.org/fhir/sid/us-npi`; Aidbox rejects top-level `Client.identifier`. A token whose Client lacks an NPI is rejected at kick-off with `403 Forbidden` — no soft-routing. Status and cancel URLs scope to the requesting client by NPI; Tasks created by another payer return `404 Not Found` rather than `403`. Full details in [Async and authorization](../async-and-auth.md#authorization).

## Parameters

The request body is a FHIR `Parameters` resource with one or more `MemberBundle` parameters. Each `MemberBundle` carries:

| Part | Card. | Type | Profile |
| --- | --- | --- | --- |
| `MemberPatient` | 1..1 | Patient | [HRex Patient Demographics](https://hl7.org/fhir/us/davinci-hrex/StructureDefinition-hrex-patient-demographics.html) |
| `CoverageToMatch` | 1..1 | Coverage | [HRex Coverage](https://hl7.org/fhir/us/davinci-hrex/StructureDefinition-hrex-coverage.html) |
| `Consent` | 1..1 | Consent | [HRex Consent](https://hl7.org/fhir/us/davinci-hrex/StructureDefinition-hrex-consent.html) (opt-in, mandatory) |
| `CoverageToLink` | 0..1 | Coverage | HRex Coverage |

The body is validated with `$validate` against `pdex-parameters-multi-member-match-bundle-in`. Validation failure returns `422 Unprocessable Entity` with the `OperationOutcome` from `$validate`, and no background job is created. `$validate` runs **before** the requesting-payer Organization lookup, so a transient lookup failure cannot mask a deterministic 422.

## Kick-off

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/Group/$bulk-member-match
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
            "beneficiary": {"reference": "Patient/test-member-001"},
            "payor": [{"reference": "Organization/test-payer"}]
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
                "code": "patient-privacy"
              }]
            },
            "category": [{
              "coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code": "IDSCL"}]
            }],
            "patient": {"reference": "Patient/test-member-001"},
            "dateTime": "2026-04-01T08:00:00Z",
            "performer": [{"reference": "Organization/test-payer"}],
            "policy": [{
              "uri": "http://hl7.org/fhir/us/davinci-hrex/StructureDefinition-hrex-consent.html#sensitive"
            }],
            "provision": {
              "type": "permit",
              "period": {"start": "2026-01-01T00:00:00Z", "end": "2027-01-01T00:00:00Z"},
              "actor": [{
                "role": {
                  "coding": [{"system": "http://terminology.hl7.org/CodeSystem/v3-ParticipationType", "code": "IRCP"}]
                },
                "reference": {"reference": "Organization/test-payer"}
              }]
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
| Content-Location | `[base]/fhir/Group/$bulk-member-match-status/<task-id>` |
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

{% tab title="Response (403)" %}
**Status**

403 Forbidden

**Body**

Returned when the OAuth client has no NPI under `Client.details.identifier`.

```json
{
  "resourceType": "OperationOutcome",
  "issue": [
    {
      "severity": "error",
      "code": "forbidden",
      "diagnostics": "Requesting payer Client must carry an NPI identifier"
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
GET [base]/fhir/Group/$bulk-member-match-status/<task-id>
```

| `Task.status` | HTTP | Headers | Body |
| --- | --- | --- | --- |
| `requested` | 202 | `Retry-After: 5` | — |
| `in-progress` | 202 | `Retry-After: 5`, `X-Progress: Processing members` | — |
| `completed` | 200 | `Content-Type: application/json` | Bulk Data manifest |
| `failed` | 500 | — | `OperationOutcome` (redacted diagnostics) |
| not found | 404 | — | `OperationOutcome` |

Transient lookup failures (transport error, Aidbox 5xx) surface as `503` retryable rather than `404`. Only a tombstoned Task returns `404`.

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
  "transactionTime": "2026-05-05T17:34:40.300Z",
  "request": "[base]/fhir/Group/$bulk-member-match",
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
      "diagnostics": "Internal error processing request"
    }
  ]
}
```

The `diagnostics` is always redacted to a generic message; specific exception text is not exposed to the requester.
{% endtab %}
{% endtabs %}

## Output

```
GET [base]/output/<task-id>.ndjson
```

The body is a single ndjson line — a `Parameters` resource conforming to `pdex-parameters-multi-member-match-bundle-out`. `MatchedMembers` is **always emitted** (`1..1` cardinality on the wrapper profile); the other two buckets appear only when non-empty.

| Bucket | Card. | Code | Profile |
| --- | --- | --- | --- |
| `MatchedMembers` | 1..1 | `match` | `pdex-member-match-group` |
| `NonMatchedMembers` | 0..1 | `nomatch` | `pdex-member-no-match-group` |
| `ConsentConstrainedMembers` | 0..1 | `consentconstraint` | `pdex-member-no-match-group` |

`ConsentConstrainedMembers` and `NonMatchedMembers` share the same profile and differ only by code — see [Matching logic — Output buckets](../matching-logic.md#output-buckets) for the IG-asymmetry callout. Group field semantics (managing entity, member references, contained payloads for unmatched submissions, persisted-Consent join keys) are documented in [Matching logic — Output Group fields](../matching-logic.md#output-group-fields).

For every member in `MatchedMembers`, the server has already persisted the submitted HRex `Consent` at `Consent/sha1("${payer-org-id}|${patient-id}")`. `$davinci-data-export` reads that record at export time. See [Consent persistence](../matching-logic.md#consent-persistence).

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
      "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-parameters-multi-member-match-bundle-out"
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
            "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-member-match-group"
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
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "match"}]},
          "valueReference": {
            "identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"},
            "reference": "Organization/test-payer"
          },
          "exclude": false
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
      "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-parameters-multi-member-match-bundle-out"
    ]
  },
  "parameter": [
    {
      "name": "MatchedMembers",
      "resource": {
        "resourceType": "Group",
        "id": "<task-id>-matched",
        "meta": {"profile": ["http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-member-match-group"]},
        "active": true, "type": "person", "actual": true,
        "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "match"}]},
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "match"}]},
          "valueReference": {"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"}, "reference": "Organization/test-payer"},
          "exclude": false
        }],
        "quantity": 0
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
        "contained": [{
          "resourceType": "Patient", "id": "1",
          "name": [{"family": "Unknown", "given": ["Nobody"]}], "gender": "male", "birthDate": "2000-01-01"
        }],
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "nomatch"}]},
          "valueBoolean": true,
          "exclude": false
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

{% tab title="Response (consent-constrained)" %}
**Status**

200 OK

**Body**

```json
{
  "resourceType": "Parameters",
  "meta": {
    "profile": [
      "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-parameters-multi-member-match-bundle-out"
    ]
  },
  "parameter": [
    {
      "name": "MatchedMembers",
      "resource": {
        "resourceType": "Group",
        "id": "<task-id>-matched",
        "meta": {"profile": ["http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-member-match-group"]},
        "active": true, "type": "person", "actual": true,
        "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "match"}]},
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "match"}]},
          "valueReference": {"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"}, "reference": "Organization/test-payer"},
          "exclude": false
        }],
        "quantity": 0
      }
    },
    {
      "name": "ConsentConstrainedMembers",
      "resource": {
        "resourceType": "Group",
        "id": "<task-id>-consent",
        "meta": {"profile": ["http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-member-no-match-group"]},
        "active": true, "type": "person", "actual": true,
        "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "consentconstraint"}]},
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "consentconstraint"}]},
          "valueReference": {"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"}, "reference": "Organization/test-payer"},
          "exclude": false
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

**Body** — one input member per bucket: matched, consent-constrained, no match.

```json
{
  "resourceType": "Parameters",
  "meta": {
    "profile": [
      "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-parameters-multi-member-match-bundle-out"
    ]
  },
  "parameter": [
    {
      "name": "MatchedMembers",
      "resource": {
        "resourceType": "Group",
        "id": "<task-id>-matched",
        "meta": {"profile": ["http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-member-match-group"]},
        "active": true, "type": "person", "actual": true,
        "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "match"}]},
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "match"}]},
          "valueReference": {"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"}, "reference": "Organization/test-payer"},
          "exclude": false
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
        "meta": {"profile": ["http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-member-no-match-group"]},
        "active": true, "type": "person", "actual": true,
        "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "consentconstraint"}]},
        "characteristic": [{
          "code": {"coding": [{"system": "http://hl7.org/fhir/us/davinci-pdex/CodeSystem/PdexMultiMemberMatchResultCS", "code": "consentconstraint"}]},
          "valueReference": {"identifier": {"system": "http://hl7.org/fhir/sid/us-npi", "value": "5555555555"}, "reference": "Organization/test-payer"},
          "exclude": false
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
          "exclude": false
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
DELETE [base]/fhir/Group/$bulk-member-match-cancel/<task-id>
```

| `Task.status` | Action | Response |
| --- | --- | --- |
| `requested` / `in-progress` | Set Task to `cancelled`. Background processor stops at next checkpoint. | 202 Accepted |
| `completed` / `failed` / `cancelled` | Delete the Task, every resource referenced from `Task.output`, and every `Consent` persisted by the worker. | 202 Accepted |
| not found | — | 404 `OperationOutcome` |

The cancel sweep removes persisted Consent rows alongside Group and Binary outputs, so `$davinci-data-export` will not see Consents under cancelled or failed Tasks. See [Cancellation](../async-and-auth.md#cancellation).

## Error responses

| Status | Condition |
| --- | --- |
| 400 | `Prefer: respond-async` header missing. |
| 403 | OAuth client has no NPI under `Client.details.identifier`. |
| 404 | Unknown `<task-id>` on status, output, or cancel — or the Task belongs to a different payer (NPI mismatch). |
| 422 | Input `Parameters` failed profile validation. |
| 500 | Background processing failed; `OperationOutcome.diagnostics` reports a generic message. |
| 503 | Transient lookup failure (transport error or Aidbox 5xx) on status / cancel — retry. |

Per-member failures (validation issues, exceptions during evaluation, persistence errors) do not fail the whole batch — the affected members are routed to `NonMatchedMembers` (match-time failure) or `ConsentConstrainedMembers` (post-match failure).

## Limitations

| Area | Status |
| --- | --- |
| Matching algorithm | Exact match only on `family`, `given[0]`, `birthDate`, `gender`, optional `subscriberId`, optional `Patient.identifier` (AND-token semantics). No fuzzy or probabilistic matching, no confidence scoring. |
| Sensitive-data segmentation | Not implemented. `Consent.policy[].uri = #regular` (non-sensitive only) is treated as `ConsentConstrainedMembers` per REQ-P2P-2.7 fallback. |
| Group lifecycle | `Group.active = true` at creation; 7-day TTL not yet enforced. Groups stay active until cancellation or manual deletion. |
| Match/export OAuth scopes | Single bearer-token check today. PDex P2P §6.3 SHALLs separate scopes for match and export — deferred. |
| `SEARCH /Group` access policy | Not enforced. `characteristic.valueReference` carries NPI + Organization reference so a future AccessPolicy can filter by either key. |
| UDAP B2B | Not implemented. The operation relies on whatever OAuth flow Aidbox is configured for. |
| Rate limiting | Not enforced — no throttling, no `429`, no per-client concurrency caps, no brute-force protection at the operation layer. |
| Provider-access opt-out reuse | The recently-opted-out check uses the same `Consent.category = provider-access` deny pattern as `$provider-member-match`. Single member-managed opt-out covers both APIs. |

## Related

* [Matching logic](../matching-logic.md) — algorithm, opt-in consent decision tree, persistence, output Group fields.
* [Async and authorization](../async-and-auth.md) — lifecycle, NPI Client setup, cross-tenant rules.
* [Payer-to-Payer API overview](../README.md) — setup prerequisites and sibling operations.
* [`$provider-member-match`](../../provider-access-api/operations/provider-member-match.md) — Provider Access counterpart with opt-out attestation.
