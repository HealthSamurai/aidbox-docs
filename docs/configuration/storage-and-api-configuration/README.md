---
description: Configure how Aidbox stores each FHIR resource type and which REST APIs expose it, using storages and APIs.
---

# Storage and API configuration

{% hint style="info" %}
This functionality is available starting from Aidbox version **2606**.
{% endhint %}

Aidbox keeps resource persistence and resource APIs in two layers you can configure independently:

* A **storage** defines how a resource type's data is stored in PostgreSQL and lets you configure it: the table name, whether history is kept, and the name of the history table. The `default` storage type uses the table layout described in [Database schema](../../database/database-schema.md).
* An **API** connects a storage to a FHIR REST endpoint. It exposes the resource type at `/fhir/{resourceType}` and governs which [FHIR interactions](https://build.fhir.org/http.html) (read, create, update, search, history) are available.

A resource type can have several storages, but only one is active at a time: the storage an API points to. `/fhir/metadata` lists only the resource types and interactions that have an active API.

You manage both layers through FHIR operations that accept and return a `Parameters` resource.

## API auto-mount

The [`enable-api-auto-mount`](../../reference/all-settings.md#enable-api-auto-mount) setting controls whether Aidbox exposes resource types for you.

* `true` (default): Aidbox generates a storage and an API for every resource type that has a `StructureDefinition`, together with its `SearchParameter`s. `/fhir/Patient` and `/fhir/Patient?active=true` work without any configuration. This matches how Aidbox behaved before storages and APIs became configurable.
* `false`: Aidbox mounts only its essential system resources (such as `User`, `Client`, `AccessPolicy`). To expose any other resource type, create a storage and an API for it with the operations below.

Turn auto-mount off when you want to:

* expose a selected set of resource types and nothing else,
* keep a newly uploaded `StructureDefinition` from becoming available until you opt in,
* serve a resource type under an endpoint name you choose, such as `/fhir/MyResource`.

## Storages

A storage record carries these parameters:

| Parameter             | Type      | Required    | Description                                                                                                  |
|-----------------------|-----------|-------------|--------------------------------------------------------------------------------------------------------------|
| `structureDefinition` | canonical | yes         | Canonical URL (`url\|version`) of the `StructureDefinition` the storage conforms to.                         |
| `storageType`         | string    | yes         | Only `default` is supported today. Future releases add other types, such as `partitioned`.                   |
| `tableName`           | string    | yes         | Name of the main PostgreSQL table. At most 63 bytes (the PostgreSQL identifier limit).                       |
| `history`             | boolean   | no          | Keep prior versions in a history table. Defaults to `false`.                                                 |
| `historyTableName`    | string    | conditional | Name of the history table. Required when `history` is `true`, and must be omitted when `history` is `false`. |
| `storageId`           | string    | no          | Identifier of the storage. On `$create-storage` you may choose your own; when omitted, Aidbox generates a UUID. Pass it to `$configure-storage` and `$delete-storage`. |
| `ifNoneExist`         | boolean   | no          | Only on `$create-storage`, and only together with `storageId`. When a storage with that `storageId` already exists, return it unchanged with `200` instead of `409`. Not stored. |

### $create-storage

Creates a storage and its PostgreSQL table. If the table already exists, Aidbox reuses it. With `history` set to `true`, Aidbox also creates the history table. The response echoes the storage with its `storageId` and has status `201`.

{% hint style="info" %}
`storageId` and `ifNoneExist` on `$create-storage` are available starting from Aidbox version **2608**.
{% endhint %}

You can pass your own `storageId` instead of letting Aidbox generate one. A stable identifier lets you script the setup, reference the storage from `$create-api` without reading it back, and make the setup idempotent:

* `storageId` is new: the storage is created, status `201`.
* `storageId` already exists: status `409` with an `OperationOutcome`. Add `ifNoneExist` set to `true` to get the existing storage back unchanged with status `200` instead. The other parameters of the request are ignored in that case.

`ifNoneExist` is only allowed together with `storageId`; without it the request fails validation with `422`.

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/$create-storage
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "structureDefinition", "valueCanonical": "http://hl7.org/fhir/StructureDefinition/Observation|4.0.1" },
    { "name": "storageType", "valueString": "default" },
    { "name": "tableName", "valueString": "observation_main" },
    { "name": "history", "valueBoolean": false }
  ]
}
```
{% endtab %}

{% tab title="Response" %}
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "structureDefinition", "valueCanonical": "http://hl7.org/fhir/StructureDefinition/Observation|4.0.1" },
    { "name": "storageType", "valueString": "default" },
    { "name": "tableName", "valueString": "observation_main" },
    { "name": "history", "valueBoolean": false },
    { "name": "storageId", "valueString": "2791c25a-c28d-47ea-ab96-3e13162a5b58" }
  ]
}
```
{% endtab %}
{% endtabs %}

