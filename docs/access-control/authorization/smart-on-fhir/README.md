---
description: Implement SMART App Launch, backend services, scopes, and client authentication with OAuth 2.0 for FHIR applications.
---

# SMART on FHIR

{% hint style="info" %}
This functionality is available starting from version 2411.
{% endhint %}

[SMART on FHIR](https://build.fhir.org/ig/HL7/smart-app-launch/) is a framework that describes a set of foundational patterns based on OAuth 2.0 for client applications to authorize, authenticate, and integrate with FHIR-based data systems.

Aidbox can take either side of it: it can be the authorization server that authenticates the user and issues the access token, or it can accept tokens issued by another server and only enforce what they allow.

## Where to go next

**[Client authorization](smart-client-authorization/)** — how an application obtains a token. [App Launch](smart-client-authorization/smart-app-launch.md) is for applications acting on behalf of a user, started either from an EHR or standalone. [Backend Services](smart-client-authorization/smart-backend-services.md) is for server-to-server access with no user involved.

**[Client authentication](smart-client-authentication/)** — how a confidential client proves its identity when requesting a token: with a client secret ([symmetric](smart-client-authentication/smart-symmetric-docs-client-secret-authentication.md)) or with a signed JWT ([asymmetric](smart-client-authentication/smart-asymmetric-docs-private-key-jwt-authentication.md)). Backend Services requires the asymmetric method.

**[Scopes](smart-scopes-for-limiting-access.md)** — what a token is allowed to do once it is issued, including narrowing access with search parameters and limiting it to a single patient.

## Examples

* [SMART App Launch using Aidbox and Keycloak](example-smart-app-launch-using-aidbox-and-keycloak.md)
* [SMART App Launch using Smartbox and Keycloak](example-smart-app-launch-using-smartbox-and-keycloak.md)
* [Pass Inferno SMART App Launch Test Kit using Aidbox](pass-inferno-tests-with-aidbox.md)
* [How to enable SMART on FHIR on Patient Access API](../../../tutorials/security-access-control-tutorials/how-to-enable-smart-on-fhir-on-patient-access-api.md)
