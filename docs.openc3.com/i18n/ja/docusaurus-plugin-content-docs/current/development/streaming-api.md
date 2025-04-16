---
title: ストリーミングAPI
description: WebSocketストリーミングAPIを使用してデータを取得する
sidebar_custom_props:
  myEmoji: 📝
---

:::note この文書はCOSMOS開発者向けです
この情報は一般的にCOSMOSツールの裏側で使用されています
:::

COSMOS 6 ストリーミングAPIは、COSMOSシステムを通過したテレメトリパケットやコマンドパケットのストリームを、ログに記録されたものとリアルタイムの両方で受信するための主要なインターフェースです。生のバイナリパケットまたは復調されたJSONパケットのいずれかをリクエストできます。

このAPIはRails ActionCableフレームワークを使用してWebSocket上に実装されています。ActionCableクライアントライブラリは、少なくともJavascript、Ruby、Pythonで存在することが知られています。他の言語も存在するか、作成できる可能性があります。WebSocketにより、新しいCOSMOS 6のJavascriptベースのフロントエンドとの簡単な対話が可能になります。

以下の対話はすべてJavascriptで示されていますが、どの言語でも非常に似たものになります。
このAPIへの接続は、ActionCable接続を開始することから始まります。

```
cable = ActionCable.createConsumer('/openc3-api/cable')
```

このコールは指定されたURLへのHTTP接続を開き、WebSocket接続にアップグレードします。この接続は複数の「サブスクリプション」で共有できます。

サブスクリプションは、APIがあなたにストリームするデータのセットを記述します。サブスクリプションの作成は次のようになります：

```javascript
subscription = cable.subscriptions.create(
  {
    channel: "StreamingChannel",
    scope: "DEFAULT",
    token: token,
  },
  {
    received: (data) => {
      // 受信データを処理する
    },
    connected: () => {
      // ストリームしたいものを追加する最初の機会
    },
    disconnected: () => {
      // サブスクリプションが切断されたときの処理
    },
    rejected: () => {
      // サブスクリプションが拒否されたときの処理
    },
  }
);
```

ストリーミングAPIにサブスクライブするには、「StreamingChannel」に設定されたチャンネル名、通常は「DEFAULT」のスコープ、およびアクセストークン（オープンソースCOSMOSではパスワード）を渡す必要があります。Javascriptでは、サブスクリプションのさまざまなライフサイクルポイントで実行されるコールバック関数のセットも渡します。最も重要なのは `connected` と `received` です。

`connected` は、サブスクリプションがStreamApiに受け入れられたときに実行されます。このコールバックは、ストリームしたい特定のデータをリクエストする最初の機会です。データはサブスクリプションが開いている間、いつでも追加または削除できます。

データは、パケットから個々のアイテムをリクエストするか、パケット全体をリクエストすることでストリームに追加できます。

ストリームへのアイテムの追加は次のように行います：

```javascript
var items = [
  ["DECOM__TLM__INST__ADCS__Q1__RAW", "0"],
  ["DECOM__CMD__INST__COLLECT__DURATION__WITH_UNITS", "1"],
];
OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(() => {
  this.subscription.perform("add", {
    scope: window.openc3Scope,
    token: localStorage.openc3Token,
    items: items,
    start_time: this.startDateTime,
    end_time: this.endDateTime,
  });
});
```

アイテム名の値は二重のアンダースコアで区切られています。例えば `<MODE>__<CMD or TLM>__<TARGET NAME>__<PACKET NAME>__<ITEM NAME>__<VALUE TYPE>__<REDUCED TYPE>` のようになります。モードはRAW、DECOM、REDUCED_MINUTE、REDUCED_HOUR、またはREDUCED_DAYのいずれかです。次のパラメータはCMDまたはTLMで、その後にターゲット名、パケット名、アイテム名が続きます。値タイプはRAW、CONVERTED、FORMATTED、またはWITH_UNITSのいずれかです。縮小データタイプを使用する場合、最後のパラメータはオプションです。縮小タイプはSAMPLE、MIN、MAX、AVG、またはSTDDEVのいずれかです。

ストリームへのパケットの追加は次のように行います：

```javascript
var packets = [
  ["RAW__TLM__INST__ADCS", "0"],
  ["DECOM__TLM__INST__HEALTH_STATUS__FORMATTED", "1"],
];
OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(() => {
  this.subscription.perform("add", {
    scope: window.openc3Scope,
    token: localStorage.openc3Token,
    packets: packets,
    start_time: this.startDateTime,
    end_time: this.endDateTime,
  });
});
```

