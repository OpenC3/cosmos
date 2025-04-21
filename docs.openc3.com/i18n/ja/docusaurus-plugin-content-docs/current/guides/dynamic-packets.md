---
title: 動的パケット
description: COSMOSが動的にパケットを構築する方法
sidebar_custom_props:
  myEmoji: 🧱
---

COSMOSには、[COMMAND](/docs/configuration/command)と[TELEMETRY](/docs/configuration/telemetry)の設定ファイルで静的に定義するのではなく、パケットを動的に構築する機能があります。これは、[prometheus](https://prometheus.io/)メトリクスを生成する場合のように、テレメトリ項目が動的である場合に便利です。

この機能を説明する最良の方法は、例を示すことです。Enterprise顧客の場合は、[prometheus-metrics](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-prometheus-metrics)プラグインをご覧ください。

## 動的更新の使用

あなた自身のコードで動的更新機能を使用するには、`TargetModel`の`dynamic_update`メソッドを呼び出す必要があります。このメソッドは、パケットの配列/リスト、パケットがコマンドかテレメトリかの区別、および設定バケットに作成するファイル名を引数に取ります。

以下がメソッドのシグネチャです：

```ruby
def dynamic_update(packets, cmd_or_tlm = :TELEMETRY, filename = "dynamic_tlm.txt")
```

```python
def dynamic_update(self, packets, cmd_or_tlm="TELEMETRY", filename="dynamic_tlm.txt")
```

このメソッドの使用例は以下の通りです：

```ruby
# 新しいパケットを作成
packet = Packet.new('INST', 'NEW_PACKET')
# または既存のパケットを取得
packet = System.telemetry.packet('INST', 'METRICS')
# 新しいアイテムを追加してパケットを変更
packet.append_item('NEW_ITEM', 32, :FLOAT)
# パケットのターゲットに関連付けられたTargetModelを取得
target_model = TargetModel.get_model(name: 'INST', scope: 'DEFAULT')
# 新しいパケットでターゲットモデルを更新
target_model.dynamic_update([packet])
```

```python
# 新しいパケットを作成
packet = Packet('INST', 'NEW_PACKET')
# または既存のパケットを取得
packet = System.telemetry.packet('INST', 'METRICS')
# 新しいアイテムを追加してパケットを変更
packet.append_item('NEW_ITEM', 32, 'FLOAT')
# パケットのターゲットに関連付けられたTargetModelを取得
target_model = TargetModel.get_model(name='INST', scope='DEFAULT')
# 新しいパケットでターゲットモデルを更新
target_model.dynamic_update([packet])
```

このメソッドが呼び出されると、いくつかのことが起こります：

1. COSMOS Redisデータベースが新しいパケットで更新され、現在値テーブルが初期化されます
2. パケットの設定ファイルが作成され、&lt;SCOPE&gt;/targets_modified/&lt;TARGET&gt;/cmd_tlm/dynamic_tlm.txtに保存されます。`dynamic_update`を複数回呼び出す場合は、ファイル名を更新して上書きされないようにする必要があります。
3. COSMOSマイクロサービスに、生のパケットデータと分解されたパケットデータを含む新しいストリーミングトピックが通知されます。このアクションの一部として、マイクロサービスが再起動され、これらの変更が適用されます。COMMANDSの場合、次のものが再起動されます：&lt;SCOPE&gt;\_\_COMMANDLOG\_\_&lt;TARGET&gt;と&lt;SCOPE&gt;\_\_DECOMCMDLOG\_\_&lt;TARGET&gt;。TELEMETRYの場合、次のものが再起動されます：&lt;SCOPE&gt;\_\_PACKET_LOG\_\_&lt;TARGET&gt;、&lt;SCOPE&gt;\_\_DECOMLOG\_\_&lt;TARGET&gt;、および&lt;SCOPE&gt;\_\_DECOM\_\_&lt;TARGET&gt;。

`dynamic_update`はLOGマイクロサービスを再起動するため、再起動中にパケットが失われる可能性があります。したがって、重要なテレメトリ処理期間中には`dynamic_update`を呼び出すべきではありません。