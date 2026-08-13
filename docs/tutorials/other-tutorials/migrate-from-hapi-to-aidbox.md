---
description: >-
  A checklist and step-by-step guide for moving a HAPI FHIR server deployment
  to Aidbox
---

# Migrate from HAPI to Aidbox

HAPI FHIR and Aidbox both implement the FHIR spec, but they differ in how they store data, validate resources, and handle search, subscriptions, and access control. This guide walks through the pieces of a HAPI deployment you need to account for, and the steps to move data and configuration into Aidbox.

There is no one-click migration tool. Plan the migration in stages: map your configuration first, run a trial migration against a copy of your data, verify the result, then cut over.

## Before you start

* **Match your FHIR version.** Note which FHIR version your HAPI server runs (R4, R4B, or R5) and provision your Aidbox instance with the same version.
* **Inventory custom content.** List every custom `StructureDefinition`, `SearchParameter`, and `Subscription` your HAPI deployment defines. Each has a direct but not identical equivalent in Aidbox, covered below.
* **Check your interceptors.** HAPI deployments often carry custom Java interceptors for validation, authorization, or request rewriting. Aidbox replaces most of these with declarative configuration (access policies, StructureDefinition-based validation) rather than code, so plan to reimplement interceptor logic as configuration.
* **Have a rollback plan.** Keep your HAPI instance and its database running read-only until you've verified the Aidbox instance in production.

{% hint style="info" %}
Run the full migration against a copy of your data first. Verify resource counts, spot-check search results, and confirm your integrations work against the Aidbox instance before touching production data.
{% endhint %}

## Set up your target Aidbox instance

Deploy Aidbox before moving any data, so you can load into a running, licensed instance.

{% content-ref url="../../deployment-and-maintenance/deploy-aidbox/README.md" %}
[README.md](../../deployment-and-maintenance/deploy-aidbox/README.md)
{% endcontent-ref %}

## Migrate custom resources

HAPI defines custom resources through `StructureDefinition`. Aidbox uses the same resource for this.

{% content-ref url="../artifact-registry-tutorials/custom-resources/README.md" %}
[README.md](../artifact-registry-tutorials/custom-resources/README.md)
{% endcontent-ref %}

{% content-ref url="../artifact-registry-tutorials/custom-resources/custom-resources-using-structuredefinition.md" %}
[custom-resources-using-structuredefinition.md](../artifact-registry-tutorials/custom-resources/custom-resources-using-structuredefinition.md)
{% endcontent-ref %}

## Migrate custom search parameters

Recreate any custom `SearchParameter` resources from HAPI in Aidbox before loading data, since Aidbox indexes on load and a search parameter added after the fact does not retroactively index existing resources without a reindex.

{% content-ref url="../crud-search-tutorials/search-tutorials/custom-searchparameter-tutorial.md" %}
[custom-searchparameter-tutorial.md](../crud-search-tutorials/search-tutorials/custom-searchparameter-tutorial.md)
{% endcontent-ref %}

## Migrate subscriptions

Rebuild your HAPI subscriptions as Aidbox topic-based subscriptions rather than porting them as standard FHIR `Subscription` resources. They scale better under high write volume and support destinations like Kafka, SNS, and webhooks directly.

{% content-ref url="../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md" %}
[aidbox-topic-based-subscriptions.md](../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md)
{% endcontent-ref %}

## Migrate access control rules

HAPI authorization interceptors don't carry over as code. Reimplement your authorization rules as Aidbox access policies, and reuse your existing SMART on FHIR client configuration if you have one.

{% content-ref url="../../access-control/authorization/README.md" %}
[README.md](../../access-control/authorization/README.md)
{% endcontent-ref %}

{% content-ref url="../../access-control/authorization/smart-on-fhir/README.md" %}
[README.md](../../access-control/authorization/smart-on-fhir/README.md)
{% endcontent-ref %}

## Migrate terminology

If your HAPI deployment points to an external terminology server, such as Health Samurai's terminology SaaS, Aidbox's terminology module can keep using it. You can also load CodeSystems, ValueSets, and ConceptMaps into Aidbox's FHIR Artifact Registry and serve them locally, or combine both: run in hybrid mode, where Aidbox serves what it has loaded locally and falls back to the external server for everything else.

{% content-ref url="../../terminology-module/overview.md" %}
[overview.md](../../terminology-module/overview.md)
{% endcontent-ref %}

