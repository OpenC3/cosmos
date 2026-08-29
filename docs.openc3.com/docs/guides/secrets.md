---
title: Secrets
description: Storing passwords, tokens, and certificates and passing them to interfaces and microservices
sidebar_custom_props:
  myEmoji: 🔑
---

Interfaces and microservices frequently need credentials: a device password, an API token, a client certificate and key. COSMOS Secrets keep those values out of your plugin configuration and out of the git repository holding it. You store the value once, reference it by name in `plugin.txt`, and COSMOS injects it into the interface or microservice process at startup.

:::warning[Secrets Are Not a Substitute for Access Control]
Any user who can install a plugin can write a plugin that reads any secret in that scope, and any user who can edit a script running in an interface's container can read the secrets mounted there. Restrict the `admin` role accordingly. See [Roles and Permissions](roles-permissions.md).
:::

## Secret Stores (Backends)

The secret store used at runtime is selected by the `OPENC3_SECRET_BACKEND` environment variable.

| Backend      | Value        | Available in            | Set / Delete from COSMOS  |
| ------------ | ------------ | ----------------------- | ------------------------- |
| Redis/Valkey | `redis`      | Core and Enterprise     | Yes (Admin / Secrets tab) |
| Kubernetes   | `kubernetes` | Enterprise (Helm chart) | No, managed by Kubernetes |

If `OPENC3_SECRET_BACKEND` is not set it defaults to `redis`, which is what the Docker Compose deployment uses. The Helm chart sets it from the `secretsBackend` value, which defaults to `kubernetes`.

With the `redis` backend, secret values live in the Valkey key `<SCOPE>__openc3__secrets`. They are stored as-is, not encrypted at rest, so they are only as protected as your Valkey deployment. Set a Valkey password and restrict network access to it — see [Security](../getting-started/security.md).

Secrets are scoped. A secret created in the DEFAULT scope is not visible to plugins installed in another scope (Enterprise supports multiple scopes).

## Creating Secrets

### Admin Tool (redis backend)

