---
description: Permanently delete every Patient member of a Group and all resources in their compartments using the $purge operation.
---

# Group $purge

{% hint style="info" %}
Available since version 2608.
{% endhint %}

The `$purge` operation on `Group` permanently deletes every Patient member of the group and all resources in those patients' compartments, including all historical versions. It is the group-level counterpart of [`$purge` on Patient](purge.md) and applies exactly the same per-patient deletion.

This operation implements the [FHIR Group Purge](https://build.fhir.org/group-operation-purge.html) specification. By default it uses the system default compartment for Patient, or a custom compartment can be passed as a parameter.

{% hint style="danger" %}
**This deletes Group resources as well.** `Group` is part of the Patient compartment through `Group.member`, so purging a patient deletes every Group that lists them — the group you targeted, and any **other** group that happens to share a member. See [Groups are deleted too](#groups-are-deleted-too).
{% endhint %}

## Endpoint

```http
POST /fhir/Group/<group-id>/$purge
```

## Which members are purged

| Member                                                                             | Purged    |
|------------------------------------------------------------------------------------|-----------|
| Literal reference to a Patient — `{"reference": "Patient/<id>"}`                   | Yes       |
| Member with `"inactive": true`                                                     | No        |
| Non-Patient member — Practitioner, Device, and so on                               | No        |
| A nested `Group`                                                                   | See below |
| Logical reference — `{"type": "Patient", "identifier": {...}}` with no `reference` | No        |
| `display` only, or a reference Aidbox cannot resolve to `<Type>/<id>`              | No        |

The last row covers bare ids such as `{"reference": "pt-1"}` and absolute URLs such as `{"reference": "http://example.org/fhir/Patient/pt-1"}`. Neither is a resolvable relative FHIR reference, so both are skipped.

{% hint style="warning" %}
**Skipped members are not reported.** A successful response states that the group was purged; it does not list which members were left out. A group whose members are all logical references purges nothing and still returns 200. Verify membership before purging if that distinction matters to you.
{% endhint %}

When no member is purgeable, nothing is deleted and the operation returns 200:

```json
{
  "resourceType": "OperationOutcome",
  "id": "informational",
  "issue": [
    {
      "severity": "fatal",
      "code": "informational",
      "diagnostics": "Group grp-1 doesn't have any purgeable members"
    }
  ]
}
```

## Groups are deleted too

The standard Patient CompartmentDefinition includes `Group` with the search parameter `member`. Purging a patient therefore deletes every Group resource that lists that patient — including the group named in the request.

It also deletes **unrelated groups that share a member**:

```
Group/cohort-a   members: pt-1
Group/cohort-b   members: pt-1, pt-2

POST /fhir/Group/cohort-a/$purge

pt-1        deleted
cohort-a    deleted
cohort-b    deleted   ← never named in the request
pt-2        kept      ← its group is gone, its data is not purged
```

`cohort-b` disappears because `pt-1` was one of its members, while `pt-2` — who was never in `cohort-a` — keeps all their data. Only the Group resources are affected; no extra patient is purged.

Because the group itself is deleted, re-running `$purge` on the same group returns **404 Not Found**.

### Keeping Group resources

To purge the members without deleting any Group, pass a `compartmentDefinition` that omits the `Group` entry. Read the server's Patient CompartmentDefinition, remove the entry whose `code` is `Group`, and send the rest:

```json
{
  "resourceType": "Parameters",
  "parameter": [
    {
      "name": "compartmentDefinition",
      "resource": {
        "resourceType": "CompartmentDefinition",
        "url": "http://example.com/patient-without-group",
        "name": "PatientCompartmentWithoutGroup",
        "code": "Patient",
        "status": "active",
        "search": true,
        "resource": [
          { "code": "Condition",   "param": ["subject"] },
          { "code": "Observation", "param": ["subject"] }
        ]
      }
    }
  ]
}
```

Patients and their compartment resources are still purged, and every Group survives — including the purged one, which is left holding member references to patients that no longer exist.

{% hint style="warning" %}
A custom compartment definition is a copy of the server's, frozen at the time you wrote it. If a later Aidbox version adds resource types to the Patient compartment, your copy will not purge them.
{% endhint %}

## Authorization

Authorization is checked for **every** member before anything is deleted. The first member that fails aborts the whole operation with **403 Forbidden**, and no member is purged — including the ones that were permitted.

Two checks run per member:

* `$purge` on `Patient/<id>` — always.
* Search access to each resource type in the compartment — only when [`fhir.search.authorize-inline-requests`](../../reference/all-settings.md#fhir.search.authorize-inline-requests) is enabled.

```json
{
  "resourceType": "OperationOutcome",
  "id": "forbidden",
  "issue": [
    {
      "severity": "fatal",
      "code": "forbidden",
      "diagnostics": "Failed to purge Patient/pt-2: $purge on Patient is forbidden"
    }
  ]
}
```

Only the first denial is reported. With several unauthorized members you will see them one at a time as you grant access.

## Parameters

The request body is optional. When provided, it must be a FHIR `Parameters` resource. A body that is not a `Parameters` resource is rejected with **422**.

| Parameter               | Type                             | Description                                                                                                                                               |
|-------------------------|----------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------|
| `compartmentDefinition` | resource (CompartmentDefinition) | Defines which resource types and search parameters identify compartment resources. If omitted, the standard server Patient CompartmentDefinition is used. |

The definition must have `code` equal to `Patient` and at least one resource entry with a non-empty `param` list.

## Basic usage

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/Group/grp-1/$purge
Content-Type: application/json
```
{% endtab %}

{% tab title="Response" %}
**Status**

200 OK

**Body**

```json
{
  "resourceType": "OperationOutcome",
  "id": "informational",
  "issue": [
    {
      "severity": "fatal",
      "code": "informational",
      "diagnostics": "Purged all Patients in Group/grp-1"
    }
  ]
}
```
{% endtab %}
{% endtabs %}

The operation stops at the first failure. If a member cannot be purged, the request fails with **500** and the members already processed stay deleted — there is no partial-success report.

## Async mode

{% hint style="info" %}
Use async mode for large groups. A synchronous purge deletes every member in one request, so a group with many members can exceed your HTTP timeout.
{% endhint %}

Include the `Prefer: respond-async` header. Members are purged in background tasks, and the response carries a `Content-Location` header pointing at the operation status.

{% tabs %}
{% tab title="Request" %}
```http
POST /fhir/Group/grp-1/$purge
Content-Type: application/json
Prefer: respond-async
```
{% endtab %}

{% tab title="Response" %}
**Status**

202 Accepted

**Headers**

* `Content-Location` — URL to check purge status (e.g. `/fhir/$async/<operation-id>`)

**Body**

```json
{
  "resourceType": "OperationOutcome",
  "id": "informational",
  "issue": [
    {
      "severity": "fatal",
      "code": "informational",
      "diagnostics": "Purge for Group/grp-1 accepted for async processing"
    }
  ]
}
```
{% endtab %}
{% endtabs %}

Authorization is checked before any task is scheduled, so `Prefer: respond-async` does not bypass it — an unauthorized member returns 403 and no operation is created.

Members are split across background tasks. If one task fails, the operation is marked failed and its remaining tasks are cancelled; members already purged by completed tasks stay deleted. Check the status URL as described in [Check async status](purge.md#check-async-status), and cancel with `DELETE /fhir/$async/<operation-id>`.

{% hint style="info" %}
The number of concurrent async worker threads is controlled by the [`BOX_SCHEDULER_EXECUTORS`](../../reference/all-settings.md#scheduler-executors) setting (default: 4).
{% endhint %}

## Responses

| Status | When                                                                                      |
|--------|-------------------------------------------------------------------------------------------|
| 200    | Members purged, or the group has no purgeable members                                     |
| 202    | Accepted for async processing                                                             |
| 403    | A member is not authorized to be purged — nothing is deleted                              |
| 404    | The group does not exist, or was already deleted by an earlier purge                      |
| 422    | The request body is not a `Parameters` resource, or the compartment definition is invalid |
| 500    | A member failed to purge — earlier members stay deleted                                   |

## Audit logging

Both outcomes are audited with `action: "E"` (Execute), `subtype: "$purge"`, and the Group as the entity. A successful purge records `outcome: "0"`; a purge refused with 403 records `outcome: "4"`. See [How to configure audit log](../../tutorials/security-access-control-tutorials/how-to-configure-audit-log.md) for setup instructions.
