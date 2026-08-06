---
description: Read and write FHIR Binary resources as JSON or as raw binary content on the /fhir/Binary endpoints.
---

# Binary resource

{% hint style="info" %}
This functionality is available starting from Aidbox version **2608**.
{% endhint %}

The FHIR [Binary](https://www.hl7.org/fhir/binary.html) resource carries raw content such as documents and images: a `contentType` and the base64-encoded `data`. Aidbox follows the [FHIR rules for handling Binary resources over REST](https://www.hl7.org/fhir/binary.html#rest): the same endpoint returns the resource as JSON or as the decoded content, and accepts raw uploads without a JSON wrapper.

## Create and update

`POST /fhir/Binary` and `PUT /fhir/Binary/{id}` accept two kinds of body:

* A Binary resource as JSON (`Content-Type: application/fhir+json`, `application/json`, or `json`): a regular create or update.
* Any other content type: Aidbox builds the Binary itself. `contentType` comes from the `Content-Type` header and the body bytes go base64-encoded into `data`.

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/Binary
Content-Type: application/octet-stream

hello world
```
{% endtab %}

{% tab title="Response" %}
```json
{
  "resourceType": "Binary",
  "id": "b9f7a86e-16a5-45f5-8b1c-3e2a90c31c02",
  "contentType": "application/octet-stream",
  "data": "aGVsbG8gd29ybGQ="
}
```
{% endtab %}
{% endtabs %}

A JSON body without `"resourceType": "Binary"` is stored as binary content too: the JSON text becomes `data` and the request content type becomes `contentType`.

With `Prefer: return=minimal`, Aidbox returns an empty body with the `Location` header.

## Read

`GET /fhir/Binary/{id}` returns the decoded content when the `Accept` header contains the type stored in `Binary.contentType`. Aidbox decodes `data` and responds with the bytes under that content type:

{% tabs %}
{% tab title="Request" %}
```http
GET /fhir/Binary/b9f7a86e-16a5-45f5-8b1c-3e2a90c31c02
Accept: application/octet-stream
```
{% endtab %}

{% tab title="Response" %}
```
hello world
```
{% endtab %}
{% endtabs %}

The JSON content types are the one exception. When `Accept` contains `application/fhir+json` (or `application/json` and `json`, which Aidbox keeps for backward compatibility), Aidbox returns the Binary resource itself as FHIR JSON with base64 `data`, whatever `Binary.contentType` holds. A request without an `Accept` header gets the resource as well.

Any other `Accept` value gets `406` with an `OperationOutcome`.

The `_format` query parameter overrides `Accept` and takes the same values. When `_format` names a non-JSON content type that differs from `Binary.contentType`, Aidbox responds with `422`.

Version read, `GET /fhir/Binary/{id}/_history/{vid}`, negotiates the same way and serves the content of the requested version.

## Data offload

`Binary.data` can live in external blob storage instead of PostgreSQL, with reads, including raw reads, working unchanged:

{% content-ref %}
[Offload base64Binary data to external storage](../../../configuration/storage-and-api-configuration/offload-base64binary-to-external-storage.md)
{% endcontent-ref %}
