---
title: Curlを使用したテスト
description: COSMOSのAPIを操作するためにCurlを使用する方法
sidebar_custom_props:
  myEmoji: 🌊
---

:::note このガイドはCOSMOS開発者向けです
この情報は一般的にCOSMOSツールの裏側で使用されています
:::

COSMOS APIはすべてHTTP経由で提供されており、curlを使用して実験することができます。Curlは、特定のリクエストに対してAPIがどのように応答するかを正確に確認するための優れたツールです。

## OpenC3 COSMOS オープンソース版でのCurlの例

OpenC3 COSMOS オープンソース版は単一のユーザーアカウントしかありませんので、単一のパスワードをトークンとしてリクエストに渡すだけで済みます。

リクエスト:

```bash
curl -i -H "Content-Type: application/json-rpc" -H "Authorization: password" -d '{"jsonrpc": "2.0", "method": "tlm", "params": ["INST HEALTH_STATUS TEMP1"], "keyword_params": {"scope": "DEFAULT"}, "id": 8}' -X POST http://127.0.0.1:2900/openc3-api/api
```

レスポンス:

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

## OpenC3 COSMOS Enterprise版でのCurlの例

OpenC3 COSMOS Enterprise版はKeycloakシングルサインオンシステムを使用しているため、リクエストを行う前に、ユーザー名とパスワードのペアを使用してKeycloakからトークンを要求する必要があります。デフォルトでは、このトークンは5分で期限切れになり、次のリクエストの前に期限切れになった場合は更新する必要があります。

Keycloakリクエスト:

```bash
# Keycloakからトークンを取得 - ユーザー名とパスワードをあなたのアカウントに更新する必要があります
curl -i -H "Content-Type: application/x-www-form-urlencoded" -d 'username=operator&password=operator&client_id=api&grant_type=password&scope=openid' -X POST http://127.0.0.1:2900/auth/realms/openc3/protocol/openid-connect/token
```

Keycloakレスポンス:

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

COSMOSリクエスト:

```bash
# COSMOSリクエストは次のようになります:

curl -i -H "Content-Type: application/json-rpc" -H "Authorization: eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICJ0cDlERmpNZGFXMy16WXptdlBqVTZnNTVqMVNhWGhkZHJqU0szQVNvaDhVIn0.eyJleHAiOjE2ODM2Nzk1NDAsImlhdCI6MTY4MzY3OTI0MCwianRpIjoiZmVlOTQwYWYtZDY3Ny00MWUyLWIzNWYtZDI5ODhiM2RhZGQ2IiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDoyOTAwL2F1dGgvcmVhbG1zL29wZW5jMyIsInN1YiI6ImFjZTFlNmExLTkzMTktNDc2ZS1iZjQzLTZmM2NhYjllZTJkZSIsInR5cCI6IkJlYXJlciIsImF6cCI6ImFwaSIsInNlc3Npb25fc3RhdGUiOiJmMzc4NTk2Ny0yYTQ2LTRjMTItYWQwYy1jZmY3ZmM0NzdkZjkiLCJhY3IiOiIxIiwicmVhbG1fYWNjZXNzIjp7InJvbGVzIjpbImRlZmF1bHQtcm9sZXMtb3BlbmMzIiwiQUxMU0NPUEVTX19vcGVyYXRvciIsIm9mZmxpbmVfYWNjZXNzIiwiQUxMU0NPUEVTX192aWV3ZXIiXX0sInNjb3BlIjoib3BlbmlkIHByb2ZpbGUgZW1haWwiLCJzaWQiOiJmMzc4NTk2Ny0yYTQ2LTRjMTItYWQwYy1jZmY3ZmM0NzdkZjkiLCJlbWFpbF92ZXJpZmllZCI6ZmFsc2UsIm5hbWUiOiJUaGUgT3BlcmF0b3IiLCJwcmVmZXJyZWRfdXNlcm5hbWUiOiJvcGVyYXRvciIsImdpdmVuX25hbWUiOiJUaGUiLCJmYW1pbHlfbmFtZSI6Ik9wZXJhdG9yIn0.eSqSeZrmCTahwltz5jsu5r3w6W15T5h0BvIdqKWQBDcnxAcxKuT-Nwziw_ewySSgHeC172CIWJUpHVp8ACDQG-dfW4KkvA6AcGfSF_f8TBH_rZrVQwlvwwzdA_egGKzhZWcnAC8TDjXRxuaWmnOgWT0aaHZAoW8EvwmKp-1IVz2l0B-hqzfC7dkjMrCI1udLfDvDBza9OtuR-FnKGt8h4nYnRzr8pO2jwebPFyZlR00gVsyK-b411XqprpT-qpRObYZwH5womA-8xIiwRZj9dsfQ1TaHGFkp1LNzxcj_r6pfwVO263bohbeU7ImezQdbvGLJ9NHaglzVNroTui4BXA" -d '{"jsonrpc": "2.0", "method": "tlm", "params": ["INST HEALTH_STATUS TEMP1"], "keyword_params": {"scope": "DEFAULT"}, "id": 8}' -X POST http://127.0.0.1:2900/openc3-api/api
```

