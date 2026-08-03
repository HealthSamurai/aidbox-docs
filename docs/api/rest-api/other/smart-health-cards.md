---
description: >-
  Issue signed SMART Health Cards from a patient's clinical data with the
  $health-cards-issue operation.
---

# SMART Health Cards

Since the 2608 version, Aidbox can issue [SMART Health Cards](https://smarthealth.cards/): verifiable health credentials packaged as a signed, compact JSON Web Signature (JWS) that a patient presents as a QR code or file. The [`$health-cards-issue`](https://spec.smarthealth.cards/#via-fhir-health-cards-issue-operation) operation gathers the patient's clinical resources, minifies them into a `verifiableCredential` Bundle, and signs it with the issuer's ES256 key.

Aidbox publishes the verification public key at a JWKS endpoint, so any SMART Health Cards verifier can validate the cards.

## Configuration

The operation signs cards with an issuer **EC P-256 private key**, set as a PEM in `module.health-cards-links.issuer-private-key` (env `BOX_MODULE_HEALTH_CARDS_LINKS_ISSUER_PRIVATE_KEY`); the public key and JWKS are derived from it. Until it is set the operation returns `422` and the JWKS endpoint `404`.

Generate a key with OpenSSL:

```bash
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out issuer.pem
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

`verifiableCredential.valueString` is the signed SMART Health Card JWS: a raw-DEFLATE-compressed (`zip:"DEF"`) payload signed with ES256, whose protected header carries the issuer `kid`. Each `resourceLink` maps a bundled resource (`resource:N`) to its source Aidbox resource (`hostedResource`).

### Repeatable parameters

`credentialType`, `credentialValueSet`, and `includeIdentityClaim` take one `parameter` entry per value. This request asks for a card carrying both immunizations and observations (`credentialType` as a logical AND), limits the identity claim to the name, and skips resources modified before a cutoff:

```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "credentialType", "valueUri": "Immunization" },
    { "name": "credentialType", "valueUri": "Observation" },
    { "name": "includeIdentityClaim", "valueString": "Patient.name" },
    { "name": "_since", "valueInstant": "2024-01-01T00:00:00Z" }
  ]
}
```

Add a `credentialValueSet` entry the same way to filter the kept resources, for example `https://terminology.smarthealth.cards/ValueSet/immunization-covid-cvx`.

## Input parameters

### credentialType

The operation accepts any FHIR resource type in the Patient compartment, such as `Immunization`, `Observation`, or `Condition`. It searches the patient's compartment for that type and adds the matching resources to the card.

Per the [spec](https://spec.smarthealth.cards/), `credentialType` is required (at least one). Aidbox combines multiple values with logical AND: the card carries every requested type the patient has. Aidbox rejects a missing or unsupported `credentialType` with `400`.

Every issued card's `vc.type` array includes `https://smarthealth.cards#health-card`. The deprecated type URIs `#covid19`, `#immunization`, and `#laboratory` still work; see [Legacy credential types](smart-health-cards.md#legacy-credential-types).

### credentialValueSet

Restricts the card's resources to members of the given ValueSet(s). Aidbox checks each resource's clinical code (`Immunization.vaccineCode`, `Observation.code`, `MedicationRequest.medicationCodeableConcept`, `*.type`) with [`$validate-code`](validate.md).

Multiple `credentialValueSet` parameters apply as a **card-level logical AND**: Aidbox keeps a resource when it belongs to at least one supplied ValueSet, and issues the card only when the kept resources cover **every** supplied ValueSet. If some ValueSet has no matching resource, Aidbox cannot satisfy the request and returns `404`. Use this to request, for example, a card that holds both a COVID-19 vaccine **and** an mpox vaccine.

{% hint style="info" %}
Aidbox's terminology must resolve the ValueSet. A non-member code is filtered out; a ValueSet that cannot be resolved fails the request with `400` rather than a misleading empty result.
{% endhint %}

### includeIdentityClaim

Controls which `Patient` identity fields the card carries:

| Value                                                       | Effect                                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------- |
| omitted or `true`                                           | Default claims: `Patient.name` (family and given only) and `Patient.birthDate`. |
| a list of strings, e.g. `Patient.name`, `Patient.birthDate` | Only the named fields.                                                          |
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

The `kid` matches the `kid` in the JWS protected header, so a verifier can select the right key. The card issuer identifier (the `iss` claim) is `<base-url>/health-cards`, and per the SMART Health Cards spec its key set lives at `<iss>/.well-known/jwks.json`. The endpoint returns `404` while the issuer key is not configured.

## Access control

`$health-cards-issue` reads the patient's data by re-dispatching internal FHIR requests through the regular request pipeline, so Aidbox enforces the caller's [Access Policies](../../../access-control/authorization/access-policies.md). It never issues a card for data the caller may not read, and propagates a denied internal read verbatim (for example `403`).

For a single call, the operation issues these internal requests, each authorized against the caller's policies:

- `GET /fhir/Patient/{id}?_elements=name,birthDate` reads the identity claims as `FhirRead` (skipped when `includeIdentityClaim` is `false`; `_elements` lists the requested claim fields).
- `GET /fhir/{type}?{compartment-param}=Patient/{id}` searches each requested `credentialType` as `FhirSearch`, using the type's Patient-compartment search parameter (`patient` for `Immunization`, `subject` for `Observation` and `Condition`, and so on) and following `next` links to page through every match. Adds `&_lastUpdated=ge{_since}` when `_since` is set.

Grant the caller a policy for each. For the type searches, link an [AccessPolicy](../../../access-control/authorization/access-policies.md) to `Operation/FhirSearch` and restrict it inside `matcho`. For example, to let one client build cards from `Immunization` and `Observation`:

```json
{
  "resourceType": "AccessPolicy",
  "id": "health-cards-issuer-search",
  "engine": "matcho",
  "link": [{ "reference": "Operation/FhirSearch" }],
  "matcho": {
    "client": { "id": "my-client-id" },
    "params": {
      "resource/type": {
        "$enum": ["Immunization", "Observation"]
      }
    }
  }
}
```

Add each resource type you request to the `$enum`. For the `Patient` read, add a policy linked to `Operation/FhirRead`:

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

See [more AccessPolicy examples](../../../tutorials/security-access-control-tutorials/accesspolicy-examples.md).

### Organization scope (OrgBAC)

Under [organization-based access control](../../../access-control/authorization/scoped-api/organization-based-hierarchical-access-control.md), the operation is also served at:

```http
POST /Organization/<orgid>/fhir/Patient/<patient-id>/$health-cards-issue
```

It issues a card only from data in that organization. The target `Patient` and every internal read run inside the organization's compartment, so a `Patient` that belongs to another organization is not visible and the request returns `403`. The `resourceLink.hostedResource` URLs are scoped to the same `/Organization/<orgid>/fhir` base.

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