#### Idempotent creation

With `storageId` and `ifNoneExist`, the same request can be sent repeatedly, for example from every replica of a deployment or from an [init bundle](../init-bundle.md). The first call creates the storage (`201`), later calls return it (`200`):

```http
POST /fhir/$create-storage
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "storageId", "valueString": "observation-main" },
    { "name": "ifNoneExist", "valueBoolean": true },
    { "name": "structureDefinition", "valueCanonical": "http://hl7.org/fhir/StructureDefinition/Observation|4.0.1" },
    { "name": "storageType", "valueString": "default" },
    { "name": "tableName", "valueString": "observation_main" },
    { "name": "history", "valueBoolean": false }
  ]
}
```

### $configure-storage

Updates an existing storage. The operation validates the parameters you send, so pass the full storage definition (`storageType`, `tableName`, `structureDefinition`, `history`, and `historyTableName` when `history` is `true`) along with the `storageId`.

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/$configure-storage
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "structureDefinition", "valueCanonical": "http://hl7.org/fhir/StructureDefinition/Observation|4.0.1" },
    { "name": "storageType", "valueString": "default" },
    { "name": "tableName", "valueString": "observation_main" },
    { "name": "history", "valueBoolean": true },
    { "name": "historyTableName", "valueString": "observation_main_history" },
    { "name": "storageId", "valueString": "2791c25a-c28d-47ea-ab96-3e13162a5b58" }
  ]
}
```
{% endtab %}

{% tab title="Response" %}
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "structureDefinition", "valueCanonical": "http://hl7.org/fhir/StructureDefinition/Observation|4.0.1" },
    { "name": "storageType", "valueString": "default" },
    { "name": "tableName", "valueString": "observation_main" },
    { "name": "history", "valueBoolean": true },
    { "name": "historyTableName", "valueString": "observation_main_history" },
    { "name": "storageId", "valueString": "2791c25a-c28d-47ea-ab96-3e13162a5b58" }
  ]
}
```
{% endtab %}
{% endtabs %}

### $list-storage

Returns every storage as a `collection` Bundle of `Parameters`.

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/$list-storage
Content-Type: application/json

{ "resourceType": "Parameters" }
```
{% endtab %}

{% tab title="Response" %}
```json
{
  "resourceType": "Bundle",
  "type": "collection",
  "entry": [
    {
      "resource": {
        "resourceType": "Parameters",
        "parameter": [
          { "name": "structureDefinition", "valueCanonical": "http://hl7.org/fhir/StructureDefinition/Observation|4.0.1" },
          { "name": "storageType", "valueString": "default" },
          { "name": "tableName", "valueString": "observation_main" },
          { "name": "history", "valueBoolean": true },
          { "name": "historyTableName", "valueString": "observation_main_history" },
          { "name": "storageId", "valueString": "2791c25a-c28d-47ea-ab96-3e13162a5b58" }
        ]
      }
    }
  ]
}
```
{% endtab %}
{% endtabs %}

### $delete-storage

Removes the storage record. The PostgreSQL table and its data stay in place.

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/$delete-storage
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "storageId", "valueString": "2791c25a-c28d-47ea-ab96-3e13162a5b58" }
  ]
}
```
{% endtab %}

