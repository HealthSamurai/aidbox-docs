---
description: >-
  Upload FHIR Implementation Guides to Aidbox using environment variables, UI,
  API, or local packages.
---

# Upload FHIR Implementation Guide

Uploading FHIR Implementation Guides (IGs) to Aidbox can be performed using various methods, each designed to suit different use cases and preferences.

### Methods to upload FHIR IG to Aidbox:

{% cards %}
{% card icon="sliders" title="Environment variable" href="environment-variable.md" %}
Set BOX_BOOTSTRAP_FHIR_PACKAGES so Aidbox loads the IG at startup.
{% endcard %}
{% card icon="box" title="IG package from Aidbox Registry" href="aidbox-ui/ig-package-from-aidbox-registry.md" %}
Pick an Implementation Guide from the built-in package registry in the Aidbox UI.
{% endcard %}
{% card icon="link" title="Public URL to IG package" href="aidbox-ui/public-url-to-ig-package.md" %}
Upload an IG by pointing Aidbox at a public .tar.gz URL.
{% endcard %}
{% card icon="doc" title="Local IG package" href="aidbox-ui/local-ig-package.md" %}
Upload a local .tar.gz IG package from your computer through the Aidbox UI.
{% endcard %}
{% card icon="code" title="Aidbox FHIR API" href="aidbox-fhir-api.md" %}
Load FHIR canonical resources programmatically through the Aidbox FHIR API.
{% endcard %}
{% endcards %}
