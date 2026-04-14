---
description: Create access policies to restrict client permissions to bulk API operations in Aidbox.
---

# Configure Access Policies for Bulk API

Let's create a new client and an access policy that allows the client to use only bulk API

{% hint style="info" %}
The `$dump`, `$dump-csv`, and `$dump-sql` operations are available only on **Aidbox endpoints** (without the `/fhir/` prefix). Unlike `$import` and `$load`, there are no `/fhir/`-prefixed variants for these operations. The access policy patterns below reflect this.
{% endhint %}

```yaml
PUT /

- resourceType: Client
  id: bulk-client
  secret: secret
  grant_types: ['basic']

- resourceType: AccessPolicy
  id: bulk-client-dump
  engine: matcho
  matcho:
    $one-of:
    - uri: /$dump-sql
      request-method: post
    - uri: "#/.*/\\$dump$"
      request-method: get
    - uri: "#/.*/\\$dump-csv$"
      request-method: get
    - uri:
        $one-of:
          - /$import
          - /fhir/$import
      request-method: post
    - uri:
        $one-of:
          - /$load
          - /fhir/$load
          - "#/.*/\\$load$"
  link:
  - {id: 'bulk-client', resourceType: 'Client'}
```
