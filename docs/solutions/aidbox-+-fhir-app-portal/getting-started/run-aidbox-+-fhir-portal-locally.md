---
description: Run Aidbox + FHIR App Portal locally with Docker Compose. The stack includes PostgreSQL, two Aidbox instances, and the Admin and Developer portals in multi-organization (OrgBAC) mode.
---

# Run Aidbox + FHIR Portal locally

The compose below brings up the full stack in one command: PostgreSQL, two Aidbox instances, and the FHIR App Portal (Admin Portal and Developer Portal).

* `aidbox-admin`: the admin and patient environment. It runs with [OrgBAC](../../../access-control/authorization/scoped-api/organization-based-hierarchical-access-control/README.md) enabled, so the portal works in multi-organization mode.
* `aidbox-dev`: the developer sandbox with sample patient data.

## Prerequisites

* [Docker and Docker Compose](https://docs.docker.com/get-docker/) (Docker Compose v2.0 or later)
* Two Aidbox licenses from the [Aidbox User Portal](https://aidbox.app), one per Aidbox instance in the compose:
  * License for the `aidbox-admin` instance
  * License for the `aidbox-dev` instance

Each license is a JWT string starting with `eyJhbGciOiJ...`. See [Run Aidbox locally](../../../getting-started/run-aidbox-locally.md) for how to obtain one.

## Step 1. Create docker-compose.yaml

Create an empty project directory and save the contents below as `docker-compose.yaml` in it:

```bash
mkdir fhir-app-portal && cd fhir-app-portal
```

{% code title="docker-compose.yaml" %}
```yaml
volumes:
  postgres_data: {}

services:
  postgres:
    image: postgres:18
    restart: unless-stopped
    volumes:
      - postgres_data:/var/lib/postgresql
    command:
      - postgres
      - -c
      - shared_preload_libraries=pg_stat_statements
    environment:
      POSTGRES_USER: aidbox
      POSTGRES_PASSWORD: password
      POSTGRES_DB: aidbox
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U aidbox -d postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  aidbox-admin:
    image: healthsamurai/aidboxone:edge
    pull_policy: always
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8080:8080"
    environment:
      BOX_LICENSE: PASTE_AIDBOX_ADMIN_LICENSE
      BOX_ADMIN_PASSWORD: password
      BOX_ROOT_CLIENT_SECRET: secret
      BOX_DB_HOST: postgres
      BOX_DB_PORT: "5432"
      BOX_DB_USER: aidbox
      BOX_DB_PASSWORD: password
      BOX_DB_DATABASE: aidbox-admin
      BOX_WEB_PORT: "8080"
      BOX_WEB_BASE_URL: http://localhost:8080
      BOX_FHIR_COMPLIANT_MODE: "true"
      BOX_FHIR_CORRECT_AIDBOX_FORMAT: "true"
      BOX_FHIR_SCHEMA_VALIDATION: "true"
      BOX_FHIR_SEARCH_AUTHORIZE_INLINE_REQUESTS: "true"
      BOX_FHIR_SEARCH_CHAIN_SUBSELECT: "true"
      BOX_FHIR_SEARCH_COMPARISONS: "true"
      BOX_FHIR_CREATEDAT_URL: https://aidbox.app/ex/createdAt
      BOX_SEARCH_INCLUDE_CONFORMANT: "true"
      BOX_BOOTSTRAP_FHIR_PACKAGES: "hl7.fhir.r4.core#4.0.1:hl7.fhir.us.core#6.1.0"
      BOX_FHIR_TERMINOLOGY_ENGINE: hybrid
      BOX_FHIR_TERMINOLOGY_ENGINE_HYBRID_EXTERNAL_TX_SERVER: https://tx.health-samurai.io/fhir
      BOX_FHIR_TERMINOLOGY_SERVICE_BASE_URL: https://tx.health-samurai.io/fhir
      BOX_SECURITY_AUDIT_LOG_ENABLED: "true"
      BOX_SECURITY_DEV_MODE: "true"
      BOX_SECURITY_ORGBAC_ENABLED: "true"
      BOX_SECURITY_AUTH_KEYS_SECRET: change-this-secret
      BOX_MODULE_SDC_STRICT_ACCESS_CONTROL: "true"
      BOX_SETTINGS_MODE: read-write
      BOX_INIT_BUNDLE: https://storage.googleapis.com/smartbox-public/init-bundle-admin.json
      BOX_MODULE_PROVIDER_DEFAULT_TYPE: ""
      BOX_MODULE_PROVIDER_DEFAULT_URL: ""
      BOX_MODULE_PROVIDER_DEFAULT_USERNAME: ""
      BOX_MODULE_PROVIDER_DEFAULT_FROM: ""
      BOX_MODULE_PROVIDER_DEFAULT_PASSWORD: ""
      BOX_COMPATIBILITY_VALIDATION_JSON__SCHEMA_REGEX: "#{:fhir-datetime}"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 30
      start_period: 120s

  aidbox-dev:
    image: healthsamurai/aidboxone:edge
    pull_policy: always
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    ports:
      - "8090:8090"
    environment:
      BOX_LICENSE: PASTE_AIDBOX_DEV_LICENSE
      BOX_ADMIN_PASSWORD: password
      BOX_ROOT_CLIENT_SECRET: secret
      BOX_DB_HOST: postgres
      BOX_DB_PORT: "5432"
      BOX_DB_USER: aidbox
      BOX_DB_PASSWORD: password
      BOX_DB_DATABASE: aidbox-dev
      BOX_WEB_PORT: "8090"
      BOX_WEB_BASE_URL: http://localhost:8090
      BOX_FHIR_COMPLIANT_MODE: "true"
      BOX_FHIR_CORRECT_AIDBOX_FORMAT: "true"
      BOX_FHIR_SCHEMA_VALIDATION: "true"
      BOX_FHIR_SEARCH_AUTHORIZE_INLINE_REQUESTS: "true"
      BOX_FHIR_SEARCH_CHAIN_SUBSELECT: "true"
      BOX_FHIR_SEARCH_COMPARISONS: "true"
      BOX_FHIR_CREATEDAT_URL: https://aidbox.app/ex/createdAt
      BOX_SEARCH_INCLUDE_CONFORMANT: "true"
      BOX_BOOTSTRAP_FHIR_PACKAGES: "hl7.fhir.r4.core#4.0.1:hl7.fhir.us.core#6.1.0"
      BOX_FHIR_TERMINOLOGY_ENGINE: hybrid
      BOX_FHIR_TERMINOLOGY_ENGINE_HYBRID_EXTERNAL_TX_SERVER: https://tx.health-samurai.io/fhir
      BOX_FHIR_TERMINOLOGY_SERVICE_BASE_URL: https://tx.health-samurai.io/fhir
      BOX_SECURITY_AUDIT_LOG_ENABLED: "true"
      BOX_SECURITY_DEV_MODE: "true"
      BOX_MODULE_SDC_STRICT_ACCESS_CONTROL: "true"
      BOX_SETTINGS_MODE: read-write
      BOX_INIT_BUNDLE: https://storage.googleapis.com/smartbox-public/init-bundle-developer.json
      BOX_MODULE_PROVIDER_DEFAULT_URL: ""
      BOX_MODULE_PROVIDER_DEFAULT_USERNAME: ""
      BOX_MODULE_PROVIDER_DEFAULT_FROM: ""
      BOX_MODULE_PROVIDER_DEFAULT_PASSWORD: ""
      BOX_COMPATIBILITY_VALIDATION_JSON__SCHEMA_REGEX: "#{:fhir-datetime}"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8090/health"]
      interval: 10s
      timeout: 5s
      retries: 30
      start_period: 120s

  fhir-app-portal:
    image: healthsamurai/fhir-app-portal:edge
    pull_policy: always
    restart: unless-stopped
    depends_on:
      aidbox-admin:
        condition: service_healthy
      aidbox-dev:
        condition: service_healthy
    ports:
      - "8095:8095"
      - "8096:8096"
    environment:
      NODE_ENV: production
      PORTAL_BACKEND_PORT: "8081"
      SESSION_SECRET: changeme-secure-session-secret
      DEPLOYMENT_MODE: prod
      AIDBOX_DEV_URL: http://aidbox-dev:8090
      AIDBOX_ADMIN_URL: http://aidbox-admin:8080
      ADMIN_AIDBOX_PUBLIC_URL: http://localhost:8080
      DEVELOPER_AIDBOX_PUBLIC_URL: http://localhost:8090
      ADMIN_FRONTEND_URL: http://localhost:8095
      DEVELOPER_FRONTEND_URL: http://localhost:8096
      AIDBOX_DEV_PUBLIC_URL: http://localhost:8090
      AIDBOX_ADMIN_PUBLIC_URL: http://localhost:8080
      CORS_ORIGINS: http://localhost:8095,http://localhost:8096
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8095/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
```
{% endcode %}

## Step 2. Fill in the license placeholders

Open `docker-compose.yaml` and replace two values with the JWT licenses you obtained:

| Placeholder | Value |
|---|---|
| `PASTE_AIDBOX_ADMIN_LICENSE` | License JWT for the `aidbox-admin` instance |
| `PASTE_AIDBOX_DEV_LICENSE` | License JWT for the `aidbox-dev` instance |

{% hint style="info" %}
**Email provider is optional.** The FHIR App Portal sends developer sign-up verification and password reset emails through Mailgun, SendGrid, Postmark, or SMTP. To enable it, set `BOX_MODULE_PROVIDER_DEFAULT_TYPE`, `BOX_MODULE_PROVIDER_DEFAULT_URL`, `BOX_MODULE_PROVIDER_DEFAULT_USERNAME`, `BOX_MODULE_PROVIDER_DEFAULT_FROM`, and `BOX_MODULE_PROVIDER_DEFAULT_PASSWORD` on both Aidbox services. With the empty values shown above, the stack starts, but developers cannot complete sign-up in the Developer Portal.
{% endhint %}

## Step 3. Start the stack

```bash
docker compose up
```

The first start takes several minutes. Both Aidbox instances download the FHIR packages listed in `BOX_BOOTSTRAP_FHIR_PACKAGES` and apply their init bundles, and the developer sandbox loads sample patient data. The FHIR App Portal starts once both Aidbox instances report healthy.

{% hint style="info" %}
The init bundles create the portal OAuth clients, API clients, access policies, search parameters, and the `portal-admin` user. You can review them before the start: [init-bundle-admin.json](https://storage.googleapis.com/smartbox-public/init-bundle-admin.json) and [init-bundle-developer.json](https://storage.googleapis.com/smartbox-public/init-bundle-developer.json).
{% endhint %}

## Step 4. Open the UIs

| Service | URL | Credentials |
|---|---|---|
| Admin Portal | http://localhost:8095 | `portal-admin` / `password` |
| Developer Portal | http://localhost:8096 | Sign up as a new developer |
| Admin Aidbox UI | http://localhost:8080 | `admin` / `password` |
| Developer Sandbox Aidbox UI | http://localhost:8090 | `admin` / `password` |

## Explore the portals

* **Admin Portal** at http://localhost:8095. Sign in with `portal-admin` / `password` to manage organizations, patients, and users, review developer apps, and configure the platform. With OrgBAC on, the portal works in multi-organization mode: each Organization has its own patients, users, and FHIR endpoint `http://localhost:8080/Organization/<id>/fhir`.
* **Developer Portal** at http://localhost:8096. External developers sign up here, register SMART on FHIR apps and backend services, and test them against the sandbox. A developer picks the Organization when registering a backend service.
* **FHIR App Gallery**: the patient-facing catalog of approved SMART apps.

## Stop and reset

```bash
docker compose down      # stop containers, keep data
docker compose down -v   # stop and delete the PostgreSQL volume
```

## Next steps

{% content-ref url="../tutorials/admin-portal.md" %}
[Admin Portal](../tutorials/admin-portal.md)
{% endcontent-ref %}

{% content-ref url="../tutorials/developer-sandbox.md" %}
[Developer Sandbox](../tutorials/developer-sandbox.md)
{% endcontent-ref %}

{% content-ref url="../tutorials/app-gallery.md" %}
[FHIR App Gallery](../tutorials/app-gallery.md)
{% endcontent-ref %}
