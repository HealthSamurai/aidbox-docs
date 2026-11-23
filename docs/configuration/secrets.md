---
description: >-
  Which secrets Aidbox uses, where it keeps them, and how it protects
  and rotates them: settings, resource fields, and external secret files.
---

# Secrets

Aidbox keeps secrets in three places:

* [Settings](#secrets-in-settings): credentials and keys you pass as environment variables, such as the database password or the JWT signing key.
* [Resource fields](#secrets-in-resources): values stored in the database inside resources, such as a `Client` secret or an `AwsAccount` access key.
* [External secret files](#keep-secrets-out-of-the-database): files that Aidbox reads at runtime, so the value never reaches the database.

## Secrets in settings

Aidbox marks the settings below as sensitive. For a sensitive setting, Aidbox:

* masks the value in the Admin UI and in the settings API;
* leaves the value out of error messages when it can't parse it;
* accepts the value only from an environment variable and rejects attempts to store it in the database.

{% hint style="warning" %}
The settings export endpoint (`/api/v1/settings/export`) returns sensitive values in plaintext. It is off by default. Keep [`BOX_EXPORT_SETTINGS_ENDPOINT`](../reference/all-settings.md#export-settings-endpoint) set to `false` in production.
{% endhint %}

The [settings reference](../reference/all-settings.md) lists the deprecated environment variable names and the details for each setting.

### Bootstrap credentials

| Environment variable     | Purpose                                                                                    |
| ------------------------ | ------------------------------------------------------------------------------------------ |
| `BOX_ROOT_CLIENT_SECRET` | Secret of the `root` client, which has full access to the API.                             |
| `BOX_ADMIN_PASSWORD`     | Password of the `admin` user for the Admin UI.                                             |

Set both in every environment. See [Recommended environment variables](recommended-envs.md).

### Database

| Setting                                                                                                            | Environment variable                          | Purpose                                                                 |
| ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------- | ----------------------------------------------------------------------- |
| [`db.password`](../reference/all-settings.md#db.password)                                                          | `BOX_DB_PASSWORD`                             | Password of the database user.                                          |
| `db.maintenance.password`                                                                                          | `BOX_DB_MAINTENANCE_PASSWORD`                 | Password of the user that creates the database and runs maintenance. Falls back to `BOX_DB_PASSWORD`. |
| [`db.ro-replica.password`](../reference/all-settings.md#db.ro-replica.password)                                    | `BOX_DB_RO_REPLICA_PASSWORD`                  | Password for the read-only replica.                                     |
| [`db.databricks-client-secret`](../reference/all-settings.md#db.databricks-client-secret)                          | `BOX_DB_DATABRICKS_CLIENT_SECRET`             | OAuth client secret for Databricks Lakebase authentication.             |
| [`db.ro-replica.databricks-client-secret`](../reference/all-settings.md#db.ro-replica.databricks-client-secret)    | `BOX_DB_RO_REPLICA_DATABRICKS_CLIENT_SECRET`  | The same for the read-only replica.                                     |

### Token signing and encryption keys

| Setting                                                                                  | Environment variable              | Purpose                                                                                                 |
| ---------------------------------------------------------------------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------------- |
| [`security.auth.keys.private`](../reference/all-settings.md#security.auth.keys.private)  | `BOX_SECURITY_AUTH_KEYS_PRIVATE`  | RSA private key that signs the JWTs Aidbox issues (RS256). Pair it with `BOX_SECURITY_AUTH_KEYS_PUBLIC`. |
| [`security.auth.keys.secret`](../reference/all-settings.md#security.auth.keys.secret)    | `BOX_SECURITY_AUTH_KEYS_SECRET`   | Shared secret for HS256 JWTs.                                                                           |
| [`security.encrypt-secret`](../reference/all-settings.md#security.encrypt-secret)        | `BOX_SECURITY_ENCRYPT_SECRET`     | Key for the [Encryption API](../api/other/encryption-api.md) and for resource fields that Aidbox encrypts. |

### Email providers

| Setting                                                                                  | Environment variable                    | Purpose                          |
| ---------------------------------------------------------------------------------------- | --------------------------------------- | -------------------------------- |
| [`provider.default.password`](../reference/all-settings.md#provider.default.password)    | `BOX_MODULE_PROVIDER_DEFAULT_PASSWORD`  | Password of the default provider. |
| [`provider.smtp.password`](../reference/all-settings.md#provider.smtp.password)          | `BOX_MODULE_PROVIDER_SMTP_PASSWORD`     | SMTP password.                   |
| [`provider.mailgun.password`](../reference/all-settings.md#provider.mailgun.password)    | `BOX_MODULE_PROVIDER_MAILGUN_PASSWORD`  | Mailgun password.                |
| [`provider.postmark.api-key`](../reference/all-settings.md#provider.postmark.api-key)    | `BOX_MODULE_PROVIDER_POSTMARK_API_KEY`  | Postmark API key.                |
| [`provider.sendgrid.api-key`](../reference/all-settings.md#provider.sendgrid.api-key)    | `BOX_MODULE_PROVIDER_SENDGRID_API_KEY`  | SendGrid API key.                |

{% hint style="warning" %}
Aidbox doesn't mark the Postmark and SendGrid API keys as sensitive, so the Admin UI shows them in plaintext. Limit access to the Admin UI settings page if you use these providers.
{% endhint %}

### Observability

| Setting                                                                                            | Environment variable                    | Purpose                                         |
| -------------------------------------------------------------------------------------------------- | --------------------------------------- | ----------------------------------------------- |
| [`observability.datadog.api-key`](../reference/all-settings.md#observability.datadog.api-key)      | `BOX_OBSERVABILITY_DATADOG_API_KEY`     | Datadog API key for log shipping.               |
| [`observability.elasticsearch.auth`](../reference/all-settings.md#observability.elasticsearch.auth) | `BOX_OBSERVABILITY_ELASTICSEARCH_AUTH` | Elasticsearch credentials as `<user>:<password>`. |

### Modules and integrations

| Setting                                                                                                                                        | Environment variable                                          | Purpose                                              |
| ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------- |
| [`module.subscriptions.pubsub.service-account.private-key`](../reference/all-settings.md#module.subscriptions.pubsub.service-account.private-key) | `BOX_MODULE_SUBSCRIPTIONS_PUBSUB_SERVICE_ACCOUNT_PRIVATE_KEY` | GCP service account key for Pub/Sub subscriptions.   |
| [`module.webpush.private-key`](../reference/all-settings.md#module.webpush.private-key)                                                        | `BOX_MODULE_WEBPUSH_PRIVATE_KEY`                              | Private key for web push notifications.              |
| [`module.health-cards-links.issuer-private-key`](../reference/all-settings.md#module.health-cards-links.issuer-private-key)                    | `BOX_MODULE_HEALTH_CARDS_LINKS_ISSUER_PRIVATE_KEY`            | Issuer key that signs SMART Health Cards.            |
| [`module.sdc.openai-api-key`](../reference/all-settings.md#module.sdc.openai-api-key)                                                          | `BOX_MODULE_SDC_OPENAI_API_KEY`                               | OpenAI API key for Formbox AI features.              |
| [`modules.sdc.gemini-api-key`](../reference/all-settings.md#modules.sdc.gemini-api-key)                                                        | `BOX_SDC_GEMINI_API_KEY`                                      | Gemini API key for Formbox.                          |
| [`module.sdc.twilio-auth-token`](../reference/all-settings.md#module.sdc.twilio-auth-token)                                                    | `BOX_MODULE_SDC_TWILIO_AUTH_TOKEN`                            | Twilio auth token for Formbox outbound voice calls.  |
| [`module.sdc.dtr.client-secret`](../reference/all-settings.md#module.sdc.dtr.client-secret)                                                    | `BOX_MODULE_SDC_DTR_CLIENT_SECRET`                            | Client secret for the Da Vinci DTR service.          |

Formbox also takes API keys for ElevenLabs, Deepgram, and Cartesia (`BOX_MODULE_SDC_ELEVENLABS_API_KEY`, `BOX_MODULE_SDC_DEEPGRAM_API_KEY`, `BOX_MODULE_SDC_CARTESIA_API_KEY`).

## Secrets in resources

### Values Aidbox hashes or encrypts

Aidbox transforms these fields before it saves the resource:

| Field                                                                 | What Aidbox stores                                                             |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `User.password`                                                       | An scrypt hash.                                                                |
| `Client.secret`                                                       | A SHA-256 hash.                                                                |
| `Session.access_token`, `Session.refresh_token`, `Session.authorization_code` | A SHA-256 hash.                                                        |
| `SDCConfig` `auth.client-secret` (form store, data store, terminology server, DTR service) | A value encrypted with [`security.encrypt-secret`](../reference/all-settings.md#security.encrypt-secret). |

Aidbox can't recover a hashed value, only compare a submitted one against it. To change a client secret or a password, write a new value.

### Values Aidbox stores as you send them

These fields hold credentials for external systems, and Aidbox saves them in the database unchanged:

| Resource                                         | Fields                                                                                              |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| [`AwsAccount`](../file-storage/aws-s3.md)        | `secret-access-key`                                                                                 |
| [`GcpServiceAccount`](../file-storage/gcp-cloud-storage.md) | `private-key`                                                                            |
| [`AzureAccount`](../file-storage/azure-blob-storage.md) | `key`, `clientSecret`                                                                         |
| `IdentityProvider`                               | `client.secret`, `client.private-key`, `client.certificate`                                         |
| `TokenIntrospector`                              | `jwt.secret`, `jwt.keys.k`, `introspection_endpoint.authorization`                                  |
| `AidboxTopicDestination`                         | Kafka `saslJaasConfig` and `sslKeystoreKey`, webhook `header`                                       |

Restrict read access to these resource types with [access policies](../access-control/authorization/README.md). For the `IdentityProvider`, `TokenIntrospector`, `AidboxTopicDestination`, and `Client` fields, you can keep the value out of the database with [External Secrets](secret-files.md).

## Keep secrets out of the database

[External Secrets](secret-files.md) let a resource field point to a file instead of holding the value:

1. You mount the secret as a file, for example from a Kubernetes Secret or a vault CSI driver.
2. A vault config file, set with `BOX_VAULT_CONFIG`, maps a secret name to the file path and to the resources that may use it.
3. The resource stores only the secret name in a `secret-reference` extension. Aidbox reads the file when it needs the value and never returns the value through the API.

External Secrets also hold the keys for [field-level encryption](storage-and-api-configuration/field-level-encryption.md), with `"kind": "encryption"` in the vault config.

See the [Azure Key Vault](../tutorials/other-tutorials/azure-key-vault-external-secrets.md) and [HashiCorp Vault](../tutorials/other-tutorials/hashicorp-vault-external-secrets.md) tutorials for end-to-end setups.

## Rotate secrets

| Secret                                              | How to rotate                                                                                                                                                                       |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Settings                                            | Change the environment variable and restart Aidbox. Aidbox reads sensitive settings only from environment variables, so a new value takes effect after the restart.                  |
| JWT signing keys                                    | Tokens signed with the old key stop validating after the restart, so clients have to get new tokens.                                                                                |
| `security.encrypt-secret`                           | Aidbox can't decrypt values encrypted with the old key. Write the encrypted `SDCConfig` fields again after you change it.                                                           |
| `Client.secret`, `User.password`                    | Write a new value to the resource.                                                                                                                                                  |
| External secret files                               | Replace the file. Aidbox notices the new modification time and uses the new value without a restart.                                                                                |
| Field-level encryption keys                         | Add the new key next to the old one, as described in [Key rotation](storage-and-api-configuration/field-level-encryption.md#key-rotation).                                           |

## Recommendations

* Pass secrets as environment variables from your orchestrator's secret store, such as Kubernetes Secrets. Don't commit them to `docker-compose.yaml` or Helm values files.
* Use [External Secrets](secret-files.md) for credentials in resources where Aidbox supports it.
* Generate long random values for `BOX_ROOT_CLIENT_SECRET`, `BOX_ADMIN_PASSWORD`, and `BOX_SECURITY_AUTH_KEYS_SECRET`.
* Give the database user only the privileges Aidbox needs, and use a separate maintenance user if your platform allows it.
* Keep the settings export endpoint off.
* See [Security hardening](../access-control/security-hardening.md) for related recommendations.
