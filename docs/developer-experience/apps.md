---
description: Create custom endpoints and extend Aidbox functionality with Apps for business logic, operations, and custom resource integration.
---

# Apps

Apps allow you to create custom endpoints in [Aidbox](https://www.health-samurai.io/aidbox). When a request is made to a custom endpoint, Aidbox proxies it to your application service.

An App is a standalone service that handles custom business logic. To enable this integration, you need to register the App resource in Aidbox, defining which endpoints should be proxied to your service and where to send the requests.

## Example of App resource

To define the App, we should provide the app manifest.

<pre class="language-yaml"><code class="lang-yaml"><strong>PUT /App/myorg.myapp
</strong>
<strong>resourceType: App
</strong>id: myorg.myapp
apiVersion: 1
type: app
endpoint:
   url: https://my.service.com:8888
   type: http-rpc
   secret: &#x3C;your-sercret>
operations: &#x3C;Operations-definitions>
</code></pre>

## App manifest structure

Here's the manifest structure:

<table><thead><tr><th width="207">Key</th><th width="149">Type</th><th>Description</th></tr></thead><tbody><tr><td><strong>id</strong></td><td>string</td><td>Id of the App resource</td></tr><tr><td><strong>apiVersion (required)</strong></td><td>integer</td><td>App API version. Currently, the only option is <code>1</code></td></tr><tr><td><strong>type (required)</strong></td><td>enum</td><td>Type of application. Currently, the only option is <code>app</code></td></tr><tr><td><strong>endpoint</strong></td><td>object</td><td>Information about endpoint: url to redirect the request, protocol, and secret</td></tr><tr><td><strong>operations</strong></td><td>array of operations</td><td>Custom endpoints</td></tr><tr><td><strong>resources</strong></td><td>array of resources in Aidbox format</td><td>Deprecated. Related resources that should be also created</td></tr><tr><td><strong>subscriptions</strong></td><td>array of subscriptions</td><td>Deprecated subscriptions support. Consider using <a href="../modules/topic-based-subscriptions/aidbox-topic-based-subscriptions.md">Aidbox topic-based subscriptions</a> or <a href="../modules/topic-based-subscriptions/aidbox-subsubscriptions.md">SubsSubscriptions</a> instead</td></tr></tbody></table>

### endpoint

In the `endpoint` section, you describe how Aidbox will communicate with your service:

<table><thead><tr><th width="172">Key</th><th width="103.33333333333331">Type</th><th>Description</th></tr></thead><tbody><tr><td><strong>type (required)</strong></td><td>string</td><td>Protocol of communication. The only option now is <code>http-rpc</code></td></tr><tr><td><strong>url (required)</strong></td><td>string</td><td>Url of the service to redirect a request</td></tr><tr><td><strong>secret</strong></td><td>string</td><td>Secret for Basic Authorization header: <code>base64(id:secret)</code></td></tr></tbody></table>

### operations

In the operation section, you define Custom REST operations as a map \<operation-id>: \<operation-definition> and access policy (which will be bound to this operation):

```yaml
operations:
  daily-patient-report:
    method: GET
    # GET /Patient/$daily-report/2024-01-01
    # GET /Patient/$daily-report/2024-01-02
    path: ['Patient', '$daily-report', { name: 'date'} ]
  register-user:
    method: POST
    path: [ 'User', '$register' ]
    policies: 
      register-user: {  engine: allow }
```

Parameters:

| Key          | Type                        | Description                                               |
| ------------ | --------------------------- | --------------------------------------------------------- |
| **method**   | string                      | One of: `GET`, `POST`, `PUT`, `DELETE`, `PATCH`, `OPTIONS` |
| **path**     | array of strings or objects | New endpoint in Aidbox in array                           |
| **policies** | object                      | Access policies to create and bound to this operation     |
| **timeout**  | integer                     | Timeout in milliseconds; defaults to `30000`. See [Timeout](#timeout) for HTTP streaming and bundle behavior. |

### resources

{% hint style="warning" %}
It is a deprecated option to create resources via Aidbox format.
{% endhint %}

In the resources section, you can provide other resources for Aidbox in the form `{resourceType: {id: resource}}` using Aidbox format:

<pre class="language-yaml"><code class="lang-yaml">resourceType: App
resources:
<strong>  # resource type
</strong>  AccessPolicy:
    # resource id
    public-policy:
      # resource body
      engine: allow
      link:
        - {id: 'opname', resourceType: 'Operation'}
</code></pre>

In this example, the AccessPolicy resource will be created as well as the App resource.

## Request Format

When Aidbox proxies a request to your service, it sends a POST request to the configured endpoint URL.

### Request

```yaml
type: operation
request:
  resource:                 # request body, can be anything (null for GET)
    resourceType: Parameters
    parameter:
      - name: patientNHSNumber
        valueIdentifier:
          system: https://fhir.nhs.uk/Id/nhs-number
          value: "9876543210"
  params: {}                # Query parameters
  route-params:             # Path parameters from operation path
    date: "2026-01-01"
  headers:
    content-type: application/fhir+json
    authorization: Bearer <user-token>
box:
  base-url: http://localhost:8080
operation:
  id: getstructuredrecord
  app:
    id: myapp
    resourceType: App
```

### Response

Aidbox forwards your service's HTTP status code, response body, and end-to-end response headers to the client. This includes redirect and error responses. Aidbox returns redirects to the client without following them.

Aidbox preserves compressed response bytes and the `Content-Encoding`, `Content-Length`, and `Content-Disposition` headers. Each `Set-Cookie` value reaches the client as a separate header. Aidbox removes hop-by-hop headers, including `Connection`, `Transfer-Encoding`, and headers named in `Connection`, and manages transfer framing for the client connection. Your service can omit `Content-Length` when it does not know the response size in advance.

### Streaming responses

For an App with `endpoint.type: http-rpc`, Aidbox enables response streaming by default for HTTP requests that match an operation's `method` and `path`. Aidbox sends a `POST` to `endpoint.url` with the JSON RPC envelope described above, regardless of the client's HTTP method. The envelope identifies the operation and carries the client's request data.

Aidbox forwards the body of this `POST` response to the original client as it reads bytes from your service, without waiting for the complete body. This applies to text and binary responses, including CSV (`text/csv`), NDJSON (`application/x-ndjson`), and server-sent events (`text/event-stream`). Aidbox forwards the body bytes without parsing the payload.

To deliver data before your service finishes the response, flush each portion of the body from your service. Aidbox flushes the bytes it reads to the client. For `HEAD` requests, Aidbox sends the response headers and omits the body.

For an App operation invoked as an entry in a transaction or batch bundle, Aidbox reads the complete response and decodes a JSON body before including the result in the bundle.

#### Timeout

Set `operations.<operation-id>.timeout` to control the timeout for that operation. The default is `30000` milliseconds.

For HTTP streaming, this value limits connection setup and idle socket reads while Aidbox waits for response headers or body bytes from your service. It does not limit the total duration of an active response. For SSE, send events or heartbeat comments at intervals shorter than the timeout to keep the connection active.

For calls within transaction or batch bundles, the timeout limits the complete App request, including reading the response body.

#### Cancellation and transport errors

When the client disconnects, Aidbox closes its connection to your service, including while waiting for headers or body bytes. Your service must handle the closed connection and stop producing the response.

If a connection failure or timeout occurs before Aidbox sends response headers to the client, Aidbox returns HTTP `500` with `Content-Type: application/json`. The body contains `message` with the transport error and `endpoint` with the App endpoint configuration, excluding `secret`.

If a transport error or idle timeout occurs after Aidbox sends response headers, Aidbox aborts the client connection. The client retains the status code and any body bytes it has received. Handle the interrupted response as an incomplete result.
