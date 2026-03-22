---
description: Custom SDC operations supported by Aidbox Forms.
---

# Aidbox SDC API

* [$generate-link](aidbox-sdc-api.md#generate-a-link-to-a-questionnaireresponse-generate-link)
* [$save](aidbox-sdc-api.md#save-a-questionnaireresponse-save)
* [$submit](aidbox-sdc-api.md#submit-a-questionnaireresponse-submit)
* [$notify-patient](aidbox-sdc-api.md#notify-a-patient-notify-patient)
* [$send](aidbox-sdc-api.md#send-a-questionnaire-to-a-patient-send)
* [$stop-notification](aidbox-sdc-api.md#stop-notification-stop-notification)

## Generate a link to a QuestionnaireResponse - $generate-link

This operation generates a link to a web page to be used to continue answering a specified [QuestionnaireResponse](https://hl7.org/fhir/R4/questionnaireresponse.html).

### URLs

```
POST [base]/QuestionnaireResponse/[id]/$generate-link
```

### Parameters

{% hint style="warning" %}
NOTE: All parameters wrapped with `Parameters object`

```yaml
resourceType: Parameters
parameter:
- name:  [var-name]
  value: [var-value]
```
{% endhint %}

| Parameter                                                  | Cardinality | Type                                                                                                                                         |
| ---------------------------------------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| [allow-amend](aidbox-sdc-api.md#allow-amend)               | 0..1        | [Boolean](http://hl7.org/fhir/R4/datatypes.html#boolean)                                                                                     |
| [allow-repopulate](aidbox-sdc-api.md#allow-repopulate)     | 0..1        | [Boolean](http://hl7.org/fhir/R4/datatypes.html#boolean)                                                                                     |
| [redirect-on-submit](aidbox-sdc-api.md#redirect-on-submit) | 0..1        | [String](http://hl7.org/fhir/R4/datatypes.html#string)                                                                                       |
| [redirect-on-save](aidbox-sdc-api.md#redirect-on-save)     | 0..1        | [String](http://hl7.org/fhir/R4/datatypes.html#string)                                                                                       |
| [expiration](aidbox-sdc-api.md#expiration)                 | 0..1        | [Integer](http://hl7.org/fhir/R4/datatypes.html#integer)                                                                                     |
| [theme](aidbox-sdc-api.md#theme)                           | 0..1        | [String](http://hl7.org/fhir/R4/datatypes.html#string)                                                                                       |
| [read-only](aidbox-sdc-api.md#read-only)                   | 0..1        | [Boolean](http://hl7.org/fhir/R4/datatypes.html#boolean)                                                                                     |
| [app-name](aidbox-sdc-api.md#read-only)                    | 0..1        | [String](http://hl7.org/fhir/R4/datatypes.html#string)                                                                                       |
| source                                                     |             | [Reference\<Device, Organization, Patient, Practitioner, PractitionerRole, RelatedPerson>](http://hl7.org/fhir/R4/references.html#Reference) |
| partOf                                                     |             | [Reference\<Observation, Procedure>](http://hl7.org/fhir/R4/references.html#Reference)                                                       |
| author                                                     |             | [Reference\<Device, Practitioner, PractitionerRole, Patient, RelatedPerson, Organization>](http://hl7.org/fhir/R4/references.html#Reference) |
| basedOn                                                    |             | [Reference\<CarePlan, ServiceRequest>](http://hl7.org/fhir/R4/references.html#Reference)                                                     |

#### allow-amend

Whether the generated link will allow amending and re-submitting the form.

```
name: allow-amend
value:
  Boolean: true
```

#### allow-repopulate

Whether the generated link will allow re-populating the form.

NOTE: Repopulate will be working only with forms that contain populate behavior

```
name: allow-repopulate
value:
  Boolean: true
```

#### redirect-on-submit

A URL where the user will be redirected to after successfully submitting the form.

```yaml
name: redirect-on-submit
value:
  String: https://example.com/submit-hook?questionnaire=123
```

#### redirect-on-save

A URL where the user will be redirected to after hitting Save button.

> By default `Save button is not visible` - form autosaved after every keystroke. But sometimes it's usefull to close form in a partially-filled state

```yaml
name: redirect-on-save
value:
  String: https://example.com/submit-hook?questionnaire=123
```

#### expiration

Link expiration period (days)

```yaml
name: expiration
value:
  Integer: 30
```

> By default thir parameter = 7 days

#### theme

Form theme.

```yaml
name: theme
value:
  String: hs-theme
```

#### read-only

Show form in a **read-only** mode

```yaml
name: read-only
value:
  Boolean: true
```

**app-name**

Application name that will be used in Audit logging when returned link was used.

> Audit logging should be enabled.

```yaml
- name: app-name
  value
    String: my-app
```

### Usage Example

{% tabs %}
{% tab title="Request" %}
```http
POST [base]/QuestionnaireResponse/[id]/$generate-link
content-type: text/yaml

resourceType: Parameters
parameter:
  - name: allow-amend
    value:
      Boolean: true
  - name: redirect-on-submit
    value:
      String: https://example.com/submit-hook?questionnaire=123
```
{% endtab %}

{% tab title="Success Response" %}
HTTP status: 200

```yaml
link: http://forms.aidbox.io/ui/sdc#/questionnaire-response/12c1178c-70a9-4e02-a53d-65b13373926e?token=eyJhbGciOiJIUzI
```
{% endtab %}

{% tab title="Failure Response" %}
HTTP status: 422

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: Parameters are invalid
issue:
- severity: error
  code: invalid
  expression:
  - parameter.0.resource
  diagnostics: unknown key :resource

```
{% endtab %}
{% endtabs %}

> Aidbox uses HS256 to sign JWT token by default. To use RS256 you need to set
>
> `BOX_SECURITY_AUTH_KEYS_PRIVATE` and `BOX_SECURITY_AUTH_KEYS_PUBLIC` environment variables.
>
> [See settings](https://docs.aidbox.app/reference/settings/security-and-access-control#security.auth.keys.public)

## Save a QuestionnaireResponse - $save

This operation validates the structure of a QuestionnaireResponse and saves it. It performs basic structural validation, but does not validate against the associated Questionnaire definition.

The operation validates only FHIR structure of QuestionnaireResponse and have associated Questionnaire. Operation doesn't validate for example — required fields like $submit operation

### URLs

```
POST [base]/fhir/QuestionnaireResponse/$save
```

### Parameters

{% hint style="warning" %}
NOTE: All parameters wrapped with `Parameters object`

```yaml
resourceType: Parameters
parameter:
- name: response
  resource:
    # QuestionnaireResponse resource here
```
{% endhint %}

The operation takes a single input parameter named "response" containing a QuestionnaireResponse resource wrapped in a Parameters resource.

### Output Parameters

The operation returns:

* **response**: The saved QuestionnaireResponse resource
* **issues**: Any validation issues encountered (if applicable)

### Usage Example

{% tabs %}
{% tab title="Request" %}
```http
POST [base]/fhir/QuestionnaireResponse/$save
content-type: text/yaml

resourceType: Parameters
parameter:
- name: response
  resource:
    resourceType: QuestionnaireResponse
    questionnaire: Questionnaire/patient-registration
    status: in-progress
    item:
    - linkId: name
      text: Patient Name
      item:
      - linkId: name.given
        text: Given Name
        answer:
        - valueString: John
      - linkId: name.family
        text: Family Name
        answer:
        - valueString: Smith
```
{% endtab %}

{% tab title="Success Response" %}
HTTP status: 200

```yml
resourceType: Parameters
parameter:
- name: response
  resource:
    resourceType: QuestionnaireResponse
    id: 12c1178c-70a9-4e02-a53d-65b13373926e
    questionnaire: Questionnaire/patient-registration
    status: in-progress
    item:
    - linkId: name
      text: Patient Name
      item:
      - linkId: name.given
        text: Given Name
        answer:
        - valueString: John
      - linkId: name.family
        text: Family Name
        answer:
        - valueString: Smith
```
{% endtab %}

{% tab title="Validation Failure Response" %}
HTTP status: 422

```yml
resourceType: Parameters
parameter:
- name: issue
  resource:
    resourceType: OperationOutcome
    issue:
    - severity: fatal
      code: invalid
      expression:
      - QuestionnaireResponse.item[0].item[1].answer[0].valueDecimal
      details:
        coding:
        - system: http://aidbox.app/CodeSystem/operation-outcome-type
          code: invalid-type
        - system: http://aidbox.app/CodeSystem/schema-id
          code: QuestionnaireResponse
      diagnostics: Invalid type for the field. Expected 'string', but got 'decimal'

```
{% endtab %}
{% endtabs %}

## Submit a QuestionnaireResponse - $submit

This operation validates and submits a QuestionnaireResponse, marking it as "completed" or "amended". It performs comprehensive validation against the associated Questionnaire definition. If validation fails, it returns only the "issues" parameter without the "response" parameter and does not save the QuestionnaireResponse.

### URLs

```
POST [base]/fhir/QuestionnaireResponse/$submit
```

### Parameters

{% hint style="warning" %}
NOTE: All parameters wrapped with `Parameters object`

```yml
resourceType: Parameters
parameter:
- name: response
  resource:
    # QuestionnaireResponse resource here
```
{% endhint %}

The operation takes a single input parameter named "response" containing a QuestionnaireResponse resource wrapped in a Parameters resource.

### Output Parameters

The operation returns:

* **response**: The submitted QuestionnaireResponse resource with status updated to "completed"
* **issues**: Any validation issues encountered (if applicable)

### Usage Example

{% tabs %}
{% tab title="Request" %}
```http
POST [base]/fhir/QuestionnaireResponse/$submit
content-type: text/yaml

resourceType: Parameters
parameter:
- name: response
  resource:
    resourceType: QuestionnaireResponse
    questionnaire: Questionnaire/patient-registration
    status: in-progress
    item:
    - linkId: name
      text: Patient Name
      item:
      - linkId: name.given
        text: Given Name
        answer:
        - valueString: John
      - linkId: name.family
        text: Family Name
        answer:
        - valueString: Smith
    - linkId: birthDate
      text: Date of Birth
      answer:
      - valueDate: '1970-01-01'
    - linkId: gender
      text: Gender
      answer:
      - valueCoding:
          system: http://hl7.org/fhir/administrative-gender
          code: male
          display: Male
```
{% endtab %}

{% tab title="Success Response" %}
HTTP status: 200

```yml
resourceType: Parameters
parameter:
- name: response
  resource:
    resourceType: QuestionnaireResponse
    id: 12c1178c-70a9-4e02-a53d-65b13373926e
    questionnaire: Questionnaire/patient-registration
    status: completed
    item:
    - linkId: name
      text: Patient Name
      item:
      - linkId: name.given
        text: Given Name
        answer:
        - valueString: John
      - linkId: name.family
        text: Family Name
        answer:
        - valueString: Smith
    - linkId: birthDate
      text: Date of Birth
      answer:
      - valueDate: '1970-01-01'
    - linkId: gender
      text: Gender
      answer:
      - valueCoding:
          system: http://hl7.org/fhir/administrative-gender
          code: male
          display: Male
```
{% endtab %}

{% tab title="Validation Failure Response" %}
HTTP status: 422

```yml
resourceType: Parameters
parameter:
- name: issues
  resource:
    resourceType: OperationOutcome
    issue:
    - severity: error
      code: required
      expression:
      - QuestionnaireResponse.item[3]
      diagnostics: 'Missing required field: Contact Information'
```
{% endtab %}
{% endtabs %}


## Notify a Patient - $notify-patient

This is an asynchronous operation that sends an email notification to a patient with a generated form link for an existing QuestionnaireResponse. It supports scheduled sending, follow-up reminders, form expiration, and clinician notifications on completion or expiration.

The operation returns immediately with HTTP 202.

### URLs

```
POST [base]/fhir/QuestionnaireResponse/$notify-patient
```

### Parameters

{% hint style="warning" %}
NOTE: All parameters wrapped with `Parameters` object

```yaml
resourceType: Parameters
parameter:
- name: provider
  valueString: sendgrid-provider # required. One of: smtp-provider, postmark-provider, mailgun-provider, sendgrid-provider
- name: response
  valueReference:
    reference: QuestionnaireResponse/qr-1 # required
- name: email
  valueString: patient@example.com # required
- name: email-subject
  valueString: "Please complete this form" # optional
- name: email-message
  valueString: "Hi {{patient.firstName}}, please complete the {{form.title}} form." # optional, mustache
- name: clinician-email
  valueString: doctor@example.com # optional
- name: send-at
  valueString: "2026-03-25T14:00:00Z" # optional, ISO 8601
- name: config
  part:
  - name: deadline-days
    valueInteger: 7 # optional, default: 7
  - name: follow-up-enabled
    valueBoolean: true # optional, default: false
  - name: follow-up-delay-days
    valueInteger: 3 # optional, default: 3
  - name: follow-up-time
    valueString: "10:00" # optional, HH:mm UTC, default: 10:00
  - name: follow-up-message
    valueString: "Reminder: please complete the form" # optional, mustache
```
{% endhint %}

The operation takes:

* **provider** (required): Email provider name. Must be one of `smtp-provider`, `postmark-provider`, `mailgun-provider`, `sendgrid-provider`.
* **response** (required): QuestionnaireResponse reference.
* **email** (required): Recipient email address.
* **email-subject** (optional): Custom email subject line. If not provided, the default subject like `"Please complete this form"` is used.
* **email-message** (optional): Custom email body message. Supports mustache templates with `{{patient.firstName}}`, `{{patient.lastName}}`, `{{form.title}}`, `{{form.link}}`. If not provided, a default message is used.
* **clinician-email** (optional): Practitioner email to notify when the patient completes or misses the form.
* **send-at** (optional): ISO 8601 datetime for scheduled sending. If not provided, the email is sent immediately.
* **config** (optional): Configuration:
  * **deadline-days** (optional, default `7`): Number of days before the form link expires.
  * **follow-up-enabled** (optional, default `false`): Enable follow-up reminder emails.
  * **follow-up-delay-days** (optional, default `3`): Days after initial send to send the reminder.
  * **follow-up-time** (optional, default `"10:00"`): Time of day (HH:mm, UTC) to send the reminder.
  * **follow-up-message** (optional): Custom reminder message. Supports the same mustache templates as `email-message`.

### Output

**Success Response** — HTTP 202 Accepted

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: "Workflow accepted"
issue:
- severity: information
  code: informational
  diagnostics: "Workflow accepted"
```

**Validation Error** — HTTP 422

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: "'provider' is required and should be one of: smtp-provider, postmark-provider, mailgun-provider, sendgrid-provider"
issue:
- severity: fatal
  code: invalid
  diagnostics: "'provider' is required and should be one of: smtp-provider, postmark-provider, mailgun-provider, sendgrid-provider"
```

### Usage Example

{% tabs %}
{% tab title="Request" %}
```yaml
POST [base]/fhir/QuestionnaireResponse/$notify-patient
content-type: text/yaml

resourceType: Parameters
parameter:
- name: provider
  valueString: sendgrid-provider
- name: response
  valueReference:
    reference: QuestionnaireResponse/qr-1
- name: email
  valueString: patient@example.com
- name: clinician-email
  valueString: doctor@clinic.com
- name: config
  part:
  - name: deadline-days
    valueInteger: 7
```
{% endtab %}

{% tab title="Success Response" %}
HTTP status: 202

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: "Workflow accepted"
issue:
- severity: information
  code: informational
  diagnostics: "Workflow accepted"
```
{% endtab %}

{% tab title="Failure Response" %}
HTTP status: 422

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: "'provider' is required and should be one of: smtp-provider, postmark-provider, mailgun-provider, sendgrid-provider"
issue:
- severity: fatal
  code: invalid
  diagnostics: "'provider' is required and should be one of: smtp-provider, postmark-provider, mailgun-provider, sendgrid-provider"
```
{% endtab %}
{% endtabs %}

## Send a Questionnaire to a Patient - $send

This is an asynchronous operation that populates a QuestionnaireResponse from a Questionnaire, generates a form link, and sends it to the patient via email. It supports scheduled sending, follow-up reminders, form expiration, and clinician notifications on completion or expiration.

This is the same as [`$notify-patient`](aidbox-sdc-api.md#notify-a-patient-notify-patient), but called at the Questionnaire level.

The operation returns immediately with HTTP 202.

### URLs

```
POST [base]/fhir/Questionnaire/$send
```

### Parameters

{% hint style="warning" %}
NOTE: All parameters wrapped with `Parameters` object

```yaml
resourceType: Parameters
parameter:
- name: provider
  valueString: sendgrid-provider # required. One of: smtp-provider, postmark-provider, mailgun-provider, sendgrid-provider
- name: questionnaire
  valueReference:
    reference: Questionnaire/intake-form # required
- name: email
  valueString: patient@example.com # required
- name: subject
  valueReference:
    reference: Patient/pt-1 # optional
- name: encounter
  valueReference:
    reference: Encounter/enc-1 # optional
- name: email-subject
  valueString: "Please complete this form" # optional
- name: email-message
  valueString: "Hi {{patient.firstName}}, please complete the {{form.title}} form." # optional, mustache
- name: clinician-email
  valueString: doctor@example.com # optional
- name: send-at
  valueString: "2026-03-25T14:00:00Z" # optional, ISO 8601
- name: config
  part:
  - name: deadline-days
    valueInteger: 7 # optional, default: 7
  - name: follow-up-enabled
    valueBoolean: true # optional, default: false
  - name: follow-up-delay-days
    valueInteger: 3 # optional, default: 3
  - name: follow-up-time
    valueString: "10:00" # optional, HH:mm UTC, default: 10:00
  - name: follow-up-message
    valueString: "Reminder: please complete the form" # optional, mustache
```
{% endhint %}

The operation takes:

* **provider** (required): Email provider name. Must be one of `smtp-provider`, `postmark-provider`, `mailgun-provider`, `sendgrid-provider`.
* **questionnaire** (required): Questionnaire reference. The operation will populate a new QuestionnaireResponse from it.
* **email** (required): Recipient email address.
* **subject** (optional): Patient reference. Used for populating the QuestionnaireResponse and personalizing the email template (e.g. `{{patient.firstName}}`).
* **encounter** (optional): Encounter reference. Passed to `$populate` for context.
* **email-subject** (optional): Custom email subject line. If not provided, the default subject `"Please complete this form"` is used.
* **email-message** (optional): Custom email body message. Supports mustache templates with `{{patient.firstName}}`, `{{patient.lastName}}`, `{{form.title}}`, `{{form.link}}`. If not provided, a default message is used.
* **clinician-email** (optional): Practitioner email to notify when the patient completes or misses the form.
* **send-at** (optional): ISO 8601 datetime for scheduled sending. If not provided, the email is sent immediately after population.
* **config** (optional): Configuration:
  * **deadline-days** (optional, default `7`): Number of days before the form link expires.
  * **follow-up-enabled** (optional, default `false`): Enable follow-up reminder emails.
  * **follow-up-delay-days** (optional, default `3`): Days after initial send to send the reminder.
  * **follow-up-time** (optional, default `"10:00"`): Time of day (HH:mm, UTC) to send the reminder.
  * **follow-up-message** (optional): Custom reminder message. Supports the same mustache templates as `email-message`.

### Steps

The operation performs the following steps:

1. **populate-form** — Calls `Questionnaire/$populate` to create a QuestionnaireResponse.
2. **send-form** — Generates a shared link and sends the email. If `send-at` is provided, the email is scheduled for later.
3. **check-completed** — Periodically checks if the patient completed the form. If a follow-up is configured and the form is not yet completed, proceeds to `send-reminder`. If the deadline expires, proceeds to `notify-failure`.
4. **send-reminder** — Sends a follow-up reminder email and returns to `check-completed`.
5. **notify-success** — Notifies the clinician (if `clinician-email` is provided) that the form was completed.
6. **notify-failure** — Notifies the clinician (if `clinician-email` is provided) that the form expired without completion.

### Output

**Success Response** — HTTP 202 Accepted

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: "Workflow accepted"
issue:
- severity: information
  code: informational
  diagnostics: "Workflow accepted"
```

**Validation Error** — HTTP 422

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: "'provider' is required and should be one of: smtp-provider, postmark-provider, mailgun-provider, sendgrid-provider"
issue:
- severity: fatal
  code: invalid
  diagnostics: "'provider' is required and should be one of: smtp-provider, postmark-provider, mailgun-provider, sendgrid-provider"
```

### Usage Example

{% tabs %}
{% tab title="Request" %}
```yaml
POST [base]/fhir/Questionnaire/$send
content-type: text/yaml

resourceType: Parameters
parameter:
- name: provider
  valueString: sendgrid-provider
- name: questionnaire
  valueReference:
    reference: Questionnaire/intake-form
- name: email
  valueString: patient@example.com
- name: subject
  valueReference:
    reference: Patient/pt-1
- name: email-subject
  valueString: "Please complete the intake form"
- name: email-message
  valueString: "Hi {{patient.firstName}}, please fill out your intake form before the visit."
- name: clinician-email
  valueString: doctor@clinic.com
- name: config
  part:
  - name: deadline-days
    valueInteger: 14
  - name: follow-up-enabled
    valueBoolean: true
  - name: follow-up-delay-days
    valueInteger: 3
  - name: follow-up-time
    valueString: "09:00"
```
{% endtab %}

{% tab title="Success Response" %}
HTTP status: 202

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: "Workflow accepted"
issue:
- severity: information
  code: informational
  diagnostics: "Workflow accepted"
```
{% endtab %}

{% tab title="Failure Response" %}
HTTP status: 422

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: "'provider' is required and should be one of: smtp-provider, postmark-provider, mailgun-provider, sendgrid-provider"
issue:
- severity: fatal
  code: invalid
  diagnostics: "'provider' is required and should be one of: smtp-provider, postmark-provider, mailgun-provider, sendgrid-provider"
```
{% endtab %}
{% endtabs %}

## Stop Notification - $stop-notification

This operation cancels all in-progress notifications associated with a given QuestionnaireResponse. It stops pending email sends, follow-up reminders, and completion checks.

### URLs

```
POST [base]/fhir/QuestionnaireResponse/{id}/$stop-notification
```

### Parameters

This operation takes no body parameters. The QuestionnaireResponse ID is provided in the URL path.

### Output

**Success Response** — HTTP 200

Returns the number of cancelled notifications.

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: "Cancelled 1 notification workflow(s)"
issue:
- severity: information
  code: informational
  diagnostics: "Cancelled 1 notification workflow(s)"
```

If no in-progress notifications are found for the given QuestionnaireResponse, the operation still returns 200 with a count of 0.

### Usage Example

{% tabs %}
{% tab title="Request" %}
```yaml
POST [base]/fhir/QuestionnaireResponse/qr-123/$stop-notification
```
{% endtab %}

{% tab title="Response" %}
HTTP status: 200

```yaml
resourceType: OperationOutcome
text:
  status: generated
  div: "Cancelled 1 notification workflow(s)"
issue:
- severity: information
  code: informational
  diagnostics: "Cancelled 1 notification workflow(s)"
```
{% endtab %}
{% endtabs %}
