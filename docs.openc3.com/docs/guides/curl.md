---
title: Testing with Curl
description: How to use Curl to call COSMOS APIs
sidebar_custom_props:
  myEmoji: 🌊
---

The COSMOS APIs are all served over HTTP, which means you can use curl to experiment with them. Curl is a great tool for seeing exactly how the API responds to any given request.

:::info OpenC3 CLI is Available
Before diving too deeping into `curl` make sure what you're trying to accomplish can't be achieved using the [OpenC3 CLI](/docs/getting-started/cli). There are options to load plugins, spawn scripts, check script status, etc. This curl information is for developers or executing APIs calls outside the CLI.
:::

## Curl Example with OpenC3 COSMOS Core

OpenC3 COSMOS Core just has a single user account, so all you need to do is pass the single password as the token with your requests like this.

Request:

```bash
curl -i -H "Content-Type: application/json-rpc" -H "Authorization: eyJhbGciOiJSUzI1NiIsInR5cCI...<access_token>" \
-d '{"jsonrpc": "2.0", "method": "tlm", "params": ["INST HEALTH_STATUS TEMP1"], "keyword_params": {"scope": "DEFAULT"}, "id": 8}' \
-X POST http://127.0.0.1:2900/openc3-api/api
```

Response:

```bash
HTTP/1.1 200 OK
Cache-Control: max-age=0, private, must-revalidate
Content-Length: 51
Content-Type: application/json-rpc
Etag: W/"e806aacfdbed0b325e7a5928e3bb5cf4"
Vary: Origin
X-Request-Id: bbad6c6b-6d22-4374-a86f-b5b0b95e6939
X-Runtime: 0.059044
Date: Wed, 10 May 2023 00:40:40 GMT

{"jsonrpc":"2.0","id":8,"result":53.26555000000001}
```

## Curl Example with OpenC3 COSMOS Enterprise

OpenC3 COSMOS Enterprise uses the Keycloak Single Sign-on system, so you must first request a token from Keycloak using a username and password pair, before you make requests. By default this token will expire in 5 minutes, and will need to be refreshed if it expires before your next request.

Keycloak Request:

```bash
# Get tokens from Keycloak - You will need to update the username and password with your account
curl -i -H "Content-Type: application/x-www-form-urlencoded" \
-d 'username=operator&password=operator&client_id=api&grant_type=password' \
-X POST http://127.0.0.1:2900/auth/realms/openc3/protocol/openid-connect/token
```

Keycloak Response:

```bash
HTTP/1.1 200 OK
Cache-Control: no-store
Content-Length: 3207
Content-Type: application/json
Pragma: no-cache
Referrer-Policy: no-referrer
Set-Cookie: KEYCLOAK_LOCALE=; Version=1; Comment=Expiring cookie; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Max-Age=0; Path=/auth/realms/openc3/; HttpOnly
Set-Cookie: KC_RESTART=; Version=1; Expires=Thu, 01-Jan-1970 00:00:10 GMT; Max-Age=0; Path=/auth/realms/openc3/; HttpOnly
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
X-Xss-Protection: 1; mode=block
Date: Wed, 10 May 2023 00:40:40 GMT

{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCI...",
 "expires_in":300,
 "refresh_expires_in":1800,
 "refresh_token":"eyJhbGciOiJIUzI1NiIsInR5cCI...",
 "token_type":"Bearer",
 "not-before-policy":0,
 "session_state":"4qBpizFTTzm5ZVHfBTXWgRAH",
 "scope":"profile roles email"
}
```

COSMOS Request:

```bash
# COSMOS Request now looks like this:

curl -i -H "Content-Type: application/json-rpc" -H "Authorization: eyJhbGciOiJSUzI1NiIsInR5cCI...<access_token>" \
-d '{"jsonrpc": "2.0", "method": "tlm", "params": ["INST HEALTH_STATUS TEMP1"], "keyword_params": {"scope": "DEFAULT"}, "id": 8}' \
-X POST http://127.0.0.1:2900/openc3-api/api
```

COSMOS Response:

