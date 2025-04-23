---
sidebar_position: 2
title: プラグイン
description: プラグイン定義ファイルのフォーマットとキーワード
sidebar_custom_props:
  myEmoji: 🔌
---

<!-- Be sure to edit _plugins.md because plugins.md is a generated file -->

## はじめに

このドキュメントは、COSMOSプラグインを設定するために必要な情報を提供します。プラグインはCOSMOSを設定および拡張する方法です。

プラグインでは、ターゲット（およびそれに対応するコマンドとテレメトリパケット定義）を定義し、ターゲットと通信するために必要なインターフェースを設定し、COSMOSから生データをストリームするためのルーターを定義し、COSMOSユーザーインターフェースに新しいツールを追加する方法、そして新しい機能を提供するための追加のマイクロサービスを実行する方法を定義します。

各プラグインはRubyのgemとして構築されるため、プラグインをビルドするためのplugin.gemspecファイルを持っています。プラグインには、プラグインで使用されるすべての変数と、それに含まれるターゲットへのインターフェース方法を宣言するplugin.txtファイルがあります。

## 概念

### TARGET

ターゲットは、COSMOSが通信する外部のハードウェアやソフトウェアです。これらは、フロントエンドプロセッサ（FEP）、地上支援機器（GSE）、カスタムソフトウェアツール、衛星自体などのハードウェアなどです。ターゲットは、COSMOSがコマンドを送信し、テレメトリを受信できるものです。

### INTERFACE

インターフェースは、1つ以上のターゲットへの物理的な接続を実装します。通常、TCPやUDPを使用したイーサネット接続ですが、シリアルポートなどの他の接続も可能です。インターフェースはターゲットにコマンドを送信し、ターゲットからテレメトリを受信します。

### ROUTER

ルーターは、テレメトリパケットのストリームをCOSMOSから流出させ、コマンドのストリームをCOSMOSに受信します。コマンドはCOSMOSによって関連するインターフェースに転送されます。テレメトリは関連するインターフェースから来ます。

### TOOL

COSMOSツールは、テレメトリの表示、コマンドの送信、スクリプトの実行などのタスクを実行するためにCOSMOS APIと通信するウェブベースのアプリケーションです。

### MICROSERVICE

マイクロサービスは、COSMOS環境内で実行される永続的なバックエンドコードです。データを処理し、その他の有用なタスクを実行できます。

## プラグインのディレクトリ構造

COSMOSプラグインには、[コードジェネレーター](../getting-started/generators)のドキュメントに詳細に記載されている、明確に定義されたディレクトリ構造があります。

## plugin.txt 設定ファイル

plugin.txt設定ファイルは、すべてのCOSMOSプラグインに必要です。これはプラグインの内容を宣言し、プラグインが最初にインストールまたはアップグレードされるときに設定できる変数を提供します。
このファイルは、キーワードの後に0個以上のスペース区切りのパラメータが続く標準のCOSMOS設定ファイル形式に従っています。plugin.txt設定ファイルでサポートされる以下のキーワードがあります：


## VARIABLE
**プラグインの設定可能な変数を定義する**

VARIABLEキーワードは、プラグインのインストール中にユーザーが入力を求められる変数を定義します。変数は、特定のIPアドレスやポートなど、ユーザーが定義するターゲットの詳細を処理するために使用できます。また、変数は、ユーザーがターゲットを好きな名前に変更し、同じターゲットを異なる名前で複数インストールすることをサポートするためにも使用する必要があります。変数は、Ruby ERB構文を使用してplugin.txtまたはプラグインに含まれる他の設定ファイルで後で使用できます。変数はファイル内のアクセス可能なローカル変数に割り当てられます。高レベルでは、ERBを使用すると設定ファイル内でRubyコードを実行できます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Variable Name | 変数の名前 | True |
| Default Value | 変数のデフォルト値 | True |

## NEEDS_DEPENDENCIES
<div class="right">(Since 5.5.0)</div>**プラグインが依存関係を必要とし、GEM_HOME環境変数を設定することを示す**

プラグインにトップレベルのlibフォルダがある場合、またはgemspecにランタイム依存関係がリストされている場合、NEEDS_DEPENDENCIESは実質的に既に設定されています。Enterprise版では、NEEDS_DEPENDENCIESを持つことで、KubernetesポッドにNFSボリュームマウントが追加されることに注意してください。


