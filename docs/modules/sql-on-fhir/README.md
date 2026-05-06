---
description: Create flat SQL views from FHIR resources using ViewDefinitions for simplified analytics, reporting, and BI integration.
---

# SQL on FHIR

{% hint style="warning" %}
Starting from version **2604**, SQL on FHIR requires **fhir-schema mode** (`fhir.validation.fhir-schema-validation=true`). ViewDefinitions are stored in the FHIR Artifact Registry (FAR), which is only available in fhir-schema mode. Without it, ViewDefinition CRUD, `$run`, `$sql`, and `$materialize` operations will not work.
{% endhint %}

Performing analysis on FHIR data requires extracting data from deeply nested structures of resources, which may be cumbersome in some cases. To address this problem, Aidbox implements [SQL on FHIR](https://build.fhir.org/ig/FHIR/sql-on-fhir-v2/index.html) specification allowing users to create flat views of their resources in a simple, straightforward way

## Create View Definitions

To utilize SQL on FHIR it's important to understand what a View Definition is and how to use it to define flat views.

See [Defining flat Views with ViewDefinitions](./defining-flat-views-with-view-definitions.md).

## Query data from the defined views

Once your flat view is defined and materialized, you can query data from it using plain SQL.

See [Query data from flat views](./query-data-from-flat-views.md).

## Run shareable SQL queries

Bundle a SQL query, its ViewDefinition dependencies, and parameters into a SQLQuery Library and execute it synchronously with the `$sqlquery-run` operation.

See [$sqlquery-run operation](./operation-sqlquery-run.md).

## De-identification

Starting from version **2604**, ViewDefinition columns can be annotated with de-identification methods to transform sensitive data during SQL generation. Supported methods include redact, cryptoHash, dateshift, encrypt, substitute, perturb, and custom PostgreSQL functions.

See [De-identification](./de-identification.md).

## SQL on FHIR reference

To dive deeper into the nuances of using SQL on FHIR in Aidbox, consult the reference page.

{% content-ref url="reference.md" %}
[reference.md](reference.md)
{% endcontent-ref %}
