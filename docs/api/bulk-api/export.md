---
description: Export FHIR resources in bulk using the $export operation with cloud storage backends
---

# $export

The `$export` operation implements the [FHIR Bulk Data Export](https://hl7.org/fhir/uv/bulkdata/export.html) specification, allowing you to export large volumes of FHIR resources in ndjson format. This operation is designed for scenarios where you need to extract data for analytics, migration, or backup purposes.

Aidbox supports three export levels: patient-level, group-level, and system-level. When you submit an export request, the server processes it asynchronously and returns a status URL. You can poll this URL to check when the export completes. Once finished, the status endpoint provides signed URLs to download the exported files from your configured cloud storage.

Export operations run one at a time to prevent resource exhaustion. If you attempt to start a new export while another is in progress, the server returns a `429 Too Many Requests` error.

## Cloud storage setup

$export requires cloud storage to be configured. If no storage provider is set, export requests (system-, group-, or patient-level) return **500** with an error such as "storage-type not specified". Storage validation is performed before other checks (e.g. group existence or output format).

Aidbox exports data to cloud storage backends including GCP, Azure, and AWS. Export files are organized in timestamped folders with the pattern `<datetime>_<uuid>` to ensure unique paths for each export operation.

Each cloud provider supports two authentication modes: credential-based (using stored keys or tokens) and workload identity (using cloud-native pod identity). Workload identity is recommended for managed Kubernetes deployments (GKE, AKS) as it eliminates the need to manage credentials in Aidbox resources and uses the pod's identity to authenticate with cloud storage.

### GCP

Start by [creating a Cloud Storage bucket](https://cloud.google.com/storage/docs/creating-buckets) where Aidbox will write export files. The bucket should have appropriate lifecycle policies if you want to automatically delete old exports.

#### Using workload identity

This is the recommended approach for GKE deployments. When running Aidbox in [Google Kubernetes Engine with Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity), your pods automatically authenticate using their Kubernetes service account. No credentials need to be stored in Aidbox.

Before configuring bulk export, set up workload identity following the [GCP Cloud Storage: Workload Identity](../../file-storage/gcp-cloud-storage.md#workload-identity-recommended-since-2510) guide. This includes enabling Workload Identity on your GKE cluster, creating a GCP service account with Cloud Storage permissions, granting URL signing permissions, and binding your Kubernetes service account to the GCP service account.

Once workload identity is configured, set the environment variables:

```bash
BOX_FHIR_BULK_STORAGE_PROVIDER=gcp
BOX_FHIR_BULK_STORAGE_GCP_BUCKET=your-bucket-name
```

With workload identity configured, Aidbox uses the pod's identity to generate signed URLs for export files.

#### Using service account credentials

For non-GKE deployments or when workload identity isn't available, [create a service account](https://cloud.google.com/iam/docs/creating-managing-service-accounts) with Storage Object Admin role on your bucket.

Create a `GcpServiceAccount` resource in Aidbox:

```yaml
resourceType: GcpServiceAccount
id: gcp-service-account
service-account-email: export@your-project.iam.gserviceaccount.com
private-key: |
  -----BEGIN PRIVATE KEY-----
  your-private-key-here
  -----END PRIVATE KEY-----
```

Configure environment variables:

```bash
BOX_FHIR_BULK_STORAGE_PROVIDER=gcp
BOX_FHIR_BULK_STORAGE_GCP_SERVICE_ACCOUNT=gcp-service-account
BOX_FHIR_BULK_STORAGE_GCP_BUCKET=your-bucket-name
```

See also:
* [File storage: GCP Cloud Storage](../../file-storage/gcp-cloud-storage.md)

### Azure

Start by [creating an Azure storage account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create?tabs=azure-portal) and [a blob container](https://learn.microsoft.com/en-us/azure/storage/blobs/blob-containers-portal#create-a-container) where Aidbox will write export files.

#### Using workload identity

This is the recommended approach for AKS deployments. When running Aidbox in [Azure Kubernetes Service with Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview), your pods automatically authenticate using Azure managed identities. No credentials need to be stored in Aidbox.

Before configuring bulk export, set up workload identity following the [Azure Blob Storage: Workload identity](../../file-storage/azure-blob-storage.md#workload-identity) guide. This includes creating a managed identity, configuring federated credentials, assigning storage roles, and setting up your Kubernetes ServiceAccount.

Once workload identity is configured, create an `AzureContainer` resource in Aidbox that references your storage account and container:

```yaml
resourceType: AzureContainer
id: export-container
storage: mystorageaccount
container: exports
```

Note that the `AzureContainer` resource does not include an `account` field for workload identity mode.

Configure environment variables:

```bash
BOX_FHIR_BULK_STORAGE_PROVIDER=azure
BOX_FHIR_BULK_STORAGE_AZURE_CONTAINER=export-container
```

With workload identity configured, Aidbox uses the pod's managed identity to generate user delegation SAS tokens for export files.

#### Using SAS tokens

For non-AKS deployments or when workload identity isn't available, you can use [Shared Access Signature (SAS) tokens](https://learn.microsoft.com/en-us/azure/storage/common/storage-sas-overview) for authentication.

Create an `AzureAccount` resource with your storage account key:

```yaml
resourceType: AzureAccount
id: azure-account
key: your-storage-account-key-here
```

Create an `AzureContainer` resource that references both the storage account and the Azure account:

```yaml
resourceType: AzureContainer
id: export-container
storage: mystorageaccount
container: exports
account:
  resourceType: AzureAccount
  id: azure-account
```

Configure environment variables:

```bash
BOX_FHIR_BULK_STORAGE_PROVIDER=azure
BOX_FHIR_BULK_STORAGE_AZURE_CONTAINER=export-container
```

When the `AzureContainer` has an `account` field, Aidbox uses the account key to generate SAS tokens.

### AWS

Start by [creating an S3 bucket](https://docs.aws.amazon.com/AmazonS3/latest/userguide/create-bucket-overview.html) where Aidbox will write export files. Configure appropriate bucket policies and lifecycle rules for your use case.

#### IAM permissions

The IAM role or user needs the following permissions on the bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::your-bucket-name",
        "arn:aws:s3:::your-bucket-name/*"
      ]
    }
  ]
}
```

Required actions:
- `s3:PutObject` - Write export files to the bucket
- `s3:GetObject` - Generate signed URLs for downloading export results
- `s3:ListBucket` - List bucket contents for export operations

#### Using default credentials

{% hint style="info" %}
Available since version 2601.
{% endhint %}

This is the recommended approach for AWS deployments. When running Aidbox on AWS compute (EKS, ECS, EC2, Lambda), you can use the [default credentials provider chain](https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/credentials-chain.html) instead of storing credentials in Aidbox.

Before configuring bulk export, set up credentials for your compute environment:
- **EKS**: [Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html) or [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- **ECS/Fargate**: [Task IAM Role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html)
- **EC2**: [Instance Profile](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)

See [File storage: AWS S3 — EKS Pod Identity](../../file-storage/aws-s3.md#eks-pod-identity) for detailed setup instructions.

Create an `AwsAccount` resource without credentials:

```yaml
resourceType: AwsAccount
id: aws-account
region: us-east-1
```

Configure environment variables:

```bash
BOX_FHIR_BULK_STORAGE_PROVIDER=aws
BOX_FHIR_BULK_STORAGE_AWS_ACCOUNT=aws-account
BOX_FHIR_BULK_STORAGE_AWS_BUCKET=your-bucket-name
```

When `access-key-id` is omitted, Aidbox uses the default credentials provider to authenticate with S3.

#### Using access keys

For S3-compatible services (MinIO, Garage) or legacy setups, use explicit credentials.

[Create an IAM user](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html) with the [IAM permissions](#iam-permissions) and create an `AwsAccount` resource with credentials:

```yaml
resourceType: AwsAccount
id: aws-account
region: us-east-1
access-key-id: your-access-key-id
secret-access-key: your-secret-access-key
```

Configure environment variables:

```bash
BOX_FHIR_BULK_STORAGE_PROVIDER=aws
BOX_FHIR_BULK_STORAGE_AWS_ACCOUNT=aws-account
BOX_FHIR_BULK_STORAGE_AWS_BUCKET=your-bucket-name
```

See also:
* [File storage: AWS S3](../../file-storage/aws-s3.md)

## Parameters

The `$export` operation accepts several parameters to customize the export: **query parameters on GET**, or the same parameters inside a **FHIR Parameters resource** when you use **POST** on patient- and group-level exports (see [POST with a Parameters body](#post-with-a-parameters-body-patient-and-group)). Supported parameter names are `_outputFormat`, `_since`, `_until`, `_type`, `_typeFilter`, and `patient`.

| Parameter       | Description |
| --------------- | ----------- |
| `_outputFormat` | Specifies the format in which the server generates files. Default: `application/fhir+ndjson`. Canonical values are `application/fhir+ndjson` (generates `.ndjson` files) and `application/fhir+ndjson+gzip` (generates compressed `.ndjson.gz` files). |
| `_type`         | Comma-separated list of resource types to include in the export. Only the specified types will be exported. |
| `_since`        | Includes only resources whose **last modification time** is **after** the given instant (`ts > _since`). ISO 8601 format. |
| `_until`        | Includes only resources whose **last modification time** is **before** the given instant (`ts < _until`). ISO 8601 format. Together with `_since`, this defines an open window on the modification timestamp. |
| `_typeFilter`   | Restricts exported rows using FHIR search criteria **per resource type**, in the form `ResourceType?searchParams` (same idea as the [FHIR Bulk Data `_typeFilter`](https://hl7.org/fhir/uv/bulkdata/export.html) parameter). You may repeat `_typeFilter` multiple times. Multiple filters for the **same** resource type are combined with **OR**. If `_type` is present, every type used in `_typeFilter` must also appear in `_type`; types listed in `_type` but without a filter are exported in full. Standard FHIR search parameters such as `_id` are allowed. Not allowed inside the search part: `_sort`, `_count`, `_page`, `_total`, `_summary`, `_elements`, `_include`, `_revinclude`, `_has`, `_assoc`, `_with`. |
| `patient`       | Restricts the export to specific patients. **GET:** comma-separated patient **ids** (not full references), e.g. `patient=pt-1,pt-2`. Supported only on **patient-level** GET. **POST:** repeat a `parameter` named `patient`, each with `valueReference.reference` set to `Patient/{id}`. Supported on **patient-level** and **group-level** POST; for group export, every listed patient must exist and be a **member** of that group. |
| `onPatientError` | Controls behavior when `patient` references are invalid or not group members. `fail` (default): abort with **422**. `ignore`: drop invalid refs, proceed with valid ones, report dropped in export status `error[]`. See [Lenient patient handling](#lenient-patient-handling). |
| `_elements` | *Experimental.* Comma-separated list of root element names to include in exported resources. Mandatory elements (`resourceType`, `id`, `meta`) are always included. Resources are tagged with `SUBSETTED`. Server may ignore this parameter if `Prefer: handling=lenient` is not set. |

### POST with a Parameters body (patient and group)

For **patient-level** and **group-level** exports you can use **POST** with a JSON body of `resourceType: Parameters` instead of query string parameters. System-level export (`GET /fhir/$export`) does not support POST with a Parameters body in this implementation.

Use the same async headers as for GET and include a body content type:

- `Accept: application/fhir+json`
- `Content-Type: application/fhir+json`
- `Prefer: respond-async`

Each parameter uses the same name as its query-string counterpart. The value type for each:

| Parameter       | Type             |
| --------------- | ---------------- |
| `_outputFormat` | `valueString`    |
| `_since`        | `valueInstant`   |
| `_until`        | `valueInstant`   |
| `_type`         | `valueString`    |
| `_typeFilter`   | `valueString`    |
| `patient`       | `valueReference` |

For `patient`, set `valueReference.reference` to `Patient/{id}`. For `_type`, use one part with comma-separated resource types or repeat `_type` several times; Aidbox joins all `_type` values into one comma-separated list. Repeat `_typeFilter` or `patient` parts when you need multiple values.

Any other parameter name in the body returns **400** with an operation outcome. Unknown or invalid `_typeFilter` syntax, search errors, or patient ids that do not exist (or are not in the group, for group export) also return **400**.

**Example:** POST `/fhir/Patient/$export`

```http
POST /fhir/Patient/$export
Accept: application/fhir+json
Content-Type: application/fhir+json
Prefer: respond-async
```

```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "_type", "valueString": "Patient,Observation" },
    { "name": "_since", "valueInstant": "2024-01-01T00:00:00Z" },
    { "name": "_until", "valueInstant": "2025-01-01T00:00:00Z" },
    { "name": "_typeFilter", "valueString": "Observation?status=final" },
    { "name": "patient", "valueReference": { "reference": "Patient/pt-1" } }
  ]
}
```

## Storage override parameters

{% hint style="info" %}
Available since version 2605.
{% endhint %}

You can override the system-level cloud storage configuration on a per-request basis using Aidbox-specific parameters. This is useful when different export jobs need to write to different buckets or storage accounts.

Storage override parameters use the `_aidbox.` prefix to distinguish them from standard FHIR parameters:

| Parameter                  | Type        | Description                                                    |
| -------------------------- | ----------- | -------------------------------------------------------------- |
| `_aidbox.storageProvider`  | `string`    | Storage provider type: `gcp`, `aws`, or `azure`.               |
| `_aidbox.storageBucket`    | `string`    | Bucket name (GCP or AWS S3).                                   |
| `_aidbox.storageAccount`   | `Reference` | Cloud account resource reference (e.g. `AwsAccount/my-acct`).  |
| `_aidbox.azureStorage`     | `string`    | Azure storage account name.                                    |
| `_aidbox.azureContainer`   | `string`    | Azure blob container name.                                     |

These parameters can be passed as GET query parameters or in a POST Parameters body. Only the parameters you specify are overridden; unspecified values fall back to the system-level settings.

{% tabs %}
{% tab title="GET" %}
```http
GET /fhir/Group/grp-1/$export?_type=Patient&_aidbox.storageBucket=custom-bucket&_aidbox.storageProvider=gcp
```
{% endtab %}

{% tab title="POST" %}
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "_type", "valueString": "Patient" },
    { "name": "_aidbox.storageProvider", "valueString": "aws" },
    { "name": "_aidbox.storageBucket", "valueString": "custom-bucket" },
    { "name": "_aidbox.storageAccount", "valueReference": { "reference": "AwsAccount/my-acct" } }
  ]
}
```
{% endtab %}
{% endtabs %}