COSMOSレスポンス:

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

## Suite Runnerの例

継続的テストサーバーからリモートでスイートやスクリプトを実行することは非常に便利です。COSMOSのREST APIはこれを可能にします。ウェブGUIで特定のタスクを実行するために必要なものを把握するには、ブラウザの開発者ツールを開いてネットワークトラフィックを監視することができます。コマンドを実行するために必要なすべてのリクエストとレスポンスが表示され、自分の目的に合わせて再フォーマットすることができます。以下はChromiumベースのブラウザからテストスクリプトを実行する例です：
![ブラウザの開発者ツールでのネットワークトラフィック](https://github.com/OpenC3/cosmos/assets/55999897/df642d42-43e0-47f9-9b52-d42746d9746b)

合計5つのトランザクションがあることがわかります。調査するには、ネットワークトランザクションを右クリックして「`curl`としてコピー」をクリックするだけです（ブラウザによって異なります）。以下は2番目のトランザクションの例です：

```bash
curl 'http://localhost:2900/script-api/scripts/TARGET/procedures/cmd_tlm_test.rb/lock?scope=DEFAULT' \
  -X 'POST' \
  -H 'Accept: application/json' \
  -H 'Accept-Language: en-US,en;q=0.9' \
  -H 'Authorization: pass' \
  -H 'Connection: keep-alive' \
  -H 'Content-Length: 0' \
  -H 'Origin: http://ascportal:2900' \
  -H 'Referer: http://localhost:2900/tools/scriptrunner/?file=TARGET%2Fprocedures%2Fcmd_tlm_test.rb' \
  -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0' \
  --insecure
```

ブラウザ固有のヘッダーの多くは必要ありません。ここで重要なのはURLとリクエスト（この場合は`POST`）です。これらをすべて調査すると、それぞれの役割がわかります：

1. スクリプトの内容を設定する
   - ローカルの変更を更新します
   - スクリプトの内容を`GET`するのとは異なるリクエストであることに注意してください。これはページ読み込み時に行われます。
2. スクリプトをロックする（実行中に他のユーザーが編集できないようにするため）
3. スクリプトを実行する（オプションを含むJSONを取ります）
4. ログ用のWebsocketを開く
5. 結果をリクエストする（結果はredisに保存されるため、このURLは少し異なります）

以下はいくつかのオプションを指定して上記のすべてを実行するbashスクリプトです。ウェブリクエストには`curl`、JSONの解析とフォーマットには`jq`が必要です。スクリプトをロックして実行し、継続的にステータスを確認し、結果をリクエストします。

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
	-H 'Authorization: password'
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
