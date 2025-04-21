---
title: ブリッジ
description: シリアルポート、PCIなどからCOSMOSにデータをブリッジする
sidebar_custom_props:
  myEmoji: 🌉
---

COSMOSブリッジは、イーサネット通信に対応していないデバイスからCOSMOSにデータを取り込むための簡単なソリューションを提供します。
シリアルポートが最も一般的ですが、USB、PCIカード、Bluetoothデバイスなども、
ホストコンピュータからアクセス可能なデバイスをイーサネットバイトストリームに変換するブリッジを使用することで、COSMOSがコンテナ内から処理できるようになります。

:::warning ブリッジはシンプルであることを意図しています

ブリッジの目的は、バイトをCOSMOSに取り込むことです。パケット区切りなどの詳細を含む処理は、COSMOS自体で行うべきです。
:::

## ブリッジは基本的にインターフェースとルーターのみで構成されています

ブリッジは一般的に、ホスト接続デバイスからデータを取得するCOSMOS Interfaceクラスと、そのデータをTCP/IP経由でCOSMOSに転送するRouterで構成されています。
ほとんどの場合、BURSTプロトコルを使用してデータを安全にCOSMOSに送信し、COSMOS側でLENGTHなどの適切なパケット区切りプロトコルを使用できます。

## ブリッジを実行するためのホスト要件

- ホストRubyインストールが必要（Ruby 3）
- OpenC3 gemのインストール
  - gem install openc3
- Rubyのgem実行可能パスがPATH環境変数に含まれていることを確認
  - このパスは`gem environment`を実行し、EXECUTABLE DIRECTORYを確認することで見つけられます
- 成功した場合、ターミナルから`openc3cli`を実行できるはずです

## ブリッジ設定: bridge.txt

ブリッジはbridge.txtという名前の設定ファイルを使用して実行されます。このファイルはplugin.txt設定構文のサブセットで、VARIABLE、INTERFACE、ROUTER、および関連する修飾キーワードをサポートしています。ただし、ブリッジはターゲットの知識を持ちません。そのため、MAP_TARGETSの代わりに、INTERFACEはROUTEキーワードを使用してROUTERに関連付けられます。

以下は、`openc3cli bridgesetup`を実行することで生成されるデフォルトのbridge.txtです。

```ruby
# 書き込みシリアルポート名
VARIABLE write_port_name COM1

# 読み取りシリアルポート名
VARIABLE read_port_name COM1

# ボーレート
VARIABLE baud_rate 115200

# パリティ - NONE、ODD、またはEVEN
VARIABLE parity NONE

# ストップビット - 0、1、または2
VARIABLE stop_bits 1

# 書き込みタイムアウト
VARIABLE write_timeout 10.0

# 読み取りタイムアウト
VARIABLE read_timeout nil

# フロー制御 - NONE、またはRTSCTS
VARIABLE flow_control NONE

# ワードあたりのデータビット - 通常は8
VARIABLE data_bits 8

# COSMOSからの接続をリッスンするポート - プラグインと一致する必要があります
VARIABLE router_port 2950

# COSMOSからの接続をリッスンするポート。セキュリティのためにデフォルトではlocalhostです。COSMOSが別のマシンにある場合は、
# 開放する必要があります。
VARIABLE router_listen_address 127.0.0.1

INTERFACE SERIAL_INT serial_interface.rb <%= write_port_name %> <%= read_port_name %> <%= baud_rate %> <%= parity %> <%= stop_bits %> <%= write_timeout %> <%= read_timeout %>
  OPTION FLOW_CONTROL <%= flow_control %>
  OPTION DATA_BITS <%= data_bits %>

ROUTER SERIAL_ROUTER tcpip_server_interface.rb <%= router_port %> <%= router_port %> 10.0 nil BURST
  ROUTE SERIAL_INT
  OPTION LISTEN_ADDRESS <%= router_listen_address %>
```

VARIABLEは、ブリッジ起動時に変更できる変数のデフォルト値を提供します。この例では、serial_interface.rbクラスを使用するように設定されたINTERFACEを示しています。また、COSMOSが接続してシリアルポートからデータを取得できるtcpip_server_interface.rbを使用する標準的なROUTERも含まれています。この例ではLISTEN_ADDRESSが127.0.0.1に設定されており、ホストシステム外からのアクセスを防止しています。同じマシン上で実行されているDockerは、host.docker.internalホスト名と設定されたポート（この例では2950）を使用してこのサーバーにアクセスできます。

## ブリッジコマンド: openc3cli

`openc3cli bridgesetup`

bridge.txtの例ファイルを生成します

`openc3cli bridge [filename] [variable1=value1] [variable2=value2]`

指定された設定ファイルからブリッジを実行します。デフォルトでは現在のディレクトリのbridge.txtを使用します。VARIABLEのデフォルト値を上書きするために変数を渡すこともできます。

`openc3cli bridgegem [gem_name] [variable1=value1] [variable2=value2]`

ブリッジgemで提供されるbridge.txtを使用してブリッジを実行します。VARIABLEのデフォルト値を上書きするために変数を渡すこともできます。

## ブリッジGemの例

- シリアルポート: [openc3-cosmos-bridge-serial](https://github.com/OpenC3/openc3-cosmos-bridge-serial)
- ホスト: [openc3-cosmos-bridge-host](https://github.com/OpenC3/openc3-cosmos-bridge-host)
- HIDAPI: [openc3-cosmos-bridge-hidapi](https://github.com/OpenC3/openc3-cosmos-bridge-hidapi)
- PS5 Dual Senseコントローラ: [openc3-cosmos-bridge-dualsense](https://github.com/OpenC3/openc3-cosmos-bridge-dualsense)

## シリアルポートに関する注意

Linux Dockerインストールでは、ブリッジを使わずに直接シリアルポートを使用できます。

compose.yamlのoperatorサービスに以下を追加します：

```
   devices:
     - "/dev/ttyUSB0:/dev/ttyUSB0"
```

シリアルデバイスに、Dockerを実行しているユーザーがアクセスするための権限があることを確認してください：

```
sudo chmod 666 /dev/ttyUSB0
```