---
description: >-
  Configure NGINX, Aidbox, and your client to ingest high-volume FHIR bundles
  without 502 / 503 / 504 errors.
---

# How to load large FHIR bundles via NGINX

## Objectives

* Configure NGINX (vanilla and Kubernetes Ingress) so it does not reject or time out on large [Bundle](../../api/batch-transaction.md) requests.
* Tune Aidbox web and database limits for the same volume.
* Choose the right bundle shape (transaction vs batch, isolation level, size) for sustained loading.
* Diagnose `502` / `503` / `504` errors that appear during data import.

## Before you begin

* Aidbox is reachable behind your NGINX proxy (or NGINX Ingress on Kubernetes).
* You can edit the proxy configuration and Aidbox environment variables.
* Your client can send `POST /fhir` with arbitrary headers.

## Why two layers

When you `POST` a bundle through NGINX, two independent layers each enforce their own limits:

| Layer | What it checks | Default |
| --- | --- | --- |
| NGINX | Request body size, connect / send / read timeouts | `client_max_body_size 1m`, `proxy_*_timeout 60s` |
| Aidbox | [`BOX_WEB_MAX_BODY`](../../reference/all-settings.md#web.max-body), web threads, DB pool | `20 MB`, `8` threads, pool of `16` |

A `1 MB` request body and a `60 s` upstream timeout are not enough for FHIR data loading — NGINX rejects the bundle (`413` from NGINX, surfaced as `502` to some clients) or kills the connection while Aidbox is still processing it (`504`). Aidbox itself handles 500-resource bundles and concurrent loads correctly when NGINX is out of the path.

## Step 1. Configure NGINX

Set the body limit at least as high as `BOX_WEB_MAX_BODY` (Aidbox returns `413` if the body exceeds its own limit anyway), and raise the upstream timeouts to cover your largest transaction.

{% tabs %}
{% tab title="nginx.conf" %}
```nginx
server {
    listen 443 ssl;
    server_name aidbox.example.com;

    # Must be >= BOX_WEB_MAX_BODY. Default is 1m, which rejects almost any FHIR bundle.
    client_max_body_size 100m;

    location / {
        proxy_pass http://aidbox:8080;

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Default for all four is 60s. Raise to cover the slowest bundle.
        proxy_connect_timeout 300s;
        proxy_send_timeout    300s;
        proxy_read_timeout    300s;
        send_timeout          300s;
    }
}
```
{% endtab %}
{% tab title="Kubernetes Ingress" %}
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aidbox
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size:       "100m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout:    "300"
    nginx.ingress.kubernetes.io/proxy-read-timeout:    "300"
spec:
  rules:
    - host: aidbox.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: aidbox
                port:
                  number: 8080
```
{% endtab %}
{% endtabs %}

{% hint style="info" %}
Pick `100m` / `300s` as a starting point and adjust to your traffic. Setting the timeout much higher than your slowest transaction only delays failure detection.
{% endhint %}

## Step 2. Tune Aidbox

Defaults are conservative. For sustained bundle loading raise the body limit, web threads, and database pool together — the [tuning guidance](../../configuration/configure-aidbox-and-multibox.md) is `BOX_WEB_THREAD = 2 × CPU` and `BOX_DB_POOL_MAXIMUM_POOL_SIZE = 2 × BOX_WEB_THREAD`.

```bash
BOX_WEB_MAX_BODY=104857600          # 100 MB (default 20 MB)
BOX_WEB_THREAD=16                   # default 8
BOX_DB_POOL_MAXIMUM_POOL_SIZE=32    # default 16
```

| Setting | Default | Why raise it |
| --- | --- | --- |
| [`BOX_WEB_MAX_BODY`](../../reference/all-settings.md#web.max-body) | `20 MB` | Aidbox rejects the request with `413` if exceeded — must match or stay below NGINX `client_max_body_size`. |
| [`BOX_WEB_THREAD`](../../reference/all-settings.md#web.thread) | `8` | Concurrent request handlers. Throughput on parallel loaders is capped here. |
| [`BOX_DB_POOL_MAXIMUM_POOL_SIZE`](../../reference/all-settings.md) | `16` | If web threads outnumber the pool, requests queue on `BOX_DB_POOL_CONNECTION_TIMEOUT` and may surface as `503`. |

## Step 3. Pick the right bundle shape

Aidbox accepts both `transaction` and `batch` bundles. They differ in atomicity and isolation:

* **`transaction`** runs all entries inside one `SERIALIZABLE` PostgreSQL transaction. Atomic, but concurrent transactions can be aborted on serialization conflicts.
* **`batch`** runs entries independently. No atomicity, but no `SERIALIZABLE` contention either — the right default for one-time data loading where partial failures are tolerable.

Recommendations for a large data load:

1. Split data into bundles of **100–200 resources**. Aidbox handles 500+ in one bundle, but smaller bundles fail individually instead of taking the whole load down and parallelize better through `BOX_WEB_THREAD`.
2. Prefer `batch` over `transaction` when you do not need atomicity across the bundle.
3. If you must use `transaction` and run several in parallel, lower the isolation level via the [`x-max-isolation-level` header](../../api/batch-transaction.md#transaction-isolation-level) to reduce conflict aborts:

   ```http
   POST /fhir
   Content-Type: application/json
   x-max-isolation-level: read-committed

   {
     "resourceType": "Bundle",
     "type": "transaction",
     "entry": [ ... ]
   }
   ```

   {% hint style="danger" %}
   `read-committed` removes serialization protection. Only use it when you understand that concurrent writers can produce data anomalies the application must tolerate.
   {% endhint %}

4. Send bundles concurrently up to roughly `BOX_WEB_THREAD`. Beyond that requests just queue and add latency.

## Step 4. Verify

Send a bundle that intentionally exceeds your old limits and confirm it succeeds:

```bash
# 5 MB bundle — would have been rejected by default NGINX (1m)
curl -v -X POST https://aidbox.example.com/fhir \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  --data-binary @big-bundle.json
```

Expected: `HTTP/1.1 200 OK` from Aidbox. If the response comes from NGINX (`Server: nginx`), the request never reached Aidbox — recheck Step 1.

## Troubleshooting 502 / 503 / 504

| Status | Where it comes from | Likely cause | Fix |
| --- | --- | --- | --- |
| `413 Request Entity Too Large` | NGINX or Aidbox | Body exceeds `client_max_body_size` or `BOX_WEB_MAX_BODY` | Step 1 / Step 2; check `Server` response header to see which layer rejected |
| `502 Bad Gateway` | NGINX | Aidbox dropped the connection (OOM, crash, restart) or NGINX could not connect | Check Aidbox logs and liveness; raise `proxy_connect_timeout` |
| `503 Service Unavailable` | NGINX | Aidbox missed the health check while busy; or DB pool exhausted | Raise `BOX_WEB_THREAD` and `BOX_DB_POOL_MAXIMUM_POOL_SIZE`; relax health-check thresholds |
| `504 Gateway Timeout` | NGINX | `proxy_read_timeout` elapsed while Aidbox was still processing the bundle | Step 1 (raise `proxy_read_timeout`); or split the bundle into smaller chunks (Step 3) |
| `409 Conflict` (intermittent) | Aidbox | `SERIALIZABLE` conflict between concurrent transactions | Use `batch`, or set `x-max-isolation-level: read-committed` and retry |

Reproduce without NGINX to confirm the diagnosis: send the same bundle directly to Aidbox (port-forward or Service ClusterIP). If it succeeds, the problem is in the proxy layer.

## See also

* [Bundle / Batch and Transaction](../../api/batch-transaction.md)
* [Configure Aidbox and Multibox](../../configuration/configure-aidbox-and-multibox.md)
* [All settings reference](../../reference/all-settings.md)
