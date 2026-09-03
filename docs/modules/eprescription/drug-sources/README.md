---
description: Search medications and check interactions with SDB, FDB and RxNorm drug sources in Aidbox ePrescription.
---

# Drug Sources

The ePrescription module exposes SDB (Scholz DataBank), FDB (First DataBank) and RxNorm as separate drug sources. All source routes remain mounted, and each request selects a source in its path. One deployment can use any combination of the three sources.

The routes below use the module's `/api` prefix. The matching Aidbox App routes use `/e-prescription` in place of `/api`.

## SDB requests

`GET /api/drug-sources/sdb/medications` requires the `query` parameter. It searches by brand name or NDC based on the query value.

* Set `type=generic` to search by generic name.
* Set `type=ndc` to force an NDC search.
* `exclude-non-us` excludes drugs that are not marketed in the United States. It defaults to `true`.
* `exclude-missing-package-ndc` excludes drugs without FDA package data. It defaults to `true`.

The two exclusion parameters affect NDC searches. Brand and generic searches ignore them.

`POST /api/drug-sources/sdb/interactions/drug-drug` requires a `medications` array. Each item contains a `system` and `code`.

`POST /api/drug-sources/sdb/interactions/drug-allergy` requires `patientId` and a `medications` array. The module reads the patient's allergies from Aidbox.

## FDB requests

`GET /api/drug-sources/fdb/medications` requires the `query` parameter.

`GET /api/drug-sources/fdb/medications/{dispensable-drug-id}/sigs` requires the FDB dispensable drug ID returned in a medication search result.

`GET /api/drug-sources/fdb/allergies` requires the `query` parameter.

`POST /api/drug-sources/fdb/interactions` accepts `medications` and `allergies` arrays. Each item contains a `system` and `code`. The default response is a FHIR `Bundle` of `DetectedIssue` resources. Set `format=cards` to return CDS cards.

See [FDB identifiers and Rx/OTC codes](fdb.md) for the supported coding systems and Federal Legend Code values.

## RxNorm requests

`GET /api/drug-sources/rxnorm/medications` requires the `query` parameter.

## Responses

* `200` means the source completed the request. An empty result means the source found no matches for most operations.
* `400` means the request failed parameter or body validation.
* `500` with an `OperationOutcome` whose issue has `severity: fatal` and `code: exception` means the source call failed. Do not treat it as an empty result.
* `503` with an `OperationOutcome` whose issue has `severity: error` and `code: not-supported` means the source configuration is unusable. The `diagnostics` field names the configuration problem.
