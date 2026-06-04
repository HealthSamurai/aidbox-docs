---
description: Use RPC to run a validation operation to check a resource conformance
---

# Asynchronous resource validation

### Asynchronous Batch Validation

It may happen that you updated your profiles when data is already in your database, or you want to efficiently load a batch of data and validate it later. Batch validation runs on the asynchronous task engine: each validation run is split into id-range chunks that are executed in parallel by the task scheduler, and the results are persisted, so they survive Aidbox restarts.

The API consists of 4 procedures and a couple of resources:

* [aidbox.validation/batch-validation](asynchronous-resource-validation.md#aidbox-validation-batch-validation) - run validation for one resource type
* [aidbox.validation/resources-batch-validation-task](asynchronous-resource-validation.md#aidbox-validation-resources-batch-validation-task) - run validation for many resource types
* [aidbox.validation/batch-validation-result](asynchronous-resource-validation.md#aidbox-validation-batch-validation-result) - inspect results
* [aidbox.validation/clear-batch-validation](asynchronous-resource-validation.md#aidbox-validation-clear-batch-validation) - clear validation results

#### Parallelism

A validation run is split into chunks of `chunkSize` resources (1000 by default). Chunks are independent tasks executed by the scheduler, so a single large table is validated in parallel. The number of executor threads is controlled by the `scheduler-executors` setting (`BOX_SCHEDULER_EXECUTORS`, default `4`) — increase it to speed up validation of large datasets.

{% hint style="warning" %}
The previous implementation based on the Aidbox Workflow (AWF) engine is deprecated. It is still used when the setting `batch-validation-legacy-engine` (`BOX_BATCH_VALIDATION_LEGACY_ENGINE`) is set to `true`, or when the async task scheduler is not available. The legacy engine will be removed in a future release. Legacy-only parameters: `filter`, `limit`, `async`.
{% endhint %}

#### Prepare data

To illustrate let's create some invalid data in Aidbox:

```yaml
POST /Patient
content-type: text/yaml

id: 'pt1'
birthDate: '1980-03-05'
```

Break data from DB Console:

```sql
update patient
set resource = resource || '{"ups": "extra"}'
where id = 'pt1'
returning *
```

#### aidbox.validation/batch-validation

Validate existing data of one resource type with the rpc `aidbox.validation/batch-validation`:

```yaml
POST /rpc
content-type: text/yaml

method: aidbox.validation/batch-validation
params:
  # resourceType to validate
  resource: Patient
  ## specify profiles to validate against
  # profiles: ['profile-url-1', 'profile-url-2']
  ## stop the run after this many invalid resources
  # errorsThreshold: 10
  ## resources per chunk task (default 1000)
  # chunkSize: 1000

# response
result:
  run-id: c2b2bcb9-30f3-4632-9a8a-1d04b3a14b99
  operation-id: c2b2bcb9-30f3-4632-9a8a-1d04b3a14b99
  status: in-progress
  chunks: 1
```

The call returns immediately; validation runs in the background. Use `run-id` with [batch-validation-result](asynchronous-resource-validation.md#aidbox-validation-batch-validation-result) to poll for the outcome.

If you pass `profiles`, every resource is validated against the given profile URLs in addition to its base schema — this is the way to check how a new profile version would affect existing data.

#### aidbox.validation/resources-batch-validation-task

Validate several resource types at once. One chunked run is created across every table selected by `include`/`exclude`:

```yaml
POST /rpc
accept: text/yaml
content-type: text/yaml

method: aidbox.validation/resources-batch-validation-task
params:
  include: ['patient', 'observation']
  # error-threshold: 10000
  # profiles: ['profile-url-1']
  # chunkSize: 1000

# response
result:
  run-id: 7addda33-003e-4892-a1d9-0faffbedf86d
  operation-id: 7addda33-003e-4892-a1d9-0faffbedf86d
  status: in-progress
  chunks: 12
```

{% hint style="info" %}
If you specify `include` param, only types you passed will be validated.

If you specify `exclude` param, all types will be validated except the ones you passed.

`include` and `exclude` params cannot be used together. With neither, all resource types are validated.
{% endhint %}

When `error-threshold` (or `errorsThreshold`) is reached, the whole operation is cancelled — remaining chunks are stopped and the run status becomes `cancelled`.

#### aidbox.validation/batch-validation-result

Both run methods respond instantly and validate in the background. Get the current state and validation problems with `aidbox.validation/batch-validation-result`:

```yaml
POST /rpc?_format=yaml
content-type: text/yaml

method: aidbox.validation/batch-validation-result
params:
  id: c2b2bcb9-30f3-4632-9a8a-1d04b3a14b99
  # problems are paged; defaults: page 0, pageSize 100
  # page: 0
  # pageSize: 100

# response
status: 200
result:
  run:
    id: c2b2bcb9-30f3-4632-9a8a-1d04b3a14b99
    resource: patient
    status: in-progress
    invalid: 2
    resourceType: BatchValidationRun
  status: completed   # in-progress | completed | cancelled | failed
  problems:
    - resource:
        id: pt1
        resourceType: Patient
      errors:
        - path: ups
          type: unknown-key
```

`status` reflects the live state of the scheduled chunk tasks. `run.invalid` is the total number of invalid resources recorded so far. `problems` is paged with `page`/`pageSize`, so large result sets can be inspected fully.

#### aidbox.validation/clear-batch-validation

When you do not need results of this validation you can clean up resources with:

```yaml
POST /rpc?_format=yaml
content-type: text/yaml

method: aidbox.validation/clear-batch-validation
params:
  id: c2b2bcb9-30f3-4632-9a8a-1d04b3a14b99
```

This deletes the `BatchValidationRun`, its `BatchValidationError` resources and the scheduler bookkeeping for the operation.

#### BatchValidationRun & BatchValidationError Resources

When you run a validation operation Aidbox internally creates a BatchValidationRun resource and puts errors of validation in BatchValidationError. You can access these resources through standard CRUD/Search API — for example, to aggregate errors by type or build a report:

```yaml
GET /BatchValidationError?.run.id=c2b2bcb9-30f3-4632-9a8a-1d04b3a14b99&_format=yaml&_result=array

# response
- run:
    id: c2b2bcb9-30f3-4632-9a8a-1d04b3a14b99
    resourceType: BatchValidationRun
  errors:
    - path: ups
      type: unknown-key
  resource:
    id: pt1
    resourceType: Patient
  id: 6c8c5045-71b8-43d4-9e44-b3a0bfbe6e54
```

Both resources are persisted in the database, so validation results survive Aidbox restarts.
