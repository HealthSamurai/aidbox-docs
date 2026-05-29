---
description: Aidbox Bulk API for importing and exporting large FHIR datasets including $dump, $export, and $import operations.
---

# Bulk API

Aidbox supports various options for the bulk import and export of data.

The list of available Bulk API endpoints:

{% cards %}
{% card icon="download" title="$dump" href="dump.md" %}
Export all FHIR resources of a type as NDJSON stream with chunked transfer encoding.
{% endcard %}
{% card icon="database" title="$dump-sql" href="dump-sql.md" %}
Export SQL query results as CSV or NDJSON stream for analytics.
{% endcard %}
{% card icon="download" title="$export" href="export.md" %}
Export FHIR resources in bulk to cloud storage backends.
{% endcard %}
{% card icon="upload" title="$import" href="import-and-fhir-import.md" %}
Bulk import FHIR resources asynchronously with progress monitoring.
{% endcard %}
{% card icon="trash" title="$purge" href="purge.md" %}
Permanently delete a Patient and all resources in their compartment.
{% endcard %}
{% endcards %}

## Read more

* Load Synthea with Bulk API [tutorial](../../tutorials/bulk-api-tutorials/synthea-by-bulk-api.md)
* $dump-sql for analytics [tutorial](../../tutorials/bulk-api-tutorials/dump-sql-tutorial.md)
* [Configure access policies for Bulk API](configure-access-policies-for-bulk-api.md)
