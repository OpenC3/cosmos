---
sidebar_position: 5
title: コマンドラインインターフェース
description: openc3.shの使用方法
sidebar_custom_props:
  myEmoji: ⌨️
---

COSMOSコマンドラインインターフェースは、COSMOS [プロジェクト](https://github.com/OpenC3/cosmos-project)に含まれている`openc3.sh`と`openc3.bat`です（[プロジェクト](key-concepts#プロジェクト)の詳細はこちら）。

[インストールガイド](installation.md)に従った場合、すでにクローンした[openc3-project](https://github.com/OpenC3/cosmos-project)内にいるはずです。これはPATHに含まれている必要があります（openc3.bat / openc3.shを解決するために必要）。利用可能なすべてのコマンドを確認するには、次のように入力します：

```bash
% openc3.sh cli
Usage:
  cli help                          # この情報を表示します
  cli rake                          # ローカルディレクトリでrakeを実行します
  cli irb                           # ローカルディレクトリでirbを実行します
  cli script list /PATH SCOPE       # スコープ内のパスでフィルタリングされたスクリプト名を一覧表示します。指定されない場合は'DEFAULT'
  cli script spawn NAME SCOPE  variable1=value1 variable2=value2  # 指定されたスクリプトをリモートで開始します
  cli script run NAME SCOPE variable1=value1 variable2=value2  # 指定されたスクリプトを開始し、コンソールでステータスを監視します。デフォルトではエラーまたは終了するまで
    PARAMETERS                      # 名前と値のペアでスクリプトの実行環境を形成します
    OPTIONS: --wait 0               # 実行中のスクリプトから切り離す前にステータスを監視する秒数。例：--wait 100
             --disconnect           # スクリプトを切断モードで実行
  cli script init                   # 実行中のスクリプトを初期化します（Enterprise版のみ）
  cli validate /PATH/FILENAME.gem SCOPE variables.txt # COSMOSプラグインgemファイルを検証します
  cli load /PATH/FILENAME.gem SCOPE variables.txt     # COSMOSプラグインgemファイルをロードします
  cli list <SCOPE>                  # インストールされているプラグインを一覧表示します。指定されない場合、SCOPEはDEFAULTです
  cli generate TYPE OPTIONS         # 様々なCOSMOSエンティティを生成します
    OPTIONS: --rubyまたは--python は生成されたコードの言語を指定するためにOPENC3_LANGUAGEが設定されていない限り、必要です
  cli bridge CONFIG_FILENAME        # COSMOS ホストブリッジを実行します
  cli bridgegem gem_name variable1=value1 variable2=value2 # gemのbridge.txtを使用してブリッジを実行します
  cli bridgesetup CONFIG_FILENAME   # デフォルト設定ファイルを作成します
  cli pkginstall PKGFILENAME SCOPE  # ロードされたパッケージ（Rubygemまたはpythonパッケージ）をインストールします
  cli pkguninstall PKGFILENAME SCOPE  # ロードされたパッケージ（Rubygemまたはpythonパッケージ）をアンインストールします
  cli rubysloc                      # 非推奨：scc (https://github.com/boyter/scc) を使用してください
  cli xtce_converter                # XTCE形式との間で変換します。詳細は--helpで実行してください
  cli cstol_converter               # CSTOLファイル（.prc）をCOSMOSに変換します。詳細は--helpで実行してください
```

:::note seccompプロファイル
`WARNING: daemon is not using the default seccomp profile`は安全に無視できます
:::

## Rake

`openc3.sh cli rake`を使用してrakeタスクを実行できます。最も一般的な使用法は、プラグインを生成してからビルドすることです。例えば：

```bash
% openc3.sh cli rake build VERSION=1.0.0
```

## IRB

IRBはInteractive Rubyの略で、Rubyインタープリタを起動して使う事ができる方法です。CLIから使用する場合、COSMOSのRubyパスが含まれているため、`require 'cosmos'`を実行して様々なメソッドを試すことができます。例えば：

```bash
% openc3.sh cli irb
irb(main):001:0> require 'cosmos'
=> true
irb(main):002:0> Cosmos::Api::WHITELIST
=>
["get_interface",
 "get_interface_names",
 ...
]
```

## Script

スクリプトメソッドを使用すると、利用可能なスクリプトの一覧表示、スクリプトの起動、出力を監視しながらスクリプトの実行が可能です。オープンソース版ではOPENC3_API_PASSWORDを、Enterprise版ではOPENC3_API_USERとOPENC3_API_PASSWORDの両方を設定する必要があることに注意してください。

:::note オフラインアクセストークン
他のスクリプトCLIメソッドが機能するようになる前に、OPENC3_API_USERとしてフロントエンドのScript Runnerページにアクセスするか、「openc3.sh cli script init」を実行してオフラインアクセストークンを取得する必要があります。
:::

### List

すべてのターゲットディレクトリにあるすべてのファイルを含む、利用可能なすべてのスクリプトを一覧表示します。bashを使ってこのリストをフィルタリングし、procedures、Rubyファイル、Pythonファイルなどだけを含めることができます。

```bash
% export OPENC3_API_USER=operator
% export OPENC3_API_PASSWORD=operator
% openc3.sh cli script list
EXAMPLE/cmd_tlm/example_cmds.txt
EXAMPLE/cmd_tlm/example_tlm.txt
...
```

### Spawn

起動されたスクリプトのIDが返されます。Script Runnerで`http://localhost:2900/tools/scriptrunner/1`にアクセスすることで接続できます。最後の値はIDです。

```bash
% openc3.sh spawn INST/procedures/checks.rb
1
```

### Run

Runはスクリプトを起動し、出力をキャプチャしてシェルに表示します。これはユーザー入力プロンプトでは機能しないため、スクリプトはユーザー入力を防ぐように書かれている必要があります。CLIヘルプに示されているように、スクリプトに変数を渡すこともできます。

```bash
% openc3.sh cli script run INST/procedures/stash.rb
Filename INST/procedures/stash.rb scope DEFAULT
2025/03/22 19:50:40.429 (SCRIPTRUNNER): Script config/DEFAULT/targets/INST/procedures/stash.rb spawned in 0.796683293 seconds <ruby 3.2.6>
2025/03/22 19:50:40.453 (SCRIPTRUNNER): Starting script: stash.rb, line_delay = 0.1
At [INST/procedures/stash.rb:3] state [running]
At [INST/procedures/stash.rb:4] state [running]
2025/03/22 19:50:40.732 (stash.rb:4): key1: val1
At [INST/procedures/stash.rb:5] state [running]
At [INST/procedures/stash.rb:6] state [running]
2025/03/22 19:50:40.936 (stash.rb:6): key2: val2
At [INST/procedures/stash.rb:7] state [running]
2025/03/22 19:50:41.039 (stash.rb:7): CHECK: 'val1' == 'val1' is TRUE
At [INST/procedures/stash.rb:8] state [running]
2025/03/22 19:50:41.146 (stash.rb:8): CHECK: 'val2' == 'val2' is TRUE
At [INST/procedures/stash.rb:9] state [running]
2025/03/22 19:50:41.256 (stash.rb:9): CHECK: '["key1", "key2"]' == '["key1", "key2"]' is TRUE
At [INST/procedures/stash.rb:10] state [running]
At [INST/procedures/stash.rb:11] state [running]
At [INST/procedures/stash.rb:12] state [running]
2025/03/22 19:50:41.556 (stash.rb:12): CHECK: '{"key1"=>1, "key2"=>2}' == '{"key1"=>1, "key2"=>2}' is TRUE
At [INST/procedures/stash.rb:13] state [running]
At [INST/procedures/stash.rb:14] state [running]
2025/03/22 19:50:41.763 (stash.rb:14): CHECK: true == true is TRUE
At [INST/procedures/stash.rb:15] state [running]
At [INST/procedures/stash.rb:16] state [running]
At [INST/procedures/stash.rb:17] state [running]
At [INST/procedures/stash.rb:18] state [running]
2025/03/22 19:50:42.176 (stash.rb:18): CHECK: '[1, 2, [3, 4]]' == '[1, 2, [3, 4]]' is TRUE
At [INST/procedures/stash.rb:19] state [running]
At [INST/procedures/stash.rb:21] state [running]
At [INST/procedures/stash.rb:22] state [running]
At [INST/procedures/stash.rb:23] state [running]
2025/03/22 19:50:42.587 (stash.rb:23): CHECK: '{"one"=>1, "two"=>2, "string"=>"string"}' == '{"one"=>1, "two"=>2, "string"=>"string"}' is TRUE
At [INST/procedures/stash.rb:24] state [running]
2025/03/22 19:50:42.697 (SCRIPTRUNNER): Script completed: stash.rb
At [INST/procedures/stash.rb:0] state [stopped]
script complete
%
```

## Validate

ValidateはビルドされたCOSMOSプラグインを検証するために使用されます。プラグインを実際にインストールせずにインストールプロセスをステップバイステップで実行します。

```bash
% openc3.sh cli validate openc3-cosmos-cfdp-1.0.0.gem
Installing openc3-cosmos-cfdp-1.0.0.gem
Successfully validated openc3-cosmos-cfdp-1.0.0.gem
```

## Load

LoadはGUIを使用せずにプラグインをCOSMOSにロードできます。これはスクリプトやCI/CDパイプラインに役立ちます。

```bash
% openc3.sh cli load openc3-cosmos-cfdp-1.0.0.gem
Loading new plugin: openc3-cosmos-cfdp-1.0.0.gem
{"name"=>"openc3-cosmos-cfdp-1.0.0.gem", "variables"=>{"cfdp_microservice_name"=>"CFDP", "cfdp_route_prefix"=>"/cfdp", "cfdp_port"=>"2905", "cfdp_cmd_target_name"=>"CFDP2", "cfdp_cmd_packet_name"=>"CFDP_PDU", "cfdp_cmd_item_name"=>"PDU", "cfdp_tlm_target_name"=>"CFDP2", "cfdp_tlm_packet_name"=>"CFDP_PDU", "cfdp_tlm_item_name"=>"PDU", "source_entity_id"=>"1", "destination_entity_id"=>"2", "root_path"=>"/DEFAULT/targets_modified/CFDP/tmp", "bucket"=>"config", "plugin_test_mode"=>"false"}, "plugin_txt_lines"=>["VARIABLE cfdp_microservice_name CFDP", "VARIABLE cfdp_route_prefix /cfdp", "VARIABLE cfdp_port 2905", "", "VARIABLE cfdp_cmd_target_name CFDP2", "VARIABLE cfdp_cmd_packet_name CFDP_PDU", "VARIABLE cfdp_cmd_item_name PDU", "", "VARIABLE cfdp_tlm_target_name CFDP2", "VARIABLE cfdp_tlm_packet_name CFDP_PDU", "VARIABLE cfdp_tlm_item_name PDU", "", "VARIABLE source_entity_id 1", "VARIABLE destination_entity_id 2", "VARIABLE root_path /DEFAULT/targets_modified/CFDP/tmp", "VARIABLE bucket config", "", "# Set to true to enable a test configuration", "VARIABLE plugin_test_mode \"false\"", "", "MICROSERVICE CFDP <%= cfdp_microservice_name %>", "  WORK_DIR .", "  ROUTE_PREFIX <%= cfdp_route_prefix %>", "  ENV OPENC3_ROUTE_PREFIX <%= cfdp_route_prefix %>", "  ENV SECRET_KEY_BASE 324973597349867207430793759437697498769349867349674", "  PORT <%= cfdp_port %>", "  CMD rails s -b 0.0.0.0 -p <%= cfdp_port %> -e production", "  # MIB Options Follow -", "  # You will need to modify these for your mission", "  OPTION source_entity_id <%= source_entity_id %>", "  OPTION tlm_info <%= cfdp_tlm_target_name %> <%= cfdp_tlm_packet_name %> <%= cfdp_tlm_item_name %>", "  OPTION destination_entity_id <%= destination_entity_id %>", "  OPTION cmd_info <%= cfdp_cmd_target_name %> <%= cfdp_cmd_packet_name %> <%= cfdp_cmd_item_name %>", "  OPTION root_path <%= root_path %>", "  <% if bucket.to_s.strip != '' %>", "    OPTION bucket <%= bucket %>", "  <% end %>", "", "<% include_test = (plugin_test_mode.to_s.strip.downcase == \"true\") %>", "<% if include_test %>", "  TARGET CFDPTEST CFDP", "  TARGET CFDPTEST CFDP2", "", "  MICROSERVICE CFDP CFDP2", "    WORK_DIR .", "    ROUTE_PREFIX /cfdp2", "    ENV OPENC3_ROUTE_PREFIX /cfdp2", "    ENV SECRET_KEY_BASE 324973597349867207430793759437697498769349867349674", "    PORT 2906", "    CMD rails s -b 0.0.0.0 -p 2906 -e production", "    OPTION source_entity_id <%= destination_entity_id %>", "    OPTION tlm_info CFDP CFDP_PDU PDU", "    OPTION destination_entity_id <%= source_entity_id %>", "    OPTION cmd_info CFDP CFDP_PDU PDU", "    OPTION root_path <%= root_path %>", "    <% if bucket.to_s.strip != '' %>", "      OPTION bucket <%= bucket %>", "    <% end %>", "", "  <% test_host = ENV['KUBERNETES_SERVICE_HOST'] ? (scope.to_s.downcase + \"-interface-cfdp2-int-service\") : \"openc3-operator\" %>", "  INTERFACE CFDP_INT tcpip_client_interface.rb <%= test_host %> 2907 2907 10.0 nil LENGTH 0 32 4 1 BIG_ENDIAN 0 nil nil true", "    MAP_TARGET CFDP", "", "  INTERFACE CFDP2_INT tcpip_server_interface.rb 2907 2907 10.0 nil LENGTH 0 32 4 1 BIG_ENDIAN 0 nil nil true", "    PORT 2907", "    MAP_TARGET CFDP2", "<% end %>"], "needs_dependencies"=>false, "updated_at"=>nil}
Updating local plugin files: /plugins/DEFAULT/openc3-cosmos-cfdp
```

## List

Listはインストールされているすべてのプラグインを表示します。

```bash
% openc3.sh cli list
openc3-cosmos-cfdp-1.0.0.gem__20250325160956
openc3-cosmos-demo-6.2.2.pre.beta0.20250325143120.gem__20250325160201
openc3-cosmos-enterprise-tool-admin-6.2.2.pre.beta0.20250325155648.gem__20250325160159
openc3-cosmos-tool-autonomic-6.2.2.pre.beta0.20250325155658.gem__20250325160225
openc3-cosmos-tool-bucketexplorer-6.2.2.pre.beta0.20250325143107.gem__20250325160227
openc3-cosmos-tool-calendar-6.2.2.pre.beta0.20250325155654.gem__20250325160224
openc3-cosmos-tool-cmdhistory-6.2.2.pre.beta0.20250325155651.gem__20250325160212
openc3-cosmos-tool-cmdsender-6.2.2.pre.beta0.20250325143111.gem__20250325160211
openc3-cosmos-tool-cmdtlmserver-6.2.2.pre.beta0.20250325143114.gem__20250325160208
openc3-cosmos-tool-dataextractor-6.2.2.pre.beta0.20250325143104.gem__20250325160219
openc3-cosmos-tool-dataviewer-6.2.2.pre.beta0.20250325143108.gem__20250325160220
openc3-cosmos-tool-docs-6.2.2.pre.beta0.20250325155535.gem__20250325160228
openc3-cosmos-tool-grafana-6.2.2.pre.beta0.20250325155658.gem__20250325160233
openc3-cosmos-tool-handbooks-6.2.2.pre.beta0.20250325143113.gem__20250325160222
openc3-cosmos-tool-iframe-6.2.2.pre.beta0.20250325143110.gem__20250325160158
openc3-cosmos-tool-limitsmonitor-6.2.2.pre.beta0.20250325155448.gem__20250325160209
openc3-cosmos-tool-packetviewer-6.2.2.pre.beta0.20250325143104.gem__20250325160215
openc3-cosmos-tool-scriptrunner-6.2.2.pre.beta0.20250325143111.gem__20250325160214
openc3-cosmos-tool-tablemanager-6.2.2.pre.beta0.20250325143116.gem__20250325160223
openc3-cosmos-tool-tlmgrapher-6.2.2.pre.beta0.20250325143105.gem__20250325160218
openc3-cosmos-tool-tlmviewer-6.2.2.pre.beta0.20250325143108.gem__20250325160216
openc3-enterprise-tool-base-6.2.2.pre.beta0.20250325155704.gem__20250325160153
```

## Generate

Generateは新しいCOSMOSプラグイン、ターゲット、変換などを構築するために使用されます！詳細については、[ジェネレーター](/docs/getting-started/generators)ページを参照してください。

## Bridge

COSMOS Bridgeは、Dockerコンテナで利用できないハードウェアに接続するためにローカルコンピュータで実行される小さなアプリケーションです。良い例としては、非Linuxシステム上のシリアルポートへの接続があります。詳細については、
[ブリッジガイド](/docs/guides/bridges)を参照してください。

## Pkginstall と pkguninstall

RubyのgemやPythonのホイールをCOSMOSにインストールまたは削除することができます。これらは、COSMOSプラグイン自体にパッケージ化されていない依存関係です。

```bash
% openc3.sh cli pkginstall rspec-3.13.0.gem
```

## Rubysloc (非推奨)

現在のディレクトリから再帰的にRubyのSource Lines of Code (SLOC)を計算します。任意のプログラミング言語で動作し、より多くの統計を計算し、非常に高速な[scc](https://github.com/boyter/scc)を使用することをお勧めします。

## XTCE Converter

XTCE形式からCOSMOS形式への変換と、COSMOSプラグインからXTCEファイルをエクスポートします。

```bash
% openc3.sh cli xtce_converter
Usage: xtce_converter [options] --import input_xtce_filename --output output_dir
       xtce_converter [options] --plugin /PATH/FILENAME.gem --output output_dir --variables variables.txt

    -h, --help                       このメッセージを表示
    -i, --import VALUE               指定された.xtceファイルをインポート
    -o, --output DIRECTORY           ディレクトリにファイルを作成
    -p, --plugin PLUGIN              プラグインから.xtceファイルをエクスポート
    -v, --variables                  プラグインに渡すオプションの変数ファイル
```

## CSTOL Converter

Colorado System Test and Operations Language (CSTOL)からCOSMOS Script Runner Rubyスクリプトに変換します。現在、Pythonへの変換はサポートしていません。CSTOLファイル（\*.prc）と同じディレクトリで実行するだけで、すべてのファイルを変換します。

```bash
% openc3.sh cli cstol_converter
```