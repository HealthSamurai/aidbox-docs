---
description: Partially update FHIR resources using Merge Patch, JSON Patch, or FHIRPath Patch operations in Aidbox.
---

# Patch

In most Operations in FHIR, you manipulate a resource as a whole (create, update, delete operations). But sometimes you want to update specific data elements in a resource and do not care about the rest. In other words, you need an element/attribute level operation.

With the `patch` operation, you can update a part of a resource by sending a declarative description of operations that should be performed on an existing resource. To describe these operations in Aidbox, you can use different notations (methods):

* Merge Patch — simple merge semantics ([read more in RFC](https://tools.ietf.org/html/rfc7386));
* JSON Patch — advanced JSON transformation ([read more in RFC](https://tools.ietf.org/html/rfc6902));
* [FHIRPath Patch](https://www.hl7.org/fhir/fhirpatch.html) — JSON patch with [FHIRPath](https://www.hl7.org/fhir/fhirpatch.html) (since version 2503).

### Patch Method

You can specify a `patch` method by the `content-type` header or by the `_method` parameter.

| method             | parameter        | header                       |
| ------------------ | ---------------- | ---------------------------- |
| **json-patch**     | `json-patch`     | application/json-patch+json  |
| **merge-patch**    | `merge-patch`    | application/merge-patch+json |
| **fhirpath-patch** | `fhirpath-patch` | -                            |

If the method is not specified, Aidbox will try to guess it by the following algorithm:

* if the body contains "Parameters" resourceType, it is `fhirpath-patch`
* if the payload is an array, it is `json-patch`&#x20;
* else `merge-patch`

### Binary JSON-patch

Since version 2503, It is also possible to [encode JSON patches using base64 Binary.data](https://www.hl7.org/fhir/http.html#jsonpatch-transaction):

```
PATCH /fhir/Patient/1?_method=json-patch
content-type: application/json
accept: application/json

{
  "resourceType": "Binary",
  "contentType": "application/json-patch+json",
  "data": "WyB7ICJvcCI6InJlcGxhY2UiLCAicGF0aCI6Ii9hY3RpdmUiLCAidmFsdWUiOmZhbHNlIH0gXQ=="
}
```

### Events and subscriptions

A PATCH request that changes a resource triggers the same resource lifecycle events as a `PUT`. Any subscriptions or topic-based notification channels listening for resource updates will receive notifications as expected.

If the patch produces no actual change to the resource, Aidbox returns `200 OK` but does not fire any event — subscribers will not be notified.

The audit log records PATCH operations under the `fhir/patch` event type, distinct from `fhir/update`, so patch-originated changes can be identified separately in audit history.

## Examples

Let's suppose we've created a Patient resource with the id `pt-1`

```json
POST /Patient

{
  "resourceType": "Patient",
  "id": "pt-1",
  "active": true,
  "name": [
    {
      "given": ["John"],
      "family": "Doe",
      "use": "official"
    },
    {
      "given": ["Johny"],
      "family": "Doe"
    }
  ],
  "telecom": [
    {
      "system": "phone",
      "value": "(03) 5555 6473",
      "use": "work",
      "rank": 1
    }
  ],
  "birthDate": "1979-01-01"
}
```

### Merge Patch

Let's say we want to switch to an `active` flag to false and remove `telecom`:

```json
PATCH /Patient/pt-1

{
  "active": false,
  "telecom": null
}
```

Response:

```json
// 200

{
  "id": "pt-1",
  "resourceType": "Patient",
  "name": [
    {
      "use": "official",
      "given": ["John"],
      "family": "Doe"
    },
    {
      "given": ["Johny"],
      "family": "Doe"
    }
  ],
  "active": false,
  "birthDate": "1979-01-01"
}
```

### JSON Patch

With JSON patch, we can do more sophisticated transformations — change the first `given` name, delete the second `name`, and change the `active` attribute value to `true`:

{% hint style="warning" %}
The JSON Patch body **must** be a JSON array of operation objects per [RFC 6902](https://tools.ietf.org/html/rfc6902). Sending a single object instead of an array will result in an error.

{% tabs %}
{% tab title="Correct" %}
```json
[{"op": "add", "path": "/birthDate", "value": "1990-01-01"}]
```
{% endtab %}
{% tab title="Incorrect" %}
```json
{"op": "add", "path": "/birthDate", "value": "1990-01-01"}
```
{% endtab %}
{% endtabs %}
{% endhint %}

```json
PATCH /Patient/pt-1

[
  {"op": "replace", "path": "/name/0/given/0", "value": "Nikolai"},
  {"op": "remove", "path": "/name/1"},
  {"op": "replace", "path": "/active", "value": true}
]
```

Response:

```json
// 200 OK
{
  "id": "pt-1",
  "resourceType": "Patient",
  "name": [
    {
      "use": "official",
      "given": ["Nikolai"],
      "family": "Doe"
    }
  ],
  "active": true,
  "birthDate": "1979-01-01"
}
```

#### Array append with `/-`

In JSON Pointer paths, `/-` refers to the end of an array and can be used with the `add` operation to append a new element:

```json
PATCH /Patient/pt-1

[
  {
    "op": "add",
    "path": "/name/-",
    "value": {
      "given": ["Jane"],
      "family": "Doe"
    }
  }
]
```

This appends a new name entry to the `name` array instead of replacing an element at a specific index.

### FHIRPath Patch

FHIRPath Patch is a syntax-agnostic mechanism within the FHIR standard that enables precise modifications to FHIR resources by utilizing FHIRPath expressions to identify target elements. \
\
This approach allows for operations such as **add**, **insert**, **delete**, **replace**, and **move**.\
\
FHIRPath Patch operations are represented within a Parameters resource:

#### Add

The **add** operation appends a new value to a specified element within a FHIR resource

* The **path** specifies where the new value should be added
* The **name** represents the property being added
* The **value** provides the data that will be added

{% code title="Add primitive example" %}
```json
PATCH /fhir/Patient/pt-1

{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "operation",
      "part": [
        {"name": "type", "valueCode": "add"},
        {"name": "path", "valueString": "Patient"},
        {"name": "name", "valueString": "birthDate"},
        {"name": "value", "valueDate": "1931-01-01"}
      ]
    }
  ]
}
```
{% endcode %}

{% code title="Add BackboneElement example" %}
```json
PATCH /fhir/Patient/pt-1

{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "operation",
      "part": [
        {"name": "type", "valueCode": "add"},
        {"name": "path", "valueString": "Patient"},
        {"name": "name", "valueString": "contact"},
        {
          "name": "value",
          "part": [
            {
              "name": "name",
              "valueHumanName": {"text": "a name"}
            }
          ]
        }
      ]
    }
  ]
}
```
{% endcode %}

#### Insert

The **insert** operation allows you to insert a new element into an existing list at a specified position

* The **path** specifies the collection where the element should be inserted. Collection must be present
* The **value** specifies the new data to insert
* The **index** defines the position (0-based) at which to insert the element. The index is mandatory and must be equal to or less than the number of elements already in the list

{% code title="Insert example" %}
```json
PATCH /fhir/Patient/pt-1

{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "operation",
      "part": [
        {"name": "type", "valueCode": "insert"},
        {"name": "path", "valueString": "Patient.name"},
        {"name": "index", "valueInteger": 0},
        {
          "name": "value",
          "valueHumanName": {"given": ["John"]}
        }
      ]
    }
  ]
}
```
{% endcode %}

#### Delete

The **delete** operation removes an element from a resource. Only one element can be deleted at a time.

* The **path** specifies the element to be deleted

{% code title="Delete primitive example" %}
```json
PATCH /fhir/Patient/pt-1

{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "operation",
      "part": [
        {"name": "type", "valueCode": "delete"},
        {"name": "path", "valueString": "Patient.gender"}
      ]
    }
  ]
}
```
{% endcode %}

{% code title="Delete specific array element" %}
```json
PATCH /fhir/Patient/pt-1

{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "operation",
      "part": [
        {"name": "type", "valueCode": "delete"},
        {"name": "path", "valueString": "Patient.identifier.where(system = 'foo')"}
      ]
    }
  ]
}
```
{% endcode %}

#### Replace

The **replace** operation updates the value of an existing element within a FHIR resource

* The **path** specifies the element to be replaced
* The **value** provides the new data that will replace the existing value
* The operation will fail if the specified element does not exist

{% code title="Replace primitive example" %}
```json
PATCH /fhir/Patient/pt-1

{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "operation",
      "part": [
        {"name": "type", "valueCode": "replace"},
        {"name": "path", "valueString": "Patient.gender"},
        {"name": "value", "valueCode": "female"}
      ]
    }
  ]
}
```
{% endcode %}

Replace extension by id example:

```json
PATCH /fhir/Patient/pt1

{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "operation",
      "part": [
        {"name": "type", "valueCode": "replace"},
        {"name": "path", "valueString": "Patient.extension('http://example.org/my-extension').value"},
        {"name": "value", "valueString": "new-value"}
      ]
    }
  ]
}
```

#### Move

The **move** operation allows you to relocate an element within a collection from one index to another

* The **path** specifies the collection or list where the element is located
* The **from** index indicates the current position of the element to be moved (0-based index)
* The **to** index indicates the new position where the element should be moved

```json
PATCH /fhir/Patient/pt-1

{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "operation",
      "part": [
        {"name": "type", "valueCode": "move"},
        {"name": "path", "valueString": "Patient.identifier"},
        {"name": "source", "valueInteger": 1},
        {"name": "destination", "valueInteger": 0}
      ]
    }
  ]
}
```
