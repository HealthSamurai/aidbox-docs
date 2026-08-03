---
description: >-
  Issue signed SMART Health Cards from a patient's clinical data with the
  $health-cards-issue operation.
---

# SMART Health Cards

Since the 2607 version, Aidbox can issue [SMART Health Cards](https://smarthealth.cards/): verifiable health credentials packaged as a signed, compact JSON Web Signature (JWS) that a patient presents as a QR code or file. The [`$health-cards-issue`](https://spec.smarthealth.cards/#via-fhir-health-cards-issue-operation) operation issues a signed card from the patient's clinical resources.

Aidbox publishes the verification public key at a JWKS endpoint, so any SMART Health Cards verifier can validate the cards.

## Configuration

The operation signs cards with an issuer **EC P-256 private key**, set as a PEM in `module.health-cards-links.issuer-private-key`; the public key and JWKS are derived from it.

Generate a key with OpenSSL and set it as the issuer key:

```bash
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out issuer.pem
```

```
BOX_MODULE_HEALTH_CARDS_LINKS_ISSUER_PRIVATE_KEY=<your-key>
```

{% hint style="warning" %}
Keep the private key secret and back it up. Rotating it changes the `kid`, so cards signed with the previous key stop verifying against the published JWKS.
{% endhint %}

## Issuing a card

```http
POST /fhir/Patient/<patient-id>/$health-cards-issue
```

The body is a `Parameters` resource. `credentialType` is required; the other parameters are optional.

| Parameter              | Type               | Description                                                                                                                           |
| ---------------------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------------------- |
| `credentialType`       | uri / string       | Resource types the card should carry. Required, repeatable. See [credentialType](smart-health-cards.md#credentialtype).               |
| `credentialValueSet`   | uri / string       | Restrict included resources to members of a ValueSet. Repeatable. See [credentialValueSet](smart-health-cards.md#credentialvalueset). |
| `includeIdentityClaim` | string / boolean   | Which `Patient` identity fields to include. See [includeIdentityClaim](smart-health-cards.md#includeidentityclaim).                   |
| `_since`               | dateTime / instant | Only include resources modified at or after this instant (`_lastUpdated ge`).                                                         |

### Example request

```http
POST /fhir/Patient/pt-1/$health-cards-issue
```

```json
{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "credentialType",
      "valueUri": "Immunization"
    }
  ]
}
```

### Example response

```json
{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "verifiableCredential",
      "valueString": "eyJ6aXAiOiJERUYiLCJhbGciOiJFUzI1NiIsImtpZCI6Ii4uLiJ9.<deflated-payload>.<signature>"
    },
    {
      "name": "resourceLink",
      "part": [
        { "name": "vcIndex", "valueInteger": 0 },
        { "name": "bundledResource", "valueUri": "resource:0" },
        {
          "name": "hostedResource",
          "valueUri": "https://<base>/fhir/Patient/pt-1"
        }
      ]
    },
    {
      "name": "resourceLink",
      "part": [
        { "name": "vcIndex", "valueInteger": 0 },
        { "name": "bundledResource", "valueUri": "resource:1" },
        {
          "name": "hostedResource",
          "valueUri": "https://<base>/fhir/Immunization/imm-1"
        }
      ]
    }
  ]
}
```

`verifiableCredential.valueString` is the signed SMART Health Card (a compact JWS). Each `resourceLink` maps a bundled resource (`resource:N`) to its source Aidbox resource (`hostedResource`).

## Input parameters

### credentialType

The operation accepts any FHIR resource type in the Patient compartment, such as `Immunization`, `Observation`, or `Condition`. It searches the patient's compartment for that type and adds the matching resources to the card.

`credentialType` is required (at least one). Aidbox combines multiple values with logical AND: the card carries every requested type the patient has. Aidbox rejects a missing or unsupported `credentialType` with `400`.

### credentialValueSet

Keeps only resources whose clinical code is a member of the given ValueSet. For example, supply a ValueSet of COVID-19 vaccine codes to include only COVID-19 immunizations. Aidbox validates the resource's coded fields (`vaccineCode`, `code`, `medicationCodeableConcept`, and `type`) against the ValueSet with [`$validate-code`](validate.md), so the ValueSet must be loaded into Aidbox's terminology. An unresolvable ValueSet fails the request with `400`.

For example, a COVID-19-only immunization card:

```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "credentialType", "valueUri": "Immunization" },
    {
      "name": "credentialValueSet",
      "valueUri": "https://terminology.smarthealth.cards/ValueSet/immunization-covid-cvx"
    }
  ]
}
```

Passing several `credentialValueSet` parameters combines them as a card-level logical AND: a resource is kept if it matches at least one, and the card is issued only when every ValueSet matched some resource (otherwise `404`). So passing a COVID-19 vaccine ValueSet and an mpox vaccine ValueSet requests a card that carries a vaccine from each.

Any ValueSet that Aidbox's terminology can resolve works. The standard SMART Health Cards value sets come from the [SMART Health Cards terminology IG](https://terminology.smarthealth.cards/artifacts.html); load the ones you need into Aidbox as `ValueSet` resources. Their codes come from external code systems (CVX, SNOMED CT, LOINC), so also run the [terminology engine](../../../terminology-module/aidbox-terminology-module/hybrid.md) in `hybrid` mode against a terminology server that provides those code systems, otherwise the codes will not validate.

The common value sets, under `https://terminology.smarthealth.cards/ValueSet/`:

| ValueSet | Contents |
| --- | --- |
| `immunization-covid-all` | COVID-19 vaccines (CVX, SNOMED CT, ICD-11) |
| `immunization-covid-cvx` | COVID-19 vaccines (CVX) |
| `immunization-orthopoxvirus-all` | mpox / orthopoxvirus vaccines |
| `immunization-all-cvx` | All CVX vaccine codes |
| `lab-qualitative-test-covid` | Qualitative COVID-19 lab tests (LOINC) |
| `lab-qualitative-result` | Qualitative infectious-disease lab results |

### includeIdentityClaim

Controls which `Patient` identity fields the card carries:

| Value                                                       | Effect                                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------- |
| omitted or `true`                                           | Default claims: `Patient.name` (family and given only) and `Patient.birthDate`. |
| `Patient.name`, `Patient.gender` (one `valueString` each)   | Only the named fields.                                                          |
| `false`                                                     | Omit the `Patient` from the card entirely.                                      |

### \_since

The operation includes only resources with `_lastUpdated` at or after the given instant, for example `2024-01-01T00:00:00Z`.

## Verifying cards (JWKS)

Aidbox publishes the issuer's public key as a JWK Set at a public endpoint:

```http
GET /health-cards/.well-known/jwks.json
```

```json
{
  "keys": [
    {
      "kty": "EC",
      "crv": "P-256",
      "x": "vbo4liL4JMgrGcYgAhVWreZPFMisG65EhM0p3Vdgzi8",
      "y": "U3_QRvRc12uGpFiwBlX43vXbqYoVwGQ2obGZgF2gCYc",
      "kid": "jDfy60_p2Gyvcl_sXayw0FcSECzZtrC7WUKrVaigVYI",
      "use": "sig",
      "alg": "ES256"
    }
  ]
}
```

A verifier picks the right key by the `kid` in the card's JWS header. The card's issuer (`iss`) is `<base-url>/health-cards`, and its key set lives at `<iss>/.well-known/jwks.json`. Returns `404` until the issuer key is configured.

## Access control

A caller needs both permission to **invoke the operation** and permission for the **internal reads** it issues. The operation re-dispatches those reads through the regular pipeline, so your [Access Policies](../../../access-control/authorization/access-policies.md) gate them; a read the caller may not perform stops the card (for example `403`). The `credentialValueSet` terminology check (`$validate-code`) runs in-process and needs no policy.

For a single call the operation issues these authorized requests:

- `POST /fhir/Patient/{id}/$health-cards-issue`, the operation itself (`fhir-patient-health-cards-issue`).
- `GET /fhir/Patient/{id}?_elements=name,birthDate` reads the identity claims as `FhirRead` (skipped when `includeIdentityClaim` is `false`; `_elements` lists the requested claim fields).
- `GET /fhir/{type}?{compartment-param}=Patient/{id}` searches each requested `credentialType` as `FhirSearch`, using the type's Patient-compartment parameter (`patient` for `Immunization`, `subject` for `Observation` and `Condition`, and so on) and following `next` links to page through every match. Adds `&_lastUpdated=ge{_since}` when `_since` is set.

Each policy links to an operation. First, allow invoking the operation itself:

```json
{
  "resourceType": "AccessPolicy",
  "id": "health-cards-issuer-op",
  "engine": "matcho",
  "link": [{ "reference": "Operation/fhir-patient-health-cards-issue" }],
  "matcho": { "client": { "id": "my-client-id" } }
}
```

Next, allow the type searches. Link to `FhirSearch` and, with `$one-of`, match the compartment parameter each requested type uses so the policy only permits patient-scoped searches:

```json
{
  "resourceType": "AccessPolicy",
  "id": "health-cards-issuer-search",
  "engine": "matcho",
  "link": [{ "reference": "Operation/FhirSearch" }],
  "matcho": {
    "client": { "id": "my-client-id" },
    "params": {
      "$one-of": [
        { "resource/type": "Immunization", "patient": "present?" },
        { "resource/type": { "$enum": ["Observation", "Condition"] }, "subject": "present?" }
      ]
    }
  }
}
```

List the resource types you request under the compartment parameter each one uses (`patient` for `Immunization`, `subject` for `Observation` and `Condition`). Finally, allow the `Patient` read:

```json
{
  "resourceType": "AccessPolicy",
  "id": "health-cards-issuer-read-patient",
  "engine": "matcho",
  "link": [{ "reference": "Operation/FhirRead" }],
  "matcho": {
    "client": { "id": "my-client-id" },
    "params": { "resource/type": "Patient" }
  }
}
```

### Organization scope (OrgBAC)

Under [organization-based access control](../../../access-control/authorization/scoped-api/organization-based-hierarchical-access-control.md), the operation is also served at:

```http
POST /Organization/<orgid>/fhir/Patient/<patient-id>/$health-cards-issue
```

It issues a card only from the organization's data: the target `Patient` and every internal read run inside the organization's compartment, so a `Patient` from another organization returns `403`. `hostedResource` URLs use the same `/Organization/<orgid>/fhir` base.

Access Policies still apply (the compartment restricts data but does not grant access). Under OrgBAC the operation and its reads run as the org-scoped operations `orgbac-fhir-health-cards-issue`, `orgbac-fhir-read`, and `orgbac-fhir-search` (kebab-case route ids, not the camel-case `FhirRead` / `FhirSearch`), so link the org policies to those. The three policies mirror the ones above with the ids swapped:

```json
{
  "resourceType": "AccessPolicy",
  "id": "health-cards-org-issuer-op",
  "engine": "matcho",
  "link": [{ "reference": "Operation/orgbac-fhir-health-cards-issue" }],
  "matcho": { "client": { "id": "my-client-id" } }
}
```

```json
{
  "resourceType": "AccessPolicy",
  "id": "health-cards-org-issuer-search",
  "engine": "matcho",
  "link": [{ "reference": "Operation/orgbac-fhir-search" }],
  "matcho": {
    "client": { "id": "my-client-id" },
    "params": {
      "$one-of": [
        { "resource/type": "Immunization", "patient": "present?" },
        { "resource/type": { "$enum": ["Observation", "Condition"] }, "subject": "present?" }
      ]
    }
  }
}
```

```json
{
  "resourceType": "AccessPolicy",
  "id": "health-cards-org-issuer-read",
  "engine": "matcho",
  "link": [{ "reference": "Operation/orgbac-fhir-read" }],
  "matcho": {
    "client": { "id": "my-client-id" },
    "params": { "resource/type": "Patient" }
  }
}
```

The response is the same `Parameters`, with each `hostedResource` under the organization:

```json
{
  "name": "resourceLink",
  "part": [
    { "name": "vcIndex", "valueInteger": 0 },
    { "name": "bundledResource", "valueUri": "resource:1" },
    { "name": "hostedResource", "valueUri": "https://<base>/Organization/<orgid>/fhir/Immunization/imm-1" }
  ]
}
```

## Errors

The operation returns every error as an `OperationOutcome`.

| Status | When                                                            |
| ------ | --------------------------------------------------------------- |
| `422`  | The issuer private key is not configured.                       |
| `400`  | `credentialType` is missing or unsupported.                     |
| `400`  | A requested `credentialValueSet` could not be resolved.         |
| `404`  | No resources match the requested credential type or value sets. |
| `403`  | An Access Policy denies reading the patient's data.             |

## Legacy credential types

Before v1.4.0, SMART Health Cards classified a card by a top-level type URI. The framework deprecated these in favor of classifying a card by its contents, but Aidbox accepts them as `credentialType` values:

| Value                                    | Meaning                                                                |
| ---------------------------------------- | ---------------------------------------------------------------------- |
| `https://smarthealth.cards#covid19`      | COVID-19 `Immunization`s only, filtered to COVID-19 CVX vaccine codes. |
| `https://smarthealth.cards#immunization` | All `Immunization`s.                                                   |
| `https://smarthealth.cards#laboratory`   | `Observation`s.                                                        |

Aidbox also stamps these URIs into the card's `vc.type` from its contents: `#immunization` when the card carries immunizations, `#covid19` for COVID-19 immunizations, and `#laboratory` when it carries observations. A card built only from other resource types carries just `#health-card`.