パケット名の値は二重のアンダースコアで区切られています。例えば `<MODE>__<CMD or TLM>__<TARGET NAME>__<PACKET NAME>__<VALUE TYPE>` のようになります。モードはRAWまたはDECOMのいずれかです。次のパラメータはCMDまたはTLMで、その後にターゲット名とパケット名が続きます。値タイプはRAW、CONVERTED、FORMATTED、またはWITH_UNITSのいずれかです。

Rawモードの場合、VALUE TYPEはRAWに設定するか省略する必要があります（例：TLM\_\_INST\_\_ADCS\_\_RAWまたはTLM\_\_INST\_\_ADCS）。
start_timeとend_timeは、Unixエポック（1970年1月1日午前0時）からのナノ秒単位の標準COSMOS 64ビット整数タイムスタンプです。start_timeがnullの場合、アイテムが削除されるか、サブスクリプションの登録が解除されるまで、現在の時刻からリアルタイムで無期限にストリーミングを開始することを示します。start_timeがnullの場合、end_timeは無視されます。start_timeが指定されend_timeがnullの場合、指定された開始時刻から再生を開始し、その後リアルタイムで無期限に継続することを示します。start_timeとend_timeの両方が指定されている場合は、履歴データの一時的な再生を示します。

ストリーミングAPIから返されるデータはJavascriptのreceivedコールバックで処理されます。データはJSON配列として返され、返された各パケットに対して配列内にJSONオブジェクトが含まれます。結果はバッチ処理され、現在の実装では各バッチで最大100パケットを返します（配列には100エントリがあります）。バッチあたり100パケットは保証されておらず、返されるデータのサイズや他の要因に基づいてバッチのサイズは変わる場合があります。空の配列は、純粋に履歴クエリに対してすべてのデータが送信されたことを示し、データ終了インジケータとして使用できます。

復調されたアイテムの場合、各パケットはJSON オブジェクトとして表現され、「time」フィールドにパケットのCOSMOSナノ秒タイムスタンプが含まれ、その後にリクエストされた各アイテムキーとパケットからの対応する値が含まれます。

```json
[
  {
    "time": 1234657585858,
    "TLM__INST__ADCS__Q1__RAW": 50.0,
    "TLM__INST__ADCS__Q2__RAW": 100.0
  },
  {
    "time": 1234657585859,
    "TLM__INST__ADCS__Q1__RAW": 60.0,
    "TLM__INST__ADCS__Q2__RAW": 110.0
  }
]
```

生パケットの場合、各パケットはJSON オブジェクトとして表現され、timeフィールドにパケットのCOSMOSナノ秒タイムスタンプが含まれ、packetフィールドにはSCOPE\_\_TELEMETRY\_\_TARGETNAME\_\_PACKETNAMEの形式でパケットが読み取られたトピックが含まれ、bufferフィールドにはパケットデータのBASE64エンコードされたコピーが含まれています。

```json
[
  {
    "time": 1234657585858,
    "packet": "DEFAULT__TELEMETRY__INST__ADCS",
    "buffer": "SkdfjGodkdfjdfoekfsg"
  },
  {
    "time": 1234657585859,
    "packet": "DEFAULT__TELEMETRY__INST__ADCS",
    "buffer": "3i5n49dmnfg9fl32k3"
  }
]
```

## Ruby の例

以下は、ストリーミングAPIを使用してテレメトリデータを取得するための簡単なRubyの例です：

