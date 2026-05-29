---
description: Deploy Aidbox to Kubernetes, managed PostgreSQL, or with Helm charts. Comprehensive deployment guides and configuration options.
---

# Deploy Aidbox

## Deployment guides

{% cards %}
{% card icon="assets/brand-icons/kubernetes.svg" title="Run Aidbox on Kubernetes" href="run-aidbox-in-kubernetes/README.md" %}
Production-ready configurations with Helm charts, HA setup, and self-signed SSL.
{% endcard %}
{% card icon="database" title="Run on managed PostgreSQL" href="run-aidbox-on-managed-postgresql.md" %}
AWS Aurora, Azure Database, GCP Cloud SQL, Databricks Lakebase. Extensions and user setup.
{% endcard %}
{% card icon="sliders" title="Inject env variables into Init Bundle" href="how-to-inject-env-variables-into-init-bundle.md" %}
Inject environment variables with envsubst or sed for secrets and CI/CD pipelines.
{% endcard %}
{% endcards %}

## Cloud deployment tutorials

{% cards %}
{% card icon="assets/brand-icons/googlecloud.svg" title="Run Aidbox in GCP Cloud Run" href="../../tutorials/other-tutorials/how-to-run-aidbox-in-gcp-cloud-run.md" %}
Deploy Aidbox on Google Cloud Run with Cloud SQL PostgreSQL.
{% endcard %}
{% card icon="assets/brand-icons/azure-container-apps.svg" title="Run Aidbox in Azure Container Apps" href="../../tutorials/other-tutorials/how-to-run-aidbox-in-azure-container-apps.md" %}
Deploy Aidbox on Azure Container Apps with Azure Database for PostgreSQL.
{% endcard %}
{% endcards %}
