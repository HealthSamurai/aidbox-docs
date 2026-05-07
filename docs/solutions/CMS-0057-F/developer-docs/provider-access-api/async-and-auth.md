---
description: Async lifecycle and authorization model shared by Provider Access API operations — Prefer header, polling, NPI-bearing OAuth client, AccessPolicy, error mapping.
---

# Async and authorization

Every Provider Access operation follows the same async pattern and authorizes the same way. This page documents both once, so individual operation pages can stay short.

## Async lifecycle

The flow follows the [FHIR Bulk Data async pattern](https://hl7.org/fhir/uv/bulkdata/export.html#bulk-data-kick-off-request).

{% stepper %}
{% step %}
**Kick-off.** `POST` the operation endpoint with `Prefer: respond-async`. The server replies `202 Accepted` and a `Content-Location` header pointing at the status URL.

A request without `Prefer: respond-async` is rejected with `400 Bad Request`.
{% endstep %}

{% step %}
**Poll.** `GET` the status URL until it returns `200 OK`. While processing is running it returns `202 Accepted` with `Retry-After: 5` and (once work has started) `X-Progress: Processing members`.
{% endstep %}

{% step %}
**Download.** Fetch the ndjson URL from the manifest's `output[0].url`. The body is a single line — a `Parameters` resource with the output Groups inline.
{% endstep %}

{% step %}
**Cancel or delete.** `DELETE` the cancel URL to stop a running job or clean up a completed one.
{% endstep %}
{% endstepper %}

The operation tracks progress with a standard FHIR `Task`. Status maps to HTTP as follows:

| `Task.status` | HTTP | Headers | Body |
| --- | --- | --- | --- |
| `requested` | 202 | `Retry-After: 5` | — |
| `in-progress` | 202 | `Retry-After: 5`, `X-Progress: Processing members` | — |
| `completed` | 200 | `Content-Type: application/json` | Bulk Data manifest |
| `failed` | 500 | — | `OperationOutcome` |
| not found | 404 | — | `OperationOutcome` |

The `failed` body's `diagnostics` reports a generic message; specific reasons are not exposed to clients.

### Cancellation

Cancellation is cooperative. The background worker checks Task status before starting, after each evaluated member, and again before persisting results. A cancelled job stops at the next checkpoint and never writes Groups or Binary.

| Task status | Action | Response |
| --- | --- | --- |
| `requested` / `in-progress` | Set Task to `cancelled`. | 202 Accepted |
| `completed` / `failed` / `cancelled` | Delete the Task and every resource referenced from `Task.output`. | 202 Accepted |
| not found | — | 404 `OperationOutcome` |

{% hint style="info" %}
Cancellation uses a dedicated `*-cancel` URL rather than `DELETE` on the status URL because Aidbox operation dispatch is keyed on HTTP method plus URL — distinct combinations must be registered separately.
{% endhint %}

## Authorization

Provider Access is a backend-services API: callers are provider organizations, not end users. Aidbox issues a token via SMART [Backend Services / `client_credentials`](https://www.hl7.org/fhir/smart-app-launch/backend-services.html) and forwards the resolved `oauth/client` to the interop app.

| Concern | Requirement |
| --- | --- |
| Auth flow | OAuth 2.0 `client_credentials`. The bearer token is presented to Aidbox; Aidbox forwards the resolved `oauth/client` to the interop app over HTTP-RPC. |
| Provider identity | The `Client` resource representing the provider must carry an NPI in `Client.identifier[*]` with `system = http://hl7.org/fhir/sid/us-npi`. The interop app stamps this NPI on `Task.requester` and on the `MatchedMembers` Group. Without it, the provider is recorded as `"unknown"`. |
| Aidbox access | The interop app needs read access to `Patient`, `Coverage`, `Consent`, `Organization` and read/write access to `Task`, `Group`, `Binary`. Granting its `App` resource an `AccessPolicy` over those types is enough. |
| App registration | The interop app must be running and registered as a FHIR `App`. Without it, `POST /fhir/Group/$provider-member-match` falls back to Aidbox's default "operation not found" response. |

### Tenant isolation

Status, output, and cancel URLs scope to the requesting client. Tasks created by another client return `404 Not Found` rather than `403 Forbidden` — existence of a Task is not disclosed across tenants.

## Limitations

UDAP B2B token validation, mTLS, and dynamic client registration are not implemented. The operation relies on whatever OAuth flow Aidbox is configured for. Rate limiting, throttling, and per-client concurrency caps are also not enforced.