```ruby
require 'openc3'
require 'openc3/script/web_socket_api'

$openc3_scope = 'DEFAULT'
ENV['OPENC3_API_HOSTNAME'] = '127.0.0.1'
ENV['OPENC3_API_PORT'] = '2900'
ENV['OPENC3_API_PASSWORD'] = 'password'
# 以下はEnterprise版で必要です（必要に応じてユーザー/パスワードを変更してください）
#ENV['OPENC3_API_USER'] = 'operator'
#ENV['OPENC3_API_PASSWORD'] = 'operator'
#ENV['OPENC3_KEYCLOAK_REALM'] = 'openc3'
#ENV['OPENC3_KEYCLOAK_URL'] = 'http://127.0.0.1:2900/auth'

# CSVデータを書き込むファイルを開く
csv = File.open('telemetry_data.csv', 'w')

# ストリーミングAPIに接続
OpenC3::StreamingWebSocketApi.new() do |api|
  # ストリームにアイテムを追加 - 昨日から1分前までのデータをリクエスト
  api.add(items: [
    'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED',
    'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'
  ],
  start_time: (Time.now - 86400).to_nsec_from_epoch,  # 24時間前
  end_time: (Time.now - 60).to_nsec_from_epoch)       # 1分前

  # CSVヘッダーを書き込む
  csv.puts "Time,TEMP1,TEMP2"

  # ストリームからすべてのデータを読み込む
  data = api.read

  # 各データポイントを処理
  data.each do |item|
    csv.puts "#{item['__time']/1_000_000_000.0},#{item['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED']},#{item['DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED']}"
  end
end
csv.close()
```

## StreamingApi アーキテクチャ

StreamingApiはCOSMOSのコアコンポーネントで、リアルタイムおよび履歴データのストリーミング機能を提供します。以下は、そのアーキテクチャと設計の概要です。

### アーキテクチャの概要

StreamingApiはいくつかの主要なコンポーネントを持つモジュラーアーキテクチャを使用しています：

```
StreamingApi
├── StreamingThread (抽象)
│   ├── RealtimeStreamingThread
│   └── LoggedStreamingThread
└── StreamingObjectCollection
    └── StreamingObject
```

### 主要コンポーネント

#### StreamingApi

ストリーミング接続を管理し、クライアントリクエストを処理するメインクラス：

- クライアントUUID、チャネル、スコープで初期化
- リアルタイムと履歴データの両方のスレッドライフサイクルを管理
- データストリームの追加または削除に関するクライアントリクエストを処理
- 履歴データからリアルタイムストリーミングへの引き渡しを調整
- バッチ処理されたデータをActionCable経由でクライアントに送信

#### StreamingThread

共通スレッド機能を定義する抽象基本クラス：

- スレッドライフサイクル（開始、停止）を管理
- さまざまなソースからのデータを処理
- 結果のバッチ処理と送信を処理
- ストリーミングが完了したかどうかを判断

#### RealtimeStreamingThread

リアルタイムデータ用の特殊スレッド：

- Redisトピックをサブスクライブ
- リアルタイムで受信メッセージを処理
- 現在の時刻からの連続的なストリーミング

#### LoggedStreamingThread

履歴データ用の特殊スレッド：

- アーカイブされたログファイルから読み取り
- データの時間ベースのソートを処理
- 履歴データが使い果たされたときにリアルタイムストリーミングに移行

#### StreamingObject

単一のサブスクリプションアイテムを表す：

- ストリームキーを解析して検証
- ストリームに関するメタデータ（モード、ターゲット、パケット、アイテム）を保存
- タイムスタンプとオフセットを追跡
- 認証を処理

#### StreamingObjectCollection

StreamingObjectのグループを管理：

- トピックによってオブジェクトを整理
- 集合的な状態を追跡
- 効率的な検索を提供

### データフロー

1. クライアントがActionCableに接続し、StreamingChannelをサブスクライブ
2. クライアントがストリームするアイテム/パケットを含む「add」リクエストを送信
3. StreamingApiが認証付きの適切なStreamingObjectを作成
4. 履歴リクエストの場合：
   - LoggedStreamingThreadがログファイルから読み取り
   - データはバッチでクライアントに送信
   - 履歴データが使い果たされたらリアルタイムに引き渡し
5. リアルタイムリクエストの場合：
   - RealtimeStreamingThreadがRedisトピックをサブスクライブ
   - データは到着次第クライアントに送信
6. クライアントはいつでもアイテムの追加/削除が可能
7. クライアントが切断されると、すべてのスレッドが終了

### パフォーマンスに関する考慮事項

- 履歴データには「リクエストごとにスレッド」モデルを使用
- リアルタイムデータには単一のスレッドを維持
- ネットワークオーバーヘッドを減らすためにバッチ処理された結果（バッチあたり最大100アイテム）
- 効率的な履歴データアクセスのためのファイルキャッシング
- 履歴データからリアルタイムデータへのシームレスな移行

### セキュリティ

すべてのStreamingObjectは、リクエストされた特定のターゲットとパケットの認証を検証し、ユーザーが表示権限を持つデータのみにアクセスできるようにします。