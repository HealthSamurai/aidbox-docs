# FHIR Package Installation

The module stores its FHIR definitions, such as extensions, custom resources, and search parameters, in the `io.healthsamurai.e-prescription` package.
On every start, before it serves requests, the module uploads its version of the package if the installed version differs, and deletes the other versions of the package.

## Fix a Failed Package Check

Follow these steps when the module log reports that the installed package fails the check.

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

You can delete the versions in the [Artifact Registry web interface](../../artifact-registry/artifact-registry-overview.md#access-via-web-interface) instead.
