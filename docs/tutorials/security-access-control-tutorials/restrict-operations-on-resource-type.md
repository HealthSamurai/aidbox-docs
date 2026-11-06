---
description: >-
  This article shows how to create an access policy with restricted set of
  operations on Patient resource
---

# Restrict operations on resource type

### Create a patient

```yaml
POST /fhir/Patient

id: pt-1
resourceType: Patient
name:
  - given:
      - John
```

### Create an access policy

Create an access policy which allows only `FhirRead` operation on Patient.

```yaml
POST /fhir/AccessPolicy

engine: matcho
matcho:
  operation:
    id: FhirRead
  params:
    resource/type: Patient
```

### Try it

#### Create

We won't be able to create new patient because we're not allowed to use `FhirCreate` operation

{% tabs %}
{% tab title="Request" %}
```yaml
POST /fhir/Patient

id: pt-2
resourceType: Patient
name:
  - given:
      - Jane
```
{% endtab %}

{% tab title="Response" %}
```yaml
resourceType: OperationOutcome
id: forbidden
text:
  status: generated
  div: Forbidden
issue:
- severity: fatal
  code: forbidden
  diagnostics: Forbidden
```
{% endtab %}
{% endtabs %}

#### Read

`FhirRead` operation works as expected and you are able to read previously created patient

{% tabs %}
{% tab title="Request" %}
```yaml
GET /fhir/Patient/pt-1
```
{% endtab %}

{% tab title="Response" %}
```yaml
name:
- given: [John]
id: pt-1
resourceType: Patient
```
{% endtab %}
{% endtabs %}

### What's going on here

When you make a query

```http
GET /fhir/{resource-type}/{resource-id}
```

Aidbox router stores data in the request object:

* Reference to the `FhirRead` operation in the `operation` property.
* Resource type `Patient` from the url to the `params.resource/type` property.

Access policy engine evaluates request object. And here it checks that `operation.id` property equals `FhirRead`.

You can inspect request object [using `__debug` query parameter](debug-access-control.md#__debug-query-string-parameter).
