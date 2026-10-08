---
description: Get started with Aidbox ePrescribing module for NCPDP SCRIPT integration with Surescripts.
---

# Getting Started

The ePrescription module is available as a Docker image with several versioning options:

* The `latest` tag represents the most recent development version, though it may contain unstable features
* The `stable` tag indicates a thoroughly tested version that has passed through multiple release cycles without known issues
* For specific versions, we use `vMAJOR.MINOR.PATCH` tags following [semantic versioning](https://semver.org/#semantic-versioning-200) conventions

## Deploy the Docker Application

Deploy the Docker image to your infrastructure using the following reference compose as a guide.

```yaml
name: e-prescriptions

services:
  app:
    container_name: app
    image: <private-registry>/e-prescription:latest
    restart: unless-stopped
    secrets:
      - surescripts-authority
      - surescripts-cert
      - surescripts-private
    env_file:
      - .env
    environment:
      E_PRESCRIPTION_PORT: ${E_PRESCRIPTION_PORT}
      # ... other environment variables
    depends_on:
      aidbox:
        condition: service_healthy
    ports:
      - 8280:${E_PRESCRIPTION_PORT}
    networks:
      - e-prescription-network
    volumes:
      - ./data:/data

  # ... other services, including Aidbox

secrets:
  surescripts-authority:
    file: ./.secret/surescripts-authority.pem
  surescripts-cert:
    file: ./.secret/surescripts-cert.pem
  surescripts-private:
    file: ./.secret/surescripts-private.key

networks:
  e-prescription-network: {}
```

{% hint style="warning" %}
If you're not sure about the Surescripts secrets, please read this guide: [How to prepare authentication files.](./prescribing/how-to-test-callback.md)
{% endhint %}

{% hint style="warning" %}
For more information about available configuration options, please go to the [environment variables reference](reference/environment-variables.md).
{% endhint %}

### Volumes

The module can function without volume mounts, but we recommend mounting a volume to `/data` to enable directory backup functionality and ensure data persistence.

## Create an Application

{% hint style="warning" %}
Resource definitions will be provided by our team directly.
{% endhint %}

Create the application using the provided resource definition. To do that, simply insert the resource definition into the App section in Aidbox (`/ui/console#/entities/App`).

**Key Notes:**

* Include your real **secret** in Client section (replace `PUT_SECRET_HERE`).
* Replace `PUT_ENDPOINT_SECRET_HERE` in the App `endpoint` section with a shared secret.
* Set the module variable `AIDBOX_RPC_CREDENTIALS` to `base64("ePrescription-app:<endpoint secret>")` to authenticate calls from Aidbox to the module.
* Include your deployment host (replace `PUT_APP_ENDPOINT_URL_HERE`), but retain the `/rpc` part.

## FHIR Package Installation

The module stores its FHIR definitions, such as extensions, custom resources, and search parameters, in the `io.healthsamurai.e-prescription` package.
On every start, before it serves requests, the module uploads its version of the package to Aidbox unless Aidbox already has it, checks that Aidbox serves that version, and deletes the other versions of the package.

If the upload or the check fails, the module tries again, up to 5 attempts 30 seconds apart, and then stops with an error.
Other versions of the package stay in Aidbox until the check passes.

The module does not reinstall a version that Aidbox already has.
If that version fails the check, the error log names the version, the failed check, and the fix: delete all versions of `io.healthsamurai.e-prescription` in Aidbox, then restart the module.

To delete the versions with the [`$fhir-package-uninstall`](../../reference/package-registry-api.md#usdfhir-package-uninstall) operation:

1. List the installed versions of `io.healthsamurai.e-prescription`, for example in the [Artifact Registry web interface](../../artifact-registry/artifact-registry-overview.md#access-via-web-interface).
2. Call the operation with admin credentials, such as the `root` client.
   The module's `ePrescription-app` client gets `403 Forbidden`.
   Pass each version as its own `package` parameter in the `<name>@<version>` format:

   ```http
   POST /fhir/$fhir-package-uninstall
   Content-Type: application/json

   {
     "resourceType": "Parameters",
     "parameter": [
       { "name": "package", "valueString": "io.healthsamurai.e-prescription@0.16.19" },
       { "name": "package", "valueString": "io.healthsamurai.e-prescription@0.16.20" }
     ]
   }
   ```
3. Check that the response reports `status: deleted` for every version.
   A call that passes only the package name, without a version, returns `200` with `result: false` and deletes nothing.
4. Restart the module. It installs its version of the package from scratch.

You can delete the versions in the Artifact Registry web interface instead.

### Upgrade Aidbox to 2609 or Later

Aidbox 2609.0 and later do not serve the module's custom resources from package versions before `0.17.0`.
Before you upgrade Aidbox to 2609.0 or later, update the module to a version that installs package `0.17.0` or later.
On its next start, the module replaces the old package version, and stored records need no conversion.

## Verify Setup with API Endpoints

After deployment, test the setup by calling these endpoints:

* _(directly)_ **`/`**: Access the OpenAPI/Swagger documentation to explore available APIs.
* _(directly)_ `/api/configuration`: Get all module configuration for debugging purposes.
* _(via aidbox)_ `/e-prescription/health`: Check the current version and retrieve health state.
