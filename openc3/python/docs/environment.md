> Copyright 2022 Ball Aerospace & Technologies Corp.
>
> All Rights Reserved.
>
> This program is free software; you can modify and/or redistribute it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation; version 3 with attribution addendums as found in the LICENSE.txt

# Environment Variables

## COSMOS_USER_AGENT

---

> BASE, ENTERPRISE

If you are using cosmos v5 you MAY want to set the environment variable `COSMOS_USER_AGENT` to equal anything. This will overwrite the default User-Agent header of the request. You can use this to track requests from an external application to cosmos.

Example:

```
COSMOS_USER_AGENT='MonkeyCommand:2.0.0 (alpha)'
```

## COSMOS_VERSION

---

> BASE, ENTERPRISE

If you are using cosmos v5 you MAY want to set the environment variable `COSMOS_VERSION` to equal anything. This will be used in the User-Agent header of the request. It will default to use None. You can use this to track requests from an external application to cosmos.

Example:

```
COSMOS_VERSION=MonkeyCommand:1.2.2
```

## COSMOS_LOG_LEVEL

---

> BASE, ENTERPRISE

In v1 the libary can log much more of what is happening in the libary. If you wish to enable this you can set the environment variable `COSMOS_LOG_LEVEL` to equal "DEBUG". If this is not set you will not get log messages if this is an incorrect log level you will get a ValueError.

Example:

```
COSMOS_LOG_LEVEL=DEBUG
```

## COSMOS_API_SCHEMA

---

> BASE, ENTERPRISE

Set the schema for Cosmos. The schema can now be set via an environment variable `COSMOS_API_SCHEMA` to the network schema that Cosmos is running with. Normal options are `http` or `https`. The default is `http`

Example:

```
COSMOS_API_SCHEMA=http
```

## COSMOS_WS_SCHEMA

---

> BASE, ENTERPRISE

Set the web socket schema for Cosmos. The schema for web sockets can now be set via an environment variable `COSMOS_WS_SCHEMA` to the network schema that Cosmos is running with. Normal options are `ws` or `wss`. The default is `ws`

Example:

```
COSMOS_WS_SCHEMA=ws
```

## COSMOS_API_HOSTNAME

---

> BASE, ENTERPRISE

Set the hostname for all Cosmosc2 scripts. In v0 of cosmosc2 it would default to 127.0.0.1. The hostname can now be set via an environment variable `COSMOS_API_HOSTNAME` to network address of the computer running Cosmos.

Example:

```
COSMOS_API_HOSTNAME=127.0.0.1
```

## COSMOS_API_PORT

> BASE, ENTERPRISE

Set the port for all cosmosc2 scripts. The port can be set via an environment variable `COSMOS_API_PORT` to the network port of the computer running Cosmos. Note the default port for Cosmos v5 is 2900

Example:

```
COSMOS_API_PORT=7777
```

## COSMOS_API_USER

---

> ENTERPRISE

Set the user for all cosmosc2 enterprise scripts. To set the environment variable `COSMOS_API_USER` to the username in you Cosmos v5 Keycloak. If this is not set the user will default to python None.

Example:

```
COSMOS_API_USER=brickTamland
```

## COSMOS_API_CLIENT

---

> ENTERPRISE

Set the client_id for all cosmosc2 enterprise scripts. To set the environment variable `COSMOS_API_CLIENT` to the client_id in you Cosmos v5 Keycloak. If this is not set the client_id will default to 'api'.

Example:

```
COSMOS_APi_CLIENT=brick-tamland-client
```

## COSMOS_SCOPE

---

> BASE, ENTERPRISE

Set the scope for all cosmosc2 scripts. To set the environment variable `COSMOS_SCOPE` to the client_secret in you Cosmos v5 Keycloak. If this is not set the scope will default to `DEFAULT`.

Example:

```
COSMOS_SCOPE=sanDeigo
```

## COSMOS_API_PASSWORD

---

> BASE, ENTERPRISE

Set the password for all cosmosc2 scripts. To use a password you can set the environment variable `COSMOS_API_PASSWORD` to the password on your Cosmos v5 instance or user. If this is not set the password will default to `SuperSecret`.

Example:

```
COSMOS_API_PASSWORD=iLoveLamp
```

## COSMOS_MAX_RETRY_COUNT

---

> BASE, ENTERPRISE

Set the max_retry_count for all cosmosc2 scripts. To use max_retry_count you can set the environment variable `COSMOS_MAX_RETRY_COUNT` to the number of times you want cosmosc2 to retry if a command gets a retryable error. If this is not set the max_retry_count will default to `3`.

Example:

```
## COSMOS_MAX_RETRY_COUNT=5
```
