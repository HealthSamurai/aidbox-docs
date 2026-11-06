---
description: >-
  The Bundle resource is a container for a collection of resources and
  optionally additional info
---

# Bundle

{% hint style="info" %}
Please start [a discussion](https://github.com/Aidbox/Issues/discussions) or [contact](../../overview/contact-us.md) us if you have questions, feedback, or suggestions.
{% endhint %}

The Bundle resource is a resource which groups multiple resources in one. It is important to differentiate Bundle resource and operation which take or return Bundles.

Let's look at some operations working with Bundle resources.

* `POST /fhir`, `POST /`\
  Main article: [Transactions](../batch-transaction.md).\
  This operation accepts Bundle resource (with type batch or transaction); executes contained requests; then returns Bundle resource in response (with type batch-response or transaction-response).\
  Operation `POST /fhir` accepts and returns Bundle in FHIR format; operation `POST /` accepts and returns Bundle in Aidbox format.
* `GET /fhir/<resourceType>`, `GET /<resourceType>`\
  Main article: [fhir-search](./fhir-search/README.md)\
  This operation searches for resource of type `resourceType` using search parameters provided in query string, and returns Bundle resource (with type `searchset`) containing all resources matching the given filters.
* `GET /fhir/<resourceType>/<id>/_history`, `GET /<resourceType>/<id>/_history`\
  Main article: [history.md](./history.md)\
  This operation returns the Bundle resource (with type `history`) containing previous versions of the specified resource.
* CRUD operations with Bundle resource\
  Main article: [crud](./crud/README.md)\
  These are the usual FHIR CRUD operations with Bundle resource. They only store/update/get/search Bundle resources without additional semantics.\
  These operations are rarely used.\
  Examples: `POST /fhir/Bundle`, `GET /fhir/Bundle`, `GET /fhir/Bundle/<id>`,\
  `PUT /fhir/Bundle/<id>`, `POST /Bundle`, `GET /Bundle`, `GET /Bundle/<id>`, `PUT /Bundle`

See more about the difference between FHIR and Aidbox formats (`/fhir/...` and `/...` endpoints) in the [aidbox-and-fhir-formats.md](other/aidbox-and-fhir-formats.md) page.

{% hint style="info" %}
To turn off the Aidbox format API, set `BOX_FHIR_AIDBOX_FORMAT_API_ENABLED` to `false`. See [Turn off the Aidbox format API](other/aidbox-and-fhir-formats.md#turn-off-the-aidbox-format-api).
{% endhint %}

### `POST /fhir`, `POST /` endpoint

Aidbox supports FHIR batch and transaction interactions, as well as some additional options to this endpoint.

Same as with other endpoint, `POST /fhir` accepts and returns Bundle in FHIR format,\
while `POST /` accepts and returns Bundle in Aidbox format.

```yaml
POST /fhir
content-type: text/yaml
accept: text/yaml

resourceType: Bundle
type: <type>
...
```

Use the `Prefer` header to [control the response size](../batch-transaction.md#control-the-response-size) of a batch or transaction request.

Behavior of the endpoint depends on the `type` of a bundle resource provided in a request body.

Supported `type` values:

* `transaction`\
  Executes provided rest requests in a transaction.\
  In case of an entry execution error the whole transaction is rolled back and the error is returned in the response.\
  Returns `transaction-response` type bundle.
* `batch`\
  Executes provided rest requests, execution doesn't stop on error, all results and errors are returned in the response.\
  Returns `batch-response` type bundle.
* `collection`\
  Works the same way as the `batch` type, but does `PUT /<resourceType>/<id>` for each resource in entry.\
  Returns `batch-response` type bundle.

### Validate Bundle

To validate bundle without storing it content, use `Bundle/$validate` operation.

```json
POST /fhir/Bundle/$validate
content-type: application/json
accept: application/json

{
 "resourceType": "Bundle",
 "type": "message",
 // ...
}
```