## INTERFACE
**物理的なターゲットへの接続を定義する**

インターフェースは、OpenC3が特定のハードウェアと通信するために使用するものです。インターフェースには、ハードウェアと通信するために必要なすべてのインターフェースメソッドを実装するRubyまたはPythonファイルが必要です。OpenC3は多くの組み込みインターフェースを定義していますが、インターフェースプロトコルを実装する限り、独自のインターフェースを定義することもできます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Interface Name | インターフェースの名前。この名前はサーバーのインターフェースタブに表示され、他のキーワードからも参照されます。OpenC3の慣例では、インターフェースにはターゲットの名前に '_INT' を付けた名前を付けます。例えば、INSTターゲットの場合は INST_INT です。 | True |
| Filename | インターフェースをインスタンス化する際に使用するRubyまたはPythonファイル。<br/><br/>有効な値: <span class="values">tcpip_client_interface, tcpip_server_interface, udp_interface, serial_interface</span> | True |

追加のパラメータが必要です。詳細については、[インターフェース](../configuration/interfaces.md)のドキュメントを参照してください。

## INTERFACE MODIFIERS
以下のキーワードはINTERFACEキーワードに続いて使用する必要があります。

### MAP_TARGET
**ターゲット名をインターフェースにマッピングする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | このインターフェースにマッピングするターゲット名 | True |

Rubyの例:
```ruby
INTERFACE DATA_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TARGET DATA
```

Pythonの例:
```python
INTERFACE DATA_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TARGET DATA
```

### MAP_CMD_TARGET
<div class="right">(Since 5.2.0)</div>**コマンド専用のターゲット名をインターフェースにマッピングする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | このインターフェースにマッピングするコマンドターゲット名 | True |

Rubyの例:
```ruby
INTERFACE CMD_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil BURST
  MAP_CMD_TARGET DATA # DATAコマンドのみがCMD_INTインターフェースで送信される
```

Pythonの例:
```python
INTERFACE CMD_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 nil BURST
  MAP_CMD_TARGET DATA # DATAコマンドのみがCMD_INTインターフェースで送信される
```

### MAP_TLM_TARGET
<div class="right">(Since 5.2.0)</div>**テレメトリ専用のターゲット名をインターフェースにマッピングする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | このインターフェースにマッピングするテレメトリターゲット名 | True |

Rubyの例:
```ruby
INTERFACE TLM_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TLM_TARGET DATA # DATAテレメトリのみがTLM_INTインターフェースで受信される
```

Pythonの例:
```python
INTERFACE TLM_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TLM_TARGET DATA # DATAテレメトリのみがTLM_INTインターフェースで受信される
```

### DONT_CONNECT
**サーバーは起動時にインターフェースに自動的に接続しようとしない**


### DONT_RECONNECT
**接続が失われた場合、サーバーはインターフェースに再接続しようとしない**


### RECONNECT_DELAY
**再接続の遅延（秒）**

DONT_RECONNECTが存在しない場合、接続が失われるとサーバーはインターフェースへの再接続を試みます。再接続遅延は、再接続試行の間隔を秒単位で設定します。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Delay | 再接続試行の間隔（秒）。デフォルトは15秒です。 | True |

### DISABLE_DISCONNECT
**サーバーのインターフェースタブの切断ボタンを無効にする**

このキーワードを使用して、ユーザーがインターフェースから切断できないようにします。これは通常、ユーザーが誤ってターゲットから切断することを防ぎたい「本番」環境で使用されます。


### LOG_RAW
**非推奨、LOG_STREAMを使用してください**


### LOG_STREAM
<div class="right">(Since 5.5.2)</div>**インターフェースのすべてのデータを送受信されたままの形式で記録する**

LOG_STREAMはOpenC3ヘッダーを追加しないため、OpenC3ツールで読み取ることはできません。主にインターフェースの低レベルデバッグに役立ちます。これらのログは、16進エディタなどのアプリケーションを使用して手動で解析する必要があります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Cycle Time | ログファイルをサイクルする前に待機する時間。デフォルトは10分。nilの場合はCycle HourとCycle Minuteを参照します。 | False |
| Cycle Size | ログファイルをサイクルする前に書き込むデータ量。デフォルトは50MB。 | False |
| Cycle Hour | ログをサイクルする時刻。Cycle Minuteと組み合わせて、指定された時刻に毎日ログをサイクルします。nilの場合、ログは指定されたCycle Minuteに毎時サイクルされます。Cycle Timeがnilの場合にのみ適用されます。 | False |
| Cycle Minute | Cycle Hourを参照してください。 | False |

