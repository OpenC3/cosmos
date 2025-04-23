---
title: COSMOSとNASA cFS
description: NASA cFSとの統合チュートリアル
sidebar_custom_props:
  myEmoji: 🚀
---

## 動作確認済み構成

このチュートリアルは、以下のコンポーネントを使用してテストされています：

- COSMOS v5リリース [5.0.6](https://github.com/OpenC3/cosmos/releases/tag/v5.0.6)
- cFS masterブランチコミット: 561b128 (2022年6月1日)
- Docker Desktop 4.9.0 on Windows

すべての `<xxxxxx>` を対応するパスや名前に置き換えてください。例：`<USERNAME>`。

## COSMOSのセットアップ

公式の[インストール](../getting-started/installation.md)手順に従ってCOSMOSをインストールします。

### COSMOSの設定

NASA cFSとの相互運用性のためにDocker設定を変更します。テレメトリをサブスクライブするには、
`compose.yaml`ファイルの`openc3-operator`セクションにポートバインディングを追加する必要があります。
ポート番号はcFSがテレメトリを送信するポート番号と一致させる必要があります。

```yaml
openc3-operator:
  ports:
    - "1235:1235/udp"
```

COSMOSを実行します。初回の実行には時間がかかります（約15分）。

```bash
openc3.sh start
```

起動したら、ブラウザで[http://localhost:2900](http://localhost:2900)に接続します。

COSMOSをシャットダウンするには：

```bash
openc3.sh stop
```

## cFSのセットアップ

[NASA cFS](https://github.com/nasa/cFS)をDockerコンテナとして実行するには、以下の手順を実行します：

### cFSのクローン

```bash
git clone --recurse-submodules https://github.com/nasa/cFS.git
```

### cFSディレクトリにDockerfileを作成

```docker
FROM ubuntu:22.10 AS builder

ARG DEBIAN_FRONTEND=noninteractive
ARG SIMULATION=native
ENV SIMULATION=${SIMULATION}
ARG BUILDTYPE=debug
ENV BUILDTYPE=${BUILDTYPE}
ARG OMIT_DEPRECATED=true
ENV OMIT_DEPRECATED=${OMIT_DEPRECATED}

RUN \
  apt-get update && \
  apt-get -y upgrade && \
  apt-get install -y build-essential git cmake && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /cFS
COPY . .

RUN git submodule init \
  && git submodule update \
  && cp cfe/cmake/Makefile.sample Makefile \
  && cp -r cfe/cmake/sample_defs .

RUN make prep
RUN make
RUN make install

FROM ubuntu:22.10
COPY --from=builder /cFS/build /cFS/build
WORKDIR /cFS/build/exe/cpu1
ENTRYPOINT [ "./core-cpu1" ]
```

### cFSのビルドと実行

COSMOSネットワーク（`docker network ls`で確認できます）に接続し、cFSポートを公開していることに注意してください。

```bash
docker build -t cfs .
docker run --cap-add CAP_SYS_RESOURCE --net=openc3-cosmos-network --name cfs -p1234:1234/udp -p1235:1235 cfs
```

## cFSとのTM/TCインターフェース用COSMOSプラグインの作成

プラグインの作成に関する詳細な手順は、
[こちら](../getting-started/gettingstarted.md)の「ハードウェアとのインターフェース」の章にあります。

`CFS`という名前で新しいプラグインを作成します。COSMOSドキュメントによると、`CFS`はプラグイン名であり、
大文字である必要があります。このコマンドはプラグイン構造を作成するはずです。
その後、プラグインのディレクトリに移動してターゲットを作成します。

```bash
# cd .. でcfsディレクトリの場所に移動
$PATH_TO_OPENC3/openc3.sh cli generate plugin CFS
cd openc3-cosmos-cfs
$PATH_TO_OPENC3/openc3.sh cli generate target CFS
```

この新しく作成されたプラグインで、`plugin.txt`ファイルを変更して、
通信がUDP経由で行われるようにします。`port_tm`はcFSがテレメトリメッセージを送信するポート番号です。
`port_tc`はcFSがテレコマンドをリッスンするポートを示します。

```ruby
VARIABLE ip 127.0.0.1
VARIABLE port_tm 1235
VARIABLE port_tc 1234
VARIABLE cfs_target_name CFS

TARGET CFS <%= cfs_target_name %>
# hostname   write_dest_port   read_port   write_src_port   interface_address   ttl   write_timeout   read_timeout   bind_address
INTERFACE <%= cfs_target_name %>_INT udp_interface.rb <%= ip %> <%= port_tc %> <%= port_tm %> nil nil 128 nil nil
  MAP_TARGET <%= cfs_target_name %>
```

`TARGET`パラメータへの2つの引数に注意してください：

1. プラグインの名前と一致する物理ターゲット名、つまり`CFS`。
   この名前は`targets`フォルダ内のフォルダ名と一致する必要があります。例：
   `CFS`プラグインでは、ターゲット仕様は
   `openc3-cfs/targets/CFS`にある必要があります。この
   規則に従わない場合、サーバーは次のステップでプラグインのインストールを拒否します。

1. ターゲットの名前と、それがユーザーインターフェースでどのように表示されるか。

この例では、両方の名前を`CFS`にしています。

## TM/TC定義の作成

ターゲットフォルダに移動し、既存のファイルを削除して独自のファイルを作成します。

```bash
cd openc3-cfs/targets/CFS/cmd_tlm
rm *
touch cfs_cmds.txt
touch cfs_tlm.txt
touch to_lab_cmds.txt
```

これらの新しく作成されたファイルをテキストエディタで開き、以下の内容を入力します。

`to_lab_cmds.txt`：

```ruby
COMMAND CFS TO_LAB_ENABLE BIG_ENDIAN "Enable telemetry"
  #                   NAME      BITS TYPE   min VAL     max VAL    init VAL  DESCRIPTION
  APPEND_ID_PARAMETER STREAM_ID  16  UINT   0x1880      0x1880     0x1880    "Stream ID"
    FORMAT_STRING "0x%04X"
  APPEND_PARAMETER    SEQUENCE   16  UINT   0xC000      MAX_UINT16 0xC000    ""
    FORMAT_STRING "0x%04X"
  APPEND_PARAMETER    PKT_LEN    16  UINT   0x0001      0xFFFF     0x0012    "length of the packet"
  APPEND_PARAMETER    CMD_ID      8  UINT   6           6          6         ""
  APPEND_PARAMETER    CHECKSUM    8  UINT   MIN_UINT8   MAX_UINT8  0x98      ""
    FORMAT_STRING "0x%2X"
  APPEND_PARAMETER    DEST_IP   144  STRING "127.0.0.1"                      "Destination IP, i.e. 172.16.9.112, pc-57"
```

:::info テレメトリの有効化
コマンド`0x1880`はテレメトリを有効にするために必要です。cFSがこのコマンドを受信すると、
`DEST_IP`フィールドで提供されたIPアドレスにテレメトリの送信を開始します。
:::

`cfs_cmds.txt`：

```ruby
COMMAND CFS NOOP BIG_ENDIAN "NOOP Command"
  # cFS primary header
  APPEND_ID_PARAMETER    STREAM_ID   16   UINT   0x1882      0x1882      0x1882      "Packet Identification"
      FORMAT_STRING "0x%04X"
  APPEND_PARAMETER       SEQUENCE    16   UINT   MIN_UINT16  MAX_UINT16  0xC000      ""
      FORMAT_STRING "0x%04X"
  APPEND_PARAMETER       PKT_LEN     16   UINT   0x0001      0x0001      0x0001      "Packet length"
  # cFS CMD secondary header
  APPEND_PARAMETER       CMD_ID       8   UINT   0           0           0           ""
  APPEND_PARAMETER       CHECKSUM     8   UINT   MIN_UINT8   MAX_UINT8   MIN_UINT8   ""

COMMAND CFS RESET BIG_ENDIAN "Reset Counters Command"
  APPEND_ID_PARAMETER    STREAM_ID   16   UINT   0x1882      0x1882      0x1882      "Packet Identification"
      FORMAT_STRING "0x%04X"
  APPEND_PARAMETER       SEQUENCE    16   UINT   MIN_UINT16  MAX_UINT16  0xC000      ""
      FORMAT_STRING "0x%04X"
  APPEND_PARAMETER       PKT_LEN     16   UINT   0x0001      0x0001      0x0001      "Packet length"
  APPEND_PARAMETER       CMD_ID       8   UINT   1           1           1           ""
  APPEND_PARAMETER       CHECKSUM     8   UINT   MIN_UINT8   MAX_UINT8   MIN_UINT8   ""

COMMAND CFS PROCESS BIG_ENDIAN "Process Command"
  APPEND_ID_PARAMETER    STREAM_ID   16   UINT   0x1882      0x1882      0x1882      "Packet Identification"
      FORMAT_STRING "0x%04X"
  APPEND_PARAMETER       SEQUENCE    16   UINT   MIN_UINT16  MAX_UINT16  0xC000      ""
      FORMAT_STRING "0x%04X"
  APPEND_PARAMETER       PKT_LEN     16   UINT   0x0001      0x0001      0x0001      "Packet length"
  APPEND_PARAMETER       CMD_ID       8   UINT   2           2           2           ""
  APPEND_PARAMETER       CHECKSUM     8   UINT   MIN_UINT8   MAX_UINT8   MIN_UINT8   ""
```

`cfs_tlm.txt`：

```ruby
TELEMETRY CFS HK BIG_ENDIAN "housekeeping telemetry"
  #                NAME       BITS  TYPE    ID      DESCRIPTION
  APPEND_ID_ITEM   STREAM_ID   16   UINT    0x0883  "Stream ID"
    FORMAT_STRING "0x%04X"
  APPEND_ITEM      SEQUENCE    16   UINT            "Packet Sequence"
    FORMAT_STRING "0x%04X"
  APPEND_ITEM      PKT_LEN     16   UINT            "Length of the packet"
  # telemetry secondary header
  APPEND_ITEM      SECONDS     32   UINT            ""
        UNITS Seconds sec
  APPEND_ITEM      SUBSECS     16   UINT            ""
        UNITS Milliseconds ms
  # some bytes not known for what
  APPEND_ITEM      SPARE2ALIGN 32   UINT            "Spares"
  # payload
  APPEND_ITEM      CMD_ERRS     8   UINT            "Command Error Counter"
  APPEND_ITEM      CMD_CNT      8   UINT            "Command Counter"
  # spare / alignment
  APPEND_ITEM      SPARE       16   UINT            "Spares"
```

プラグインフォルダのベースからプラグインをビルドします：

```bash
# cd openc3-cfs
$PATH_TO_OPENC3/openc3.sh cli rake build VERSION=1.0.0
```

:::info プラグインのバージョン管理
プラグインのバージョン間をより簡単に区別したい場合は、ビルドごとにバージョン番号を変更するのを忘れないでください。
バージョンがプラグインの.gemファイル名に表示されると、既存のバージョンと新しくアップロードされたバージョンを
視覚化しやすくなります。
:::

:::info プラグインパラメータ
プラグイン設定には複数のパラメータが利用可能です。[プラグイン](../configuration/plugins.md)ページを参照してください。
:::

## プラグインのアップロード

プラグインがビルドされたら、ページの管理エリアでプラグインをインポートできます。

ブラウザで[http://localhost:2900/tools/admin](http://localhost:2900/tools/admin)に接続します。

クリップアイコンをクリックし、プラグインが保存されている場所に移動して
`openc3-cosmos-cfs-1.0.0.gem`ファイルを選択します。選択行の右側にある`UPLOAD`をクリックします。

cFSコンテナとCOSMOS operatorコンテナが実行されているIPアドレスを確認します：

```bash
docker network ls
NETWORK ID     NAME             DRIVER    SCOPE
d842f813f1c7   openc3-cosmos-network   bridge    local

docker network inspect openc3-cosmos-network
[
    {
        "Name": "openc3-cosmos-network",
        ...
        "Containers": {
            "03cb6bf1b27c631fad1366e9342aeaa5b80f458a437195e4a95e674bb5f5983d": {
                "Name": "cfs",
                "IPv4Address": "172.20.0.9/16",
            },
            "ceb9ea99b00849fd8867dcd1646838fef3471f7d64b69014703dbedbcc8147fc": {
                "Name": "openc3_openc3-operator_1",
                "IPv4Address": "172.20.0.8/16",
            }
        }
        ...
    }
]
```

このプラグインを使用する際は、アップロード時に`ip`変数をcFSが実行されている場所に合わせて変更してください。
上記の例では、172.20.0.9に設定します。
`port_tm`はcFSがテレメトリメッセージを送信するポート番号です。
`port_tc`はcFSがテレコマンドをリッスンしているポートを示します。

`cfs_target_name`でこのプラグインのターゲット名を変更できます。
プラグインが`CFS`として表示されることに問題がなければ、このステップはオプションです。

![プラグイン変数設定](pathname:///img/guides/plugin_variables.png)

:::warning ポートサブスクリプション
COSMOS上で最後にアップロードされたプラグインがポート1235でテレメトリをサブスクライブします。
他のプラグインはテレメトリを受信しなくなります。
:::

:::info タイプミスエラー
プラグインファイルの一つにタイプミスがあると、プラグインの.gemファイルのアップロードとインストール時に
問題が発生する可能性があります。設定にタイプミスがないことを確認してください。
:::

上記の例では、operatorイメージは172.20.0.8で実行されています。テレメトリを有効にするには、ブラウザで
[http://localhost:2900/tools/cmdsender/CFS/TO_LAB_ENABLE](http://localhost:2900/tools/cmdsender/CFS/TO_LAB_ENABLE)に接続します。
`DEST_IP`をoperatorイメージのIPアドレス（172.20.0.8）に変更し、コマンドを送信します。

[http://localhost:2900/tools/cmdtlmserver/tlm-packets](http://localhost:2900/tools/cmdtlmserver/tlm-packets)で、
受信パケットが表示されるはずです。CmdTlmServerでは、CFS_INT UNKNOWNパケットも表示されることに注意してください。
これは完全なcFSパケットセットを定義していないためです。この演習は読者に委ねられています。