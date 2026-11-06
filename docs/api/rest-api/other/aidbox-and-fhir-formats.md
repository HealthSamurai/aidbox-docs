---
description: Understand Aidbox storage format differences from FHIR including parsed references and union types.
---

# Aidbox and FHIR formats

Aidbox stores FHIR resources almost as is with 2 types of isomorphic transformations:

* References
* Union (Choice Types)

### References:

In FHIR, references are represented as URI string. In most cases, you are interested in discrete parts of references like resource id and type. For performance and accuracy reasons Aidbox parses reference and stores its parts in discrete fields. There are three types of references - absolute, relative, and local. Aidbox parses them into different attributes.

**Relative** (interpreted as a reference to a resource on the same server; trigger referential consistency check) :

```yaml
# FHIR
subject:
  reference: "Patient/pt-1" 

# Aidbox
subject:
  resourceType: "Patient"
  id: "pt-1"
```

**reference** is parsed into a pair of **`{id,resourceType}`** attributes

**Absolute** (interpreted as a reference to an external resource;  no ref validation)

```yaml
# FHIR
subject:
  reference: "http://external/fhir/Patient/pt-1" 

# Aidbox
subject:
  uri: "http://external/fhir/Patient/pt-1"
```

reference is parsed into the **uri** attribute

**Local** (interpreted as a local ref to contained resources )

```yaml
# FHIR
subject:
  reference: "#pt" 

# Aidbox
subject:
  localRef: "pt"
```

reference is parsed into a **localRef** attribute

### Union (Choice) Types:

Some elements can have multiple types. Such elements in FHIR spec prefixed with `[x]` like `Observation.value[x]` and represented in JSON in a _wrong_ (postfixed) way like`Observation.valueString` . The simple logical check "why it's wrong" is "you could not have a collection of union elements in FHIR JSON!". Aidbox fixes this moving type as a key inside a nested object - `valueString:... => value: {string: ...}`

```yaml
#FHIR
resourceType: Observation
valueQuantity:
  unit: ...
  value: ...

# becomes Aidbox
resourceType: Observation
value:
  Quantity:
    unit: ...
    value: ...
```

## Turn off the Aidbox format API

{% hint style="info" %}
Available since the 2610 release.
{% endhint %}

Aidbox serves two REST APIs:

* the FHIR API under `/fhir` (for example `GET /fhir/Patient`), which takes and returns FHIR format;
* the Aidbox format API outside `/fhir` (for example `GET /Patient`), which takes and returns Aidbox format.

The Aidbox format API stores a request body without the FHIR to Aidbox conversion. If you send a FHIR resource there, Aidbox stores `subject: {reference: "Patient/pt-1"}` as is, and the search `GET /fhir/Observation?subject=Patient/pt-1` doesn't find the resource.

To make Aidbox accept data through the FHIR API alone, set [`BOX_FHIR_AIDBOX_FORMAT_API_ENABLED`](../../../reference/all-settings.md#fhir.aidbox-format-api.enabled) to `false`:

```yaml
BOX_FHIR_AIDBOX_FORMAT_API_ENABLED: false
```

Aidbox reads the setting from the environment at startup. Restart Aidbox to change it.

### Endpoints that turn off

With `false`, the Aidbox format endpoints answer `404` with `<METHOD> <path> not found`. Send these requests to the FHIR API:

| Aidbox format API                                                    | FHIR API                                                     |
| -------------------------------------------------------------------- | ------------------------------------------------------------ |
| `/<type>`, `/<type>/<id>`: create, read, update, patch, delete, search | `/fhir/<type>`, `/fhir/<type>/<id>`                        |
| `GET /<type>/_history`, `GET /<type>/<id>/_history`                  | `GET /fhir/<type>/_history`, `GET /fhir/<type>/<id>/_history` |
| `POST /` with a `batch` or `transaction` Bundle                      | `POST /fhir`                                                 |
| `POST /$sql`                                                         | `POST /fhir/$sql`                                            |
| `GET /metadata`                                                      | `GET /fhir/metadata`                                         |
| `POST /$validate`, `POST /<type>/$validate`                          | `POST /fhir/$validate`, `POST /fhir/<type>/$validate`        |
| `GET /Patient/<id>/$everything`                                      | `GET /fhir/Patient/<id>/$everything`                         |
| `GET /Observation/$lastn`                                            | `GET /fhir/Observation/$lastn`                               |
| `GET /$export`, `GET /Patient/$export`, `GET /Group/<id>/$export`    | `GET /fhir/$export`, `GET /fhir/Patient/$export`, `GET /fhir/Group/<id>/$export` |
| `POST /$import`, `POST /v2/$import`                                  | `POST /fhir/$import`, `POST /v2/fhir/$import`                |
| `POST /$load`, `POST /<type>/$load`                                  | `POST /fhir/$load`, `POST /fhir/<type>/$load`                |
| `POST /terminology/$import`                                          | `POST /fhir/terminology/$import`                             |
| `POST /Mapping/<id>/$apply`                                          | `POST /fhir/Mapping/<id>/$apply`                             |
| `POST /$drop-cache`                                                  | `POST /fhir/$drop-cache`                                     |
| `/Organization/<org-id>/aidbox/<type>` ([organization-based access control](../../../access-control/authorization/scoped-api/organization-based-hierarchical-access-control/README.md)) | `/Organization/<org-id>/fhir/<type>` |

These endpoints have no `/fhir` counterpart and keep working with `false`:

* `POST /rpc`;
* `GET /<type>/$dump`, `GET /<type>/$dump-csv` and `POST /$dump-sql`;
* `GET /<type>/$changes`;
* `GET /$query/<name>` and `POST /$query/<name>` ([AidboxQuery](../aidbox-search.md));
* `POST /$psql` and `POST /$to-format/<format>`.

### Move to the FHIR API

Before you set `false`, check the clients, policies and configuration resources that call the Aidbox format API:

* **Requests.** Add the `/fhir` prefix: `PUT /Client/my-app` becomes `PUT /fhir/Client/my-app`.
* **Request bodies.** Write them in FHIR format: `subject: {reference: "Patient/pt-1"}` instead of `subject: {resourceType: Patient, id: pt-1}`, `valueString` instead of `value: {string: ...}`. To convert an Aidbox format resource, send it to [`POST /$to-format/fhir`](to-format.md).
* **AccessPolicy `uri` patterns.** A `matcho` policy with `uri: /Patient` doesn't match `GET /fhir/Patient`. Rewrite the pattern with the prefix:

  ```yaml
  engine: matcho
  matcho:
    uri: '#^/fhir/Patient'
    request-method: get
  ```

* **Mappings.** Use `/fhir/<type>` URLs in the `request.url` of the transaction a [Mapping](../../../modules/integration-toolkit/mappings.md) returns. Aidbox routes each entry like a separate request, so `url: /Patient/pt-1` answers `404` with `false` and `$apply` fails. [HL7 v2](../../../modules/integration-toolkit/hl7-v2-integration/README.md) messages that use such a mapping end with `status: error`.

### Fix references stored without conversion

To find resources that the Aidbox format API stored with FHIR references, query the reference element with [`$sql`](sql-endpoints.md):

```http
POST /fhir/$sql
Content-Type: application/json

["SELECT id FROM observation WHERE resource #>> '{subject,reference}' IS NOT NULL"]
```

To fix a resource, read it with `GET /fhir/Observation/<id>` and send the same body back with `PUT /fhir/Observation/<id>`. Aidbox converts the references on write, and the search by `subject` finds the resource.
