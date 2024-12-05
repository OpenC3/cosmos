# OpenC3 COSMOS HTTP Example

This plugin provides an example of using the HttpClientInterface and the HttpServerInterface

## Upload plugin

1. Go to localhost:2900/tools/admin
1. Click the paperclip icon and choose your plugin.gem file
1. Fill out plugin parameters
1. Click Install

## Use the Clients

NOTE: The COSMOS Demo must be installed for the Clients to work

First connect either the PYTHON_CLIENT_INT or the RUBY_CLIENT_INT (they can't both be connected). Then go to Packet Viewer and view the PYTHON_CLIENT / RUBY_CLIENT TLM_RESPONSE packet to see the value retrieved from the COSMOS API (INST HEALTH_STATUS TEMP1).

## Use the Server

NOTE: The COSMOS Demo does NOT need to be installed for the Server to work

NOTE: You must expose the server ports in the compose.yaml. Add the following:

```yaml
openc3-operator:
  ports:
    - 127.0.0.1:9090:9090
    - 127.0.0.1:9191:9191
```

The main way to interact with the server is to use curl as follows:

```bash
% curl "127.0.0.1:9090/webhook"
RESPONSE_TEXT=Webhook+Received%21%
% curl "127.0.0.1:9191/webhook"
RESPONSE_TEXT=Webhook+Received%21%
```

To update the HTTP_QUERY_TEMP value you can pass a 'temp' query parameter to the URL:

```bash
% curl "127.0.0.1:9090/webhook?temp=456"
RESPONSE_TEXT=Webhook+Received%21%
% curl "127.0.0.1:9191/webhook?temp=456"
RESPONSE_TEXT=Webhook+Received%21%
```

You can also post data to the server. Since the servers are using the FormAccessor we pass the data in the form of `key=value`.

```bash
% curl -H "Content-Type: application/json" --request POST --data 'temperature=123' "127.0.0.1:9090/webhook"
RESPONSE_TEXT=Webhook+Received%21%
% curl -H "Content-Type: application/json" --request POST --data 'temperature=123' "127.0.0.1:9191/webhook"
RESPONSE_TEXT=Webhook+Received%21%
```

The request data is mirrored back to the PYTHON_SERVER / RUBY_SERVER REQUEST packet and the TEMPERATURE field will contain 123.
