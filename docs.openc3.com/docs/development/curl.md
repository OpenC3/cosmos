---
title: Testing with Curl
---

:::note This documentation is for COSMOS Developers
This information is just generally used behind the scenes in COSMOS tools
:::

The COSMOS APIs are all served over HTTP, which means you can use curl to experiment with them. Curl is a great tool for seeing exactly how the API responds to any given request.

## Curl Example with OpenC3 COSMOS Open Source

OpenC3 COSMOS Open Source just has a single user account, so all you need to do is pass the single password as the token with your requests like this.

Request:

```bash
curl -i -H "Content-Type: application/json-rpc" -H "Authorization: password" -d '{"jsonrpc": "2.0", "method": "tlm", "params": ["INST HEALTH_STATUS TEMP1"], "keyword_params": {"scope": "DEFAULT"}, "id": 8}' -X POST http://127.0.0.1:2900/openc3-api/api
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
Date: Sat, 04 Nov 2023 21:34:47 GMT

{"jsonrpc":"2.0","id":8,"result":53.26555000000001}
```

## Curl Example with OpenC3 COSMOS Enterprise

OpenC3 COSMOS Enterprise uses the Keycloak Single Sign-on system, so you must first request a token from Keycloak using a username and password pair, before you make requests. By default this token will expire in 5 minutes, and will need to be refreshed if it expires before your next request.

Keycloak Request:

