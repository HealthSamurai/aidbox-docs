---
description: Delete all data belonging to an organization and its nested organizations when offboarding a tenant.
keywords: [purge, offboarding, tenant deletion, orgbac, multi-tenant, data removal]
---

# Organization purge

{% hint style="info" %}
Available since Aidbox 2608.
{% endhint %}

`$purge` removes the data an organization owns. Use it to offboard a tenant: the operation deletes
the matching rows from the resource tables and from the history tables, with no tombstones and no
version left behind. Deleted data cannot be recovered.

{% hint style="danger" %}
`$purge` bypasses referential integrity checks and access policies. It issues raw `DELETE`
statements, so no subscription, trigger or other change hook sees the removals. Take a backup before
you offboard a tenant.
{% endhint %}

## Request

```http
POST <AIDBOX_BASE_URL>/Organization/<org-id>/fhir/$purge
```

The body is a `Parameters` resource. Name the resource types you want removed, or ask for all of
them. Pick one form: a request that carries both returns `422`.

### Named resource types

Pass one `resourceType` parameter per type:

```http
POST /Organization/org-a/fhir/$purge
Content-Type: application/fhir+json

{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "resourceType", "valueString": "Patient"},
    {"name": "resourceType", "valueString": "Observation"}
  ]
}
```

Aidbox answers with the number of rows it deleted per type:

```json
{
  "resourceType": "OperationOutcome",
  "id": "informational",
  "issue": [
    {
      "severity": "information",
      "code": "informational",
      "diagnostics": "Purged for Organization/org-a - Patient: 12 current, 30 history; Observation: 148 current, 148 history"
    }
  ]
}
```

### All resource types

`allResourceTypes` covers every type Aidbox treats as tenant data, and the tenant's `Organization`
resources with them:

```http
POST /Organization/org-a/fhir/$purge
Content-Type: application/fhir+json

{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "allResourceTypes", "valueBoolean": true}
  ]
}
```

`allResourceTypes` needs FHIR Schema mode. Without it Aidbox has no resource classification to work
from and refuses the request with `422`.

## What the operation deletes

Aidbox matches rows by the tenant tag that the organization-scoped API writes into
`meta.extension`, over the organization you name and every organization nested under it through
`partOf`. An organization that carries the tenant tag but sits outside the `partOf` tree belongs to
a different scope, so `$purge` leaves it alone.

Three rules decide the rest:

Ownership: `$purge` takes what the tenant owns. A `shared` resource owned by an ancestor
organization stays with that ancestor, even though the tenant can read it. A `system-shared`
resource survives every purge, even when it carries the purged organization's tag.

`Organization`: only `allResourceTypes` removes the tenant tree. Naming `Organization` in a
`resourceType` parameter returns `422`.

History: the current row decides. When a resource carries the tenant tag, Aidbox deletes it together
with all of its stored versions, whatever tag those versions carry. When the current row has no
tenant tag, Aidbox keeps the resource and its history, even if an earlier version was tagged. A
resource the tenant owned and then deleted has no current row, so its history stays.

## Resources Aidbox does not purge

`allResourceTypes` skips Aidbox system resources: identity and access configuration, operational
state, scheduler and migration bookkeeping, SDC documents, console state. The full list lives in the
system resources reference.

{% content-ref url="../../../reference/system-resources-reference/core-module-resources.md" %}
[Core Module Resources](../../../reference/system-resources-reference/core-module-resources.md)
{% endcontent-ref %}

On top of the system resources, `$purge` skips FHIR canonical resources. A canonical describes how
data is shaped rather than holding a patient record, and one tenant's `ValueSet` or `Questionnaire`
is often referenced from outside that tenant, so offboarding leaves them in place:

```text
ActivityDefinition, ActorDefinition, CapabilityStatement, ChargeItemDefinition,
Citation, CodeSystem, CompartmentDefinition, ConceptMap, ConditionDefinition,
DeviceDefinition, EffectEvidenceSynthesis, EventDefinition, Evidence, EvidenceReport,
EvidenceVariable, ExampleScenario, GraphDefinition, ImplementationGuide, Library,
Measure, MessageDefinition, NamingSystem, ObservationDefinition, OperationDefinition,
PlanDefinition, Questionnaire, Requirements, ResearchDefinition,
ResearchElementDefinition, RiskEvidenceSynthesis, SearchParameter, SpecimenDefinition,
StructureDefinition, StructureMap, SubscriptionTopic, TerminologyCapabilities, TestPlan,
TestScript, ValueSet
```

