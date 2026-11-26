---
description: >-
  The CapabilityStatement resource is a statement of the kinds of resources and
  operations provided and/or consumed by an application.
---

# Capability Statement

## Overview

Using `GET /fhir/metadata` you can access [FHIR capabilities](https://www.hl7.org/fhir/http.html#capabilities) interaction.

Response is a `CapabilityStatement` generated from _meta resources_ created in an Aidbox instance. The list of this _meta resource_ types used for the response generation:

* `Operation`
* `SearchParameter`
* `Entity`

{% hint style="info" %}
Aidbox `CapabilityStatement` updates automatically after _meta resources_ change. No interaction needed to apply changes to `CapabilityStatement`.
{% endhint %}

Read more about [conformance rules](http://build.fhir.org/conformance-rules.html) and the [CapabilityStatement resource](http://build.fhir.org/capabilitystatement.html) itself.

Base URL for FHIR compatible API is `<server-domain>/fhir/`.

The `capabilities` interaction returns a capability statement describing the server's current operational functionality. The interaction is performed by the HTTP `GET` command as shown:

```javascript
GET [base]/metadata{?mode=[mode]}{&_format=[mime-type]}
```

You can get [Capability Statement](https://www.hl7.org/fhir/capabilitystatement.html) of your Aidbox with the command:

```javascript
GET <server-domain>/fhir/metadata
```

## &#x20;Get metadata

<mark style="color:blue;">`GET`</mark> `<your-domain>/fhir/metadata`

#### Query Parameters

| Name                       | Type    | Description                                                                                                                       |
| -------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------- |
| mode                       | string  | `full`, `normative`, or `terminology`. See [Mode](#mode).                                                                         |
| \_format                   | string  | `json`, `yaml`, or `edn`. In [FHIR compliant mode](../../../reference/all-settings.md#fhir.compliant-mode), the CapabilityStatement is always JSON. |
| include-custom-resources   | boolean | In FHIR compliant mode, `true` adds custom resources to `rest.resource`. Without it, Aidbox lists core FHIR resource types there.  |

{% tabs %}
{% tab title="200 " %}
```yaml
resourceType: CapabilityStatement
name: aidbox
title: '[a]idbox'
kind: instance
software:
  name: Aidbox
  version: '2611'
implementation:
  description: Aidbox FHIR Server
format: [json, yaml, edn]
patchFormat: [json-patch, merge-patch]
rest:
- mode: server
  interaction:
  - {code: batch}
  - {code: transaction}
  operation:
  - {name: patient_list, definition: Operation/patient_list}
  ....
  resource:
  - interaction:
    - {code: read}
    - {code: vread}
    - {code: update}
    - {code: patch}
    - {code: delete}
    - {code: history-instance}
    - {code: history-type}
    - {code: create}
    - {code: search-type}
    readHistory: true
    updateCreate: true
    versioning: versioned-update
    searchRevInclude: [all]
    referencePolicy: local
    conditionalRead: full-support
    searchInclude: [all]
    type: Patient
    conditionalDelete: single
    conditionalUpdate: true
    conditionalCreate: true
    searchParam:
    - {name: address-city, definition: /SearchParameter/Patient.address-city, type: string}
    - {name: active, definition: /SearchParameter/Patient.active, type: token}
    - {name: given, definition: /SearchParameter/Patient.given, type: string}
    - {name: address-state, definition: /SearchParameter/Patient.address-state, type: string}
    - {name: general-practitioner, definition: /SearchParameter/Patient.general-practitioner,
      type: reference}
    - {name: gender, definition: /SearchParameter/Patient.gender, type: token}
    - {name: name, definition: /SearchParameter/Patient.name, type: string}
    - {name: family, definition: /SearchParameter/Patient.family, type: string}
    - {name: telecom, definition: /SearchParameter/Patient.telecom, type: token}
    - {name: animal-species, definition: /SearchParameter/Patient.animal-species,
      type: token}
    - {name: identifier, definition: /SearchParameter/Patient.identifier, type: token}
    - {name: link, definition: /SearchParameter/Patient.link, type: reference}
    - {name: address-use, definition: /SearchParameter/Patient.address-use, type: token}
    - {name: language, definition: /SearchParameter/Patient.language, type: token}
    - {name: phonetic, definition: /SearchParameter/Patient.phonetic, type: string}
    - {name: death-date, definition: /SearchParameter/Patient.death-date, type: date}
    - {name: animal-breed, definition: /SearchParameter/Patient.animal-breed, type: token}
    - {name: deceased, definition: /SearchParameter/Patient.deceased, type: token}
    - {name: address, definition: /SearchParameter/Patient.address, type: string}
    - {name: email, definition: /SearchParameter/Patient.email, type: token}
    - {name: organization, definition: /SearchParameter/Patient.organization, type: reference}
    - {name: birthdate, definition: /SearchParameter/Patient.birthdate, type: date}
    - {name: address-country, definition: /SearchParameter/Patient.address-country,
      type: string}
    - {name: phone, definition: /SearchParameter/Patient.phone, type: token}
    - {name: address-postalcode, definition: /SearchParameter/Patient.address-postalcode,
      type: string}
```
{% endtab %}
{% endtabs %}

{% hint style="info" %}
If you want more control over CapabilityStatement, please contact us in the community chat!
{% endhint %}

### Software

`software` names the product that runs the server, and FHIR clients use `software.name` to identify it:

* `software.name`: `Aidbox`.
* `software.version`: the running Aidbox version, the same value as `about.version` in [`GET /health`](health-check.md). A release reports its version, such as `2611`. Other builds report the channel and the commit, such as `edge:f303edfec6`.

`implementation.description` describes the installation: `Aidbox FHIR Server`.

### Mode

The `mode` parameter selects the response:

| Value                  | Response                                                                                                                                                                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `full` or no `mode`    | A [CapabilityStatement](https://hl7.org/fhir/R4/capabilitystatement.html) with the resource types and interactions Aidbox supports.                                                                                                                                        |
| `normative`            | Aidbox ignores this value and returns the full CapabilityStatement.                                                                                                                                                                                                       |
| `terminology`          | A [TerminologyCapabilities](https://hl7.org/fhir/R4/terminologycapabilities.html) resource that describes the terminology operations, when [`fhir.terminology.engine`](../../../reference/all-settings.md#fhir.terminology.engine) is `hybrid` or `local`. With the `legacy` engine, Aidbox returns the CapabilityStatement. |

The FHIR specification [allows](https://hl7.org/fhir/R4/http.html#capabilities) a server to ignore `mode` and return a CapabilityStatement. Aidbox ignores `mode` on the [organization-scoped](../../../access-control/authorization/scoped-api/organization-based-hierarchical-access-control/README.md) route `GET /Organization/<org-id>/fhir/metadata`.

TerminologyCapabilities carries the same `software` as the CapabilityStatement:

```http
GET /fhir/metadata?mode=terminology
```

```yaml
resourceType: TerminologyCapabilities
name: Aidbox
title: Aidbox Terminology Server
version: 0.0.1
status: active
kind: capability
software:
  name: Aidbox
  version: '2611'
expansion:
  paging: true
  ...
```

### Notes

#### rest\[].resource\[].profile

The profile property is set when zen profiling is enabled and the following conditions are met:

* the corresponding resource is defined in zen profile
* there is exactly one zen schema tagged with `base-profile` for the corresponding resource

## Aidbox native metadata

To get metadata in the internal Aidbox format, use [`/$metadata?_format=yaml`](http://localhost:7777/$metadata?\_format=yaml)

## Get Aidbox native metadata

<mark style="color:blue;">`GET`</mark> `<your-domain>/$metadata`

#### Path Parameters

| Name     | Type   | Description         |
| -------- | ------ | ------------------- |
| \_format | string | yaml \| json \| edn |

#### Query Parameters

| Name | Type   | Description                                                    |
| ---- | ------ | -------------------------------------------------------------- |
| path | string | Path to specific part of metadata (for example Entity.Patient) |

Capability statements can become quite large; servers are encouraged to support the [`_summary`](https://hl7.org/fhir/R4/search.html#summary) and [`_elements`](https://hl7.org/fhir/R4/search.html#elements) parameters on the capabilities interaction, though this is not required. In addition, servers are encouraged to implement the [$subset](https://hl7.org/fhir/R4/capabilitystatement-operation-subset.html) and [$implements](https://hl7.org/fhir/R4/capabilitystatement-operation-implements.html) operations to make it easy for a client to check conformance.