Go to the [Admin tool's Secrets tab](../tools/admin.md#secrets). Enter a Secret Name, then either type the value into Secret Value or select a file to upload the file's contents as the value (the normal choice for certificates and keys). Secret names are case sensitive and are what you reference from `plugin.txt`.

### API

The same operations are available over the REST API and require the `admin` role. In Core, `$TOKEN` comes from `/openc3-api/auth/verify`; in Enterprise it is a Keycloak access token. See [Curl](curl.md) for how to obtain it.

```bash
# List secret names (values are never returned)
curl -H "Authorization: $TOKEN" \
  "http://localhost:2900/openc3-api/secrets?scope=DEFAULT"

# Set a secret from a value
curl -X POST -H "Authorization: $TOKEN" \
  -d "value=mypassword" \
  "http://localhost:2900/openc3-api/secrets/MQTT_PASSWORD?scope=DEFAULT"

# Set a secret from a file (certificates, keys)
curl -X POST -H "Authorization: $TOKEN" \
  -F "file=@/path/to/ca.pem" \
  "http://localhost:2900/openc3-api/secrets/CA_FILE?scope=DEFAULT"

# Delete a secret
curl -X DELETE -H "Authorization: $TOKEN" \
  "http://localhost:2900/openc3-api/secrets/MQTT_PASSWORD?scope=DEFAULT"
```

The API never returns secret values, only names. Every set and delete is logged with the requesting username.

This is the hook to use for scripted provisioning: a CI job or a startup script can pull values out of an external secret manager and POST them into COSMOS, so no credential is ever typed into the Admin tool or committed anywhere. See [External Secret Managers](#external-secret-managers) below.

## Using Secrets in a Plugin

Secrets are requested with the [SECRET](../configuration/plugins.md#secret) keyword under an `INTERFACE`, `ROUTER`, or `MICROSERVICE`:

```bash
SECRET <ENV or FILE> <Secret Name> <Env Var Name or File Path> <Option Name (interfaces only)> <Secret Store Name>
```

- **Type** `ENV` passes the value in an environment variable, `FILE` writes the value into a file.
- **Secret Name** is the name from the Secrets tab (with the Kubernetes backend, the key inside a Kubernetes Secret).
- **Env Var Name or File Path** is where the value is placed in the process. For `FILE`, use a full path in a writable location such as `/tmp/<TARGET>/CERT`.
- **Option Name** (interfaces and routers only) is an interface option to set to the secret's value. This is the preferred way to hand a secret to an interface, because the interface reads it through `set_option` rather than having to read the environment or a file itself.
- **Secret Store Name** is only used by stores with multipart keys, i.e. the Kubernetes backend, where it names the Kubernetes Secret resource.

Interfaces additionally support `BRIDGE_SECRET`, which has identical syntax and applies the secret to the host-side bridge interface instead of the container-side interface. See [Bridges](bridges.md).

### Interface Example

From `examples/openc3-cosmos-mqtt-test/plugin.txt`:

```cosmos
INTERFACE MQTT_INT openc3/interfaces/mqtt_interface.py test.mosquitto.org 8883
  MAP_TARGET MQTT
  # Username isn't sensitive, so set the option directly
  OPTION USERNAME myuser
  # Password comes from the MQTT_PASSWORD secret, delivered via the PASSWORD option
  SECRET ENV MQTT_PASSWORD MQTT_PASSWORD PASSWORD
  # Certificates are files, so use FILE and pass the contents through the option
  SECRET FILE MQTT_CERT "/tmp/MQTT/MQTT_CERT" CERT
  SECRET FILE MQTT_KEY "/tmp/MQTT/MQTT_KEY" KEY
  SECRET FILE MQTT_CA_FILE "/tmp/MQTT/MQTT_CA_FILE" CA_FILE
```

With an Option Name given, the third parameter only has to be unique — the interface never reads it, since COSMOS resolves the secret and calls `set_option` before connecting.

### Microservice Example

Microservices have no options, so the secret is only available as an environment variable or a file:

```cosmos
MICROSERVICE MY_SERVICE my_service
  CMD ruby my_service.rb
  SECRET ENV API_TOKEN MY_API_TOKEN
  SECRET FILE CLIENT_CERT "/tmp/MY_SERVICE/cert.pem"
```

Read them like any other environment variable or file:

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
import os

token = os.environ["MY_API_TOKEN"]
with open("/tmp/MY_SERVICE/cert.pem") as file:
    cert = file.read()
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
token = ENV['MY_API_TOKEN']
cert = File.read('/tmp/MY_SERVICE/cert.pem')
```

</TabItem>
</Tabs>

### Reading Secrets in Custom Interface Code

Every interface has a `secrets` client whose `get` returns the values declared by that interface's `SECRET` lines. Prefer the Option Name form above; use this when you need the raw value inside a custom interface class:

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
import os

scope = os.environ.get("OPENC3_SCOPE", "DEFAULT")
password = self.secrets.get("MQTT_PASSWORD", scope=scope)
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
scope = ENV.fetch('OPENC3_SCOPE', 'DEFAULT')
password = @secrets.get('MQTT_PASSWORD', scope: scope)
```

</TabItem>
</Tabs>

How `get` resolves depends on the backend: with `redis` it queries the secret store directly, and with `kubernetes` it returns the value Kubernetes already mounted into the process (the env var or file named by the `SECRET` line). Either way, only secrets declared on that interface are reliably available.

### Failure Modes

- A secret name referenced by a `SECRET` line that does not exist in the store: the operator logs `references unknown secret: <NAME>` and the interface or microservice starts anyway, with the option unset or the file missing. Connections then fail with an authentication error rather than a configuration error, so check the operator logs first.
- Secrets are read at process start. After changing a secret's value, restart the interface or microservice (Disconnect/Connect from CMD/TLM Server, or restart the target's microservice) to pick up the new value.

## Kubernetes

In a Helm-based Enterprise deployment, COSMOS does not store secrets itself. `secretsBackend: kubernetes` in `values.yaml` sets `OPENC3_SECRET_BACKEND=kubernetes`, and secrets come from native [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/). The Kubernetes operator translates each `SECRET` line into the corresponding field of the Deployment it generates, and the kubelet mounts the value — COSMOS never reads the secret value through the Kubernetes API.

This means, with the `kubernetes` backend:

- **Secret Store Name is required.** It names the Kubernetes Secret resource, and the Secret Name is the key within it. A `SECRET` line without a store name has nothing to resolve against.
- **The Admin / Secrets tab does not work.** Creating, listing, and deleting are not implemented for this backend; use `kubectl`, Helm, or a secrets operator instead.
- **The Secret must be in the same namespace** as the COSMOS deployment (`OPENC3_KUBERNETES_NAMESPACE`, `default` if unset). A Secret in another namespace cannot be mounted.

### Creating the Kubernetes Secret

```bash
# Key/value secrets
kubectl create secret generic mqtt-secrets \
  --namespace openc3 \
  --from-literal=MQTT_PASSWORD='mypassword' \
  --from-literal=API_TOKEN='abc123'

# File-based secrets (certificates and keys)
kubectl create secret generic mqtt-certs \
  --namespace openc3 \
  --from-file=MQTT_CERT=./client.pem \
  --from-file=MQTT_KEY=./client.key \
  --from-file=MQTT_CA_FILE=./ca.pem
```

### Referencing It from plugin.txt

The store name is the last parameter, so an interface line that uses an option must also supply the Option Name:

```cosmos
INTERFACE MQTT_INT openc3/interfaces/mqtt_interface.py test.mosquitto.org 8883
  MAP_TARGET MQTT
  # <store name> is mqtt-secrets, key within it is MQTT_PASSWORD
  SECRET ENV MQTT_PASSWORD MQTT_PASSWORD PASSWORD mqtt-secrets
  SECRET FILE MQTT_CERT "/tmp/MQTT/MQTT_CERT" CERT mqtt-certs
  SECRET FILE MQTT_KEY "/tmp/MQTT/MQTT_KEY" KEY mqtt-certs
  SECRET FILE MQTT_CA_FILE "/tmp/MQTT/MQTT_CA_FILE" CA_FILE mqtt-certs
```

For a microservice, which has no Option Name, leave that parameter off entirely — the store name moves up into fourth position:

```cosmos
MICROSERVICE MY_SERVICE my_service
  CMD ruby my_service.rb
  SECRET ENV API_TOKEN MY_API_TOKEN mqtt-secrets
```

### What the Operator Generates

- `SECRET ENV <key> <ENV_VAR> ... <store>` becomes a container env var sourced from `secretKeyRef: {name: <store>, key: <key>}`.
- `SECRET FILE <key> <path> ... <store>` becomes a read-only volume from that Secret, mounted at `dirname(<path>)`, with the key projected to `basename(<path>)`.

The volume mount consequence is worth planning around: **the directory containing the file is replaced by the mount**, so give each `FILE` secret a path under a directory dedicated to it (`/tmp/MQTT/MQTT_CERT`, not `/tmp/MQTT_CERT`) or multiple secrets in the same directory will conflict and shadow other files there. Keys from the same Secret resource can share a directory safely only if they are declared as separate mounts with distinct directories.

Because the values are baked into the Deployment spec, changing a Kubernetes Secret does not update a running interface. Restart the interface (or delete its Deployment and let the operator recreate it) after rotating a value.

## External Secret Managers

COSMOS has no native Vault, AWS Secrets Manager, or Azure Key Vault driver. `OPENC3_SECRET_BACKEND` accepts `redis` and `kubernetes` only. External managers integrate by _syncing_ a value into one of those two stores, which keeps the external manager as the source of truth and rotation authority while COSMOS just consumes the current value.

### On Kubernetes (Sync into a Kubernetes Secret)

This is the cleanest path, because the sync is a solved problem with off-the-shelf controllers and requires no COSMOS configuration at all — COSMOS sees an ordinary Kubernetes Secret and the `plugin.txt` above is unchanged.

- **[External Secrets Operator](https://external-secrets.io/)** — supports Vault, AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, and others. Define a `SecretStore` pointing at your manager and an `ExternalSecret` that materializes a Kubernetes Secret; reference that Secret's name as the Secret Store Name.
- **[Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/platform/k8s/vso)** — HashiCorp's own controller, same shape: a `VaultStaticSecret` renders a Kubernetes Secret you then name in `plugin.txt`.

An External Secrets Operator manifest pulling from Vault:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: mqtt-secrets
  namespace: openc3
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    # This name is the Secret Store Name used in plugin.txt
    name: mqtt-secrets
  data:
    # This key is the Secret Name used in plugin.txt
    - secretKey: MQTT_PASSWORD
      remoteRef:
        key: secret/cosmos/mqtt
        property: password
```

Rotation caveat: when the controller updates the Kubernetes Secret, the COSMOS interface or microservice does **not** pick up the change. The value was already injected into the running process at start. Restart the interface after a rotation (see [Rotating a Secret](#rotating-a-secret)).

### On Docker Compose (Sync into the Redis Store)

With the `redis` backend there is no controller to do this for you, so push the value in over the API. Fetch from the manager, POST to COSMOS, and don't write it to disk in between:

```bash
#!/bin/bash
# Provision COSMOS secrets from Vault. Run at deploy time and after each rotation.
set -euo pipefail

TOKEN=$(curl -s -X POST "http://localhost:2900/openc3-api/auth/verify" \
  -H "Content-Type: application/json" -d "{\"password\": \"$OPENC3_PASSWORD\"}")

# Read from Vault (VAULT_ADDR and VAULT_TOKEN already in the environment)
MQTT_PASSWORD=$(vault kv get -field=password secret/cosmos/mqtt)

curl -s -X POST -H "Authorization: $TOKEN" \
  -d "value=$MQTT_PASSWORD" \
  "http://localhost:2900/openc3-api/secrets/MQTT_PASSWORD?scope=DEFAULT" > /dev/null
```

The equivalent for AWS Secrets Manager substitutes `aws secretsmanager get-secret-value --secret-id cosmos/mqtt --query SecretString --output text`, and for Azure Key Vault `az keyvault secret show --vault-name myvault --name mqtt-password --query value -o tsv`.

Two things to keep in mind with this approach:

- The value comes to rest in Valkey, unencrypted. The external manager gives you central rotation, audit, and access policy, but it does not make the COSMOS-side copy any better protected — secure Valkey as described in [Security](../getting-started/security.md).
- Nothing re-syncs automatically. Re-run the script after a rotation, then restart the consuming interface or microservice.

### Choosing an Approach

| Need                                                        | Approach                                                                                                                                                                                                                                       |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Kubernetes, want automatic sync                             | External Secrets Operator or Vault Secrets Operator                                                                                                                                                                                            |
| Docker Compose, central rotation                            | API provisioning script from the manager                                                                                                                                                                                                       |
| Docker Compose, keep value out of the COSMOS store entirely | Export it as a shell environment variable at launch (see [Injecting Secrets at Runtime](../getting-started/security.md#injecting-secrets-at-runtime)) and read it in your interface or microservice code; the `SECRET` keyword is not involved |
| Short-lived / dynamic credentials (Vault database engine)   | Fetch inside a custom interface or microservice at connect time rather than using `SECRET`; COSMOS's `SECRET` values are resolved once at process start and never refreshed                                                                    |

That last row is the real limitation to design around: `SECRET` is for long-lived credentials. If you need leased credentials that expire in minutes, have your interface code talk to the manager directly on each reconnect, and use `SECRET` only for the manager's own auth credential (an AppRole secret ID, for example).

## Rotating a Secret

1. Update the value in whichever store is authoritative (external manager, `kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`, or the Admin tool).
2. If using the `redis` backend with an external manager, re-run the provisioning sync.
3. Restart the consumer so it reads the new value: Disconnect then Connect the interface in CMD/TLM Server, or restart the microservice. On Kubernetes, deleting the interface's Deployment also works — the operator recreates it.
4. Confirm the connection re-established in the CMD/TLM Server before retiring the old credential.

## Deployment Secrets vs. COSMOS Secrets

The secrets described here are the ones your plugins consume. COSMOS's own infrastructure credentials (Valkey passwords, bucket keys, `SECRET_KEY_BASE`) are separate and configured in the environment, not in the Secrets tab. See [Security](../getting-started/security.md) for those, including `.env.local` and runtime injection.

## Best Practices

- Never put a credential directly into `plugin.txt`, a target config file, or a script. Use a `SECRET` line, and use a plugin `VARIABLE` for the secret's _name_ when a plugin is installed more than once.
- Prefer the Option Name form for interfaces so the value stays inside the process and never has to be read from disk.
- Use `FILE` for anything multi-line (PEM certificates, private keys); environment variables handle them poorly.
- Don't log secret values. `Logger` output goes to the log bucket, which has different access controls than the secret store.
- Give each scope its own secrets rather than sharing one credential across scopes.
- Rotate by updating the secret and then restarting the consuming interface or microservice, and confirm the connection re-establishes.
