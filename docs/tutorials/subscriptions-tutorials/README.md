---
description: Learn to configure Aidbox subscriptions with FHIR Subscriptions, Kafka, RabbitMQ, ActiveMQ, ClickHouse, and webhook integrations.
---

# Subscriptions Tutorials

## FHIR topic-based subscriptions

{% cards %}
{% card icon="check" title="FHIR R5 Subscription" href="fhir-subscription-r5.md" %}
Set up FHIR R5 Topic-Based Subscriptions in Aidbox.
{% endcard %}
{% card icon="check" title="FHIR R4B Backport" href="fhir-subscription-r4b-backport.md" %}
Set up FHIR R4B Backport Topic-Based Subscriptions.
{% endcard %}
{% card icon="check" title="FHIR R4 Backport" href="fhir-subscription-r4-backport.md" %}
Set up FHIR R4 Backport Topic-Based Subscriptions.
{% endcard %}
{% endcards %}

## Message brokers and queues

{% cards %}
{% card icon="assets/brand-icons/kafka.svg" title="Kafka" href="kafka-aidboxtopicdestination.md" %}
Stream FHIR resource events to Apache Kafka with best-effort or at-least-once delivery.
{% endcard %}
{% card icon="assets/brand-icons/webhook.svg" title="Webhook" href="webhook-aidboxtopicdestination.md" %}
Send FHIR resource events to HTTP webhooks with retry logic and batch support.
{% endcard %}
{% card icon="assets/brand-icons/pubsub.svg" title="GCP Pub/Sub" href="gcp-pub-sub-aidboxtopicdestination.md" %}
Stream FHIR resource events to Google Cloud Pub/Sub with guaranteed delivery.
{% endcard %}
{% card icon="assets/brand-icons/aws.svg" title="AWS EventBridge" href="aws-eventbridge-aidboxtopicdestination.md" %}
Route FHIR resource events to AWS EventBridge for serverless processing.
{% endcard %}
{% card icon="assets/brand-icons/aws.svg" title="AWS SNS" href="aidboxtopicsubscription-sns-tutorial.md" %}
Stream FHIR resource events to AWS SNS for pub/sub messaging and fan-out notifications.
{% endcard %}
{% card icon="assets/brand-icons/nats.png" title="NATS" href="aidboxtopicsubscription-nats-tutorial.md" %}
Integrate Aidbox topic-based subscriptions with NATS and NATS JetStream.
{% endcard %}
{% card icon="assets/brand-icons/rabbitmq.svg" title="RabbitMQ" href="rabbitmq-tutorial.md" %}
Connect Aidbox subscriptions to RabbitMQ over AMQP for real-time FHIR events.
{% endcard %}
{% card icon="assets/brand-icons/activemq.png" title="ActiveMQ" href="activemq-tutorial.md" %}
Integrate Aidbox subscriptions with ActiveMQ using AMQP 1.0 for event streaming.
{% endcard %}
{% endcards %}

## Analytics destinations

{% cards %}
{% card icon="assets/brand-icons/clickhouse.svg" title="ClickHouse" href="clickhouse-aidboxtopicdestination.md" %}
Export FHIR resources to ClickHouse with SQL-on-FHIR ViewDefinitions for real-time reporting.
{% endcard %}
{% card icon="assets/brand-icons/bigquery.svg" title="BigQuery" href="bigquery-aidboxtopicdestination.md" %}
Export FHIR resources to Google BigQuery with SQL-on-FHIR ViewDefinitions.
{% endcard %}
{% card icon="assets/brand-icons/databricks.svg" title="Data Lakehouse (Databricks)" href="data-lakehouse-aidboxtopicdestination.md" %}
Export FHIR resources to Databricks Unity Catalog managed Delta tables.
{% endcard %}
{% endcards %}

## End-to-end tutorials

{% cards %}
{% card icon="user" title="Subscribe to new Patient resource" href="subscribe-to-new-patient-resource.md" %}
Make Aidbox notify your service when a new Patient resource is created using the Subscription module.
{% endcard %}
{% card icon="hammer" title="QuestionnaireResponse to Kafka" href="tutorial-produce-questionnaireresponse-to-kafka-topic.md" %}
Stream FHIR QuestionnaireResponse data to Apache Kafka using Aidbox Forms and topic subscriptions.
{% endcard %}
{% endcards %}
