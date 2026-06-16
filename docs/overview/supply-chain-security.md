# Supply Chain Security

Aidbox secures its software supply chain so you can verify the integrity and provenance of every release you run.

## Signed container images

Health Samurai signs all official Aidbox container images with [Cosign](https://github.com/sigstore/cosign). Verify a signature before deploying an image to confirm it was built and published by Health Samurai and has not been tampered with.

The public key is available at [cosign.pub](https://storage.googleapis.com/samurai-public/cosign.pub).

Verify an image signature with the Cosign CLI:

```bash
# Download the public key
curl -O https://storage.googleapis.com/samurai-public/cosign.pub

# Verify the image signature
cosign verify --key cosign.pub healthsamurai/aidboxone:edge
```

A successful run prints the verified signature payload. A non-zero exit code means the signature is missing or invalid: do not deploy the image.

## Software Bill of Materials (SBOM)

Each Aidbox release ships with a Software Bill of Materials that lists the components and dependencies bundled in the image. Use the SBOM to audit dependencies and track them against your vulnerability management process.

Download the SBOM for the edge build: [edge-sbom.json](https://storage.googleapis.com/aidbox_sbom/edge/edge-sbom.json).

## Vulnerability scanning

Health Samurai scans Aidbox images for known vulnerabilities before release. [Trivy](https://github.com/aquasecurity/trivy) is the primary scanner: it inspects the image for vulnerable OS packages and application dependencies. You can run the same scan against any Aidbox image:

```bash
trivy image healthsamurai/aidboxone:edge
```

## Remediation SLAs

Health Samurai triages and remediates reported vulnerabilities on a schedule driven by CVSS v3.1 severity:

| Severity | CVSS v3.1 | Triage | Remediation |
|---|---|---|---|
| Critical | 9.0–10.0 | ≤ 24 hours | ≤ 7 days |
| High | 7.0–8.9 | ≤ 3 business days | ≤ 30 days |
| Medium | 4.0–6.9 | ≤ 7 days | ≤ 90 days |
| Low | 0.1–3.9 | ≤ 30 days | ≤ 180 days |

Vulnerabilities under active exploitation or involving exposure of protected health information (PHI) are handled as security incidents, outside the severity tiers above.

Health Samurai maintains a VEX (Vulnerability Exploitability eXchange) document that records the exploitability status of scanner findings. Request it through the [customer Zulip](https://connect.health-samurai.io/) or by email at [security@health-samurai.io](mailto:security@health-samurai.io).

Fixes are delivered through the `:stable` channel and supported LTS releases, which receive backports for two years. See [Release Notes](release-notes.md) for fixes included in each version.

## Reporting a security issue

If you discover a security vulnerability in Aidbox, report it to [security@health-samurai.io](mailto:security@health-samurai.io) or through the [customer Zulip](https://connect.health-samurai.io/). Do not disclose the issue publicly until it has been resolved.
