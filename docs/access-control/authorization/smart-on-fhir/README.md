---
description: Implement SMART App Launch, backend services, scopes, and client authentication with OAuth 2.0 for FHIR applications.
---

# SMART on FHIR

{% hint style="info" %}
This functionality is available starting from version 2411.
{% endhint %}

[SMART on FHIR](https://build.fhir.org/ig/HL7/smart-app-launch/) is a framework that describes a set of foundational patterns based on OAuth 2.0 for client applications to authorize, authenticate, and integrate with FHIR-based data systems.

Aidbox can take either side of it: it can be the authorization server that authenticates the user and issues the access token, or it can accept tokens issued by another server and enforce what they allow.

{% cards %}
{% card icon="shield" title="Client authorization" href="smart-client-authorization/" %}
How an application obtains a token. App Launch is for applications acting on behalf of a user, started either from an EHR or standalone. Backend Services is for server-to-server access with no user involved.
{% endcard %}
{% card icon="key" title="Client authentication" href="smart-client-authentication/" %}
How a confidential client proves its identity when requesting a token: with a client secret (symmetric) or with a signed JWT (asymmetric). Backend Services requires the asymmetric method.
{% endcard %}
{% card icon="sliders" title="Scopes" href="smart-scopes-for-limiting-access.md" %}
What a token is allowed to do once it is issued, including narrowing access with search parameters and limiting it to a single patient.
{% endcard %}
{% endcards %}

## Examples

{% cards %}
{% card icon="rocket" title="Aidbox and Keycloak" href="example-smart-app-launch-using-aidbox-and-keycloak.md" %}
Run the EHR and standalone launch flows with a demo launcher and a growth chart application.
{% endcard %}
{% card icon="box" title="Smartbox and Keycloak" href="example-smart-app-launch-using-smartbox-and-keycloak.md" %}
The same EHR and patient launch flows, run with Smartbox.
{% endcard %}
{% card icon="check" title="Inferno test kit" href="pass-inferno-tests-with-aidbox.md" %}
Pass the Inferno SMART App Launch Test Kit with Aidbox.
{% endcard %}
{% card icon="user" title="Patient Access API" href="../../../tutorials/security-access-control-tutorials/how-to-enable-smart-on-fhir-on-patient-access-api.md" %}
Enable SMART on FHIR for the Patient Access API.
{% endcard %}
{% endcards %}