使用例:
```ruby
INTERFACE EXAMPLE example_interface.rb
  # デフォルトのログ時間600をオーバーライド
  LOG_STREAM 60
```

### PROTOCOL
<div class="right">(Since 4.0.0)</div>**プロトコルはデータを処理することでインターフェースを修正する**

プロトコルはREAD、WRITE、またはREAD_WRITEのいずれかになります。READプロトコルはインターフェースが受信したデータに作用し、WRITEは送信される前のデータに作用します。READ_WRITEはプロトコルを読み書きの両方に適用します。<br/><br/> 独自のカスタムプロトコルの作成についての情報は、[プロトコル](../configuration/protocols.md)を参照してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Type | プロトコルを受信データ、送信データ、またはその両方に適用するかどうか<br/><br/>有効な値: <span class="values">READ, WRITE, READ_WRITE</span> | True |
| Protocol Filename or Classname | プロトコルを実装するRubyまたはPythonのファイル名またはクラス名 | True |
| Protocol specific parameters | プロトコルで使用される追加パラメータ | False |

Rubyの例:
```ruby
INTERFACE DATA_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil nil
  MAP_TARGET DATA
  # INTERFACE行でLENGTHプロトコルを定義するのではなく、ここで定義します
  PROTOCOL READ LengthProtocol 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
```

Pythonの例:
```python
INTERFACE DATA_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TARGET DATA
  PROTOCOL READ IgnorePacketProtocol INST IMAGE # すべてのINST IMAGEパケットをドロップする
```

### OPTION
**インターフェースにパラメータを設定する**

オプションが設定されると、インターフェースクラスはset_optionメソッドを呼び出します。カスタムインターフェースはset_optionをオーバーライドして、追加のオプションを処理できます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | 設定するオプション。OpenC3はコア提供インターフェースにいくつかのオプションを定義しています。SerialInterfaceはFLOW_CONTROL（NONE（デフォルト）またはRTSCTS）とDATA_BITS（シリアルインターフェースのデータビットを変更する）を定義します。TcpipServerInterfaceとHttpServerInterfaceはLISTEN_ADDRESS（接続を受け付けるIPアドレス、デフォルトは0.0.0.0）を定義します。 | True |
| Parameters | オプションに渡すパラメータ | False |

使用例:
```ruby
INTERFACE SERIAL_INT serial_interface.rb COM1 COM1 115200 NONE 1 10.0 nil
  OPTION FLOW_CONTROL RTSCTS
  OPTION DATA_BITS 8
ROUTER SERIAL_ROUTER tcpip_server_interface.rb 2950 2950 10.0 nil BURST
  ROUTE SERIAL_INT
  OPTION LISTEN_ADDRESS 127.0.0.1
```

### SECRET
<div class="right">(Since 5.3.0)</div>**このインターフェースが必要とする秘密を定義する**

