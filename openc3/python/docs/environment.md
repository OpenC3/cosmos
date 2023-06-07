# Environment Variables

## OPENC3_API_SCHEMA

---

> BASE, ENTERPRISE

Set the schema for OpenC3 COSMOS. Normal options are `http` or `https`. The default is `http`

Example:

```
OPENC3_API_SCHEMA=http
```

## OPENC3_API_HOSTNAME

---

> BASE, ENTERPRISE

Set the hostname for all cosmos scripts.

Example:

```
OPENC3_API_HOSTNAME=127.0.0.1
```

## OPENC3_API_PORT

> BASE, ENTERPRISE

Set the port for all cosmos scripts. Note the default port for Cosmos v5 is 2900

Example:

```
OPENC3_API_PORT=2900
```

## OPENC3_API_TIMEOUT

> BASE, ENTERPRISE

Set the timeout for all cosmos api calls in seconds.

Example:

```
OPENC3_API_TIMEOUT=1.0
```

## OPENC3_SCRIPT_API_SCHEMA

---

> BASE, ENTERPRISE

Set the schema for OpenC3 COSMOS script api calls. Normal options are `http` or `https`. The default is `http`

Example:

```
OPENC3_SCRIPT_API_SCHEMA=http
```

## OPENC3_SCRIPT_API_HOSTNAME

---

> BASE, ENTERPRISE

Set the hostname for all cosmos script api calls.

Example:

```
OPENC3_SCRIPT_API_HOSTNAME=127.0.0.1
```

## OPENC3_SCRIPT_API_PORT

> BASE, ENTERPRISE

Set the port for all cosmos scripts. Note the default port for Cosmos v5 is 2900

Example:

```
OPENC3_SCRIPT_API_PORT=2900
```

## OPENC3_SCRIPT_API_TIMEOUT

> BASE, ENTERPRISE

Set the timeout for all cosmos script api calls in seconds.

Example:

```
OPENC3_SCRIPT_API_TIMEOUT=5.0
```

## OPENC3_SCOPE

---

> BASE, ENTERPRISE

Set the default scope for all cosmos script api calls.

Example:

```
OPENC3_SCOPE=DEFAULT
```

## OPENC3_API_PASSWORD

---

> BASE, ENTERPRISE

Set the password for all cosmos scripts.

Example:

```
OPENC3_API_PASSWORD=password
```

## OPENC3_LOG_LEVEL

---

> BASE, ENTERPRISE

The libary can log much more of what is happening in the library. If you wish to enable this you can set the environment variable `OPENC3_LOG_LEVEL` to equal "DEBUG". If this is not set you will not get log messages if this is an incorrect log level you will get a ValueError.

Example:

```
OPENC3_LOG_LEVEL=DEBUG
```

## OPENC3_NO_STORE

---

> BASE, ENTERPRISE

Define this environment variable if outside of the COSMOS cluster without access to Redis. Prevents trying to initialize Redis connections.

Example:

```
OPENC3_NO_STORE=1
```

## OPENC3_USER_AGENT

---

> BASE, ENTERPRISE

Setting this will overwrite the default User-Agent header of the request. You can use this to track requests from an external application to cosmos.

Example:

```
OPENC3_USER_AGENT='MonkeyCommand:2.0.0 (alpha)'
```

## OPENC3_API_USER

---

> ENTERPRISE

Set the user for all cosmos enterprise scripts. Set the environment variable `OPENC3_API_USER` to the username in your Cosmos v5 Keycloak. If this is not set the user will default to python None.

Example:

```
OPENC3_API_USER=operator
```

## OPENC3_API_CLIENT

---

> ENTERPRISE

Set the client_id for all cosmos enterprise scripts. Set the environment variable `OPENC3_API_CLIENT` to the client_id in your Cosmos v5 Keycloak. If this is not set the client_id will default to 'api'.

Example:

```
OPENC3_API_CLIENT=api
```

## OPENC3_KEYCLOAK_REALM

---

> ENTERPRISE

Set the keycloak realm for all cosmos enterprise scripts. Set the environment variable `OPENC3_KEYCLOAK_REALM` to the realm in your Cosmos v5 Keycloak. If this is not set the realm will default to 'openc3'.

Example:

```
OPENC3_KEYCLOAK_REALM=openc3
```

## OPENC3_KEYCLOAK_URL

---

> ENTERPRISE

Set the keycloak url for all cosmos enterprise scripts. Set the environment variable `OPENC3_KEYCLOAK_URL` to the URL in your Cosmos v5 Keycloak. If this is not set the realm will default to 'http://127.0.0.1:2900/auth'.

Example:

```
OPENC3_KEYCLOAK_URL=http://127.0.0.1:2900/auth
```
