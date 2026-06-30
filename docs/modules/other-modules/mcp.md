---
description: "Aidbox module: MCP for extended FHIR functionality and integration."
---

# MCP

{% hint style="warning" %}
The Aidbox MCP module is available starting from version 2505 and is currently in the alpha stage.
{% endhint %}

**MCP server** is a lightweight service that exposes tools and data sources through standardized MCP endpoints. It lets any MCP‑enabled Large Language Model securely discover and invoke those resources, acting as a universal bridge between the model and the outside world.

## Aidbox MCP Server

Aidbox MCP server supports two transports, and both are served from the same `/mcp` path (and its `/sse` alias):

* **[Streamable HTTP](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports#streamable-http)** (MCP spec `2025-03-26` / `2025-06-18`) _* available since 2606_ — the recommended transport for modern MCP clients (ChatGPT, recent Claude Desktop, etc.). A single endpoint handles everything by HTTP method:
  * `POST <aidbox-base-url>/mcp` — send JSON-RPC requests (`initialize`, `tools/list`, `tools/call`, …). The response is returned directly in the POST response.
  * `GET <aidbox-base-url>/mcp` — open an optional server-to-client SSE stream (used only for server-initiated messages).
  * `DELETE <aidbox-base-url>/mcp` — terminate the session.

  A session is created on `initialize` and identified by the `Mcp-Session-Id` response header, which the client must send on every subsequent request. The negotiated protocol version is returned in the `MCP-Protocol-Version` header. Supported versions: `2024-11-05`, `2025-03-26`, `2025-06-18`.

* **Legacy HTTP+SSE** (MCP spec `2024-11-05`) — kept for backward compatibility with stdio-bridge clients. It uses two endpoints:
  * `GET <aidbox-base-url>/mcp` (or `/sse`) without an `Mcp-Session-Id` header — opens an SSE stream and returns an `endpoint` event pointing at the messages URL.
  * `POST <aidbox-base-url>/mcp/<mcp-client-id>/messages` — send messages; responses are pushed back over the SSE stream.

Both transports are also available on the `/sse` path, so existing client configurations that point at `<aidbox-base-url>/sse` keep working.

{% hint style="info" %}
**Set `BOX_WEB_BASE_URL` to the externally visible URL** that clients connect to (scheme + host + port), not the internal listening port. Aidbox validates the `Origin` header of MCP requests against this base URL for CSRF protection. Behind Docker port-mapping or a reverse proxy, a mismatch causes browser-based MCP clients to be rejected with `403 Origin header does not match the configured Aidbox base URL`. Requests without an `Origin` header (server-to-server) are always allowed.
{% endhint %}

### Tools

Aidbox provides a set of MCP tools to cover FHIR CRUDS operations.

<table><thead><tr><th width="198.7421875">Tool Name</th><th>Properties</th><th>Description</th></tr></thead><tbody><tr><td>read-fhir-resource</td><td>- resourceType (string, required)<br>- id (string, required)</td><td>Read an individual FHIR resource</td></tr><tr><td>create-fhir-resource</td><td>- resourceType (string, required)<br>- resource (JSON object, required)<br>- headers (JSON object)</td><td>Create a new FHIR resource</td></tr><tr><td>update-fhir-resource</td><td>- resourceType (string, required)<br>- id (string, required)<br>- resource (JSON object, required)</td><td>Update an existing FHIR resource</td></tr><tr><td>conditional-update-fhir-resource</td><td>- resourceType (string, required)<br>- resource (JSON object, required)<br>- query (string)<br>- headers (JSON object)</td><td>Conditional update an existing FHIR resource</td></tr><tr><td>conditional-patch-fhir-resource</td><td>- resourceType (string, required)<br>- resource (JSON object, required)<br>- query (string)<br>- headers (JSON object)</td><td>Conditional patch an existing FHIR resource</td></tr><tr><td>patch-fhir-resource</td><td>- resourceType (string, required)<br>- id (string, required)<br>- resource (JSON object, required)</td><td>Patch an existing FHIR resource</td></tr><tr><td>delete-fhir-resource</td><td>- resourceType (string, required)<br>- id (string, required)</td><td>Delete an existing FHIR resource</td></tr><tr><td>search-fhir-resources</td><td>- resourceType (string, required)<br>- query (string, required)</td><td>Search an existing FHIR resources</td></tr><tr><td>validate-fhir-resource<br><em>* available since 2509</em></td><td>- resourceType (string, required)<br>- resource (JSON object, required)<br>- mode (string - create|update|delete|patch, required)</td><td>Validate FHIR resource</td></tr></tbody></table>

{% hint style="info" %}
The server does not expose MCP resources or prompts, but it answers the `resources/list`, `resources/templates/list`, and `prompts/list` capability probes with empty lists (rather than an error) so that strict clients can complete the `initialize` handshake. `ping` is also supported.
{% endhint %}

## Configure Aidbox MCP server

### Runme command

The easiest way to run Aidbox with MCP is use the runme command:

```bash
curl -JO https://aidbox.app/runme/mcp && docker compose up
```

You will get Aidbox with enabled MCP server and created `AccessPolicy` for it.

### Already existed Aidbox

If you have already configured Aidbox to enable the MCP server:

1. Set [`module.mcp.server-enabled` setting](../../reference/all-settings.md#module.mcp.server-enabled) to `true`
2. Set up Access Control for MCP endpoints via `AccessPolicy`

#### Option 1. Public MCP Endpoint

{% hint style="warning" %}
The easiest but unsafe way to test MCP Server. Recommended for local development tests.
{% endhint %}

Aidbox MCP endpoints are not public, so you need to set up Access Control for these endpoints.\
The easiest way (but not the safest) is to create allow `AccessPolicy` for mcp operations:

```http
PUT /AccessPolicy/allow-mcp-endpoints
content-type: application/json
accept: application/json

{
  "resourceType": "AccessPolicy",
  "id": "allow-mcp-endpoints",
  "link": [
    { "id": "mcp", "resourceType": "Operation" },
    { "id": "mcp-sse", "resourceType": "Operation" },
    { "id": "mcp-post", "resourceType": "Operation" },
    { "id": "mcp-sse-post", "resourceType": "Operation" },
    { "id": "mcp-delete", "resourceType": "Operation" },
    { "id": "mcp-sse-delete", "resourceType": "Operation" },
    { "id": "mcp-client-messages", "resourceType": "Operation" }
  ],
  "engine": "allow"
}
```

{% hint style="info" %}
The `mcp-post`, `mcp-sse-post`, `mcp-delete`, and `mcp-sse-delete` operations back the Streamable HTTP transport (`POST`/`DELETE` on `/mcp` and `/sse`). They must be allowed for modern clients such as ChatGPT and recent Claude Desktop; `mcp`/`mcp-sse`/`mcp-client-messages` alone only cover the legacy HTTP+SSE transport.
{% endhint %}

This means that Aidbox MCP endpoints become public and anybody has access to them.

#### Option 2. Restricted MCP Endpoint

The second way (safer one) is to create `Client`, `AccessPolcy`, get a token and use this token to connect to Aidbox MCP server.\
Create `Client` resource

```http
PUT /Client/mcp-client
content-type: application/json
accept: application/json

{
 "id": "mcp-client",
 "secret": "verysecret", // change secret to more reliable one
 "grant_types": ["client_credentials"]
}
```

Create AccessPolicy resource:

```http
PUT /AccessPolicy/allow-mcp-endpoints
content-type: application/json
accept: application/json

{
  "resourceType": "AccessPolicy",
  "id": "mcp-endpoints",
  "engine": "matcho",
  "matcho": {
    "client": {
      "id": "mcp-client"
    },
    "operation": {
      "$one-of": [
        { "resourceType": "Operation", "id": "mcp" },
        { "resourceType": "Operation", "id": "mcp-sse" },
        { "resourceType": "Operation", "id": "mcp-post" },
        { "resourceType": "Operation", "id": "mcp-sse-post" },
        { "resourceType": "Operation", "id": "mcp-delete" },
        { "resourceType": "Operation", "id": "mcp-sse-delete" },
        { "resourceType": "Operation", "id": "mcp-client-messages" }
      ]
    }
  }
}
```

Get token:

```http
POST /auth/token
content-type: application/json
accept: application/json

{
 "client_id": "mcp-client",
 "client_secret": "verysecret", // put here your client secret
 "grant_type": "client_credentials"
}
```

Save a token from the response to connect to MCP server.

## Connect to MCP server

### Direct connection (Streamable HTTP)

Modern MCP clients (ChatGPT, recent Claude Desktop, MCP Inspector, etc.) speak the Streamable HTTP transport and connect to Aidbox directly — no bridge required. Point the client at:

```
<your-box-base-url>/mcp
```

If you set up a restricted endpoint, supply the Aidbox token as a Bearer token in the client's authentication settings.

#### ChatGPT

ChatGPT connects over Streamable HTTP via Developer mode (available on Pro, Plus, Business, Enterprise, and Education plans; a workspace admin may need to enable custom connectors first):

1. **Settings → Apps → Advanced settings → Developer mode** — enable it.
2. **Settings → Connectors → Create** — set the MCP server URL to `<your-box-base-url>/mcp`.
3. Choose the authentication: **No authentication** for a public endpoint, or **OAuth / Bearer** with your Aidbox token for a restricted endpoint.

{% hint style="info" %}
ChatGPT must reach Aidbox over the network, so `<your-box-base-url>` has to be publicly reachable (e.g. via a tunnel like ngrok or a deployed instance) and must match `BOX_WEB_BASE_URL` (see the Origin note above).
{% endhint %}

### Using a stdio bridge (supergateway)

Clients that only support the stdio transport (e.g. older Claude Desktop / Cursor configurations) use [`supergateway`](https://github.com/supercorp-ai/supergateway) to bridge stdio to Aidbox's SSE endpoint.

Aidbox MCP server config:

```shell-session
$ npx -y supergateway --sse <your-box-base-url>/sse
```

```json
{
  "mcpServers": {
    "aidbox": {
      "command": "npx",
      "args": [
        "-y",
        "supergateway",
        "--sse",
        "<your-box-base-url>/sse",
        "--oauth2Bearer", // add this only if you created a client and got a token
        "<your-aidbox-token>" // add this only if you created a client and got a token
      ]
    }
  }
}
```

*   For Claude Code, run:

    ```
    claude mcp add aidbox-mcp -- npx -y supergateway --sse http://localhost:8080/sse
    ```
* For the `Cursor` editor add this config to your project folder `.cursor/mcp.json` and make sure that `Settings` -> `Cursor Settings` -> `MCP` is enabled.
* For LLM Desktop applications such as `Claude Desktop`, go to `Settings` -> `Developer` -> `Edit Config` and set the config above. (For clients that support remote Streamable HTTP servers, prefer the [direct connection](#direct-connection-streamable-http) instead of the stdio bridge.)

Now you can ask your LLM agent to Create, Read, Update or Delete FHIR resources in Aidbox.

{% hint style="warning" %}
You need to uninstall all node versions below 18 if you use Claude Desktop. \\

```
nvm uninstall v16
nvm uninstall ... another version below 18
nvm cache clear
```
{% endhint %}

### Using MCP Inspector

MCP Inspector is a tool that helps you to discover and test MCP tools. It is a web application that allows you to connect to the Aidbox MCP server and explore its capabilities.

1. Run MCP Inspector

```bash
npx @modelcontextprotocol/inspector
```

Open the inspector in the browser:

```bash
http://localhost:6274
```

2. Connect to Aidbox MCP server

Select `Streamable HTTP` in the `Transport Type` dropdown and set URL to `<your-aidbox-base-url>/mcp`. (The legacy `SSE` transport is also still supported.)

3. Add your Aidbox token to `Authentication` -> `Bearer Token` (only if you created Aidbox Client and got the token).
4. Click `Connect` button.

Now you can discover tools and use them.

<figure><img src="../../../assets/2a76abd4-8667-4151-a6d4-59abdd785c1f.avif" alt="MCP Inspector interface showing available Aidbox tools"><figcaption></figcaption></figure>