{% tab title="Response" %}
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "status", "valueString": "success" }
  ]
}
```
{% endtab %}
{% endtabs %}

{% hint style="warning" %}
Deleting a storage does not drop its table. The data remains, and you can reattach it by creating a storage on the same `tableName`.
{% endhint %}

## APIs

An API record carries these parameters:

| Parameter                      | Type   | Required | Description                                                                                                                                     |
|--------------------------------|--------|----------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| `resourceType`                 | string | yes      | FHIR resource type exposed at `/fhir/{resourceType}`. One active API per resource type.                                                         |
| `storageId`                    | string | yes      | Storage the API reads from and writes to.                                                                                                       |
| `apiTemplate`                  | string | yes      | `pre-2604`.                                                                                                                                     |
| `dataOffloadToExternalStorage` | parts  | no       | Store `base64Binary` element values in external storage. See [Offload base64Binary data to external storage](offload-base64binary-to-external-storage.md). |
| `apiId`                        | string | no       | Identifier of the API. On `$create-api` you may choose your own; when omitted, Aidbox generates a UUID. Pass it to `$configure-api` and `$delete-api`. |
| `ifNoneExist`                  | boolean | no      | Only on `$create-api`, and only together with `apiId`. When an API with that `apiId` already exists, return it unchanged with `200` instead of `409`. Not stored. |

`pre-2604` is the only template available, and it is required. It enables the full FHIR REST interaction set (read, vread, create, update, patch, delete, history, search), reproducing the default behavior of Aidbox APIs before this feature. Future releases add more templates. They also let an API turn individual interactions on and off without a template.

### $create-api

Connects a resource type to a storage. The resource type starts serving requests at `/fhir/{resourceType}` and appears in `/fhir/metadata`. The response echoes the API with its `apiId` and has status `201`.

`apiId` and `ifNoneExist` work the same way as `storageId` and `ifNoneExist` on [`$create-storage`](#usdcreate-storage): pass your own `apiId` to get a stable identifier; an existing `apiId` answers `409`, or `200` with the existing API unchanged when `ifNoneExist` is `true`. `ifNoneExist` requires `apiId`. Independently of that, creating a second API for a resource type that already has one answers `409`, because only one API per resource type is allowed.

{% hint style="info" %}
`apiId` and `ifNoneExist` on `$create-api` are available starting from Aidbox version **2608**.
{% endhint %}

With the optional `dataOffloadToExternalStorage` parameter, the API keeps `base64Binary` element values out of PostgreSQL and stores them in external blob storage:

{% content-ref %}
[Offload base64Binary data to external storage](offload-base64binary-to-external-storage.md)
{% endcontent-ref %}

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/$create-api
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "resourceType", "valueString": "Observation" },
    { "name": "storageId", "valueString": "2791c25a-c28d-47ea-ab96-3e13162a5b58" },
    { "name": "apiTemplate", "valueString": "pre-2604" }
  ]
}
```
{% endtab %}

{% tab title="Response" %}
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "apiId", "valueString": "39473529-a37e-4b98-afc2-bea014bbe68e" },
    { "name": "apiTemplate", "valueString": "pre-2604" },
    { "name": "resourceType", "valueString": "Observation" },
    { "name": "storageId", "valueString": "2791c25a-c28d-47ea-ab96-3e13162a5b58" }
  ]
}
```
{% endtab %}
{% endtabs %}

#### Idempotent creation

Together with a storage created with a known `storageId`, the whole setup becomes repeatable, for example in an [init bundle](../init-bundle.md) of type `transaction`:

```json
{
  "resourceType": "Bundle",
  "type": "transaction",
  "entry": [
    {
      "request": { "method": "POST", "url": "/$create-storage" },
      "resource": {
        "resourceType": "Parameters",
        "parameter": [
          { "name": "storageId", "valueString": "observation-main" },
          { "name": "ifNoneExist", "valueBoolean": true },
          { "name": "structureDefinition", "valueCanonical": "http://hl7.org/fhir/StructureDefinition/Observation|4.0.1" },
          { "name": "storageType", "valueString": "default" },
          { "name": "tableName", "valueString": "observation_main" },
          { "name": "history", "valueBoolean": false }
        ]
      }
    },
    {
      "request": { "method": "POST", "url": "/$create-api" },
      "resource": {
        "resourceType": "Parameters",
        "parameter": [
          { "name": "apiId", "valueString": "observation-api" },
          { "name": "ifNoneExist", "valueBoolean": true },
          { "name": "resourceType", "valueString": "Observation" },
          { "name": "storageId", "valueString": "observation-main" },
          { "name": "apiTemplate", "valueString": "pre-2604" }
        ]
      }
    }
  ]
}
```

Every start of every replica applies the bundle; the first one creates the storage and the API, the others find them in place. Later entries of the same bundle can already use the new API.

### $configure-api

Updates an existing API, for example to point a resource type at a different storage. Pass the `apiId` with the full API definition.

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/$configure-api
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "apiId", "valueString": "39473529-a37e-4b98-afc2-bea014bbe68e" },
    { "name": "resourceType", "valueString": "Observation" },
    { "name": "apiTemplate", "valueString": "pre-2604" },
    { "name": "storageId", "valueString": "ac2e94f7-e543-4ea4-a739-a8159a06e939" }
  ]
}
```
{% endtab %}