Three more types stay out of `allResourceTypes`:

`AuditEvent`: the record of what happened to the tenant, including the purge itself.

`OperationOutcome`: Aidbox does not store these as resources.

`ViewDefinition`: SQL on FHIR view definitions.

{% hint style="info" %}
`allResourceTypes` asks Aidbox to decide what counts as tenant data, so these lists define its
reach. A named list is your own decision: name `AuditEvent`, `Questionnaire`, `PlanDefinition` or
most of the other canonicals above in a `resourceType` parameter and `$purge` deletes it.

The exception is the canonicals Aidbox keeps in FAR rather than in the resource tables. OrgBAC does
not reach them, so naming one returns `422`:

```text
CapabilityStatement, CompartmentDefinition, Library, OperationDefinition,
SearchParameter, StructureDefinition, SubscriptionTopic, ViewDefinition
```

`CodeSystem`, `ValueSet` and `ConceptMap` join that list once you move the terminology engine off
its default `legacy` setting, since `local` and `hybrid` keep them in FAR. `OperationOutcome` is not
a stored type, so naming it returns `422` as an unknown resource type.
{% endhint %}

## Asynchronous purge

A tenant with a large data set takes minutes to purge. Send `Prefer: respond-async` and Aidbox
accepts the work and returns `202` with a `Content-Location` header:

```http
POST /Organization/org-a/fhir/$purge
Prefer: respond-async
Content-Type: application/fhir+json

{
  "resourceType": "Parameters",
  "parameter": [
    {"name": "allResourceTypes", "valueBoolean": true}
  ]
}
```

```json
{
  "resourceType": "OperationOutcome",
  "id": "informational",
  "issue": [
    {
      "severity": "information",
      "code": "informational",
      "diagnostics": "Purge for Organization/org-a accepted for async processing; Organization removed, tenant sealed"
    }
  ]
}
```

With `allResourceTypes`, Aidbox deletes the `Organization` resources before it returns `202`. That
seals the tenant: resolution of `/Organization/<org-id>/fhir/...` reads those rows, so once they are
gone no client can write new data into a tenant that is being offboarded. The remaining types run as
one background task each, and a task that fails on a database timeout retries twice, thirty seconds
apart, before it gives up.

{% hint style="warning" %}
Sealing the tenant closes the route you started from. An `allResourceTypes` purge cannot be repeated
for that organization, because `/Organization/<org-id>/fhir/$purge` no longer resolves. This holds
for the synchronous form too: it removes the organizations first as well. Check the operation status
before you assume an asynchronous offboarding finished.
{% endhint %}

Poll the status with the operation id from `Content-Location`. The status endpoint sits at the root,
outside the tenant, so it keeps working once the purge has sealed the organization:

```http
GET /fhir/$async/<operation-id>
```

`202`, with a `Retry-After` header, means tasks are still outstanding. `200` means every task has
finished. The body is a `batch-response` Bundle with one entry for the operation as a whole, and
that entry's `response.status` carries the outcome: `200 OK` when Aidbox purged every type,
`500 Internal Server Error` when a type exhausted its retries and its tenant data may remain. An
operation id Aidbox does not know returns `404`.

## Errors

| Status | Condition |
|---|---|
| `404` | The organization does not exist |
| `422` | Body is not a `Parameters` resource |
| `422` | `allResourceTypes` and `resourceType` in the same request |
| `422` | `allResourceTypes` without FHIR Schema mode |
| `422` | No `resourceType` parameter and no `allResourceTypes` |
| `422` | `resourceType` carries a blank or missing `valueString` |
| `422` | `resourceType` names `Organization` |
| `422` | `resourceType` names a type OrgBAC does not support: a canonical stored outside the resource tables, such as `StructureDefinition`, or an Aidbox configuration type, such as `AidboxConfig`, `App` or `Entity` |
| `422` | `resourceType` names a type that does not exist |
| `422` | `Prefer: respond-async` on an instance with no scheduler configured |

## Audit

Every call writes an `AuditEvent` with subtype `$purge-organization`, naming the organization and
the resource types. An asynchronous run records acceptance when it returns `202`, and a type that
exhausts its retries records its own failure, so the trail shows which data may remain.
