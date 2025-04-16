---
title: JSON API
description: JSON-RPCを使用したCOSMOS APIへのインターフェース
sidebar_custom_props:
  myEmoji: 🖥️
---

:::note このドキュメントはCOSMOS開発者向けです
COSMOS スクリプティングAPIを使用してテスト手順を作成するための利用可能なメソッドをお探しの場合は、[スクリプティングAPIガイド](../guides/scripting-api.md)のページを参照してください。お好きな言語を使用して外部アプリケーションからCOSMOSにインターフェースしようとしている場合は、ここが適切な場所です。
:::

このドキュメントは、外部アプリケーションがCOSMOS APIを使用してCOSMOSと対話するために必要な情報を提供します。任意の言語で書かれた外部アプリケーションは、このAPIを使用してコマンドを送信し、個々のテレメトリポイントを取得できます。外部アプリケーションは、COSMOS コマンド＆テレメトリサーバーに接続して、コマンド/テレメトリの生のtcp/ipストリームと対話することもできます。ただし、COSMOS JSON APIを使用すると、外部アプリケーションがパケットのバイナリ形式についての知識を持つ必要がなくなります。

## 認証

HTTP認証リクエストヘッダーには、ユーザーエージェントをサーバーで認証するための資格情報が含まれています。通常、サーバーが401 Unauthorized ステータスとWWW-Authenticateヘッダーで応答した後に使用されますが、必ずしもそうではありません。

```
Authorization: <token/password>
```

## JSON-RPC 2.0

