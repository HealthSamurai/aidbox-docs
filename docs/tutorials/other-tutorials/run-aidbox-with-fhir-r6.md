---
description: This tutorial explains how to run Aidbox with FHIR 6.0.0-ballot5.
---

# Run Aidbox with FHIR R6

FHIR 6.0.0-ballot5 was published on **July 17, 2026**, introducing new resources, complex data types, and updated profiles.

## Run in Sandbox

1. Sign up or log in at [aidbox.app](https://aidbox.app)
2. Go to your project
3. Click "New Aidbox" to create a new instance
4. Enter a name in the "License name" field
5. Set hosting type to "Sandbox"
6. Choose "Edge" as the Aidbox version
7. Enter Instance URL.
8. Set FHIR Version to "6.0.0-ballot5"

## Run locally

{% hint style="warning" %}
<img src="../../../assets/docker.avif" alt="Docker logo" data-size="original">

Please **make sure** that both [Docker & Docker Compose](https://docs.docker.com/engine/install/) are installed.
{% endhint %}

1. Create a working directory:

```bash
mkdir aidbox && cd aidbox
```

2. Download the Aidbox setup script:

```bash
curl -JO https://aidbox.app/runme/r6
```

3. Start Aidbox:

```bash
docker compose up
```

## Explore canonicals

Open the **FHIR packages** section in the Aidbox UI sidebar and find the `hl7.fhir.r6.core 6.0.0-ballot5` package. Select it to see the canonical resources it loaded into the [FHIR Artifact Registry](../../artifact-registry/artifact-registry-overview.md): Profiles, Operations, Extensions, FHIRSchemas, SearchParameters, ValueSets, and CodeSystems.

<figure><img src="../../../assets/fhir-packages-r6-core.avif" alt="FHIR packages section of the Aidbox UI showing the hl7.fhir.r6.core package"><figcaption></figcaption></figure>
