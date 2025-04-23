---
sidebar_position: 6
title: インターフェース
description: ビルトインCOSMOSインターフェースと作成方法
sidebar_custom_props:
  myEmoji: 💡
---

## 概要

インターフェースは、[ターゲット](target)と呼ばれる外部の組み込みシステムへの接続です。インターフェースはplugin.txtファイル内のトップレベルの[INTERFACE](plugins.md#interface-1)キーワードで定義されます。

インターフェースクラスは、COSMOSがターゲットからリアルタイムテレメトリを受信し、ターゲットにコマンドを送信するために使用するコードを提供します。ターゲットが使用するインターフェースは何でも可能であり（TCP/IP、シリアル、MQTT、SNMPなど）、これは再利用可能なコマンド・テレメトリシステムのカスタマイズ可能な部分であることが重要です。幸いなことに、最も一般的なインターフェース形式はTCP/IPソケット経由であり、COSMOSはこれらのインターフェースソリューションを提供します。このガイドでは、これらのインターフェースクラスの使用方法と、独自のインターフェースの作成方法について説明します。ほとんどの場合、新しいインターフェースを実装するのではなく、[プロトコル](protocols.md)でインターフェースを拡張できることに注意してください。

:::info インターフェースとルーターは非常に似ています
インターフェースとルーターは非常に似ており、同じ設定パラメータを共有していることに注意してください。ルーターは単に、既存のインターフェースのテレメトリデータを接続されたターゲットに送り出し、接続されたターゲットのコマンドを元のインターフェースのターゲットに戻すインターフェースです。
:::

### プロトコル

プロトコルは、パケット境界の区別やデータの必要に応じた変更など、インターフェースの動作を定義します。詳細については[プロトコル](protocols)を参照してください。

### アクセサ

アクセサはインターフェースによってターゲットに送信されるバッファの読み書きを担当します。詳細については[アクセサ](accessors)を参照してください。

インターフェース、プロトコル、アクセサがどのように連携するかについての詳細は、[標準なしの相互運用性](https://www.openc3.com/news/interoperability-without-standards)を参照してください。

## 提供されるインターフェース

COSMOSは以下のインターフェースを提供しています：TCPIPクライアント、TCPIPサーバー、UDP、HTTPクライアント、HTTPサーバー、MQTTおよびシリアル。使用するインターフェースは[INTERFACE](plugins.md#interface)および[ROUTER](plugins.md#router)キーワードで定義されます。INTERFACEキーワードの後に続くキーワードの説明については、[インターフェース修飾子](plugins.md#interface-modifiers)を参照してください。

COSMOS Enterpriseは次のインターフェースを提供しています：SNMP、SNMPトラップ、GEMS、InfluxDB。

#### すべてのインターフェースオプション

以下のオプションはすべてのインターフェースに適用されます。オプションは例に示すように、インターフェース定義の直下に追加されます。

| オプション     | 説明                                                                                                   |
| -------------- | ------------------------------------------------------------------------------------------------------ |
| PERIODIC_CMD | 定期的な間隔で送信するコマンド。3つのパラメータを取ります：LOG/DONT_LOG、間隔（秒）、および実際のコマンド（文字列）。 |

例：

```ruby
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 10.0
  # 'INST ABORT'コマンドを5秒ごとに送信し、CmdTlmServerメッセージにログを残さない
  # 注：すべてのコマンドはバイナリログに記録されます
  OPTION PERIODIC_CMD DONT_LOG 5.0 "INST ABORT"
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 10.0
  # 'INST2 COLLECT with TYPE NORMAL'コマンドを10秒ごとに送信し、CmdTlmServerメッセージに出力する
  OPTION PERIODIC_CMD LOG 10.0 "INST2 COLLECT with TYPE NORMAL"
```

| オプション    | 説明                                                                                           |
| ------------- | ---------------------------------------------------------------------------------------------- |
| CONNECT_CMD | インターフェースが接続したときに送信するコマンド。2つのパラメータを取ります：LOG/DONT_LOGと実際のコマンド（文字列）。 |

例：

```ruby
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 10.0
  # 接続時に'INST ABORT'コマンドを送信し、CmdTlmServerメッセージにログを残さない
  # 注：すべてのコマンドはバイナリログに記録されます
  OPTION CONNECT_CMD DONT_LOG "INST ABORT"
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 10.0
  # 接続時に'INST2 COLLECT with TYPE NORMAL'を送信し、CmdTlmServerメッセージに出力する
  OPTION CONNECT_CMD LOG "INST2 COLLECT with TYPE NORMAL"
```

### TCPIPクライアントインターフェース

TCPIPクライアントインターフェースはTCPIPソケットに接続してコマンドを送信し、テレメトリを受信します。このインターフェースは、ソケットを開いて接続を待機するターゲット用に使用されます。これは最も一般的なインターフェースタイプです。

| パラメータ         | 説明                                                                                            | 必須    |
| ------------------ | ----------------------------------------------------------------------------------------------- | ------- |
| Host               | 接続するマシン名                                                                                | はい    |
| Write Port         | コマンドを書き込むポート（読み取りポートと同じでも可）。nil / Noneを渡すとインターフェースは読み取り専用になります。 | はい    |
| Read Port          | テレメトリを読み取るポート（書き込みポートと同じでも可）。nil / Noneを渡すとインターフェースは書き込み専用になります。 | はい    |
| Write Timeout      | 書き込みを中止するまで待機する秒数                                                              | はい    |
| Read Timeout       | 読み取りを中止するまで待機する秒数。nil / Noneを渡すと読み取りでブロックします。                | はい    |
| Protocol Type      | プロトコルを参照してください。                                                                  | いいえ  |
| Protocol Arguments | 各ストリームプロトコルが取る引数については、プロトコルを参照してください。                      | いいえ  |

plugin.txt Rubyの例：

```ruby
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil LENGTH 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 nil BURST 4 0xDEADBEEF
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 nil FIXED 6 0 nil true
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 10.0 TERMINATED 0x0D0A 0x0D0A true 0 0xF005BA11
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 10.0 TEMPLATE 0xA 0xA
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 nil PREIDENTIFIED 0xCAFEBABE
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 10.0 # ビルトインプロトコルなし
```

plugin.txt Pythonの例：

```ruby
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 None LENGTH 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 None BURST 4 0xDEADBEEF
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 None FIXED 6 0 None true
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 10.0 TERMINATED 0x0D0A 0x0D0A true 0 0xF005BA11
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 10.0 TEMPLATE 0xA 0xA
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 None PREIDENTIFIED 0xCAFEBABE
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 10.0 # ビルトインプロトコルなし
```

### TCPIPサーバーインターフェース

TCPIPサーバーインターフェースはTCPIPサーバーを作成し、着信接続をリッスンして、ターゲットと通信するソケットを動的に作成します。このインターフェースは、ソケットを開いてサーバーに接続しようとするターゲット用に使用されます。

注意：内部dockerネットワーク外からの接続を受け入れるには、compose.yamlファイルでTCPポートを公開する必要があります。例えば、ポート8080での接続を許可するには、openc3-operatorセクションを見つけて次の例のように変更します：

```yaml
openc3-operator:
  ports:
    - "127.0.0.1:8080:8080" # tcpポート8080を開く
```

| パラメータ         | 説明                                                                             | 必須    |
| ------------------ | -------------------------------------------------------------------------------- | ------- |
| Write Port         | コマンドを書き込むポート（読み取りポートと同じでも可）                          | はい    |
| Read Port          | テレメトリを読み取るポート（書き込みポートと同じでも可）                        | はい    |
| Write Timeout      | 書き込みを中止するまで待機する秒数                                              | はい    |
| Read Timeout       | 読み取りを中止するまで待機する秒数。nil / Noneを渡すと読み取りでブロックします。| はい    |
| Protocol Type      | プロトコルを参照してください。                                                  | いいえ  |
| Protocol Arguments | 各ストリームプロトコルが取る引数については、プロトコルを参照してください。      | いいえ  |

#### インターフェースオプション

オプションは例に示すように、インターフェース定義の直下に追加されます。

| オプション      | 説明                           | デフォルト |
| --------------- | ------------------------------ | ---------- |
| LISTEN_ADDRESS | 接続を受け付けるIPアドレス      | 0.0.0.0    |

plugin.txt Rubyの例：

```ruby
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8081 10.0 nil LENGTH 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8080 10.0 nil BURST 4 0xDEADBEEF
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8080 10.0 nil FIXED 6 0 nil true
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8080 10.0 10.0 TERMINATED 0x0D0A 0x0D0A true 0 0xF005BA11
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8080 10.0 10.0 TEMPLATE 0xA 0xA
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8080 10.0 nil PREIDENTIFIED 0xCAFEBABE
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8080 10.0 10.0 # ビルトインプロトコルなし
  OPTION LISTEN_ADDRESS 127.0.0.1
```

plugin.txt Pythonの例：

```ruby
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8081 10.0 None LENGTH 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8080 10.0 None BURST 4 0xDEADBEEF
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8080 10.0 None FIXED 6 0 None true
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8080 10.0 10.0 TERMINATED 0x0D0A 0x0D0A true 0 0xF005BA11
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8080 10.0 10.0 TEMPLATE 0xA 0xA
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8080 10.0 None PREIDENTIFIED 0xCAFEBABE
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8080 10.0 10.0 # ビルトインプロトコルなし
```

### UDPインターフェース

UDPインターフェースはUDPパケットを使用してターゲットとの間でコマンドの送信とテレメトリの受信を行います。

注意：内部dockerネットワーク外からUDPパケットを受信するには、compose.yamlファイルでUDPポートを公開する必要があります。例えば、ポート8081でUDPパケットを許可するには、openc3-operatorセクションを見つけて次の例のように変更します：

```yaml
openc3-operator:
  ports:
    - "127.0.0.1:8081:8081/udp" # udpポート8081を開く
```

| パラメータ        | 説明                                                                                               | 必須    | デフォルト                                  |
| ----------------- | -------------------------------------------------------------------------------------------------- | ------- | ------------------------------------------- |
| Host              | データの送受信を行うマシンのホスト名またはIPアドレス                                               | はい    |                                             |
| Write Dest Port   | コマンドを送信するリモートマシン上のポート                                                         | はい    |                                             |
| Read Port         | テレメトリを読み取るリモートマシン上のポート                                                       | はい    |                                             |
| Write Source Port | コマンドを送信するローカルマシン上のポート                                                         | いいえ  | nil (ソケットは発信ポートにバインドされない) |
| Interface Address | リモートマシンがマルチキャストをサポートしている場合、インターフェースアドレスは発信マルチキャストアドレスを設定するために使用されます | いいえ  | nil (使用されない)                          |
| TTL               | Time to Live。パケットを破棄する前に許可される中間ルーターの数。                                   | いいえ  | 128 (Windows)                               |
| Write Timeout     | 書き込みを中止するまで待機する秒数                                                                 | いいえ  | 10.0                                        |
| Read Timeout      | 読み取りを中止するまで待機する秒数                                                                 | いいえ  | nil (読み取りでブロック)                    |

plugin.txt Rubyの例：

```ruby
INTERFACE INTERFACE_NAME udp_interface.rb host.docker.internal 8080 8081 8082 nil 128 10.0 nil
```

plugin.txt Pythonの例：

```ruby
INTERFACE INTERFACE_NAME openc3/interfaces/udp_interface.py host.docker.internal 8080 8081 8082 None 128 10.0 None
```

### HTTPクライアントインターフェース

HTTPクライアントインターフェースはHTTPサーバーに接続してコマンドを送信し、テレメトリを受信します。このインターフェースは[HttpAccessor](accessors#http-accessor)および[JsonAccessor](accessors#json-accessor)と共に使用されることが一般的です。詳細については[openc3-cosmos-http-example](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-http-example)を参照してください。

| パラメータ                  | 説明                                                                              | 必須    | デフォルト |
| --------------------------- | --------------------------------------------------------------------------------- | ------- | ---------- |
| Host                        | 接続するマシン名                                                                  | はい    |            |
| Port                        | コマンドを書き込み、テレメトリを読み取るポート                                    | いいえ  | 80         |
| Protocol                    | HTTPまたはHTTPSプロトコル                                                         | いいえ  | HTTP       |
| Write Timeout               | 書き込みを中止するまで待機する秒数。nil / Noneを渡すと書き込みでブロックします。  | いいえ  | 5          |
| Read Timeout                | 読み取りを中止するまで待機する秒数。nil / Noneを渡すと読み取りでブロックします。  | いいえ  | nil / None |
| Connect Timeout             | 接続を中止するまで待機する秒数                                                    | いいえ  | 5          |
| Include Request In Response | リクエストを追加データに含めるかどうか                                           | いいえ  | false      |

plugin.txt Rubyの例：

```ruby
INTERFACE INTERFACE_NAME http_client_interface.rb myserver.com 80
```

plugin.txt Pythonの例：

```ruby
INTERFACE INTERFACE_NAME openc3/interfaces/http_client_interface.py mysecure.com 443 HTTPS
```

### HTTPサーバーインターフェース

HTTPサーバーインターフェースは、シンプルな暗号化されていない、認証されていないHTTPサーバーを作成します。このインターフェースは[HttpAccessor](accessors#http-accessor)および[JsonAccessor](accessors#json-accessor)と共に使用されることが一般的です。詳細については[openc3-cosmos-http-example](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-http-example)を参照してください。

| パラメータ | 説明                                       | 必須    | デフォルト |
| ---------- | ------------------------------------------ | ------- | ---------- |
| Port       | コマンドを書き込み、テレメトリを読み取るポート | いいえ  | 80         |

#### インターフェースオプション

オプションは例に示すように、インターフェース定義の直下に追加されます。

| オプション      | 説明                           | デフォルト |
| --------------- | ------------------------------ | ---------- |
| LISTEN_ADDRESS | 接続を受け付けるIPアドレス      | 0.0.0.0    |

plugin.txt Rubyの例：

```ruby
INTERFACE INTERFACE_NAME http_server_interface.rb
  LISTEN_ADDRESS 127.0.0.1
```

plugin.txt Pythonの例：

```ruby
INTERFACE INTERFACE_NAME openc3/interfaces/http_server_interface.py 88
```

### MQTTインターフェース

MQTTインターフェースは一般的にIoT（Internet of Things）デバイスとの接続に使用されます。COSMOS MQTTインターフェースはメッセージ（コマンドとテレメトリ）の公開と受信の両方ができるクライアントです。SSL証明書と認証のためのサポートが組み込まれています。MQTTストリーミングインターフェースとは、コマンドとテレメトリがコマンドとテレメトリの定義で`META TOPIC`で指定されたトピックを介して送信される点が異なります。

| パラメータ | 説明                                                                             | 必須    | デフォルト |
| ---------- | -------------------------------------------------------------------------------- | ------- | ---------- |
| Host       | MQTTブローカーのホスト名またはIPアドレス                                         | はい    |            |
| Port       | 接続するMQTTブローカー上のポート。SSLを使用するかどうかを考慮してください。     | いいえ  | 1883       |
| SSL        | 接続にSSLを使用するかどうか                                                      | いいえ  | false      |

#### インターフェースオプション

オプションは例に示すように、インターフェース定義の直下に追加されます。

| オプション         | 説明                                                                                |
| ------------------ | ----------------------------------------------------------------------------------- |
| ACK_TIMEOUT       | MQTTブローカーに接続するときに待機する時間                                          |
| USERNAME          | MQTTブローカーとの認証用のユーザー名                                                |
| PASSWORD          | MQTTブローカーとの認証用のパスワード                                                |
| CERT              | クライアントTLSベースの認証にKEYと共に使用されるPEMエンコードされたクライアント証明書ファイル名 |
| KEY               | PEMエンコードされたクライアント秘密鍵ファイル名                                     |
| KEYFILE_PASSWORD  | CERTとKEYファイルを復号化するためのパスワード（Pythonのみ）                        |
| CA_FILE           | このクライアントが信頼すべき認証局証明書ファイル名                                  |

plugin.txt Rubyの例：

```ruby
INTERFACE MQTT_INT mqtt_interface.rb test.mosquitto.org 1883
```

plugin.txt Pythonの例（注：この例では[SECRET](plugins#secret)キーワードを使用してインターフェースのPASSWORDオプションを設定しています）：

```ruby
INTERFACE MQTT_INT openc3/interfaces/mqtt_interface.py test.mosquitto.org 8884
  OPTION USERNAME rw
  # PASSWORDという名前のシークレットでMQTT_PASSWORDという環境変数を作成し、
  # シークレット値を持つPASSWORDというオプションを設定します
  # シークレットの詳細については、管理ツールのページを参照してください
  SECRET ENV PASSWORD MQTT_PASSWORD PASSWORD
```

#### パケット定義

MQTTインターフェースはコマンドとテレメトリの定義ファイルで「META TOPIC &lt;トピック名&gt;」を利用して、メッセージを公開および受信するトピックを決定します。したがって、「TEST」というトピックに送信するには、次のようなコマンドを作成します（注：コマンド名「TEST」はトピック名と一致する必要はありません）：

```
COMMAND MQTT TEST BIG_ENDIAN "Test"
  META TOPIC TEST # <- トピック名は'TEST'
  APPEND_PARAMETER DATA 0 BLOCK '' "MQTT Data"
```

同様に、「TEST」というトピックから受信するには、次のようなテレメトリパケットを作成します（注：テレメトリ名「TEST」はトピック名と一致する必要はありません）：

```
TELEMETRY MQTT TEST BIG_ENDIAN "Test"
  META TOPIC TEST # <- トピック名は'TEST'
  APPEND_ITEM DATA 0 BLOCK "MQTT Data"
```

完全な例については、COSMOSソースの[openc3-cosmos-mqtt-test](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-mqtt-test)を参照してください。

### MQTTストリーミングインターフェース

MQTTストリーミングインターフェースは一般的にIoT（Internet of Things）デバイスとの接続に使用されます。COSMOS MQTTストリーミングインターフェースはメッセージ（コマンドとテレメトリ）の公開と受信の両方ができるクライアントです。SSL証明書と認証のためのサポートが組み込まれています。MQTTインターフェースとは、すべてのコマンドが単一のトピックで送信され、すべてのテレメトリが単一のトピックで受信される点が異なります。

| パラメータ         | 説明                                                                                | 必須    | デフォルト |
| ------------------ | ----------------------------------------------------------------------------------- | ------- | ---------- |
| Host               | MQTTブローカーのホスト名またはIPアドレス                                            | はい    |            |
| Port               | 接続するMQTTブローカー上のポート。SSLを使用するかどうかを考慮してください。        | いいえ  | 1883       |
| SSL                | 接続にSSLを使用するかどうか                                                         | いいえ  | false      |
| Write Topic        | すべてのコマンド用の書き込みトピック名。nil / Noneを渡すとインターフェースは読み取り専用になります。 | いいえ  | nil / None |
| Read Topic         | すべてのテレメトリ用の読み取りトピック名。nil / Noneを渡すとインターフェースは書き込み専用になります。 | いいえ  | nil / None |
| Protocol Type      | プロトコルを参照してください。                                                      | いいえ  |            |
| Protocol Arguments | 各ストリームプロトコルが取る引数については、プロトコルを参照してください。          | いいえ  |            |

#### インターフェースオプション

オプションは例に示すように、インターフェース定義の直下に追加されます。

| オプション         | 説明                                                                                |
| ------------------ | ----------------------------------------------------------------------------------- |
| ACK_TIMEOUT       | MQTTブローカーに接続するときに待機する時間                                          |
| USERNAME          | MQTTブローカーとの認証用のユーザー名                                                |
| PASSWORD          | MQTTブローカーとの認証用のパスワード                                                |
| CERT              | クライアントTLSベースの認証にKEYと共に使用されるPEMエンコードされたクライアント証明書ファイル名 |
| KEY               | PEMエンコードされたクライアント秘密鍵ファイル名                                     |
| KEYFILE_PASSWORD  | CERTとKEYファイルを復号化するためのパスワード（Pythonのみ）                        |
| CA_FILE           | このクライアントが信頼すべき認証局証明書ファイル名                                  |

plugin.txt Rubyの例：

```ruby
INTERFACE MQTT_INT mqtt_stream_interface.rb test.mosquitto.org 1883 false write read
```

plugin.txt Pythonの例（注：この例では[SECRET](plugins#secret)キーワードを使用してインターフェースのPASSWORDオプションを設定しています）：

```ruby
INTERFACE MQTT_INT openc3/interfaces/mqtt_stream_interface.py test.mosquitto.org 8884 False write read
  OPTION USERNAME rw
  # PASSWORDという名前のシークレットでMQTT_PASSWORDという環境変数を作成し、
  # シークレット値を持つPASSWORDというオプションを設定します
  # シークレットの詳細については、管理ツールのページを参照してください
  SECRET ENV PASSWORD MQTT_PASSWORD PASSWORD
```

#### パケット定義

MQTTストリーミングインターフェースはインターフェースに渡されたトピック名を使用するため、定義に追加情報は必要ありません。

完全な例については、COSMOSソースの[openc3-cosmos-mqtt-test](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-mqtt-test)を参照してください。

### シリアルインターフェース

シリアルインターフェースはシリアルポート経由でターゲットに接続します。COSMOSはWindowsとUNIXベースのシステム用のPOSIXドライバの両方を提供しています。シリアルインターフェースは現在Rubyでのみ実装されています。

| パラメータ         | 説明                                                                                         | 必須    |
| ------------------ | -------------------------------------------------------------------------------------------- | ------- |
| Write Port         | 書き込み用のシリアルポート名（例：'COM1'または'/dev/ttyS0'）。nil / Noneを渡すと書き込みを無効にします。 | はい    |
| Read Port          | 読み取り用のシリアルポート名（例：'COM1'または'/dev/ttyS0'）。nil / Noneを渡すと読み取りを無効にします。 | はい    |
| Baud Rate          | 読み書きに使用するボーレート                                                                | はい    |
| Parity             | シリアルポートのパリティ。'NONE'、'EVEN'、'ODD'のいずれかでなければなりません。           | はい    |
| Stop Bits          | ストップビット数（例：1）                                                                   | はい    |
| Write Timeout      | 書き込みを中止するまで待機する秒数                                                          | はい    |
| Read Timeout       | 読み取りを中止するまで待機する秒数。nil / Noneを渡すと読み取りでブロックします。           | はい    |
| Protocol Type      | プロトコルを参照してください。                                                              | いいえ  |
| Protocol Arguments | 各ストリームプロトコルが取る引数については、プロトコルを参照してください。                 | いいえ  |

#### インターフェースオプション

オプションは例に示すように、インターフェース定義の直下に追加されます。

| オプション     | 説明                                              | デフォルト |
| -------------- | ------------------------------------------------- | ---------- |
| FLOW_CONTROL  | シリアルポートのフロー制御。NONEまたはRTSCTSのいずれかでなければなりません。 | NONE     |
| DATA_BITS     | データビット数                                     | 8          |

plugin.txt Rubyの例：

```ruby
INTERFACE INTERFACE_NAME serial_interface.rb COM1 COM1 9600 NONE 1 10.0 nil LENGTH 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
INTERFACE INTERFACE_NAME serial_interface.rb /dev/ttyS1 /dev/ttyS1 38400 ODD 1 10.0 nil BURST 4 0xDEADBEEF
INTERFACE INTERFACE_NAME serial_interface.rb COM2 COM2 19200 EVEN 1 10.0 nil FIXED 6 0 nil true
INTERFACE INTERFACE_NAME serial_interface.rb COM4 COM4 115200 NONE 1 10.0 10.0 TERMINATED 0x0D0A 0x0D0A true 0 0xF005BA11
INTERFACE INTERFACE_NAME serial_interface.rb COM4 COM4 115200 NONE 1 10.0 10.0 TEMPLATE 0xA 0xA
INTERFACE INTERFACE_NAME serial_interface.rb /dev/ttyS0 /dev/ttyS0 57600 NONE 1 10.0 nil PREIDENTIFIED 0xCAFEBABE
INTERFACE INTERFACE_NAME serial_interface.rb COM4 COM4 115200 NONE 1 10.0 10.0 # ビルトインプロトコルなし
  OPTION FLOW_CONTROL RTSCTS
  OPTION DATA_BITS 7
```

### SNMPインターフェース（Enterprise）

SNMPインターフェースは簡易ネットワーク管理プロトコルデバイスへの接続用です。SNMPインターフェースは現在Rubyでのみ実装されています。

| パラメータ | 説明                      | 必須    | デフォルト |
| ---------- | ------------------------- | ------- | ---------- |
| Host       | SNMPデバイスのホスト名    | はい    |            |
| Port       | SNMPデバイス上のポート    | いいえ  | 161        |

#### インターフェースオプション

オプションは例に示すように、インターフェース定義の直下に追加されます。

| オプション       | 説明                                            | デフォルト |
| ---------------- | ----------------------------------------------- | ---------- |
| VERSION         | SNMPバージョン：1、2、または3                   | 1          |
| COMMUNITY       | デバイスへのアクセスを許可するパスワードやユーザーID | private    |
| USERNAME        | ユーザー名                                       | N/A        |
| RETRIES         | リクエスト送信時の再試行回数                     | N/A        |
| TIMEOUT         | エージェントからの応答を待つタイムアウト         | N/A        |
| CONTEXT         | SNMPコンテキスト                                 | N/A        |
| SECURITY_LEVEL  | NO_AUTH、AUTH_PRIV、AUTH_NO_PRIVのいずれかでなければなりません | N/A        |
| AUTH_PROTOCOL   | MD5、SHA、SHA256のいずれかでなければなりません   | N/A        |
| PRIV_PROTOCOL   | DESまたはAESのいずれかでなければなりません       | N/A        |
| AUTH_PASSWORD   | 認証パスワード                                   | N/A        |
| PRIV_PASSWORD   | プライバシーパスワード                           | N/A        |

plugin.txt Rubyの例：

```ruby
INTERFACE SNMP_INT snmp_interface.rb 192.168.1.249 161
  OPTION VERSION 1
```

完全な例については、COSMOS Enterpriseプラグインの[openc3-cosmos-apc-switched-pdu](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-apc-switched-pdu)を参照してください。

### SNMPトラップインターフェース（Enterprise）

SNMPトラップインターフェースは簡易ネットワーク管理プロトコルトラップを受信するためのものです。SNMPトラップインターフェースは現在Rubyでのみ実装されています。

| パラメータ    | 説明                     | 必須    | デフォルト |
| ------------- | ------------------------ | ------- | ---------- |
| Read Port     | 読み取り元のポート       | いいえ  | 162        |
| Read Timeout  | 読み取りタイムアウト     | いいえ  | nil        |
| Bind Address  | UDPポートをバインドするアドレス | はい    | 0.0.0.0    |

#### インターフェースオプション

オプションは例に示すように、インターフェース定義の直下に追加されます。

| オプション | 説明                   | デフォルト |
| ---------- | ---------------------- | ---------- |
| VERSION   | SNMPバージョン：1、2、または3 | 1       |

plugin.txt Rubyの例：

```ruby
INTERFACE SNMP_INT snmp_trap_interface.rb 162
  OPTION VERSION 1
```

完全な例については、COSMOS Enterpriseプラグインの[openc3-cosmos-apc-switched-pdu](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-apc-switched-pdu)を参照してください。

### gRPCインターフェース（Enterprise）

gRPCインターフェースは[gRPC](https://grpc.io/)と対話するためのものです。gRPCインターフェースは現在Rubyでのみ実装されています。

| パラメータ | 説明       | 必須    |
| ---------- | ---------- | ------- |
| Hostname   | gRPCサーバー | はい    |
| Port       | gRPCポート  | はい    |

plugin.txt Rubyの例：

```ruby
INTERFACE GRPC_INT grpc_interface.rb my.grpc.org 8080
```

#### コマンド

GrpcInterfaceを[コマンド定義](command)に使用するには、各コマンドに使用するGRPC_METHODを定義するために[META](command#meta)を使用する必要があります。

```ruby
COMMAND PROTO GET_USER BIG_ENDIAN 'Get a User'
  META GRPC_METHOD /example.photoservice.ExamplePhotoService/GetUser
```

完全な例については、COSMOS Enterpriseプラグインの[openc3-cosmos-proto-target](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-proto-target)を参照してください。

## カスタムインターフェース

インターフェースには、実装する必要のある以下のメソッドがあります：

1. **connect** - ソケットやポートを開いたり、ターゲットへの接続を確立したりします。注意：このメソッドは無期限にブロックすることはできません。実装内でsuper()を呼び出すことを忘れないでください。
1. **connected?** - 接続状態に応じてtrueまたはfalseを返します。注意：このメソッドはすぐに戻る必要があります。
1. **disconnect** - ソケットやポートを閉じたり、ターゲットから切断したりします。注意：このメソッドは無期限にブロックすることはできません。実装内でsuper()を呼び出すことを忘れないでください。
1. **read_interface** - インターフェース上のデータの最低レベルの読み取り。注意：このメソッドはデータが利用可能になるか、インターフェースが切断されるまでブロックする必要があります。クリーンな切断の場合はnilを返す必要があります。
1. **write_interface** - インターフェース上のデータの最低レベルの書き込み。注意：このメソッドは無期限にブロックすることはできません。

インターフェースには以下のメソッドも存在し、デフォルト実装があります。必要に応じてオーバーライドできますが、デフォルト実装が実行されるようにsuper()を呼び出すことを忘れないでください。

1. **read_interface_base** - このメソッドは常にread_interface()から呼び出されるべきです。読み取ったバイト数、最近読み取られた生データなど、CmdTLmServerに表示されるインターフェース固有の変数を更新し、有効な場合は生ロギングを処理します。
1. **write_interface_base** - このメソッドは常にwrite_interface()から呼び出されるべきです。書き込んだバイト数、最近書き込まれた生データなど、CmdTLmServerに表示されるインターフェース固有の変数を更新し、有効な場合は生ロギングを処理します。
1. **read** - インターフェースから次のパケットを読み取ります。COSMOSはこのメソッドを実装して、返される前にプロトコルシステムがデータとパケットを操作できるようにします。
1. **write** - パケットをインターフェースに送信します。COSMOSはこのメソッドを実装して、送信される前にプロトコルシステムがパケットとデータを操作できるようにします。
1. **write_raw** - 生のバイナリデータ文字列をターゲットに送信します。COSMOSはこのメソッドを実装して、基本的に生データでwrite_interfaceを呼び出します。

:::warning 命名規則
独自のインターフェースを作成する場合、ほとんどの場合、以下に説明する組み込みインターフェースのサブクラスになります。インターフェースファイルのファイル名とクラス名は、大文字と小文字を正確に一致させる必要があることを知っておくことが重要です。そうしないと、新しいインターフェースをロードしようとするときに「クラスが見つかりません」というエラーが発生します。例えば、labview_interface.rbというインターフェースファイルには、LabviewInterfaceというクラスが含まれている必要があります。例えば、クラスがLabVIEWInterfaceという名前だった場合、予期しない大文字と小文字のためにCOSMOSはクラスを見つけることができません。
:::