COSMOS APIは、[JSON-RPC 2.0仕様](http://www.jsonrpc.org/specification)の緩和されたバージョンを実装しています。「id」がNULLのリクエストはサポートされていません。数値には、NaNや+/-infなどの特殊な非文字列リテラルを含めることができます。リクエストパラメータは位置で指定する必要があり、名前による指定はサポートされていません。仕様のセクション6「バッチ操作」はサポートされていません。COSMOSのスコープは`"keyword_params"`オブジェクトで指定する必要があります。

## ソケット接続

COSMOS コマンド＆テレメトリサーバーは、HTTPサーバー（デフォルトポート7777）でCOSMOS APIへの接続をリッスンします。

COSMOSは、デフォルトの2900ポートの`/openc3-api/api`エンドポイントでHTTP APIリクエストをリッスンします。

## サポートされているメソッド

COSMOS APIでサポートされているメソッドのリストは、Github上の[api](https://github.com/openc3/cosmos/tree/main/openc3/lib/openc3/api)ソースコードにあります。@api_whitelistという変数は、CTSで受け入れられるすべてのメソッドの配列で初期化されています。このページでは、APIのすべてのメソッドの完全な引数リストを示しませんが、JSON APIメソッドは[スクリプト作成ガイド](../guides/script-writing.md)に記載されているCOSMOSスクリプティングAPIメソッドに対応していることに注意してください。このページでは、いくつかのJSON要求と応答の例を示します。スクリプティングガイドは、ここで明示的に文書化されていないメソッドのリクエストの構築方法とレスポンスの解析方法を推測するための参考として使用できます。

## 既存の実装

COSMOS JSON APIは以下の言語で実装されています：Ruby、PythonとJavascript。

## 使用例

### コマンドの送信

コマンドを送信するには、次のメソッドが使用されます：cmd、cmd_no_range_check、cmd_no_hazardous_check、cmd_no_checks

cmdメソッドは、システム内のCOSMOSターゲットにコマンドを送信します。cmd_no_range_checkメソッドも同様ですが、パラメータの範囲エラーを無視します。cmd_no_hazardous_checkメソッドも同様ですが、危険なコマンドの送信を許可します。cmd_no_checksメソッドも同様ですが、危険なコマンドの送信を許可し、範囲エラーを無視します。

2つのパラメータ構文がサポートされています。

1つ目は、「TARGET_NAME COMMAND_NAME with PARAMETER_NAME_1 PARAMETER_VALUE_1, PARAMETER_NAME_2 PARAMETER_VALUE_2, ...」の形式の単一の文字列です。「with ...」部分は省略可能です。指定されていないパラメータにはデフォルト値が与えられます。

| パラメータ     | データ型  | 説明                                       |
| -------------- | --------- | ------------------------------------------ |
| command_string | string    | コマンドに必要なすべての情報を含む単一文字列 |

2つ目は、最初のパラメータがターゲット名を示す文字列、2番目がコマンド名を含む文字列、そしてオプションの3番目がパラメータ名/値のハッシュである2つまたは3つのパラメータです。このフォーマットは、コマンドにASCIIテキストとして表現できないバイナリデータを取るパラメータが含まれている場合に使用する必要があります。cmdおよびcmd_no_range_checkメソッドは、危険とマークされたコマンドを送信しようとするとすべて失敗します。危険なコマンドを送信するには、cmd_no_hazardous_checkまたはcmd_no_checksメソッドを使用する必要があります。

| パラメータ      | データ型  | 説明                                |
| -------------- | --------- | ----------------------------------- |
| target_name    | String    | コマンドを送信するターゲットの名前    |
| command_name   | String    | コマンドの名前                      |
| command_params | Hash      | オプションのコマンドパラメータのハッシュ |

使用例：

```bash
--> {"jsonrpc": "2.0", "method": "cmd", "params": ["INST COLLECT with DURATION 1.0, TEMP 0.0, TYPE 'NORMAL'"], "id": 1, "keyword_params":{"scope":"DEFAULT"}}
<-- {"jsonrpc": "2.0", "result": ["INST", "COLLECT", {"DURATION": 1.0, "TEMP": 0.0, "TYPE": "NORMAL"}], "id": 1}

--> {"jsonrpc": "2.0", "method": "cmd", "params": ["INST", "COLLECT", {"DURATION": 1.0, "TEMP": 0.0, "TYPE": "NORMAL"}], "id": 1, "keyword_params":{"scope":"DEFAULT"}}
<-- {"jsonrpc": "2.0", "result": ["INST", "COLLECT", {"DURATION": 1.0, "TEMP": 0.0, "TYPE": "NORMAL"}], "id": 1}
```

### テレメトリの取得

テレメトリを取得するには、次のメソッドが使用されます：tlm、tlm_raw、tlm_formatted、tlm_with_units

tlmメソッドは、テレメトリポイントの現在の変換値を返します。tlm_rawメソッドは、テレメトリポイントの現在の生の値を返します。tlm_formattedメソッドは、テレメトリポイントの現在のフォーマット済み値を返します。tlm_with_unitsメソッドは、テレメトリポイントの現在のフォーマット済み値に単位を付加して返します。

2つのパラメータ構文がサポートされています。

1つ目は、「TARGET_NAME PACKET_NAME ITEM_NAME」の形式の単一の文字列です。

| パラメータ   | データ型  | 説明                                           |
| ---------- | --------- | ---------------------------------------------- |
| tlm_string | String    | テレメトリ項目に必要なすべての情報を含む単一文字列 |

2つ目は、最初のパラメータがターゲット名を示す文字列、2番目がパケット名を含む文字列、3番目が項目名を含む文字列である3つのパラメータです。

| パラメータ    | データ型  | 説明                                 |
| ----------- | --------- | ------------------------------------ |
| target_name | String    | テレメトリ値を取得するターゲットの名前  |
| packet_name | String    | テレメトリ値を取得するパケットの名前    |
| item_name   | String    | テレメトリ項目の名前                   |

使用例：

```bash
--> {"jsonrpc": "2.0", "method": "tlm", "params": ["INST HEALTH_STATUS TEMP1"], "id": 2, "keyword_params":{"scope":"DEFAULT"}}
<-- {"jsonrpc": "2.0", "result": 94.9438, "id": 2}

--> {"jsonrpc": "2.0", "method": "tlm", "params": ["INST", "HEALTH_STATUS", "TEMP1"], "id": 2, "keyword_params":{"scope":"DEFAULT"}}
<-- {"jsonrpc": "2.0", "result": 94.9438, "id": 2}
```

## さらなるデバッグ

別の言語からJSON APIのインターフェースを開発する場合、最適なデバッグ方法は、まず以下のようにサポートされているRubyインターフェースから同じメッセージを送信することです。デバッグモードを有効にすることで、Ruby実装から送信される正確なリクエストとレスポンスを確認できます。

1. COSMOSを起動する
2. Command Senderを開く
3. ブラウザの開発者ツールを開く（Chromeでは右クリック->検証）
4. 「Network」タブをクリック（`+`ボタンで追加する必要があるかもしれません）
5. GUIでコマンドを送信する
6. 開発者ツールでリクエストを表示する。「Payload」サブタブをクリックしてJSONを表示する

また、`curl`のようなプログラムを使用して、ターミナルからこれらの生のコマンドを送信することもできます：

```bash
curl -d '{"jsonrpc": "2.0", "method": "tlm", "params": ["INST HEALTH_STATUS TEMP1"], "id": 2, "keyword_params":{"type":"WITH_UNITS","scope":"DEFAULT"}}' http://localhost:2900/openc3-api/api  -H "Authorization: password"
```