このインターフェースの秘密を定義し、オプションでその値をオプションに割り当てます。詳細については、[管理者のシークレット](/docs/tools/admin#シークレット)を参照してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Type | ENVまたはFILE。ENVは秘密を環境変数にマウントします。FILEは秘密をファイルにマウントします。 | True |
| Secret Name | 管理者/シークレットタブから取得する秘密の名前。詳細については、[管理者のシークレット](/docs/tools/admin#シークレット)を参照してください。 | True |
| Environment Variable or File Path | 秘密を格納する環境変数名またはファイルパス。Option Nameを使用して秘密の値にオプションを設定する場合、この値は一意である限り、実際には重要ではないことに注意してください。 | True |
| Option Name | 秘密の値を渡すインターフェースオプション。これは秘密をインターフェースに渡す主要な方法です。 | False |
| Secret Store Name | マルチパートキーを持つストアのシークレットストア名 | False |

使用例:
```ruby
SECRET ENV USERNAME ENV_USERNAME USERNAME
SECRET FILE KEY "/tmp/DATA/cert" KEY
```

### ENV
<div class="right">(Since 5.7.0)</div>**マイクロサービスに環境変数を設定する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Key | 環境変数名 | True |
| Value | 環境変数値 | True |

使用例:
```ruby
ENV COMPANY OpenC3
```

### WORK_DIR
<div class="right">(Since 5.7.0)</div>**作業ディレクトリを設定する**

マイクロサービスのCMDを実行する作業ディレクトリ。プラグイン内のマイクロサービスフォルダからの相対パス、またはマイクロサービスが実行されるコンテナ内の絶対パスのいずれかです。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Directory | マイクロサービスのCMDを実行する作業ディレクトリ。プラグイン内のマイクロサービスフォルダからの相対パス、またはマイクロサービスが実行されるコンテナ内の絶対パスのいずれかです。 | True |

使用例:
```ruby
WORK_DIR '/openc3/lib/openc3/microservices'
```

### PORT
<div class="right">(Since 5.7.0)</div>**マイクロサービスのポートを開く**

Kubernetesがポートを開くためにServiceを適用する必要があるため、Kubernetesサポートにはこれが必要です

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Number | ポート番号 | True |
| Protocol | ポートプロトコル。デフォルトはTCPです。 | False |

使用例:
```ruby
PORT 7272
```

### CMD
<div class="right">(Since 5.7.0)</div>**マイクロサービスを実行するためのコマンドライン**

マイクロサービスを実行するために実行するコマンドライン。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Args | マイクロサービスを実行するためにexecする1つ以上の引数。 | True |

Rubyの例:
```ruby
CMD ruby interface_microservice.rb DEFAULT__INTERFACE__INT1
```

Pythonの例:
```python
CMD python interface_microservice.py DEFAULT__INTERFACE__INT1
```

### CONTAINER
<div class="right">(Since 5.7.0)</div>**Dockerコンテナ**

マイクロサービスを実行するコンテナ。COSMOS Enterprise Editionでのみ使用されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Args | コンテナの名前 | False |

### ROUTE_PREFIX
<div class="right">(Since 5.7.0)</div>**ルートのプレフィックス**

Traefikで外部に公開するマイクロサービスへのルートのプレフィックス

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Route Prefix | ルートプレフィックス。すべてのスコープで一意である必要があります。/myprefixのようなもの | True |

使用例:
```ruby
ROUTE_PREFIX /interface
```

### SHARD
<div class="right">(Since 6.0.0)</div>**ターゲットマイクロサービスを実行するオペレーターシャード**

オペレーターシャード。複数のオペレーターコンテナ（通常はKubernetesで）を実行している場合にのみ使用されます

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Shard | 0から始まるシャード番号 | False |

使用例:
```ruby
SHARD 0
```

## ROUTER
**一つ以上のインターフェースからコマンドを受信し、テレメトリパケットを出力するルーターを作成する**

リモートクライアントからコマンドパケットを受信し、それらを関連するインターフェースに送信するルーターを作成します。インターフェースからテレメトリパケットを受信し、それらをリモートクライアントに送信します。これにより、ルーターは外部クライアントと実際のデバイスの間の仲介者になることができます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | ルーターの名前 | True |
| Filename | インターフェースをインスタンス化する際に使用するRubyまたはPythonファイル。<br/><br/>有効な値: <span class="values">tcpip_client_interface, tcpip_server_interface, udp_interface, serial_interface</span> | True |

追加のパラメータが必要です。詳細については、[インターフェース](../configuration/interfaces.md)のドキュメントを参照してください。

## TARGET
**新しいターゲットを定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Folder Name | ターゲットフォルダ | True |
| Name | ターゲット名。これはほとんどの場合、Folder Nameと同じですが、同じターゲットフォルダに基づいて複数のターゲットを作成するために異なる場合があります。 | True |

使用例:
```ruby
TARGET INST INST
```

## TARGET MODIFIERS
以下のキーワードはTARGETキーワードに続いて使用する必要があります。

### CMD_BUFFER_DEPTH
<div class="right">(Since 5.2.0)</div>**順序どおりにログに記録されることを確実にするためにバッファリングするコマンドの数**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Buffer Depth | パケット単位のバッファ深度（デフォルト = 5） | True |

### CMD_LOG_CYCLE_TIME
**コマンドバイナリログは時間間隔でサイクルさせることができます**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | ファイル間の最大時間（秒）（デフォルト = 600） | True |

### CMD_LOG_CYCLE_SIZE
**コマンドバイナリログは、特定のログファイルサイズに達した後にサイクルさせることができます**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Size | 最大ファイルサイズ（バイト単位）（デフォルト = 50_000_000） | True |

### CMD_LOG_RETAIN_TIME
**生のコマンドログを保持する期間（秒）**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | 生のコマンドログを保持する秒数（デフォルト = nil = 永久） | True |

### CMD_DECOM_LOG_CYCLE_TIME
**コマンドデコミュテーションログは時間間隔でサイクルさせることができます**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | ファイル間の最大時間（秒）（デフォルト = 600） | True |

### CMD_DECOM_LOG_CYCLE_SIZE
**コマンドデコミュテーションログは、特定のログファイルサイズに達した後にサイクルさせることができます**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Size | 最大ファイルサイズ（バイト単位）（デフォルト = 50_000_000） | True |

### CMD_DECOM_LOG_RETAIN_TIME
**デコミュテーションコマンドログを保持する期間（秒）**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | デコミュテーションコマンドログを保持する秒数（デフォルト = nil = 永久） | True |

### TLM_BUFFER_DEPTH
<div class="right">(Since 5.2.0)</div>**順序どおりにログに記録されることを確実にするためにバッファリングするテレメトリパケットの数**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Buffer Depth | パケット単位のバッファ深度（デフォルト = 60） | True |

### TLM_LOG_CYCLE_TIME
**テレメトリバイナリログは時間間隔でサイクルさせることができます**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | ファイル間の最大時間（秒）（デフォルト = 600） | True |

### TLM_LOG_CYCLE_SIZE
**テレメトリバイナリログは、特定のログファイルサイズに達した後にサイクルさせることができます**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Size | 最大ファイルサイズ（バイト単位）（デフォルト = 50_000_000） | True |

### TLM_LOG_RETAIN_TIME
**生のテレメトリログを保持する期間（秒）**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | 生のテレメトリログを保持する秒数（デフォルト = nil = 永久） | True |

### TLM_DECOM_LOG_CYCLE_TIME
**テレメトリデコミュテーションログは時間間隔でサイクルさせることができます**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | ファイル間の最大時間（秒）（デフォルト = 600） | True |

### TLM_DECOM_LOG_CYCLE_SIZE
**テレメトリデコミュテーションログは、特定のログファイルサイズに達した後にサイクルさせることができます**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Size | 最大ファイルサイズ（バイト単位）（デフォルト = 50_000_000） | True |

### TLM_DECOM_LOG_RETAIN_TIME
**デコミュテーションテレメトリログを保持する期間（秒）**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | デコミュテーションテレメトリログを保持する秒数（デフォルト = nil = 永久） | True |

### REDUCED_MINUTE_LOG_RETAIN_TIME
**縮小された分テレメトリログを保持する期間（秒）**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | 縮小された分テレメトリログを保持する秒数（デフォルト = nil = 永久） | True |

### REDUCED_HOUR_LOG_RETAIN_TIME
**縮小された時間テレメトリログを保持する期間（秒）**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | 縮小された時間テレメトリログを保持する秒数（デフォルト = nil = 永久） | True |

### REDUCED_DAY_LOG_RETAIN_TIME
**縮小された日テレメトリログを保持する期間（秒）**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | 縮小された日テレメトリログを保持する秒数（デフォルト = nil = 永久） | True |

### LOG_RETAIN_TIME
**すべての通常のテレメトリログを保持する期間（秒）**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | すべての通常のテレメトリログを保持する秒数（デフォルト = nil = 永久） | True |

### REDUCED_LOG_RETAIN_TIME
**すべての縮小されたテレメトリログを保持する期間（秒）**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | すべての縮小されたテレメトリログを保持する秒数（デフォルト = nil = 永久） | True |

### CLEANUP_POLL_TIME
**クリーンアッププロセスを実行する周期**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Time | クリーンアッププロセスの実行間隔の秒数（デフォルト = 600 = 10分） | True |

### REDUCER_DISABLE
**ターゲットのデータ削減マイクロサービスを無効にする**


### REDUCER_MAX_CPU_UTILIZATION
**データ削減に適用するCPU使用率の最大量**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Percentage | 0から100パーセント（デフォルト = 30） | True |

### TARGET_MICROSERVICE
<div class="right">(Since 5.2.0)</div>**ターゲットマイクロサービスを独自のプロセスに分割する**

処理が遅れているリソースにより多くのリソースを与えるために使用できます。同じタイプに対して複数回定義すると、複数のプロセスが作成されます。各プロセスは、PACKETキーワードで処理する特定のパケットを指定できます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Type | ターゲットマイクロサービスのタイプ。DECOM、COMMANDLOG、DECOMCMDLOG、PACKETLOG、DECOMLOG、REDUCER、またはCLEANUPのいずれかでなければなりません | True |

### PACKET
<div class="right">(Since 5.2.0)</div>**現在のTARGET_MICROSERVICEに割り当てるパケット名**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Packet Name | パケット名。REDUCERまたはCLEANUPターゲットマイクロサービスタイプには適用されません。 | True |

### DISABLE_ERB
<div class="right">(Since 5.12.0)</div>**ERB処理を無効にする**

ターゲット全体またはそのファイル名に対する一連の正規表現のERB処理を無効にします

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Regex | ファイル名に対して一致する正規表現。一致する場合、ERB処理は行われません | False |

### SHARD
<div class="right">(Since 6.0.0)</div>**ターゲットマイクロサービスを実行するオペレーターシャード**

オペレーターシャード。複数のオペレーターコンテナ（通常はKubernetesで）を実行している場合にのみ使用されます

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Shard | 0から始まるシャード番号 | False |

使用例:
```ruby
SHARD 0
```

## MICROSERVICE
**新しいマイクロサービスを定義する**

プラグインがOpenC3システムに追加するマイクロサービスを定義します。マイクロサービスは、永続的な処理を実行するバックグラウンドソフトウェアプロセスです。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Microservice Folder Name | プラグイン内のマイクロサービスフォルダの正確な名前。例：microservices/MicroserviceFolderName | True |
| Microservice Name | OpenC3システム内のこのマイクロサービスインスタンスの特定の名前 | True |

使用例:
```ruby
MICROSERVICE EXAMPLE openc3-example
```

## MICROSERVICE修飾子
以下のキーワードはMICROSERVICEキーワードに続いて使用する必要があります。

### ENV
**マイクロサービスに環境変数を設定する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Key | 環境変数名 | True |
| Value | 環境変数値 | True |

使用例:
```ruby
MICROSERVICE EXAMPLE openc3-example
  ENV COMPANY OpenC3
```

### WORK_DIR
**作業ディレクトリを設定する**

マイクロサービスのCMDを実行する作業ディレクトリ。プラグイン内のマイクロサービスフォルダからの相対パス、またはマイクロサービスが実行されるコンテナ内の絶対パスのいずれかです。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Directory | マイクロサービスのCMDを実行する作業ディレクトリ。プラグイン内のマイクロサービスフォルダからの相対パス、またはマイクロサービスが実行されるコンテナ内の絶対パスのいずれかです。 | True |

使用例:
```ruby
MICROSERVICE EXAMPLE openc3-example
  WORK_DIR .
```

### PORT
<div class="right">(Since 5.0.10)</div>**マイクロサービスのポートを開く**

Kubernetesがポートを開くためにServiceを適用する必要があるため、Kubernetesサポートにはこれが必要です

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Number | ポート番号 | True |
| Protocol | ポートプロトコル。デフォルトはTCPです。 | False |

使用例:
```ruby
MICROSERVICE EXAMPLE openc3-example
  PORT 7272
```

### TOPIC
**Redisトピックを関連付ける**

このマイクロサービスに関連付けるRedisトピック。decom_microserviceなどの標準的なOpenC3マイクロサービスは、この情報を使用して、購読するパケットストリームを知ります。TOPICキーワードは、必要なすべてのトピックを関連付けるために必要なだけ使用できます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Topic Name | マイクロサービスに関連付けるRedisトピック | True |

使用例:
```ruby
MICROSERVICE EXAMPLE openc3-example
  # トピックを手動で割り当てることは高度なトピックであり、
  # 内部COSMOS データ構造の詳細な知識が必要です。
  TOPIC DEFAULT__openc3_log_messages
  TOPIC DEFAULT__TELEMETRY__EXAMPLE__STATUS
```

### TARGET_NAME
**OpenC3ターゲットを関連付ける**

マイクロサービスに関連付けるOpenC3ターゲット。decom_microserviceなどの標準的なOpenC3マイクロサービスでは、これによりターゲット設定がマイクロサービスのコンテナにロードされます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | マイクロサービスに関連付けるOpenC3ターゲット | True |

使用例:
```ruby
MICROSERVICE EXAMPLE openc3-example
  TARGET_NAME EXAMPLE
```

### CMD
**マイクロサービスを実行するためのコマンドライン**

マイクロサービスを実行するために実行するコマンドライン。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Args | マイクロサービスを実行するためにexecする1つ以上の引数。 | True |

Rubyの例:
```ruby
MICROSERVICE EXAMPLE openc3-example
  CMD ruby example_target.rb
```

Pythonの例:
```python
MICROSERVICE EXAMPLE openc3-example
  CMD python example_target.py
```

### OPTION
**マイクロサービスにオプションを渡す**

マイクロサービスに渡す汎用キー/値オプション。これらはOpenC3設定ファイルの行のようにKEYWORD/PARAMSの形式を取ります。複数のOPTIONキーワードを使用して、複数のオプションをマイクロサービスに渡すことができます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Option Name | オプションの名前 | True |
| Option Value(s) | オプションに関連付ける1つ以上の値 | True |

### CONTAINER
**Dockerコンテナ**

マイクロサービスを実行するコンテナ。COSMOS Enterprise Editionでのみ使用されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Args | コンテナの名前 | False |

### SECRET
<div class="right">(Since 5.3.0)</div>**このマイクロサービスが必要とする秘密を定義する**

このマイクロサービスの秘密を定義します。詳細については、[管理者のシークレット](/docs/tools/admin#シークレット)を参照してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Type | ENVまたはFILE。ENVは秘密を環境変数にマウントします。FILEは秘密をファイルにマウントします。 | True |
| Secret Name | 管理者/シークレットタブから取得する秘密の名前。詳細については、[管理者のシークレット](/docs/tools/admin#シークレット)を参照してください。 | True |
| Environment Variable or File Path | 秘密を格納する環境変数名またはファイルパス | True |
| Secret Store Name | マルチパートキーを持つストアのシークレットストア名 | False |

使用例:
```ruby
SECRET ENV USERNAME ENV_USERNAME
SECRET FILE KEY "/tmp/DATA/cert"
```

### ROUTE_PREFIX
<div class="right">(Since 5.5.0)</div>**ルートのプレフィックス**

Traefikで外部に公開するマイクロサービスへのルートのプレフィックス

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Route Prefix | ルートプレフィックス。すべてのスコープで一意である必要があります。/myprefixのようなもの | True |

使用例:
```ruby
MICROSERVICE CFDP CFDP
  ROUTE_PREFIX /cfdp
```

### DISABLE_ERB
<div class="right">(Since 5.12.0)</div>**ERB処理を無効にする**

マイクロサービス全体またはそのファイル名に対する一連の正規表現のERB処理を無効にします

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Regex | ファイル名に対して一致する正規表現。一致する場合、ERB処理は行われません | False |

### SHARD
<div class="right">(Since 6.0.0)</div>**ターゲットマイクロサービスを実行するオペレーターシャード**

オペレーターシャード。複数のオペレーターコンテナ（通常はKubernetesで）を実行している場合にのみ使用されます

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Shard | 0から始まるシャード番号 | False |

使用例:
```ruby
SHARD 0
```

### STOPPED
<div class="right">(Since 6.2.0)</div>**初期的にマイクロサービスを停止状態（有効でない）で作成する**


使用例:
```ruby
STOPPED
```

## TOOL
**ツールを定義する**

プラグインがOpenC3システムに追加するツールを定義します。ツールは、Single-SPAjavascriptライブラリを利用するウェブベースのアプリケーションで、独立したフロントエンドマイクロサービスとして実行中のシステムに動的に追加できます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Tool Folder Name | プラグイン内のツールフォルダの正確な名前。例：tools/ToolFolderName | True |
| Tool Name | OpenC3ナビゲーションメニューに表示されるツールの名前 | True |

使用例:
```ruby
TOOL DEMO Demo
```

## TOOL修飾子
以下のキーワードはTOOLキーワードに続いて使用する必要があります。

### URL
**ツールにアクセスするために使用されるURL**

ツールにアクセスするための相対URL。デフォルトは"/tools/ToolFolderName"です。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Url | URL。指定されない場合、デフォルトはtools/ToolFolderNameです。通常、外部ツールにリンクする場合を除いて指定する必要はありません。 | True |

### INLINE_URL
**ツールをロードするための内部URL**

ツールをsingle-SPAにロードするために使用されるjavascriptファイルのURL。デフォルトは"main.js"です。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Url | インラインURL。指定されない場合、デフォルトはmain.jsです。通常、非標準のファイル名を使用する場合を除いて指定する必要はありません。 | True |

### WINDOW
**ナビゲーション時にツールを表示する方法**

ツールを表示するためのウィンドウモード。INLINEはSingle-SPAフレームワークを使用してページをリフレッシュせずに内部的にツールを開きます。IFRAMEはOpenC3内のIframeで外部ツールを開きます。NEWは新しいタブでツールを開きます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Window Mode | ツール表示モード<br/><br/>有効な値: <span class="values">INLINE, IFRAME, NEW</span> | True |

### ICON
**ツールアイコンを設定する**

OpenC3ナビゲーションメニューでツール名の横に表示されるアイコン。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Icon Name | ツール名の横に表示するアイコン。アイコンはFont Awesome、Material Design（https://materialdesignicons.com/）、およびAstroから来ています。 | True |

### CATEGORY
**ツールのカテゴリ**

ツールをカテゴリに関連付けます。これはナビゲーションメニューのサブメニューになります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Category Name | ツールを関連付けるカテゴリ | True |

### SHOWN
**ツールを表示するかどうか**

ツールがナビゲーションメニューに表示されるかどうか。通常はtrueであるべきですが、openc3ベースツールを除きます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Shown | ツールが表示されるかどうか。TRUEまたはFALSE<br/><br/>有効な値: <span class="values">true, false</span> | True |

### POSITION
<div class="right">(Since 5.0.8)</div>**ナビゲーションバーでのツールの位置**

2から始まるツールの位置（1はAdmin Consoleのために予約されています）。ポジションのないツールは、インストールされるとき末尾に追加されます。すべてのCOSMOSオープンソースツールは、ポジションに連続した整数値を持っています。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Position | 数値位置 | True |

### DISABLE_ERB
<div class="right">(Since 5.12.0)</div>**ERB処理を無効にする**

ツール全体またはそのファイル名に対する一連の正規表現のERB処理を無効にします

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Regex | ファイル名に対して一致する正規表現。一致する場合、ERB処理は行われません | False |

### IMPORT_MAP_ITEM
<div class="right">(Since 6.0.0)</div>**インポートマップにアイテムを追加する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| key | インポートマップキー | True |
| value | インポートマップ値 | True |

## WIDGET
**カスタムウィジェットを定義する**

テレメトリビューア画面で使用できるカスタムウィジェットを定義します。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Widget Name | ウィジェットの名前は、ウィジェット実装へのパスを構築するために使用されます。例えば、`WIDGET HELLOWORLD`はビルドされたファイルtools/widgets/HelloworldWidget/HelloworldWidget.umd.min.jsを見つけます。詳細については、[カスタムウィジェット](../guides/custom-widgets.md)ガイドを参照してください。 | True |
| Label | Data Viewerコンポーネントのドロップダウンに表示されるウィジェットのラベル | False |

使用例:
```ruby
WIDGET HELLOWORLD
```

## WIDGET修飾子
以下のキーワードはWIDGETキーワードに続いて使用する必要があります。

### DISABLE_ERB
<div class="right">(Since 5.12.0)</div>**ERB処理を無効にする**

ウィジェット全体またはそのファイル名に対する一連の正規表現のERB処理を無効にします

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Regex | ファイル名に対して一致する正規表現。一致する場合、ERB処理は行われません | False |