---
description: Async lifecycle and authorization model shared by Payer-to-Payer Access API operations — Prefer header, polling, NPI-bearing OAuth client, AccessPolicy, tenant isolation.
---

# Async and authorization

Every Payer-to-Payer Access operation follows the same async pattern and authorizes the same way. This page documents both once, so individual operation pages can stay short.

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

The `failed` body's `diagnostics` is redacted to `"Internal error processing request"`. Specific exception text is never exposed to clients — it could leak hostnames, SQL fragments, or PHI to a different payer organization. Operators read the underlying reason from structured logs.

A transient lookup failure (transport error, Aidbox 5xx) on the status or cancel endpoint surfaces as a retryable `503` rather than `404`. Only a tombstoned Task returns `404`. Clients can therefore distinguish "go away" from "try again."

### Cancellation

Cancellation is cooperative. The background worker checks Task status before starting, after each evaluated member, and again before persisting results. A cancelled job stops at the next checkpoint and never writes Groups or Binary.

| Task status | Action | Response |
| --- | --- | --- |
| `requested` / `in-progress` | Set Task to `cancelled`. | 202 Accepted |
| `completed` / `failed` / `cancelled` | Delete the Task and every resource referenced from `Task.output`, plus every persisted `Consent` written by the worker. | 202 Accepted |
| not found | — | 404 `OperationOutcome` |

The cancel sweep includes persisted Consent ids alongside Group and Binary outputs. `$davinci-data-export` is therefore guaranteed never to see Consent rows from a cancelled or failed Task.

{% hint style="info" %}
Cancellation uses a dedicated `*-cancel` URL rather than `DELETE` on the status URL because Aidbox operation dispatch is keyed on HTTP method plus URL — distinct combinations must be registered separately.
{% endhint %}

## Authorization

Payer-to-Payer is a backend-services API: callers are payer organizations, not end users. Aidbox issues a token via SMART [Backend Services / `client_credentials`](https://www.hl7.org/fhir/smart-app-launch/backend-services.html) and forwards the resolved `oauth/client` to the interop app.

| Concern | Requirement |
| --- | --- |
| Auth flow | OAuth 2.0 `client_credentials`. The bearer token is presented to Aidbox; Aidbox forwards the resolved `oauth/client` to the interop app over HTTP-RPC. |
| Requesting payer identity | The `Client` resource representing the requesting payer must carry an NPI under `Client.details.identifier` (system `http://hl7.org/fhir/sid/us-npi`). Aidbox's `Client` schema rejects a top-level `identifier` field — payer metadata lives under `details`. The interop app stamps this NPI on `Task.requester.identifier` and on every output Group's `characteristic.valueReference`. |
| NPI-less client | A `client_credentials` token whose `Client` does not carry an NPI is rejected with `403 Forbidden` at kick-off. No soft-routing — without an NPI we cannot resolve a requesting-payer Organization or persist Consent under a stable join key. |
| Organization seeding | An `Organization` carrying the same NPI must already exist in Aidbox. Persistence keys on its id (`Consent.organization`) and the matched Group's `characteristic.valueReference.reference` resolves to it. |
| Aidbox access | The interop app needs read access to `Patient`, `Coverage`, `Consent`, `Organization` and read/write access to `Task`, `Group`, `Binary`, `Consent`. Granting its `App` resource an `AccessPolicy` over those types is enough. |
| App registration | The interop app must be running and registered as a FHIR `App`. Without it, `POST /fhir/Group/$bulk-member-match` falls back to Aidbox's default "operation not found" response. |

### Tenant isolation

Status, output, and cancel URLs scope to the requesting client. The interop app compares the caller's OAuth-client NPI against `Task.requester.identifier.value`; a mismatch returns `404 Not Found` rather than `403 Forbidden` — existence of a Task is not disclosed across payer tenants. The check is a no-op for Tasks created before NPI stamping was introduced.

## Limitations

* **No separate match/export tokens.** PDex P2P §6.3 SHALLs separate OAuth scopes for `$bulk-member-match` and `$davinci-data-export`. A single bearer-token check is enforced today; scope-token discrimination is deferred.
* **No `SEARCH /Group` access policy** restricting payers to their own Groups. The `characteristic.valueReference` carries the NPI and (when resolved) the literal Organization reference so a future AccessPolicy can filter on either key.
* **No UDAP B2B / DCRP onboarding.** Manual admin client registration only.
* **No rate limiting**, throttling, or per-client concurrency caps. Brute-force protection — required by HRex single-match, silent in the bulk spec — is delegated to the gateway or auth layer.
