---
description: Serve Aidbox under a URL path behind nginx or another reverse proxy. Configure BOX_WEB_BASE_URL or the X-Original-URI header so the UI, login pages, redirects, and cookies keep the path.
---

# Run Aidbox behind a reverse proxy

A reverse proxy or API gateway can serve Aidbox under a URL path, for example `https://example.com/aidbox/`. Aidbox needs that path to build links, redirects, and cookies for the browser. It learns the path in one of two ways:

* the path is part of [`BOX_WEB_BASE_URL`](../../reference/all-settings.md#web.base-url);
* the proxy sends the `X-Original-URI` header with every request.

Use the base URL when the public address of Aidbox is fixed. Use the header when `BOX_WEB_BASE_URL` has to keep an internal address, or when the path exists at the gateway alone.

## Path in the base URL

Put the path in the base URL:

```shell
BOX_WEB_BASE_URL=https://example.com/aidbox
```

Aidbox accepts requests with and without the `/aidbox` prefix, so the proxy may forward the path or strip it:

{% tabs %}
{% tab title="Forward the path" %}
```nginx
location /aidbox/ {
  proxy_pass http://aidbox:8080;
  proxy_set_header Host $http_host;
}
```
{% endtab %}

{% tab title="Strip the path" %}
```nginx
location /aidbox/ {
  proxy_pass http://aidbox:8080/;
  proxy_set_header Host $http_host;
}
```
{% endtab %}
{% endtabs %}

Aidbox sets session cookies on the `/aidbox/` path. Open the UI under that path: a browser that reaches Aidbox at another path can't keep a session.

## Path known to the proxy

When `BOX_WEB_BASE_URL` has no path, for example `http://aidbox:8080`, configure the proxy to send the URL the client requested in `X-Original-URI`:

```nginx
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80;

  location /aidbox/ {
    proxy_pass http://aidbox:8080/;
    proxy_http_version 1.1;
    proxy_set_header Host $http_host;
    proxy_set_header X-Original-URI $scheme://$http_host$request_uri;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
  }
}
```

Aidbox takes the path of `X-Original-URI`, removes the route it received, and uses the rest as the prefix. For `X-Original-URI: https://example.com/aidbox/auth/login` on a request to `/auth/login`, the prefix is `/aidbox`. Aidbox adds it to:

* asset and API URLs of the Aidbox UI and the legacy UI (`/ui/console`);
* links and form actions on the login, sign-up, and account pages;
* the `Location` header of redirects;
* links in search bundles and the `Location` header of created resources.

Without the header, the Aidbox UI still loads under the proxy path, but the login form and redirects point outside of it, and users can't log in.

### Header format

`X-Original-URI` accepts a full URL or a path with a query string:

| nginx value | Example | Notes |
|-------------|---------|-------|
| `$scheme://$http_host$request_uri` | `https://example.com/aidbox/fhir/Patient?name=john` | Recommended |
| `$request_uri` | `/aidbox/fhir/Patient?name=john` | Search bundle links and `Location` headers become relative |

The Kubernetes ingress-nginx controller sends the path form by default. Set the full URL to get absolute links in FHIR responses.

Aidbox ignores the header and uses the path of `BOX_WEB_BASE_URL` when:

* the path in the header doesn't end with the route Aidbox received;
* the prefix contains characters other than letters, digits, `/`, `-`, `.`, `_`, and `~`.

## Proxy path in front of the base URL path

The two ways combine. With `BOX_WEB_BASE_URL=https://example.com/aidbox` and a gateway that serves Aidbox under `/gw/aidbox/`, send `X-Original-URI` and Aidbox uses `/gw/aidbox` for links, redirects, and session cookies.

## Security

Aidbox accepts `X-Original-URI` from any client and uses it to build links in the response to that request. Configure the proxy to set the header on every request (`proxy_set_header` in nginx replaces a value the client sent), and keep Aidbox unreachable for clients that bypass the proxy. See [Security hardening](../../access-control/security-hardening.md).

## Limitations

* The Aidbox UI finds its prefix at the first `/u/` segment of the address, so the proxy path can't contain a `/u/` segment.
* Formbox (`/u/sdc`) doesn't support a URL path yet.