## Patient-level export

Patient-level export extracts all Patient resources and resources associated with them. The association is defined by [FHIR Patient Compartment](http://hl7.org/fhir/r4/compartmentdefinition-patient.html), which specifies which resource types reference patients and through which fields.

To start a patient-level export, send **GET** to `/fhir/Patient/$export` with optional query parameters, or **POST** to the same URL with a [Parameters JSON body](#post-with-a-parameters-body-patient-and-group) (for example when using `_typeFilter` or repeated `patient` references).

{% tabs %}
{% tab title="Request" %}
**Rest console**

```http
GET /fhir/Patient/$export
Accept: application/fhir+json
Prefer: respond-async
```
{% endtab %}

{% tab title="Response" %}
**Status**

202 Accepted

**Headers**

* `Content-Location` — URL to check export status (e.g. `/fhir/$export-status/<id>`)
{% endtab %}
{% endtabs %}

Poll the status endpoint to check when the export completes:

{% tabs %}
{% tab title="Request" %}
**Rest console**

```http
GET /fhir/$export-status/<id>
```
{% endtab %}

{% tab title="Response (completed)" %}
**Status**

200 OK

**Body**

```json
{
  "status": "completed",
  "transactionTime": "2021-12-08T08:28:06.489Z",
  "requiresAccessToken": false,
  "request": "[base]/fhir/Patient/$export",
  "output": [
    {
      "type": "Patient",
      "url": "https://storage/some-url",
      "count": 2
    },
    {
      "type": "Observation",
      "url": "https://storage/some-other-url",
      "count": 15
    }
  ],
  "error": []
}
```
{% endtab %}
{% endtabs %}

To cancel an active export, send a DELETE request to the status endpoint:

{% tabs %}
{% tab title="Request" %}
**Rest console**

```http
DELETE /fhir/$export-status/<id>
```
{% endtab %}

{% tab title="Response" %}
**Status**

202 Accepted
{% endtab %}
{% endtabs %}

## Group-level export

Group-level export extracts all Patient resources that belong to a specified Group resource, plus all resources associated with those patients. The group characteristics themselves are not exported. Association is defined by the [FHIR Patient Compartment](http://hl7.org/fhir/r4/compartmentdefinition-patient.html).

To start a group-level export, send **GET** to `/fhir/Group/<group-id>/$export` with optional query parameters, or **POST** to the same path with a [Parameters body](#post-with-a-parameters-body-patient-and-group) to pass `patient` restrictions or long `_typeFilter` values.

{% tabs %}
{% tab title="Request" %}
**Rest console**

```http
GET /fhir/Group/<group-id>/$export
Accept: application/fhir+json
Prefer: respond-async
```
{% endtab %}

{% tab title="Response" %}
**Status**

202 Accepted

**Headers**

* `Content-Location` — URL to check export status (e.g. `/fhir/$export-status/<id>`)
{% endtab %}
{% endtabs %}

The status endpoint works the same way as patient-level export. Poll `/fhir/$export-status/<id>` to check progress, and send a DELETE request to cancel.

## System-level export

System-level export extracts data from the entire FHIR server, whether or not it's associated with a patient. Use the `_type` parameter to restrict which resource types are exported.

{% hint style="warning" %}
System-level export works only for standard FHIR resources, not for custom resources defined in your Aidbox configuration.
{% endhint %}

{% tabs %}
{% tab title="Request" %}
```http
GET /fhir/$export
Accept: application/fhir+json
Prefer: respond-async
```
{% endtab %}

{% tab title="Response (completed)" %}
**Status**

200 OK

**Body**

```json
{
  "status": "completed",
  "transactionTime": "2021-12-08T08:28:06.489Z",
  "requiresAccessToken": false,
  "output": [
    {
      "type": "Patient",
      "url": "https://storage/some-url",
      "count": 2
    },
    {
      "type": "Practitioner",
      "url": "https://storage/some-other-url",
      "count": 5
    }
  ],
  "error": []
}
```
{% endtab %}
{% endtabs %}

The status endpoint works the same way as other export levels. Poll `/fhir/$export-status/<id>` to check progress, and send a DELETE request to cancel.

## Consent-based patient filtering

{% hint style="info" %}
Available since version 2605.
{% endhint %}

Group-level export can filter patients based on FHIR [Consent](https://hl7.org/fhir/r4/consent.html) resources. This enables workflows where patient data sharing requires explicit agreement (opt-in) or where patients can refuse sharing (opt-out) — for example, [Da Vinci PDex](https://hl7.org/fhir/us/davinci-pdex/STU2.1/) payer-to-payer exchange and provider access.

| Parameter                        | Type   | Cardinality | Description                                                                            |
| -------------------------------- | ------ | ----------- | -------------------------------------------------------------------------------------- |
| `consentStrategy`                | `code` | 0..1        | `opt-in` or `opt-out`. Determines how consents affect patient inclusion.                |
| `consentProfile`                 | `uri`  | 0..1        | StructureDefinition URL to filter consents by `meta.profile`. Omit to match any Consent.|
| `organizationIdentifierSystem`   | `uri`  | 0..1        | Which `Organization.identifier.system` to use for actor matching (opt-in only).          |

{% hint style="warning" %}
For `opt-in`, both `organizationIdentifierSystem` and a JWT token with `extensions.hl7-b2b.organization_id` are required. Missing either returns **422**.
{% endhint %}

### Consent resource requirements

Consent resources must have:

- `status` = `active`
- `provision.type` = `permit` (for opt-in) or `deny` (for opt-out)
- `provision.period` with `start` and `end` covering the current date
- `meta.profile` matching `consentProfile` (if specified)

For **opt-in**, the Consent must also have `provision.actor` entries with:

- An actor with `role.coding[0].code` = `performer` referencing the **source** Organization (the requesting payer)
- An actor with `role.coding[0].code` = `IRCP` referencing the **recipient** Organization (resolved from `Group.managingEntity`)

Both organizations are matched by their `identifier` where `system` equals `organizationIdentifierSystem`.

### Opt-out strategy

All group members are included by default. Members are excluded only if they have an active Consent with `provision.type = "deny"` matching the specified profile and a valid period covering the current date.

{% tabs %}
{% tab title="GET" %}
```http
GET /fhir/Group/grp-1/$export?_type=Patient&consentStrategy=opt-out&consentProfile=http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-provider-consent
```
{% endtab %}

{% tab title="POST" %}
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "_type", "valueString": "Patient" },
    { "name": "consentStrategy", "valueCode": "opt-out" },
    { "name": "consentProfile", "valueUri": "http://hl7.org/fhir/us/davinci-pdex/StructureDefinition/pdex-provider-consent" }
  ]
}
```
{% endtab %}
{% endtabs %}

### Opt-in strategy

No members are included by default. Members are included only if they have an active Consent with `provision.type = "permit"`, matching source and recipient organization actors, and a valid period.

The **source organization** is identified from the JWT access token's [UDAP B2B Authorization Extension](https://build.fhir.org/ig/HL7/fhir-udap-security-ig/branches/master/b2b.html) (`extensions.hl7-b2b.organization_id`). The **recipient organization** is resolved from `Group.managingEntity`, using the `organizationIdentifierSystem` to select the correct identifier.

{% tabs %}
{% tab title="GET" %}
```http
GET /fhir/Group/grp-1/$export?_type=Patient&consentStrategy=opt-in&consentProfile=http://hl7.org/fhir/us/davinci-hrex/StructureDefinition/hrex-consent&organizationIdentifierSystem=urn:oid:2.16.840.1.113883.4.4
```
{% endtab %}

{% tab title="POST" %}
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "_type", "valueString": "Patient" },
    { "name": "consentStrategy", "valueCode": "opt-in" },
    { "name": "consentProfile", "valueUri": "http://hl7.org/fhir/us/davinci-hrex/StructureDefinition/hrex-consent" },
    { "name": "organizationIdentifierSystem", "valueUri": "urn:oid:2.16.840.1.113883.4.4" }
  ]
}
```
{% endtab %}
{% endtabs %}

### UDAP B2B token configuration

For opt-in workflows, the requesting client must present a **JWT** access token containing the B2B extension. The Client must be configured with `token_format: "jwt"` in the `client_credentials` auth settings — opaque tokens do not carry B2B claims.

Add the `client-hl7B2b` extension to your Client resource:

```json
{
  "resourceType": "Client",
  "id": "payer-client",
  "grant_types": ["client_credentials"],
  "auth": {
    "client_credentials": {
      "token_format": "jwt"
    }
  },
  "extension": [
    {
      "url": "http://health-samurai.io/fhir/core/StructureDefinition/client-hl7B2b",
      "extension": [
        {
          "url": "organization",
          "valueReference": { "reference": "Organization/my-org" }
        },
        {
          "url": "organizationIdentifierSystem",
          "valueUri": "urn:oid:2.16.840.1.113883.4.4"
        },
        {
          "url": "purposeOfUse",
          "valueCoding": {
            "system": "http://terminology.hl7.org/CodeSystem/v3-ActReason",
            "code": "HPAYMT"
          }
        }
      ]
    }
  ]
}
```

When this extension is present, `/auth/token` includes the [UDAP B2B Authorization Extension](https://build.fhir.org/ig/HL7/fhir-udap-security-ig/branches/master/b2b.html) in the JWT:

```json
{
  "extensions": {
    "hl7-b2b": {
      "version": "1",
      "organization_id": "urn:oid:2.16.840.1.113883.4.4#12-3456789",
      "organization_name": "My Organization",
      "purpose_of_use": ["http://terminology.hl7.org/CodeSystem/v3-ActReason#HPAYMT"]
    }
  }
}
```

The `organization_id` is resolved from the referenced Organization's identifier where `system` matches `organizationIdentifierSystem`.

## Lenient patient handling

{% hint style="info" %}
Available since version 2605.
{% endhint %}

By default, `$export` returns **422** when a `patient` reference points to a non-existent Patient or a Patient that is not a member of the specified Group. This follows the base [FHIR Bulk Data Export](https://hl7.org/fhir/uv/bulkdata/export.html) specification.

The [Da Vinci `$davinci-data-export`](http://hl7.org/fhir/us/davinci-atr/OperationDefinition-davinci-data-export.html) specification requires different behavior: invalid patient references should be silently ignored, and the export should proceed with valid ones.

Set `onPatientError=ignore` to enable this behavior:

| `onPatientError` | Behavior |
| ---------------- | -------- |
| `fail` (default) | Abort with **422** if any patient reference is invalid or not a group member. |
| `ignore`         | Drop invalid references. Proceed with valid ones. Report each dropped patient as an OperationOutcome warning in the export status `error[]` array. |

When all requested patients are invalid, the server returns an immediate **200** with an empty `output[]` and warnings in `error[]` — no async export is started.

{% tabs %}
{% tab title="POST" %}
```json
{
  "resourceType": "Parameters",
  "parameter": [
    { "name": "_type", "valueString": "Patient" },
    { "name": "onPatientError", "valueCode": "ignore" },
    { "name": "patient", "valueReference": { "reference": "Patient/valid-member" } },
    { "name": "patient", "valueReference": { "reference": "Patient/non-existent" } }
  ]
}
```
{% endtab %}

{% tab title="Export status error[]" %}
```json
{
  "status": "completed",
  "output": [
    { "type": "Patient", "url": "https://storage/...", "count": 1 }
  ],
  "error": [
    { "type": "OperationOutcome",
      "url": "urn:warning:Patient/non-existent ignored: not found or not a member of the group" }
  ]
}
```
{% endtab %}
{% endtabs %}
