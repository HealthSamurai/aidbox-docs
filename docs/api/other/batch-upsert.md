---
description: A simple way to insert or update a collection of resources
---

# Batch Upsert

This custom operation \(a lightweight alternative to transaction\) **upserts** \(updates or creates\) a collection of resources. Put an array of resources \(with id's\) on `/`. `PUT /` takes resources in [Aidbox format](../rest-api/other/aidbox-and-fhir-formats.md) and stores them without conversion.

```yaml
PUT /
Accept: text/yaml
Content-Type: text/yaml

- status: planned
  class: {code: IMP}
  period: {start: "2013-06-08T10:57:34+00:00", end: "2013-06-08T12:00:00+00:00"}
  resourceType: Encounter
  id: enc-1

- status: planned
  class: {code: IMP}
  period: {start: "2013-06-08T11:00:05+00:00", end: "2013-06-08T11:30:00+00:00"}
  resourceType: Encounter
  id: enc-2

- status: planned
  class: {code: AMB}
  period: {start: "2013-06-08T10:21:01+00:00", end: "2013-06-08T11:42:11+00:00"}
  resourceType: Encounter
  id: enc-3

- status: planned
  class: {code: IMP}
  period: {start: "2013-06-07T09:02:01+00:00", end: "2013-06-07T15:10:09+00:00"}
  resourceType: Encounter
  id: enc-3
```

## Upsert resources in FHIR format

To upsert resources in FHIR format, send a FHIR `transaction` Bundle to `POST /fhir` with a `PUT` entry for each resource. See [Batch/Transaction](../batch-transaction.md).

```yaml
POST /fhir
Accept: text/yaml
Content-Type: text/yaml

resourceType: Bundle
type: transaction
entry:
- resource:
    resourceType: Encounter
    id: enc-1
    status: planned
    class: {code: IMP}
    period: {start: "2013-06-08T10:57:34+00:00", end: "2013-06-08T12:00:00+00:00"}
  request: {method: PUT, url: Encounter/enc-1}
- resource:
    resourceType: Encounter
    id: enc-2
    status: planned
    class: {code: IMP}
    period: {start: "2013-06-08T11:00:05+00:00", end: "2013-06-08T11:30:00+00:00"}
  request: {method: PUT, url: Encounter/enc-2}
```
