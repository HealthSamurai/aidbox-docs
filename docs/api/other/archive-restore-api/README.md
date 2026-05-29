---
description: Archive and restore FHIR resources to AWS S3 or GCP Cloud Storage for data lifecycle management.
---

# Archive/Restore API

Archive/restore API was designed to upload unnecessary resources from Aidbox to AWS or GCP cloud and restore it back when it is needed.

Archive/restore API provides the following operations:

{% cards %}
{% card icon="download" title="Create archive" href="create-archive.md" %}
Move FHIR resources to AWS S3 or GCP Cloud Storage with retention policies.
{% endcard %}
{% card icon="bolt" title="Restore archive" href="restore-archive.md" %}
Bring previously archived FHIR resources back from cloud storage into Aidbox.
{% endcard %}
{% card icon="hammer" title="Delete archive" href="delete-archive.md" %}
Permanently remove archived FHIR resource data from AWS S3 or GCP Cloud Storage.
{% endcard %}
{% card icon="database" title="Prune archived data" href="prune-archived-data.md" %}
Delete archived FHIR resource data from the Aidbox database after a successful upload.
{% endcard %}
{% endcards %}