```bash
# Get tokens from Keycloak - You will need to update the username and password with your account
curl -i -H "Content-Type: application/x-www-form-urlencoded" -d 'username=operator&password=operator&client_id=api&grant_type=password&scope=openid' -X POST http://127.0.0.1:2900/auth/realms/openc3/protocol/openid-connect/token
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

{"access_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJ0cDlERmpNZGFXMy16WXptdlBqVTZnNTVqMVNhWGhkZHJqU0szQVNvaDhVIn0.eyJleHAiOjE2ODM2Nzk1NDAsImlhdCI6MTY4MzY3OTI0MCwianRpIjoiZmVlOTQwYWYtZDY3Ny00MWUyLWIzNWYtZDI5ODhiM2RhZGQ2IiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDoyOTAwL2F1dGgvcmVhbG1zL29wZW5jMyIsInN1YiI6ImFjZTFlNmExLTkzMTktNDc2ZS1iZjQzLTZmM2NhYjllZTJkZSIsInR5cCI6IkJlYXJlciIsImF6cCI6ImFwaSIsInNlc3Npb25fc3RhdGUiOiJmMzc4NTk2Ny0yYTQ2LTRjMTItYWQwYy1jZmY3ZmM0NzdkZjkiLCJhY3IiOiIxIiwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbImRlZmF1bHQtcm9sZXMtb3BlbmMzIiwiQUxMU0NPUEVTX19vcGVyYXRvciIsIm9mZmxpbmVfYWNjZXNzIiwiQUxMU0NPUEVTX192aWV3ZXIiXX0sInNjb3BlIjoib3BlbmlkIHByb2ZpbGUgZW1haWwiLCJzaWQiOiJmMzc4NTk2Ny0yYTQ2LTRjMTItYWQwYy1jZmY3ZmM0NzdkZjkiLCJlbWFpbF92ZXJpZmllZCI6ZmFsc2UsIm5hbWUiOiJUaGUgT3BlcmF0b3IiLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJvcGVyYXRvciIsImdpdmVuX25hbWUiOiJUaGUiLCJmYW1pbHlfbmFtZSI6Ik9wZXJhdG9yIn0.eSqSeZrmCTahwltz5jsu5r3w6W15T5h0BvIdqKWQBDcnxAcxKuT-Nwziw_ewySSgHeC172CIWJUpHVp8ACDQG-dfW4KkvA6AcGfSF_f8TBH_rZrVQwlvwwzdA_egGKzhZWcnAC8TDjXRxuaWmnOgWT0aaHZAoW8EvwmKp-1IVz2l0B-hqzfC7dkjMrCI1udLfDvDBza9OtuR-FnKGt8h4nYnRzr8pO2jwebPFyZlR00gVsyK-b411XqprpT-qpRObYZwH5womA-8xIiwRZj9dsfQ1TaHGFkp1LNzxcj_r6pfwVO263bohbeU7ImezQdbvGLJ9NHaglzVNroTui4BXA","expires_in":300,"refresh_expires_in":1800,"refresh_token":"eyJhbGciOiJIUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI5NjNlMjJiMS0wZmYwLTRmZjktYTg0Zi1hOGI4MzcxOWFiMDEifQ.eyJleHAiOjE2ODM2ODEwNDAsImlhdCI6MTY4MzY3OTI0MCwianRpIjoiMmQyYjIyNmItNjJkOS00YjRjLWI3YTYtMGEwYjk4MGQyMjMwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDoyOTAwL2F1dGgvcmVhbG1zL29wZW5jMyIsImF1ZCI6Imh0dHA6Ly9sb2NhbGhvc3Q6MjkwMC9hdXRoL3JlYWxtcy9vcGVuYzMiLCJzdWIiOiJhY2UxZTZhMS05MzE5LTQ3NmUtYmY0My02ZjNjYWI5ZWUyZGUiLCJ0eXAiOiJSZWZyZXNoIiwiYXpwIjoiYXBpIiwic2Vzc2lvbl9zdGF0ZSI6ImYzNzg1OTY3LTJhNDYtNGMxMi1hZDBjLWNmZjdmYzQ3N2RmOSIsInNjb3BlIjoib3BlbmlkIHByb2ZpbGUgZW1haWwiLCJzaWQiOiJmMzc4NTk2Ny0yYTQ2LTRjMTItYWQwYy1jZmY3ZmM0NzdkZjkifQ.1HlKdxQkaL5tYuHTXsOceLZFmNNLl9BjoA4oUl70x9M","token_type":"Bearer","id_token":"eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJ0cDlERmpNZGFXMy16WXptdlBqVTZnNTVqMVNhWGhkZHJqU0szQVNvaDhVIn0.eyJleHAiOjE2ODM2Nzk1NDAsImlhdCI6MTY4MzY3OTI0MCwiYXV0aF90aW1lIjowLCJqdGkiOiJhNDJkOTY1ZS1lMzU0LTRiM2QtOTIyYS1hOWE0ZDgwZWYxMTkiLCJpc3MiOiJodHRwOi8vbG9jYWxob3N0OjI5MDAvYXV0aC9yZWFsbXMvb3BlbmMzIiwiYXVkIjoiYXBpIiwic3ViIjoiYWNlMWU2YTEtOTMxOS00NzZlLWJmNDMtNmYzY2FiOWVlMmRlIiwidHlwIjoiSUQiLCJhenAiOiJhcGkiLCJzZXNzaW9uX3N0YXRlIjoiZjM3ODU5NjctMmE0Ni00YzEyLWFkMGMtY2ZmN2ZjNDc3ZGY5IiwiYXRfaGFzaCI6IjNBWE9ISkFKYzFPVldLd2Y0a0Q4TkEiLCJhY3IiOiIxIiwic2lkIjoiZjM3ODU5NjctMmE0Ni00YzEyLWFkMGMtY2ZmN2ZjNDc3ZGY5IiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJuYW1lIjoiVGhlIE9wZXJhdG9yIiwicHJlZmVycmVkX3VzZXJuYW1lIjoib3BlcmF0b3IiLCJnaXZlbl9uYW1lIjoiVGhlIiwiZmFtaWx5X25hbWUiOiJPcGVyYXRvciJ9.gdLl6KOKIIAdl6jYEuAXQrGCNvuwLQb3RDnwrHJdqyFXshiwofBiLMFreRsIE-33xXWNBU6pnSLQHPVlQU5Vmzlk0IOfk-b4yNq0dNa1TV1kmnxRl8w1ulTQYVZjdsN-oyLNwe0v3aJcYtbvIA3DP8rgO6bVv0ogkjWtlda6MbkyZN-har8x3raUVSlUPRP2Basy1xSMNNA1jvB-nEM-aubrUZE6r0PjI6PE1hbLPmuPbcX3uuIwXu2-UoXepkB8H7omUuMm-S98aHpRarwszC0mmHD5b_wiXusMVw4xYw8eavFue4zfw-T2IKuTVtxbMTygXIah6iqi4gkpL8Mx1w","not-before-policy":0,"session_state":"f3785967-2a46-4c12-ad0c-cff7fc477df9","scope":"openid profile email"}
```

