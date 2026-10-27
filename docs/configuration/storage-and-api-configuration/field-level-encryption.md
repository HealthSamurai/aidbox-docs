---
description: Data at rest encryption for specific fields of a resource
---

# Encrypt field of a resource at rest

{% hint style="info" %}
This functionality is available starting from Aidbox version **2611**.
{% endhint %}

FHIR resources contain personal data (PII), and you may want to encrypt the fields storing sensitive data.

Field-level encryption is set up with API configuration operations: you specify FHIRPath expressions extracting
fields, and a key to encrypt data. Aidbox will store the resource with data encrypted as JSON WEB Encryption (JWE)
string.

You can encrypt fields before sending it to Aidbox (with the configured key), then Aidbox will transparently decrypt
the fields on REST interaction (same as if Aidbox encrypted them).

## JSON WEB Encryption (JWE)
JSON WEB Encryption (JWE) is an IETF standard ([RFC 7516](https://www.rfc-editor.org/info/rfc7516)) which defines
representation of encrypted content. We use compact form, it consists of 5 base65url-encoded parts separated by period:
- JOSE header;
- Encrypted data encryption key;
- Initialization vector;
- Ciphertext;
- Authentication tag.

For example,
```
eyJraWQiOiJrZWsiLCJlbmMiOiJYQzIwUCIsImFsZyI6IkEyNTZLVyJ9.wam7aJrqtAiqUlC1-ieRGjTQnPLDxdsPGlTGvCdzoh3-ZODG176TUg.__79_Pv6-fj39vX08_Lx8O_u7ezr6uno.5JUwHtTCxjrqRfV7qg.GSTB1HWZLDE5ovqxK5pkRw
```
is the representation of:
- a string "Hello, World!";
- encrypted with XChaCha20 cipher with
  - key `00 01 ... 1f`,
  - IV `ff fe ... e8`;
- authenticated with Poly1305 MAC;
- and the key is wrapped with AES-256 keywrap algorithm
  - with key `20 21 ... 3f`.

### JSON Object Signing and Encryption header (JOSE header)
The first part of the JWE is the JOSE header. This header specifies the algorithm used to encrypt data
and key-wrapping algorithm.

In our case it is (base64url-decoded):
```
{
  "kid": "kek",
  "enc": "XC20P",
  "alg": "A256KW"
}
```
Here
- `kid` is a key id (so the system knows which key to use for decryption);
- `enc` specifies encryption algorithm;
- `alg` specifies key wrapping algorithm.

## Configuration
Pass the `encryption` parameter to `$create-api` or `$configure-api`. Its parts:

| Part       | Type                | Required        | Description                                                                               |
|------------|---------------------|-----------------|-------------------------------------------------------------------------------------------|
| `jose`     | complex (see below) | yes             | JOSE header describing encryption                                                         |
| `mode`     | code                | yes             | `strict`: on data change validate that Aidbox can decrypt data; `lenient`: don't validate |
| `fhirpath` | string              | yes, repeatable | FHIRPath to elements to encrypt                                                           |

Structure of the `jose` parameter:
| Part  | Type   | Required | Description                                                                              |
|-------|--------|----------|------------------------------------------------------------------------------------------|
| `alg` | string | yes      | Key-wrapping algorithm. Only `DIR` (no key wrapping) is supported now                    |
| `enc` | string | yes      | Encryption algorithm. Supported `A256GCM` (AES-256-GCM) and `XC20P` (XChaCha20-Poly1305) |
| `kid` | string | yes      | Key ID (from [Secrets API](https://www.health-samurai.io/docs/aidbox/configuration/secret-files))                     |

Example:
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "apiId", "valueString": "patient" },
    { "name": "resourceType", "valueString": "Patient" },
    { "name": "storageId", "valueString": "patient" },
    { "name": "apiTemplate", "valueString": "pre-2604" },
    { "name": "encryption", "part": [
        { "name": "fhirpath", "valueString": "birthDate" },
        { "name": "fhirpath", "valueString": "name.family" },
        { "name": "mode", "valueCode": "lenient" },
        { "name": "jose", "part": [
            { "name": "alg", "valueCode": "dir" },
            { "name": "enc", "valueCode": "XC20P" },
            { "name": "kid", "valueString": "key-abc" }
        ]}
    ]}
  ]
}
```

Vault config example:
```
{
  "secret": {
    "key-a": {
      "path": "/path/to/key.base64",
      "scope": {
        "kind": "encryption",
        "alg": "XC20P"
      }
    }
  }
}
```

## Operation
On changes (create, update, update-as-create operations) Aidbox extracts fields with FHIRPath expression, then (in strict mode) validates that encrypted values could be decrypted, then encrypts plaintext values.
Each value is first serialized as JSON, then encoded as UTF-8, and then encrypted.

For example, number `1` will be encoded as JSON `1`, then encoded as UTF-8 `31`, then encrypted.
string `Hello` will be encoded as JSON `"Hello"`, then encoded as `22 48 65 6c 6c 6f 22`, then encrypted.

The content is stored in custom Aidbox extension `http://health-samurai.io/fhir/core/StructureDefinition/element-encryptedValue`.

Example:
```json
{
  "resourceType": "Patient",
  "birthDate": "2020-01-01"
}
```

will be encrypted as
```json
{
  "resourceType": "Patient",
  "_birthDate": {
    "extension": [
      {
        "url": "http://hl7.org/fhir/StructureDefinition/data-absent-reason",
        "valueCode": "masked"
      },
      {
        "url": "http://health-samurai.io/fhir/core/StructureDefinition/element-encryptedValue",
        "valueString": "--JWE compact form--"
      }
    ]
  }
}

On read, search, and history operations the process is reversed and Aidbox decrypts data before sending it to the client. If some element cannot be decrypted, it is send as is.