```bash
HTTP/1.1 200 OK
Cache-Control: max-age=0, private, must-revalidate
Content-Length: 42
Content-Type: application/json-rpc
Etag: W/"a1f1d2d7bc871f31c0c1977fb54778ca"
Vary: Origin
X-Request-Id: 34b7adac-4134-429a-bd8f-e16268ea4204
X-Runtime: 0.017652
Date: Wed, 28 Jan 2026 14:47:46 GMT

{"jsonrpc":"2.0","id":8,"result":-40.6714}
```

### Using keyword_params for Method Options

Many API methods accept keyword parameters for additional options beyond the standard `scope` parameter. For example, the `cmd` method accepts `validate`, `timeout`, and `log_message` options. These are passed in the `keyword_params` field of the JSON-RPC request.

Request (sending a command with validation disabled):

```bash
curl -i -H "Content-Type: application/json-rpc" -H "Authorization: eyJhbGciOiJSUzI1NiIsInR5cCI...<access_token>" \
-d '{"jsonrpc": "2.0", "method": "cmd", "params": ["INST COLLECT with DURATION 10, TYPE NORMAL"], "keyword_params": {"scope": "DEFAULT", "validate": false}, "id": 9}' \
-X POST http://127.0.0.1:2900/openc3-api/api
```

Response:

```bash
HTTP/1.1 200 OK
Cache-Control: max-age=0, private, must-revalidate
Content-Length: 42
Content-Type: application/json-rpc
Etag: W/"a1f1d2d7bc871f31c0c1977fb54778ca"
Vary: Origin
X-Request-Id: 34b7adac-4134-429a-bd8f-e16268ea4204
X-Runtime: 0.017652
Date: Wed, 28 Jan 2026 14:47:46 GMT

{"jsonrpc":"2.0","id":9,"result":{"target_name":"INST","cmd_name":"COLLECT",...}}
```

### Refreshing the Access Token

When your access token expires (default: 5 minutes), you can use the refresh token to obtain a new access token without re-authenticating with username and password. The refresh token is returned in the initial authentication response above (`refresh_token` field).

Refresh Token Request:

```bash
curl -i -H "Content-Type: application/x-www-form-urlencoded" \
  -d 'client_id=api&grant_type=refresh_token&refresh_token=eyJhbGciOiJIUzI1NiIsInR5cCI...<refresh_token>' \
  -X POST http://127.0.0.1:2900/auth/realms/openc3/protocol/openid-connect/token
```

Refresh Token Response:

```bash
HTTP/1.1 200 OK
Cache-Control: no-store
Content-Length: 1939
Content-Type: application/json
Pragma: no-cache
Referrer-Policy: no-referrer
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
Date: Wed, 28 Jan 2026 14:50:06 GMT

{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCI...",
 "expires_in":300,
 "refresh_expires_in":1800,
 "refresh_token":"eyJhbGciOiJIUzUxMiIsInR5cCI...",
 "token_type":"Bearer",
 "not-before-policy":0,
 "session_state":"wtQcxD4YyzqlzBkmtRi7KTNm",
 "scope":"profile roles email"
}
```

The response contains both a new access token and a new refresh token. Each time you refresh, you receive a fresh refresh token, and the previous one is invalidated. The refresh token idle timeout (default: 30 minutes) is reset with each refresh request.

