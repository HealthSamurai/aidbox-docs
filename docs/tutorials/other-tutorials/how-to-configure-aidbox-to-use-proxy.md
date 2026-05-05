---
description: Configure Aidbox to use a proxy for outgoing requests, install a corporate CA certificate, and troubleshoot SSL errors when fetching FHIR packages.
---

# How to configure Aidbox to use a proxy for outgoing requests

## Objectives

* Route Aidbox outbound HTTP / HTTPS traffic through a corporate proxy.
* Trust a corporate CA used for proxy SSL inspection.
* Diagnose SSL errors when fetching FHIR packages from `fs.get-ig.org`.
* Know which fallback to reach for in air-gapped environments.

## Before you begin

* You have a proxy host / port from your network team.
* If the proxy performs SSL inspection, you have the corporate root CA certificate (`.crt` / `.pem`).
* You can build a custom container image based on `healthsamurai/aidboxone`.

## Configure the HTTP / HTTPS proxy

Aidbox uses Java's standard networking stack, so the proxy is configured through `JAVA_OPTS`. Set both `https.*` and `http.*` so package downloads, webhook deliveries, terminology lookups, and any other outbound calls go through the proxy.

```yaml
# docker-compose.yaml
services:
  aidbox:
    environment:
      JAVA_OPTS: >-
        -Dhttps.proxyHost=proxy.corp.example.com
        -Dhttps.proxyPort=8080
        -Dhttp.proxyHost=proxy.corp.example.com
        -Dhttp.proxyPort=8080
        -Dhttp.nonProxyHosts=localhost|127.0.0.1|*.svc.cluster.local
```

{% hint style="warning" %}
This setting proxies **all** outbound requests from Aidbox, including [AidboxTopicDestination](../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md) webhook deliveries, GCP Pub/Sub clients, and external terminology calls. Add internal hosts you want to reach directly to `http.nonProxyHosts`.
{% endhint %}

See [Java networking properties reference](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/net/doc-files/net-properties.html) for the full property list.

## Install a corporate CA certificate

If your proxy performs SSL inspection it presents an internally-signed certificate when Aidbox connects to `https://fs.get-ig.org` (or any other upstream). Java rejects it because the corporate root CA is not in the default truststore. Add the CA to the JVM's `cacerts` keystore at image build time:

```dockerfile
FROM healthsamurai/aidboxone:edge

COPY corporate-ca.crt /tmp/corporate-ca.crt

RUN keytool -importcert -trustcacerts \
      -keystore "$JAVA_HOME/lib/security/cacerts" \
      -storepass changeit -noprompt \
      -alias corporate-ca \
      -file /tmp/corporate-ca.crt \
 && rm /tmp/corporate-ca.crt
```

If the proxy issues a chain (intermediate + root), import each certificate with a unique alias.

{% hint style="info" %}
Verify the certificate was added: `keytool -list -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit -alias corporate-ca`.
{% endhint %}

## Troubleshooting SSL errors when fetching FHIR packages

Since [Aidbox 2602](../../overview/release-notes.md#february-2026-2602) the HTTP client uses Java's standard JSSE SSL stack. JSSE is stricter than the previous client and surfaces certificate-chain problems that earlier versions silently tolerated.

**Symptoms** — startup fails to bootstrap [`BOX_BOOTSTRAP_FHIR_PACKAGES`](../../reference/all-settings.md), or [Artifact Registry](../../artifact-registry/artifact-registry-overview.md) package install errors with one of:

* `SSL peer shut down incorrectly`
* `EOFException` thrown from `sun.security.ssl.SSLSocketInputRecord.read`
* `unable to find valid certification path to requested target`
* `PKIX path building failed`

**Root cause** — corporate proxy SSL inspection presents a certificate signed by an internal CA that the JVM does not trust. The `fs.get-ig.org` certificate itself is healthy (Google Trust Services chain) — the failure is at the proxy hop, not at the upstream.

**Fix order:**

1. Confirm whether you are behind a proxy with SSL inspection: `openssl s_client -connect fs.get-ig.org:443 -servername fs.get-ig.org`. If the issuer is not Google Trust Services, the proxy is intercepting.
2. Configure the proxy via `JAVA_OPTS` ([above](#configure-the-http-https-proxy)).
3. If SSL inspection is enabled, install the corporate CA ([above](#install-a-corporate-ca-certificate)).
4. As a workaround for air-gapped or otherwise restricted environments, skip the network entirely — see [Loading packages from local filesystem](../../artifact-registry/artifact-registry-overview.md#loading-packages-from-local-filesystem).
5. Or point Aidbox at an internal package mirror (Verdaccio, Nexus, etc.) using [`BOX_FHIR_NPM_PACKAGE_REGISTRY`](../../reference/all-settings.md).

{% hint style="danger" %}
Disabling SSL verification (`-Dcom.sun.net.ssl.checkRevocation=false`, custom permissive truststores, etc.) silences the symptom but exposes Aidbox to MITM attacks on every outbound call. Fix the trust chain instead.
{% endhint %}

## See also

* [Artifact Registry overview](../../artifact-registry/artifact-registry-overview.md)
* [Loading packages from local filesystem](../../artifact-registry/artifact-registry-overview.md#loading-packages-from-local-filesystem)
* [Java networking system properties](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/net/doc-files/net-properties.html)
