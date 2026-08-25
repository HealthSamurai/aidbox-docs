---
description: >-
  This guide shows you how to migrate a standalone Aidbox instance into a box
  running inside Multibox
---

# Migrate from Aidbox to Multibox

Multibox is a management layer on top of Aidbox that runs many isolated Aidbox instances, called boxes, from a single deployment. A portal provisions, routes to, and manages every box: it keeps its own portal database for box metadata, user accounts, and collaborator relationships, and each box gets a separate PostgreSQL database for its FHIR data, grouped in the same Postgres cluster. Migrating a standalone Aidbox instance into Multibox means creating a new box and moving your existing FHIR data into it.

There is no automated migration tool for this direction. Use the steps below, and test the full flow against a copy of your data before running it against production.

## Before you start

* You need a Multibox license. A standalone Aidbox license does not work with Multibox. The license also caps how many boxes you can run.
* Note your source instance's FHIR version. You set the same version on the box you create in Multibox, since Multibox fixes the FHIR version per box at creation time and does not change it afterward. Unlike standalone Aidbox, different boxes in the same Multibox deployment can run different FHIR versions.
* Any custom resources, modules, subscriptions, and AidboxConfig/zen project settings are per-box in Multibox. They are not inherited from other boxes, so plan to redeclare them for the new box.
* Clients connect to a box through its own subdomain (`<box-id>.<cluster-domain>`), not through the standalone instance's URL. Plan to update client configuration once the box is live.

{% hint style="info" %}
Multibox gives each tenant a fully separate database, which is the right fit for strict data separation or tenants that need independent configuration and FHIR versions. If your tenants can share a database and configuration, [organization-based access control](../../access-control/authorization/scoped-api/organization-based-hierarchical-access-control/README.md) is a lighter-weight alternative worth considering before you migrate.
{% endhint %}

## Set up Multibox

Aidbox is a full-featured single instance of the Aidbox FHIR server. If you are interested in multi-tenant Aidbox, consider using the Multibox distribution.

All distributions can be used with standard PostgreSQL or managed PostgreSQL services.

