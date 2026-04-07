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