{% tab title="Response" %}
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "apiId", "valueString": "39473529-a37e-4b98-afc2-bea014bbe68e" },
    { "name": "apiTemplate", "valueString": "pre-2604" },
    { "name": "resourceType", "valueString": "Observation" },
    { "name": "storageId", "valueString": "ac2e94f7-e543-4ea4-a739-a8159a06e939" }
  ]
}
```
{% endtab %}
{% endtabs %}

### $list-api

Returns every API as a `collection` Bundle of `Parameters`.

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/$list-api
Content-Type: application/json

{ "resourceType": "Parameters" }
```
{% endtab %}

{% tab title="Response" %}
```json
{
  "resourceType": "Bundle",
  "type": "collection",
  "entry": [
    {
      "resource": {
        "resourceType": "Parameters",
        "parameter": [
          { "name": "apiId", "valueString": "39473529-a37e-4b98-afc2-bea014bbe68e" },
          { "name": "apiTemplate", "valueString": "pre-2604" },
          { "name": "resourceType", "valueString": "Observation" },
          { "name": "storageId", "valueString": "2791c25a-c28d-47ea-ab96-3e13162a5b58" }
        ]
      }
    }
  ]
}
```
{% endtab %}
{% endtabs %}

### $delete-api

Removes the API. The resource type stops being served, unless auto-mount regenerates it. The storage and its data stay in place.

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/$delete-api
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "apiId", "valueString": "39473529-a37e-4b98-afc2-bea014bbe68e" }
  ]
}
```
{% endtab %}

{% tab title="Response" %}
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "status", "valueString": "success" }
  ]
}
```
{% endtab %}
{% endtabs %}

## Example: disable history for a resource type

With auto-mount on, Aidbox serves every resource type with history enabled. To turn history off for one resource type, point its API at a `default` storage that uses the resource type's existing table with `history` set to `false`. The new storage overrides the auto-mounted one, and since `$create-storage` reuses an existing table, the data stays in place.

This example disables history for `Observation`, whose data lives in the `observation` table.

Create a storage on that table with history off:

```http
POST /fhir/$create-storage
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "structureDefinition", "valueCanonical": "http://hl7.org/fhir/StructureDefinition/Observation|4.0.1" },
    { "name": "storageType", "valueString": "default" },
    { "name": "tableName", "valueString": "observation" },
    { "name": "history", "valueBoolean": false }
  ]
}
```

Point the `Observation` API at the storage `$create-storage` returned:

```http
POST /fhir/$create-api
Content-Type: application/json

{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "resourceType", "valueString": "Observation" },
    { "name": "storageId", "valueString": "0ff1baab-411d-4682-8e42-0325caf760c5" },
    { "name": "apiTemplate", "valueString": "pre-2604" }
  ]
}
```

Reads, creates, updates, and searches keep working, and updates no longer write history rows. The `_history` interactions, at both the instance and type level, respond with `422` and an `OperationOutcome`:

{% tabs %}
{% tab title="Request" %}
```http
GET /fhir/Observation/{id}/_history
```
{% endtab %}

{% tab title="Response" %}
```json
{
  "resourceType": "OperationOutcome",
  "id": "not-supported",
  "issue": [
    {
      "severity": "fatal",
      "code": "not-supported",
      "diagnostics": "History is disabled for resource type Observation"
    }
  ]
}
```
{% endtab %}
{% endtabs %}

To bring history back, delete the API and storage so the resource type reverts to the auto-mounted storage, or configure the storage with `history` set to `true` and a `historyTableName`.