A basic installation consists of two components: the backend and the database. Both are released as docker images and can be pulled from the HealthSamurai [docker hub](https://hub.docker.com/u/healthsamurai). For each type of Aidbox license, an individual backend image is available: [Aidbox](https://hub.docker.com/r/healthsamurai/aidboxone) or [Multibox](https://hub.docker.com/r/healthsamurai/multibox).

Aidbox and Multibox work with standard PostgreSQL 13 and higher. See [PostgreSQL Requirements](../../database/postgresql-requirements.md) for details.

If you don't have Multibox running yet, pick the path that matches your target environment.

### Run locally

Follow the quickstart to run Multibox on your machine with Docker Compose:

{% content-ref url="../security-access-control-tutorials/run-multibox-locally.md" %}
[run-multibox-locally.md](../security-access-control-tutorials/run-multibox-locally.md)
{% endcontent-ref %}

### Deploy to Kubernetes

Deploying Multibox to Kubernetes follows the same steps as deploying standalone Aidbox:

{% content-ref url="../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/deploy-production-ready-aidbox-to-kubernetes.md" %}
[deploy-production-ready-aidbox-to-kubernetes.md](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/deploy-production-ready-aidbox-to-kubernetes.md)
{% endcontent-ref %}

Apply these differences on top of that guide:

* Use the `healthsamurai/multibox` image instead of `healthsamurai/aidboxone`.
* Box subdomains are created on demand, so a single static TLS certificate won't cover them. Request a wildcard certificate for `AIDBOX_CLUSTER_DOMAIN` instead, which with cert-manager means using a DNS-01 challenge rather than HTTP-01.
* Point your ingress at the wildcard domain so requests for `<box-id>.<cluster-domain>` reach the Multibox service, and set `AIDBOX_CLUSTER_DOMAIN` to that same domain.
* If you run multiple Multibox replicas, every replica needs the same `AIDBOX_CLUSTER_SECRET` and the same RSA keypair and secret. See [Highly Available Aidbox](../../deployment-and-maintenance/deploy-aidbox/run-aidbox-in-kubernetes/highly-available-aidbox.md), which applies equally to Multibox.

## Create a box

Open the Multibox portal and create a new box, or call the `multibox/create-box` RPC directly against the portal:

```yaml
POST /rpc
Content-Type: text/yaml
Accept: text/yaml

method: multibox/create-box
params:
  id: mycompany
  description: Migrated from standalone Aidbox
  fhirVersion: fhir-4.0.1
```

* `id` becomes the box's subdomain and its database name. It must match `^[a-z][a-z0-9]{4,}$`: lowercase letters and digits only, at least 5 characters, no hyphens.
* `fhirVersion` must match your source Aidbox's FHIR version, in the `fhir-<version>` format (for example `fhir-4.0.1`, `fhir-5.0.0`). Call `multibox/fhir-versions` to see which versions your Multibox deployment supports.
* You don't need to set a `participant`: Multibox assigns the calling user as the box's `owner`. Grant teammates access afterward with `multibox/add-collaborator`, choosing an `admin`, `writer`, or `reader` role.

Before creating the box, you can call `multibox/check-id` (no authentication required) to confirm the id is free and avoid a failed creation:

```yaml
POST /rpc
Content-Type: text/yaml
Accept: text/yaml

method: multibox/check-id
params:
  id: mycompany
```

Multibox provisions a dedicated PostgreSQL database and role for the box the first time it starts. Leave the box empty for now; you populate it in the next step.

## Configuration

Multibox and standalone Aidbox share most configuration: JAVA options, web worker and DB pool sizing, SSL, and authentication key setup all work the same way. See the full reference:

{% content-ref url="../../configuration/configure-aidbox-and-multibox.md" %}
[configure-aidbox-and-multibox.md](../../configuration/configure-aidbox-and-multibox.md)
{% endcontent-ref %}

A few settings apply differently once you're on Multibox:

* Performance settings (`BOX_WEB_THREAD`, `BOX_DB_POOL_MAXIMUM_POOL_SIZE`, `JAVA_OPTS`) are set on the Multibox process as a whole, not per box. Size them for the combined load of every box it hosts, including the one you're migrating.
* Authentication keys (`BOX_SECURITY_AUTH_KEYS_PRIVATE`/`PUBLIC`/`SECRET`) are also shared across the Multibox process. If your source Aidbox instance issued JWTs signed with its own key, tokens minted before the migration won't validate against the new box; plan for clients to re-authenticate.
* `BOX_DB_EXTENSION_SCHEMA`, if you used a non-default PostgreSQL schema on the source instance, has no equivalent per box in Multibox: each box already gets its own database, so there's no need to separate extensions by schema within it.
* `AIDBOX_CLUSTER_SECRET` and `AIDBOX_CLUSTER_DOMAIN` are new, Multibox-only settings with no standalone counterpart. Keep `AIDBOX_CLUSTER_SECRET` stable across restarts and replicas, since it signs the cross-box tokens the portal uses to move between boxes.

## Move your data

### Recommended: bulk export and import

Use Aidbox's Bulk API to move data at the FHIR level. This works regardless of where the source and target databases live, and keeps you on documented, supported operations.

1. Export each resource type from the source Aidbox instance with [`$export`](../../api/bulk-api/export.md), and store the resulting NDJSON files somewhere the new box can reach over HTTP (a public bucket or a pre-signed URL).
2. Import the files into the new box with [`$import`](../../api/bulk-api/import-and-fhir-import.md#import). Address the request to the portal host and target the box with the `x-box` header (or `AIDBOX_CLUSTER_BOX_HEADER`, if you renamed it) instead of relying on subdomain DNS:

```yaml
POST /fhir/$import
Accept: text/yaml
Content-Type: text/yaml
x-box: mycompany

id: migration
contentEncoding: gzip
inputs:
- resourceType: Patient
  url: https://storage.example.com/export/Patient.ndjson.gz
- resourceType: Encounter
  url: https://storage.example.com/export/Encounter.ndjson.gz
```

{% hint style="warning" %}
`$import` skips validation and does not write history by default. Set `update: true` if you need history preserved for resources that already exist, and consider running [batch validation](../../modules/profiling-and-validation/batch-resource-validation.md) after the import completes.
{% endhint %}

3. Repeat for every resource type in your source instance, then verify record counts against the source before cutting clients over.

### Alternative: direct database restore

For large datasets, restoring a PostgreSQL dump straight into the box's database is faster than round-tripping through NDJSON. This bypasses Aidbox's own import path, so treat it as an advanced option and rehearse it on a staging box first.

1. Take a dump of the source Aidbox database:

```bash
pg_dump -Fc -h <source-db-host> -U <source-db-user> -d <source-db-name> -f aidbox.dump
```

2. Start the new box once so Multibox provisions its database, then stop it again.
3. Restore the dump into the box's database. The database name matches the box id you chose. Use a role with enough privileges on the Multibox PostgreSQL cluster, and drop ownership information so the restore doesn't fight with the role Multibox already created:

```bash
pg_restore --no-owner --no-acl -h <multibox-db-host> -U <superuser> -d mycompany aidbox.dump
```

4. Reassign ownership of the restored objects to the box's own role if your setup requires it, then start the box.

## Verify and cut over

1. Call `multibox/get-box` with your box's `id` to get its live `box-url` and a short-lived `access-token`. Open `access-url` from the response (or `box-url` directly) to sign in and confirm resource counts, search, and any custom modules or subscriptions behave as they did on the standalone instance.
2. Portal collaborators (`owner`/`admin`/`writer`/`reader`, managed through `multibox/add-collaborator`) control who can manage the box from the portal. They are separate from the FHIR API clients your applications use: your source instance's `BOX_ADMIN_PASSWORD` and `BOX_ROOT_CLIENT_SECRET` don't carry over, so create new `Client` and `AccessPolicy` resources inside the box itself for machine-to-machine access, the same way you would on a fresh Aidbox instance.
3. Point clients at the box's new base URL (`https://<box-id>.<cluster-domain>`, or the portal host with an `x-box` header) using the new clients from the previous step.
4. Once you've confirmed the box is healthy, decommission the standalone Aidbox instance.

## Talk to a Health Samurai Engineer

If you'd like to learn more about using Multibox or have any questions about this guide, [connect with us on Zulip](https://connect.health-samurai.io/). We're happy to help.
