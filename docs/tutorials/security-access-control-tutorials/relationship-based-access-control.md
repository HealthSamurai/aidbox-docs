---
description: Learn how to enable ReBAC in Aidbox with AccessPolicy
---

# Relationship-based access control

Throughout this tutorial, we’ll walk you through the implementation of basic relationship-based access control model in Aidbox. We’ll assume you have Aidbox up & running already [locally](../../getting-started/run-aidbox-locally.md) or [in cloud](../../getting-started/run-aidbox-in-sandbox.md).

{% hint style="info" %}
**Where to get help:**

If you’re having trouble going through this tutorial, please head over to [our Aidbox community chat](https://t.me/aidbox).
{% endhint %}

In this tutorial we will

* model authorization for our sample application called _Research Study Repository_
* implement that authorization model in Aidbox with AccessPolicy engine.

## Authorization model

We will model access for an example application called _Research study repository_. The system is going to give researchers an access to research studies and related patient records.

Our security policy says:

> _User has access to all studies they collaborate on and to all patient records within those studies._

Authorization model that best suits our task is [relationship-based access control](https://en.wikipedia.org/wiki/Relationship-based_access_control) (ReBAC). It states that _'subject's permission to access a resource is defined by the presence of relationships between those subjects and resources'_.

We will focus only on read access, expecting that all data is uploaded. We will upload prepared sample data later on implementation section.

But before we dive into defining authorization, let's discuss our data model and UI we are going to provide our users. Good data model and UI leads to easier authorization.

### Data model & UI

The core entity of our application will be a research study. There is [a ResearchStudy resource in FHIR](https://www.hl7.org/fhir/researchstudy.html), which describes _'a process where a researcher or organization plans and then executes a series of steps intended to increase the field of healthcare-related knowledge'_.

ResearchStudy references to Group of patients invloved in the research with [`ResearchStudy.enrollment`](https://www.hl7.org/fhir/researchstudy-definitions.html#ResearchStudy.enrollment) element. Patient record is represented by two resources Patient and Observation.

ResearchStudy doesn't have references to collaborators. So, we will introduce one with an extension and make a linkage with Aidbox User.

As ResearchStudy resource is a core of our model, it's reasonable to make the list of available studies a starting point on UI. So we may imagine user's flow within UI.

* Researcher enters the system and see the list of studies, they involved into as a collaborator.
* They can drill down to a study to see details and search over related patients and observations.

Once we defined our data model, UI pages and FHIR requests, we may start implementing this.

## Implementation

As we mentioned earlier, FHIR ResearchStudy doesn't have references to collaborators. FHIR way to add such data is an [extension](https://www.hl7.org/fhir/extensibility.html). We will store collaborators as extensions with a reference to Aidbox User:

```yaml
extension:
- url: http://example.org/fhir/StructureDefinition/collaborator
  valueReference:
    reference: User/jane
```

### Upload sample data

We prepared data samples, so we could test our access policies. You can use the request below to upload sample data. You can perform this request in [Aidbox REST Console](../../overview/aidbox-ui/README.md).

```yaml
POST /fhir
Content-Type: text/yaml
Accept: text/yaml

resourceType: Bundle
type: transaction
entry:
- request: {method: PUT, url: User/jane}
  resource: {resourceType: User}
- request: {method: PUT, url: Session/janes-session}
  resource: {resourceType: Session, user: {reference: User/jane}, access_token: janes-access-token}
- request: {method: PUT, url: User/oscar}
  resource: {resourceType: User}
- request: {method: PUT, url: Session/oscars-session}
  resource: {resourceType: Session, user: {reference: User/oscar}, access_token: oscars-access-token}
- request: {method: PUT, url: Patient/patient-1}
  resource: {resourceType: Patient}
- request: {method: PUT, url: Patient/patient-2}
  resource: {resourceType: Patient}
- request: {method: PUT, url: Patient/patient-3}
  resource: {resourceType: Patient}
- request: {method: PUT, url: Observation/patient-1-obs-1}
  resource:
    resourceType: Observation
    status: final
    subject: {reference: Patient/patient-1}
    code:
      coding: [{system: 'http://loinc.org', code: 718-7, display: 'hemoglobin [mass/volume] in blood'}]
- request: {method: PUT, url: Observation/patient-2-obs-1}
  resource:
    resourceType: Observation
    status: final
    subject: {reference: Patient/patient-2}
    code:
      coding: [{system: 'http://loinc.org', code: 718-7, display: 'hemoglobin [mass/volume] in blood'}]
- request: {method: PUT, url: Observation/patient-3-obs-1}
  resource:
    resourceType: Observation
    status: final
    subject: {reference: Patient/patient-3}
    code:
      coding: [{system: 'http://loinc.org', code: 718-7, display: 'hemoglobin [mass/volume] in blood'}]
- request: {method: PUT, url: Group/group-1}
  resource:
    resourceType: Group
    actual: true
    type: person
    member:
    - entity: {reference: Patient/patient-1}
    - entity: {reference: Patient/patient-2}
- request: {method: PUT, url: Group/group-2}
  resource:
    resourceType: Group
    actual: true
    type: person
    member:
    - entity: {reference: Patient/patient-2}
    - entity: {reference: Patient/patient-3}
- request: {method: PUT, url: ResearchStudy/smoking-research}
  resource:
    resourceType: ResearchStudy
    status: active
    enrollment: [{reference: Group/group-1}]
    extension:
    - {url: 'http://example.org/fhir/StructureDefinition/collaborator', valueReference: {reference: User/jane}}
    - {url: 'http://example.org/fhir/StructureDefinition/collaborator', valueReference: {reference: User/oscar}}
- request: {method: PUT, url: ResearchStudy/diet-research}
  resource:
    resourceType: ResearchStudy
    status: active
    enrollment: [{reference: Group/group-2}]
    extension:
    - {url: 'http://example.org/fhir/StructureDefinition/collaborator', valueReference: {reference: User/oscar}}
```

In the uploaded data, Jane has access to 'Smoking research', and both users have access to 'Diet research'.

## Write access policies

Now, we are ready to define available enpoints and write AccessPolicy for them.

### List of studies

The endpoint to fetch all user's research studies is

```yaml
GET /fhir/ResearchStudy?collaborator=<user-id>
```

FHIR doesn't have search parameter `collaborator`. Aidbox allows you to define one with [SearchParameter resource](../../api/rest-api/fhir-search/searchparameter.md).

```yaml
PUT /fhir/SearchParameter/ResearchStudy-collaborator
Content-Type: text/yaml
Accept: text/yaml

resourceType: SearchParameter
url: http://example.org/fhir/SearchParameter/ResearchStudy-collaborator
name: collaborator
status: active
description: Research study collaborators
code: collaborator
base: [ResearchStudy]
type: reference
target: [User]
expression: ResearchStudy.extension.where(url='http://example.org/fhir/StructureDefinition/collaborator').value.ofType(Reference)
```

AccessPolicy:

```yaml
PUT /fhir/AccessPolicy/user-can-search-their-research-studies
Content-Type: text/yaml
Accept: text/yaml

resourceType: AccessPolicy
description: User can search for research studies, they collaborate on
engine: matcho
matcho:
  request-method: get
  uri: /fhir/ResearchStudy
  params:
    collaborator: .user.id
    _with: nil?
    _include: nil?
    _revinclude: nil?
  user:
    id: present?
```

{% hint style="info" %}
**Why did we explicitly exclude `_include`, `_revinclude` and `_with` parameters?**

matcho engine compares incoming request with defined pattern, if the key is not specified in pattern, it will be ignore while checking. `_include`, `_revinclude` and `_with` parameters expands the list of returning data with related resources. As far we want to leave only ResearchStudy resources, we excluded them explicitly.

Read more on [AccessPolicy best practicies guide](accesspolicy-best-practices.md).
{% endhint %}

Let's check it.

{% tabs %}
{% tab title="Jane searches for her studies" %}
```yaml
GET /fhir/ResearchStudy?collaborator=jane
Authorization: Bearer janes-access-token

# 200 OK
```
{% endtab %}

{% tab title="Jane searches for all studies" %}
```yaml
GET /fhir/ResearchStudy
Authorization: Bearer janes-access-token

# 403 Forbidden
```
{% endtab %}

{% tab title="Jane searches for Oscar" %}
```yaml
GET /fhir/ResearchStudy?collaborator=oscar
Authorization: Bearer janes-access-token

# 403 Forbidden
```
{% endtab %}
{% endtabs %}

We have secured endpoint for fetching list of studies. Note, that all [search parameters for ResearchStudy](https://www.hl7.org/fhir/researchstudy.html#search) is also available.

### Read study details

The endpoint to fetch research study details is

```yaml
GET /fhir/ResearchStudy/<research-study-id>
```

It's not possible find out if current user is a collaborator on this study or not by only research study id . Fortunately, Aidbox AccessPolicy supports sql engine, which allows you to make your authorization decisions based on data you have.

```yaml
PUT /fhir/AccessPolicy/user-can-read-their-research-study
Content-Type: text/yaml
Accept: text/yaml

resourceType: AccessPolicy
description: User can research study, they collaborate on
engine: complex
and:
- engine: matcho
  matcho:
    request-method: get
    uri: "#/fhir/ResearchStudy/.+"
    user:
      id: present?
- engine: sql
  sql:
    query: |
      SELECT true
      FROM "researchstudy"
      WHERE 
        id = {{params.resource/id}}
        and "researchstudy".resource @> jsonb_build_object('extension', jsonb_build_array(jsonb_build_object('url', 'http://example.org/fhir/StructureDefinition/collaborator', 'value', jsonb_build_object('Reference', jsonb_build_object('id', {{user.id}}::text)))))
      limit 1

```

Let's check it.

{% tabs %}
{% tab title="Jane reads smoking research" %}
```yaml
GET /fhir/ResearchStudy/smoking-research
Authorization: Bearer janes-access-token

# 200 OK
```
{% endtab %}

{% tab title="Jane reads diet research" %}
```yaml
GET /fhir/ResearchStudy/diet-research
Authorization: Bearer janes-access-token

# 403 Forbidden
```
{% endtab %}

{% tab title="Oscar reads diet research" %}
```yaml
GET /fhir/ResearchStudy/diet-research
Authorization: Bearer oscars-access-token

# 200 OK
```
{% endtab %}
{% endtabs %}

We have secured one more endpoint. There are only two left.

### Search for patients

The endpoint to fetch all patients by group is

```yaml
GET /fhir/Patient?_has:Group:member:_id=<group-id>
```

You may have a lot of questions to this request.

* what does mean `_has:Group:member:_id` and
* where do we know group id if we don't have access to Group resource?

#### What does mean `_has:Group:member:_id`?

The `_has` parameter is a one of standard search parameters in FHIR, called [reverse chaining](https://www.hl7.org/fhir/search.html#has). FHIR specification says:

> The `_has` parameter provides limited support for reverse chaining - that is, selecting resources based on the properties of resources that refer to them...

The `_has` parameter always goes with [modifiers](https://www.hl7.org/fhir/search.html#modifiers), which specify the search parameter. Let's get back and read the request we have.

```yaml
GET /fhir/Patient?_has:Group:member:_id=<group-id>
```

This requests the server to return Patient resources, where the patient resource is referred to by at least one Group with id \<group-id>, and where the Group refers to the patient resource in the member search parameter.

#### Where do we know group id, if we don't have access to Group resource?

Technically we don't need to have access to Group resource, we need only to know group id. And group id is available from ResearchStudy resource, we already have access to.

Thus, we may conclude the request is suitable for our needs. the AccessPolicy should check existence of ResearchStudy with that \<group-id> and user-id in collaborators.

```yaml
PUT /fhir/AccessPolicy/user-can-access-patient-related-research-study-group
Content-Type: text/yaml
Accept: text/yaml

resourceType: AccessPolicy
engine: complex
and:
- engine: matcho
  matcho:
    request-method: get
    uri: /fhir/Patient
    params:
      '_has:Group:member:_id': present?
      _include: nil?
      _revinclude: nil?
      _with: nil?
    user:
      id: present?
- engine: sql
  sql:
    query: |
      SELECT true
      FROM "researchstudy"
      WHERE "researchstudy".resource @>
      jsonb_build_object('extension', jsonb_build_array(jsonb_build_object('url', 'http://example.org/fhir/StructureDefinition/collaborator', 'value', jsonb_build_object('Reference', jsonb_build_object('id', {{user.id}}::text)))))
      AND "researchstudy".resource @> jsonb_build_object('enrollment', jsonb_build_array(jsonb_build_object('id', {{params._has:Group:member:_id}}::text)))
      limit 1
```

Let's check it.

{% tabs %}
{% tab title="Jane searches for patients from smoking research" %}
```yaml
GET /fhir/Patient?_has:Group:member:_id=group-1
Authorization: Bearer janes-access-token

# 200 OK
```
{% endtab %}

{% tab title="Jane searches for patients from diet research" %}
```yaml
GET /fhir/Patient?_has:Group:member:_id=group-2
Authorization: Bearer janes-access-token

# 403 Forbidden
```
{% endtab %}

{% tab title="Jane searches for all patients" %}
```yaml
GET /fhir/Patient
Authorization: Bearer janes-access-token

# 403 Forbidden
```
{% endtab %}

{% tab title="Oscar searches for patients from diet research" %}
```yaml
GET /fhir/Patient?_has:Group:member:_id=group-2
Authorization: Bearer oscars-access-token

# 200 OK
```
{% endtab %}
{% endtabs %}

Search for patient endpoint is secured. The only one is left.

### Search for observations

The endpoint to fetch all observation by group is

```yaml
GET /fhir/Observation?group=<group-id>
```

There is no group search parameter for Observation in FHIR. And there is no way to define our parameter with SearchParameter resource.

To enable complex search parameters, Aidbox provides [Search](../../api/rest-api/aidbox-search.md) resource. We will specify one for search Observations by group:

```yaml
PUT /fhir/Search/Observation.group
Content-Type: text/yaml
Accept: text/yaml

resourceType: Search
name: group
resource: {reference: Entity/Observation}
where: '{{table}}.resource#>>''{subject,id}'' in (select member#>>''{entity,id}'' from "group", jsonb_array_elements(resource#>''{member}'') member where id = {{param}})'
```

{% hint style="info" %}
**Chained-search & \_has search parameter in FHIR R5**

FHIR R5 is going to introduce chained-search support for [\_has parameter](https://build.fhir.org/search.html#has). So, our request would look like the following

```yaml
GET /fhir/Observation?patient._has:Group:member:_id=<group-id>
```

Aidbox is going to support it, once FHIR R5 is released.
{% endhint %}

The AccessPolicy will be very similar to previous one, we made for Patient search.

```yaml
PUT /fhir/AccessPolicy/user-can-access-observation-related-research-study-group
Content-Type: text/yaml
Accept: text/yaml

resourceType: AccessPolicy
engine: complex
and:
- engine: matcho
  matcho:
    request-method: get
    uri: /fhir/Observation
    params:
      group: present?
      _include: nil?
      _revinclude: nil?
      _with: nil?
    user:
      id: present?
- engine: sql
  sql:
    query: |
      SELECT true
      FROM "researchstudy"
      WHERE "researchstudy".resource @>
      jsonb_build_object('extension', jsonb_build_array(jsonb_build_object('url', 'http://example.org/fhir/StructureDefinition/collaborator', 'value', jsonb_build_object('Reference', jsonb_build_object('id', {{user.id}}::text)))))
      AND "researchstudy".resource @> jsonb_build_object('enrollment', jsonb_build_array(jsonb_build_object('id', {{params.group}}::text)))
      limit 1
```

Let's check it.

{% tabs %}
{% tab title="Jane searches for observations from smoking research" %}
```yaml
GET /fhir/Observation?group=group-1
Authorization: Bearer janes-access-token

# 200 OK
```
{% endtab %}

{% tab title="Jane searches for observations from diet research" %}
```yaml
GET /fhir/Observation?group=group-2
Authorization: Bearer janes-access-token

# 403 Forbidden
```
{% endtab %}

{% tab title="Jane searches for all observations" %}
```yaml
GET /fhir/Observation
Authorization: Bearer janes-access-token

# 403 Forbidden
```
{% endtab %}

{% tab title="Oscar searches for observations from diet research" %}
```yaml
GET /fhir/Observation?group=group-2
Authorization: Bearer oscars-access-token

# 200 OK
```
{% endtab %}
{% endtabs %}

Search for observation endpoint is secured for now. All endpoints are secured.

## That's it

Let's recap, what we have done. There was a security policy, which stated:

> _User has access to all studies they collaborate on and to all patient records within those studies._

And we met this requirement using ReBAC authorization model. In order to achieve this we

* defined domain model resources, UI pages and FHIR endpoints for our application,
* and we developed access policies in Aidbox to secured the endpoints.

### What's next

Writing access policies may be tricky some time, Aidbox has tooling to [debug AccessPolicy](debug-access-control.md).
