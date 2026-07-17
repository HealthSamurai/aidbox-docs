---
description: Initialize Aidbox configuration resources at startup using Init Bundle with transaction or batch bundles via BOX_INIT_BUNDLE environment variable.
coverY: 0
---

# Init Bundle

{% hint style="info" %}
Available since the 2411 release.
{% endhint %}

Init Bundle creates configuration resources when Aidbox starts.

It is equivalent to executing [Bundle](../api/batch-transaction.md) in Aidbox using `POST /fhir`, with some differences:

1. It is executed before the internal HTTP server starts, and before the health check response.
2. Unsuccessful execution of the init bundle of type **transaction** prevents Aidbox from starting.
3. Unsuccessful execution of the init bundle of type **batch** triggers warnings in the log; Aidbox continues the startup process.
4. Aidbox startup will be interrupted if the specified file is unavailable or is not a valid bundle resource of transaction or batch type.
5. Only JSON format is supported.

## Why Init Bundle instead of a seed service

A common alternative is a self-written seed service: a sidecar, an init container, or a script that waits for Aidbox to boot and then `POST`s the configuration resources to `/fhir`. Init Bundle runs inside Aidbox before the HTTP server opens, which removes the problems that approach carries.

- **No race window.** A seed service `POST`s after Aidbox reports healthy, so the orchestrator can route traffic before the configuration lands. Init Bundle finishes before `/health` responds, so a green health check guarantees it applied.
- **Fail-fast on a bad bundle.** A failed transaction init bundle stops Aidbox from starting, so the orchestrator holds back traffic or rolls the deployment back. A failed seed service leaves Aidbox serving with missing configuration.
- **No bootstrap credentials.** A seed service needs a `Client` and `AccessPolicy` before it can write the ones you want to seed. Init Bundle runs before authentication serves, so it needs no external credentials.
- **Nothing extra to operate.** Init Bundle is one environment variable and one file, with no additional container or process to monitor and retry.

## Usage

Specify `BOX_INIT_BUNDLE` env. The value must be a URL.

```
BOX_INIT_BUNDLE=<URL>
```

Examples of URLs:

- `file:///tmp/bundle.json`
- `https://storage.googleapis.com/<BUCKET_NAME>/<OBJECT_NAME>`

## Example

If a Bundle file is created at `/tmp/bundle.json`:

```json
{
  "type": "batch",
  "resourceType": "Bundle",
  "entry": [
    {
      "request": {
        "method": "POST",
        "url": "/Observation",
        "ifNoneExist": "_id=o1"
      },
      "resource": {
        "id": "o1",
        "code": {
          "text": "text"
        },
        "status": "final",
        "effectiveDateTime": "2000-01-01"
      }
    }
  ]
}
```

Aidbox will apply it if the `BOX_INIT_BUNDLE` is set to:

```
BOX_INIT_BUNDLE=file:///tmp/bundle.json
```

## Hints

