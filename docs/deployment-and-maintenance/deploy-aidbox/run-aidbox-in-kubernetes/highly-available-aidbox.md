---
description: Configure highly available Aidbox on Kubernetes with multiple replicas, RSA keypair sharing, liveness probes, and pod topology constraints.
---

# Highly Available Aidbox

{% hint style="info" %}
Run parallel Aidbox replicas supported from **2208** version
{% endhint %}

{% hint style="warning" %}
**License `max-instances`** — every replica counts as one Aidbox instance against your license. Set `max-instances` on [aidbox.app](https://aidbox.app) to at least the number of replicas you run, or you will see a [concurrent instances warning](../../../overview/licensing-and-support.md#concurrent-instances-warning) on every API response (the warning is informational and does not block operations). Read-only PostgreSQL replicas do not count.
{% endhint %}

### Concept

To provide increased High availability, the approach is to run two or more application instances. All incoming traffic is balanced between all running Aidbox instances. In case of failure of one of the instances, the network layer stops receiving incoming traffic to failed instance and distributes it to other available instances. The task of the orchestration system is to detect failure of one of the instances and restart it.

{% hint style="warning" %}
Attention: by default Aidbox generates both keypair and secret on every startup. This means that on every start all previously generated JWT will be invalid. In order to avoid such undesirable situation, you may pass RSA keypair and secret as Aidbox parameters.

It is required to pass RSA keypair and secret as Aidbox parameters if you have multiple replicas of the same Aidbox/Multibox instance. Check out this section in the docs on how to configure it properly:

[Set up RSA private/public keys and secret](../../../reference/all-settings.md#security.auth.keys.public "mention")
{% endhint %}

### Configuration

Let's take the Kubernetes example of a high availability Aidbox configuration (this example can also be applied to Multibox)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aidbox
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      service: aidbox
  template:
    metadata:
      labels:
        service: aidbox
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            service: aidbox
      containers:
        - name: main
          image: healthsamurai/aidboxone:latest
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
              protocol: TCP
          envFrom:
            - configMapRef:
                name: aidbox
            - secretRef:
                name: aidbox
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
              scheme: HTTP
            initialDelaySeconds: 20
            timeoutSeconds: 5
            periodSeconds:  5
            successThreshold: 1
            failureThreshold: 4
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
              scheme: HTTP
            initialDelaySeconds: 20
            timeoutSeconds: 5
            periodSeconds: 5
            successThreshold: 1
            failureThreshold: 2
```

#### Replicas

First of all you should specify how many replicas you need

```yaml
...
  spec:
    replicas: 2
...
```

#### Readiness probe

Readiness probe - indicates that applications running and ready to receive traffic.

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
    scheme: HTTP
  initialDelaySeconds: 20
  timeoutSeconds: 5
  periodSeconds:  5
  successThreshold: 1
  failureThreshold: 2
```

#### Liveness probe

Liveness probe - indicates whether the container is running. If the liveness probe fails, the kubelet kills the container, and the container is subjected to its restart policy.

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  scheme: HTTP
  initialDelaySeconds: 20
  timeoutSeconds: 5
  periodSeconds:  5
  successThreshold: 1
  failureThreshold: 4
```

#### Startup probe

Startup probe - provide a way to defer the execution of liveness and readiness probes until a container indicates it’s able to handle them. Kubernetes won’t direct the other probe types to a container if it has a startup probe that hasn’t yet succeeded..

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8080
  scheme: HTTP
  initialDelaySeconds: 20
  timeoutSeconds: 5
  periodSeconds:  5
  successThreshold: 1
  failureThreshold: 4

```

#### Pod topology

To improve fault tolerance in case of failure of one or more availability zones, you must specify — [Pod Topology Spread Constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: ScheduleAnyway
  labelSelector:
    matchLabels:
      service: aidbox
```

### Cache replication

Aidbox keeps a number of in-memory caches per replica — most importantly the [`AidboxTopicDestination`](../../../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md) **sender** registry, the FAR validator cache, and route / token / secret caches. When one replica creates, updates, or deletes an entity that lives in those caches, every other replica needs to refresh its own copy.

Aidbox synchronizes the caches by publishing PostgreSQL `LISTEN` / `NOTIFY` messages on the `cache_replication_msgs` channel. Each replica subscribes to the channel at startup and applies the changes locally. No additional infrastructure (Redis, message broker, etc.) is required.

You can disable the mechanism with [`BOX_CACHE_REPLICATION_DISABLE`](../../../reference/all-settings.md) — only do that on single-replica deployments.

### `AidboxTopicDestination` in multi-replica deployments

Each replica owns an in-memory **sender** for every `AidboxTopicDestination` (the Kafka producer, webhook client, GCP Pub/Sub session, etc. that actually pushes events). Senders are created via the cache replication channel above:

* When a destination is **created** on replica A, replica A initializes its sender during the same transaction and publishes a notification. Other replicas receive the notification after the transaction commits and initialize their own senders.
* When a destination is **deleted**, the same flow shuts down senders on every replica.
* `$status` counters (`messagesDelivered`, `messageBatchesDelivered`, …) are **per-replica** and held in memory — see [Counter semantics](../../../tutorials/subscriptions-tutorials/webhook-aidboxtopicdestination.md#counter-semantics). Different `$status` numbers from two replicas for the same destination are expected, not a bug.

#### `AidboxTopicDestination has no sender associated with it`

If `$status` (or an event publish) returns this error on some replicas while working on the replica that created the destination, the local sender failed to initialize.

* On Aidbox **2603 and later** the cache notification is published on the same DB connection as the destination create / update / delete, so other replicas only see the change once the transaction commits. Sub-second propagation is normal.
* On Aidbox **before 2603** there is a known race where `pg_notify` could fire before the transaction committed, so other replicas missed the change permanently. Fixed in commit `71dded75`. **Upgrade to 2603+** if you hit this on an older build.
* As an immediate workaround, restart all replicas — each one rebuilds the sender registry from the database on startup.

For other init-time failures (malformed `fhirPathCriteria`, unreachable broker, etc.) the symptom is identical but the fix is different. Walk through the [`No sender associated` troubleshooting table](../../../tutorials/subscriptions-tutorials/webhook-aidboxtopicdestination.md#internal-server-error-aidboxtopicdestination-has-no-sender-associated-with-it) — it covers FHIRPath compile errors, missing `AidboxSubscriptionTopic`, and the multi-replica race together.

#### Reachability of external systems

Each replica establishes its own connection to the destination's external system (Kafka broker, webhook endpoint, GCP project, etc.) at sender-init time. A connectivity issue on one replica — wrong DNS, missing network policy, expired credentials mounted only in some pods — produces the same `no sender associated` error on that replica only.

Validate from inside each pod (for example `kubectl exec`) before assuming the destination is misconfigured:

* For [`kafka-at-least-once`](../../../tutorials/subscriptions-tutorials/kafka-aidboxtopicdestination.md): the Kafka producer must connect to `bootstrapServers` and authenticate with the configured SASL mechanism. A failed producer init prevents the sender from registering.
* For `webhook-at-least-once`: the [proxy / SSL configuration](../../../tutorials/other-tutorials/how-to-configure-aidbox-to-use-proxy.md) must be present in every replica's `JAVA_OPTS`.
* For GCP / AWS destinations: workload identity, service account secrets, and IAM bindings must be applied to every pod, not just one.