{% content-ref url="../../terminology-module/aidbox-terminology-module/README.md" %}
[README.md](../../terminology-module/aidbox-terminology-module/README.md)
{% endcontent-ref %}

{% content-ref url="../../terminology-module/aidbox-terminology-module/hybrid.md" %}
[hybrid.md](../../terminology-module/aidbox-terminology-module/hybrid.md)
{% endcontent-ref %}

## Migrate the data

Export your resources from HAPI using the standard FHIR Bulk Data Export operation, `$export`, which HAPI implements the same way Aidbox does. Aidbox exposes the matching endpoint for reference:

{% content-ref url="../../api/bulk-api/export.md" %}
[export.md](../../api/bulk-api/export.md)
{% endcontent-ref %}

Load the resulting NDJSON into Aidbox with `/fhir/$import`. It skips validation and runs fastest, so use it once you've already validated your data against your target profiles in a trial run.

{% content-ref url="../../api/bulk-api/import-and-fhir-import.md" %}
[import-and-fhir-import.md](../../api/bulk-api/import-and-fhir-import.md)
{% endcontent-ref %}

For a smaller dataset, a transactional bundle can be the better option: it validates every resource as part of the transaction and rolls back the whole bundle if one entry fails, so you don't have to separately validate the load afterward.

{% content-ref url="../../api/batch-transaction.md" %}
[batch-transaction.md](../../api/batch-transaction.md)
{% endcontent-ref %}

## Validate the migrated data

Aidbox validates resources against loaded StructureDefinitions, which can be stricter about some constraints than HAPI's default validator. Run a validation pass over your imported data and fix any resources that fail before cutting over.

{% content-ref url="../../modules/profiling-and-validation/README.md" %}
[README.md](../../modules/profiling-and-validation/README.md)
{% endcontent-ref %}

If you loaded data with `/fhir/$import`, which skips validation, run `$batch-validate` afterward to check the resources already in the database asynchronously and get an offender-indexed report of what fails and why.

{% content-ref url="../../modules/profiling-and-validation/batch-resource-validation.md" %}
[batch-resource-validation.md](../../modules/profiling-and-validation/batch-resource-validation.md)
{% endcontent-ref %}

## Create indexes

Aidbox stores resources as `jsonb` and does not create a database index for every search parameter by default. A search parameter works without one, but Postgres falls back to a sequential scan, which gets slow as a table grows. Plan to create indexes for the search parameters your clients actually query before you cut over.

{% content-ref url="../../deployment-and-maintenance/indexes/README.md" %}
[README.md](../../deployment-and-maintenance/indexes/README.md)
{% endcontent-ref %}

Aidbox can suggest an index for a given resource type and search parameter, and, once traffic hits the new instance, surface which search parameter shapes are actually hot and lack a backing index. Run your usual client queries against the migrated instance during your trial run, then check the suggestions before cutover.

{% content-ref url="../../deployment-and-maintenance/indexes/get-suggested-indexes.md" %}
[get-suggested-indexes.md](../../deployment-and-maintenance/indexes/get-suggested-indexes.md)
{% endcontent-ref %}

{% content-ref url="../../deployment-and-maintenance/indexes/search-parameter-usage-stats.md" %}
[search-parameter-usage-stats.md](../../deployment-and-maintenance/indexes/search-parameter-usage-stats.md)
{% endcontent-ref %}

## Set up backups before cutover

Before you point production traffic at the new instance, put a backup schedule in place.

{% content-ref url="../../deployment-and-maintenance/backup-and-restore/README.md" %}
[README.md](../../deployment-and-maintenance/backup-and-restore/README.md)
{% endcontent-ref %}

## Checklist

* [ ] Aidbox instance deployed, licensed, and set to the source FHIR version
* [ ] Custom resources recreated using StructureDefinition
* [ ] Custom search parameters recreated
* [ ] Subscriptions rebuilt as Aidbox topic-based subscriptions
* [ ] Access policies written to replace HAPI interceptors
* [ ] Terminology resources migrated or external terminology server repointed
* [ ] Data exported from HAPI and imported into Aidbox in a trial run
* [ ] Imported data validated against your target StructureDefinitions
* [ ] Indexes created for the search parameters your clients query
* [ ] Client applications repointed and integrations retested
* [ ] Backup schedule configured on the new instance
* [ ] Production data migrated and HAPI instance kept read-only as a fallback
