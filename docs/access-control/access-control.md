---
description: Comprehensive access control for healthcare applications with identity management, authentication, authorization, and audit logging.
---

# Overview

Aidbox offers everything you need for secure identity, authentication, and auditing.

{% cards %}
{% card icon="users" title="Identity Management" href="identity-management/" %}
Use Aidbox's built-in provider or plug in Google, Okta, or any OIDC-compliant service.
{% endcard %}
{% card icon="key" title="Authentication" href="authentication/" %}
Basic, OAuth 2.0 and OpenID Connect flows, JWT-based auth, and Single Sign-On through external OAuth 2.0 providers.
{% endcard %}
{% card icon="shield" title="Authorization" href="authorization/" %}
Access Policies, SMART scopes, the Security Labels framework, and Scoped APIs (Patient API, Organization API, Compartments API).
{% endcard %}
{% card icon="doc" title="Audit and Logging" href="audit-and-logging.md" %}
FHIR BALP (Basic Audit Logging Profile) for Audit Events and OpenTelemetry for structured logging.
{% endcard %}
{% endcards %}

Want to try it out? Check out our tutorials:

* [Managing Admin Access to the Aidbox UI Using Okta Groups](../tutorials/security-access-control-tutorials/managing-admin-access-to-the-aidbox-ui-using-okta-groups.md)
* [SMART App Launch using Aidbox and Keycloak](authorization/smart-on-fhir/example-smart-app-launch-using-aidbox-and-keycloak.md)
* [How to configure Audit Log](../tutorials/security-access-control-tutorials/how-to-configure-audit-log.md)