1. First, check that Aidbox handles the Bundle as it should using `POST /fhir`. Try to post it several times to make sure it is idempotent. Then add it to `BOX_INIT_BUNDLE`.
2. Note that the [Aidbox format](../api/rest-api/other/aidbox-and-fhir-formats.md) is not supported.
3. Aidbox handles an `id` in the body of the POST request. That's why posting the resource with an id twice will cause an `duplicate key` error. Use [conditional create](../api/rest-api/crud/create.md) or [update](../api/rest-api/crud/update.md) for that.
4. Most resources support `PUT` for idempotent updates inside an init bundle. **Exception:** [`AidboxTopicDestination`](../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md#updating-a-topicdestination) is immutable and rejects `PUT` / `PATCH` (also inside bundles). Use a [conditional create](../api/rest-api/crud/create.md) (`POST` with `ifNoneExist=_id=<id>`) so the entry is a no-op when the resource already exists and creates it on the first run:

   ```json
   {
     "request": {
       "method": "POST",
       "url": "AidboxTopicDestination",
       "ifNoneExist": "_id=<id>"
     },
     "resource": {
       "resourceType": "AidboxTopicDestination",
       "id": "<id>",
       "...": "..."
     }
   }
   ```

   To change configuration of an already-created destination, delete it manually and let the next bundle run recreate it. See [Updating a TopicDestination](../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md#updating-a-topicdestination).

## Delivering the bundle to the pod

`BOX_INIT_BUNDLE` points at a `file://` path inside the container or an `https://` URL, so deploying an init bundle comes down to getting that file to the container. Common options:

| Method                          | How                                                                                                                 | Pros                                                                                                                                           | Cons                                                                                                                        |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| **Bake into a custom image**    | `FROM healthsamurai/aidboxone`, `COPY bundle.json` into the image, set `BOX_INIT_BUNDLE=file:///…`                  | Immutable, versioned artifact; atomic deploy and rollback by image tag; no boot-time external dependency; a local package `.tgz` ships with it | Rebuild and push the image on every bundle change                                                                           |
| **Mounted volume / ConfigMap**  | Mount the file into the stock image (a Kubernetes `ConfigMap` or a volume); `BOX_INIT_BUNDLE=file://<mount>`        | Stock image; change the bundle without rebuilding (GitOps-friendly)                                                                            | A `ConfigMap` is text-only and limited to ~1 MiB — it cannot carry a binary package `.tgz`, and large bundles hit the limit |
| **Init container / sidecar**    | An init container builds or downloads the bundle into a shared volume that the Aidbox container reads via `file://` | Stock image; can fetch from private storage using the pod's identity; carries the `.tgz` on the same volume                                    | An extra container and its wiring to operate                                                                                |
| **Remote URL (object storage)** | Upload the bundle to object storage (GCS, S3, Azure Blob); `BOX_INIT_BUNDLE=https://…`                              | Stock image; fully decoupled; per-environment is a different URL; versioned in the bucket                                                      | Startup depends on storage availability and access; a local package `.tgz` must also be reachable by URL                    |

Two things apply across all of them:

- **A local package `.tgz` travels with the bundle.** If the bundle installs a local FHIR package via [`$fhir-package-install`](../reference/package-registry-api.md) with a `file://` path, that tarball must reach the container too: bake it into the image, place it on the same volume, or reference it by `https://`. A `ConfigMap` cannot hold it.
- **Secrets and private storage.** A bundle baked into an image layer or served from a public URL exposes any secret it contains. Keep secrets out of the static bundle and inject them at container start. See [How to inject env variables into init bundle](../deployment-and-maintenance/deploy-aidbox/how-to-inject-env-variables-into-init-bundle.md). `BOX_INIT_BUNDLE` fetches an `https://` URL with a plain HTTP `GET` and does not authenticate with cloud IAM, so for a **private** bucket either put a pre-signed URL (S3 pre-signed URL, Azure SAS) in `BOX_INIT_BUNDLE`, or let an init container or a CSI volume driver (Azure Blob CSI or GCS FUSE with workload identity) fetch the object using the pod's identity and expose it to Aidbox as a `file://` path.

## See also

{% content-ref url="../deployment-and-maintenance/deploy-aidbox/how-to-inject-env-variables-into-init-bundle.md" %}
[how-to-inject-env-variables-into-init-bundle.md](../deployment-and-maintenance/deploy-aidbox/how-to-inject-env-variables-into-init-bundle.md)
{% endcontent-ref %}
{% content-ref url="../tutorials/other-tutorials/how-to-run-sql-via-init-bundle.md" %}
[how-to-run-sql-via-init-bundle.md](../tutorials/other-tutorials/how-to-run-sql-via-init-bundle.md)
{% endcontent-ref %}
{% content-ref url="../tutorials/artifact-registry-tutorials/upload-fhir-implementation-guide/how-to-load-fhir-ig-with-init-bundle.md" %}
[how-to-load-fhir-ig-with-init-bundle](../tutorials/artifact-registry-tutorials/upload-fhir-implementation-guide/how-to-load-fhir-ig-with-init-bundle.md)
{% endcontent-ref %}