COSMOS Request:

```bash
# COSMOS Request now looks like this:

curl -i -H "Content-Type: application/json-rpc" -H "Authorization: eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJ0cDlERmpNZGFXMy16WXptdlBqVTZnNTVqMVNhWGhkZHJqU0szQVNvaDhVIn0.eyJleHAiOjE2ODM2Nzk1NDAsImlhdCI6MTY4MzY3OTI0MCwianRpIjoiZmVlOTQwYWYtZDY3Ny00MWUyLWIzNWYtZDI5ODhiM2RhZGQ2IiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDoyOTAwL2F1dGgvcmVhbG1zL29wZW5jMyIsInN1YiI6ImFjZTFlNmExLTkzMTktNDc2ZS1iZjQzLTZmM2NhYjllZTJkZSIsInR5cCI6IkJlYXJlciIsImF6cCI6ImFwaSIsInNlc3Npb25fc3RhdGUiOiJmMzc4NTk2Ny0yYTQ2LTRjMTItYWQwYy1jZmY3ZmM0NzdkZjkiLCJhY3IiOiIxIiwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbImRlZmF1bHQtcm9sZXMtb3BlbmMzIiwiQUxMU0NPUEVTX19vcGVyYXRvciIsIm9mZmxpbmVfYWNjZXNzIiwiQUxMU0NPUEVTX192aWV3ZXIiXX0sInNjb3BlIjoib3BlbmlkIHByb2ZpbGUgZW1haWwiLCJzaWQiOiJmMzc4NTk2Ny0yYTQ2LTRjMTItYWQwYy1jZmY3ZmM0NzdkZjkiLCJlbWFpbF92ZXJpZmllZCI6ZmFsc2UsIm5hbWUiOiJUaGUgT3BlcmF0b3IiLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJvcGVyYXRvciIsImdpdmVuX25hbWUiOiJUaGUiLCJmYW1pbHlfbmFtZSI6Ik9wZXJhdG9yIn0.eSqSeZrmCTahwltz5jsu5r3w6W15T5h0BvIdqKWQBDcnxAcxKuT-Nwziw_ewySSgHeC172CIWJUpHVp8ACDQG-dfW4KkvA6AcGfSF_f8TBH_rZrVQwlvwwzdA_egGKzhZWcnAC8TDjXRxuaWmnOgWT0aaHZAoW8EvwmKp-1IVz2l0B-hqzfC7dkjMrCI1udLfDvDBza9OtuR-FnKGt8h4nYnRzr8pO2jwebPFyZlR00gVsyK-b411XqprpT-qpRObYZwH5womA-8xIiwRZj9dsfQ1TaHGFkp1LNzxcj_r6pfwVO263bohbeU7ImezQdbvGLJ9NHaglzVNroTui4BXA" -d '{"jsonrpc": "2.0", "method": "tlm", "params": ["INST HEALTH_STATUS TEMP1"], "keyword_params": {"scope": "DEFAULT"}, "id": 8}' -X POST http://127.0.0.1:2900/openc3-api/api
```

COSMOS Response:

```bash
HTTP/1.1 200 OK
Cache-Control: max-age=0, private, must-revalidate
Content-Type: application/json-rpc
Etag: W/"1e44c0878528687014e1e60a1cbebdae"
Vary: Origin
X-Request-Id: 47a8dd26-1348-4693-8df1-5375f60abc6c
X-Runtime: 0.046477
Date: Wed, 10 May 2023 00:41:33 GMT
Transfer-Encoding: chunked

{"jsonrpc":"2.0","id":8,"result":29.204100000000007}
```