For more details on token types and lifespans, see [Keycloak](/docs/getting-started/architecture#keycloak-enterprise) in Architecture.

## Suite Runner Example

It can be very useful to run the a suite or script remotely from a continuous testing server. COSMOS' REST API allows for this. To figure out what is required to run a certain task on the web GUI you can open up your browser's developer tools to monitor the network traffic. You will see all the requests and responses required to run a command and you can reformat them yourself to suit your own purposes. Below is an example of running a test script from a Chromium-based browser:
![Network Traffic in browser developer tools](https://github.com/OpenC3/cosmos/assets/55999897/df642d42-43e0-47f9-9b52-d42746d9746b)

You can see that there are 5 transactions total. To investigate just right-click on the network transaction and click "copy as `curl`" (depends on the browser). Here is an example of the second one:

```bash
curl 'http://localhost:2900/script-api/scripts/TARGET/procedures/cmd_tlm_test.rb/lock?scope=DEFAULT' \
  -X 'POST' \
  -H 'Accept: application/json' \
  -H 'Accept-Language: en-US,en;q=0.9' \
  -H 'Authorization: eyJhbGciOiJSUzI1NiIsInR5cCI...<access_token>' \
  -H 'Connection: keep-alive' \
  -H 'Content-Length: 0' \
  -H 'Origin: http://ascportal:2900' \
  -H 'Referer: http://localhost:2900/tools/scriptrunner/?file=TARGET%2Fprocedures%2Fcmd_tlm_test.rb' \
  -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0' \
  --insecure
```

Many of the browser-specific headers are not required. The important thing to notice here is the URL and the request (in this case `POST`). If we inspect all of these we'll find out what each one does:

1. Set the script contents
   - this updates any local changes)
   - Note that this is a different request to `GET` the script contents. This is done on the page load.
2. Lock the script (so other users can't edit it during execution)
3. Run script (this takes a JSON with options)
4. Open Websocket for logs
5. Request Result (this URL is a little different because the results are saved in redis)

Below is a bash script which does all the above given some options. It requires `curl` for the web requests and `jq` for JSON parsing and formatting. It locks and runs the script, continually checks its status, then requests the result.

```bash
#!/bin/bash
set -e
TARGET=${1:-'TARGET'}
SCRIPT=${2:-'procedures/cmd_tlm_test.rb'}
SUITE=${3:-'TestSuite'}
COSMOS_HOST='http://localhost:2900'
SCRIPT_API="$COSMOS_HOST/script-api"
SCRIPT_PATH="scripts/$TARGET/$SCRIPT"
CURL_ARGS=(
	-H 'Accept: application/json'
	-H 'Authorization: eyJhbGciOiJSUzI1NiIsInR5cCI...<access_token>'
	-H 'Accept-Language: en-US,en;q=0.9'
	-H 'Connection: keep-alive'
	-H 'Content-Type: application/json'
	--insecure
	--silent )

# Lock script #
curl "$SCRIPT_API/$SCRIPT_PATH/lock?scope=DEFAULT" -X "POST" "${CURL_ARGS[@]}"

# Run script #
RUN_OPTS=$(cat <<-json
{
  "environment": [],
  "suiteRunner": {
    "method": "start",
    "suite": "$SUITE",
    "options": [
      "continueAfterError"
    ]
  }
}
json
)
RUN_OPTS=$(<<<"$RUN_OPTS" jq -rc .)
ID=$(curl "$SCRIPT_API/$SCRIPT_PATH/run?scope=DEFAULT" --data-raw "$RUN_OPTS" "${CURL_ARGS[@]}")

echo "Starting Script '$SCRIPT_PATH' at $(date) (may take up to 15 minutes)" > /dev/stderr
echo "You can monitor it in Script Runner here: $COSMOS_HOST/tools/scriptrunner/$ID" > /dev/stderr
# Loop while Script ID is still running #
while true; do
	SCRIPT_STATUS="$(curl "$SCRIPT_API/running-script?scope=DEFAULT" "${CURL_ARGS[@]}" | jq ".[]|select(.id==$ID)")"
	if [[ -z $SCRIPT_STATUS ]]; then
		break;
	fi
	sleep 2
done

# Request results #
BUCKET_FILE_URI="$(curl "$SCRIPT_API/completed-scripts?scope=DEFAULT" "${CURL_ARGS[@]}" |\
	jq '[.[]|select(.name | test("'"${SCRIPT_PATH#scripts/}"' "))][0] | .log | @uri' -r)"

URL="$(curl "$COSMOS_HOST/openc3-api/storage/download/$BUCKET_FILE_URI?bucket=OPENC3_LOGS_BUCKET&scope=DEFAULT" "${CURL_ARGS[@]}" |jq .url -r)"

curl "$COSMOS_HOST$URL" "${CURL_ARGS[@]}"
```
