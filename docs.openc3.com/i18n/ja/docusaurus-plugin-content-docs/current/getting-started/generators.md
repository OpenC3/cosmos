---
sidebar_position: 6
title: コードジェネレーター
description: openc3.shを使用してコードを生成する
sidebar_custom_props:
  myEmoji: 🏭
---

COSMOSコードジェネレーターは、COSMOS [プロジェクト](https://github.com/OpenC3/cosmos-project)に含まれる`openc3.sh`と`openc3.bat`スクリプトに組み込まれています（[プロジェクト](key-concepts#projects)についての詳細はこちら）。

[インストールガイド](installation.md)に従った場合、すでにクローンした[openc3-project](https://github.com/OpenC3/cosmos-project)内にいるはずです。これはPATHに含まれている必要があります（openc3.bat / openc3.shを解決するために必要）。利用可能なすべてのコードジェネレーターを確認するには、次のように入力します：

```bash
% openc3.sh cli generate
Unknown generator ''. Valid generators: plugin, target, microservice, widget, conversion,
limits_response, tool, tool_vue, tool_angular, tool_react, tool_svelte
```

:::note トレーニング利用可能
トレーニングが必要である場合は、<a href="mailto:support@openc3.com">support@openc3.com</a>までお問い合わせください。トレーニングクラスをご用意しています！
:::

## プラグインジェネレーター

プラグインジェネレーターは、新しいCOSMOSプラグインのスキャフォールディング（構造）を作成します。プラグイン名が必要で、`openc3-cosmos-<name>`という新しいディレクトリを作成します。例えば：

```bash
% openc3.sh cli generate plugin
Usage: cli generate plugin <name>

% openc3.sh cli generate plugin GSE
Plugin openc3-cosmos-gse successfully generated!
```

これにより以下のファイルが作成されます：

| 名前                       | 説明                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| .gitignore                | gitにnode_modulesディレクトリを無視するよう指示します（ツール開発用）                                                                                                                                                                                                                                                                                                                                                                                     |
| LICENSE.txt               | プラグインのライセンス。COSMOSプラグインは、COSMOS Enterprise版でのみ使用するように設計されていない限り、AGPLv3と互換性のある方法でライセンスされるべきです                                                                                                                                                                                                                                                                                       |
| openc3-cosmos-gse.gemspec | 説明、作者、メール、ホームページなどのユーザー固有の情報を追加するために編集すべきGemspecファイル。このファイルの名前は、プラグインの内容を最終的な対応するgemファイルにコンパイルする際に使用されます（例：openc3-cosmos-gse-1.0.0.gem）。COSMOSプラグインは、Rubygemsリポジトリで簡単に識別できるように、常にopenc3-cosmos接頭で始める必要があります。このファイルは次の場所でドキュメント化されているフォーマットに従っています：https://guides.rubygems.org/specification-reference/ |
| plugin.txt                | プラグイン作成のためのCOSMOS固有のファイル。詳細は[こちら](../configuration/plugins)をご覧ください。                                                                                                                                                                                                                                                                                                                                                       |
| Rakefile                  | "openc3.sh cli rake build VERSION=X.X.X"を実行してプラグインをビルドするように設定されたRuby Rakeファイル。X.X.Xはプラグインのバージョン番号です                                                                                                                                                                                                                                                                                                           |
| README.md                 | プラグインを文書化するために使用されるMarkdownファイル                                                                                                                                                                                                                                                                                                                                                                                                    |
| requirements.txt          | Python依存関係ファイル（Pythonプラグインのみ）                                                                                                                                                                                                                                                                                                                                                                                                            |

この構造は必須ですが、それ自体ではあまり役に立ちません。プラグインジェネレーターは、他のジェネレーターが使用するフレームワークを作成するだけです。

## ターゲットジェネレーター

ターゲットジェネレーターは、新しいCOSMOSターゲットの基本構造を作成します。既存のCOSMOSプラグイン内で動作する必要があり、ターゲット名が必要です。例えば：

```bash
openc3-cosmos-gse % openc3.sh cli generate target
Usage: cli generate target <n> (--ruby or --python)

openc3-cosmos-gse % openc3.sh cli generate target GSE
Target GSE successfully generated!
```

これにより以下のファイルとディレクトリが作成されます：

| 名前                                    | 説明                                                                                                                                                                                                                                                                                                                                                                                                                   |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| targets/GSE                            | GSEターゲットの設定を含みます。ターゲット名は常に大文字で定義されます。これは通常、ターゲットのデフォルト名ですが、適切に設計されたターゲットはインストール時に名前を変更できるようにします                                                                                                                                                                                                                               |
| targets/GSE/cmd_tlm                    | GSEターゲットのコマンドとテレメトリの定義ファイルを含みます。これらのファイルは、ターゲットに送信できるコマンドの形式と、COSMOSがターゲットから受信すると予想されるテレメトリパケットを捕捉します。デフォルトでは、このフォルダ内のファイルはアルファベット順に処理されることに注意してください。これは、別のファイルでパケットを参照する場合に重要になることがあります（すでに定義されている必要があります）。                 |
| targets/GSE/cmd_tlm/cmd.txt            | [コマンド](../configuration/command.md)設定の例。ターゲット固有のコマンド用に編集する必要があります                                                                                                                                                                                                                                                                                                                         |
| targets/GSE/cmd_tlm/tlm.txt            | [テレメトリ](../configuration/telemetry)設定の例。ターゲット固有のテレメトリ用に編集する必要があります                                                                                                                                                                                                                                                                                                                     |
| targets/GSE/lib                        | ターゲットに必要なカスタムコードを含みます。カスタムコードの良い例としては、ライブラリファイル、カスタム[インターフェース](../configuration/interfaces)クラス、および[プロトコル](../configuration/protocols)があります                                                                                                                                                                                                        |
| targets/GSE/lib/gse.rb/py              | ターゲットの開発に伴って拡張できるライブラリファイルの例。COSMOSでは、コードの重複を避け、再利用を容易にするためにライブラリメソッドを構築することをお勧めします                                                                                                                                                                                                                                                            |
| targets/GSE/procedures                 | このフォルダには、ターゲットの機能を実行するターゲット固有の手順とヘルパーメソッドが含まれています。これらの手順はシンプルに保ち、このターゲットに関連付けられたコマンドとテレメトリの定義のみを使用する必要があります。詳細については、[スクリプト作成ガイド](../guides/script-writing)を参照してください。                                                                                                     |
| targets/GSE/procedures/procedure.rb/py | コマンドの送信とテレメトリのチェックの例を含む手順                                                                                                                                                                                                                                                                                                                                                                         |
| targets/GSE/public                     | [CANVASIMAGE](../configuration/telemetry-screens.md#canvasimage)や[CANVASIMAGEVALUE](configuration/telemetry-screens.md#canvasimagevalue)などのテレメトリビューアのキャンバス画像ウィジェットで使用する画像ファイルをここに配置します                                                                                                                                                                                       |
| targets/GSE/screens                    | ターゲット用のテレメトリ[画面](../configuration/telemetry-screens.md)を含みます                                                                                                                                                                                                                                                                                                                                            |
| targets/GSE/screens/status.txt         | テレメトリ値を表示するための[画面](../configuration/telemetry-screens.md)の例                                                                                                                                                                                                                                                                                                                                               |
| targets/GSE/target.txt                 | コマンドとテレメトリアイテムの無視やcmd/tlmファイルの処理方法などの[ターゲット](../configuration/target)設定                                                                                                                                                                                                                                                                                                                  |

また、新しいターゲットを追加するためにplugin.txtファイルも更新されます：

```ruby
VARIABLE gse_target_name GSE

TARGET GSE <%= gse_target_name %>
INTERFACE <%= gse_target_name %>_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TARGET <%= gse_target_name %>
```

## マイクロサービスジェネレーター

マイクロサービスジェネレーターは、新しいCOSMOSマイクロサービスの基本構造を作成します。既存のCOSMOSプラグイン内で動作する必要があり、ターゲット名が必要です。例えば：

```bash
openc3-cosmos-gse % openc3.sh cli generate microservice
Usage: cli generate microservice <n> (--ruby or --python)

openc3-cosmos-gse % openc3.sh cli generate microservice background
Microservice BACKGROUND successfully generated!
```

これにより以下のファイルとディレクトリが作成されます：

| 名前                                    | 説明                                                                                                                                                                                                                                                                           |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| microservices/BACKGROUND               | BACKGROUNDマイクロサービスのコードと必要な設定を含みます。名前は常に大文字で定義されます。これは通常、マイクロサービスのデフォルト名ですが、適切に設計されたマイクロサービスはインストール時に名前を変更できるようにします                                                           |
| microservices/BACKGROUND/background.rb | 毎分実行してメッセージをログに記録する完全に機能するマイクロサービス。バックグラウンドで実行したいカスタムロジックを実装するために編集します。潜在的な用途としては、複雑なイベントを確認して自律的に対応し、アクションを実行できる安全マイクロサービスがあります（注：単純なアクションはリミットレスポンスだけで十分かもしれません） |

また、新しいマイクロサービスを追加するためにplugin.txtファイルも更新されます：

```ruby
MICROSERVICE BACKGROUND background-microservice
  CMD ruby background.rb
```

## 変換ジェネレーター

変換ジェネレーターは、新しいCOSMOS [変換(Conversion)](../configuration/telemetry#read_conversion)の基本構造を作成します。既存のCOSMOSプラグイン内で動作する必要があり、ターゲット名と変換名の両方が必要です。例えば：

```bash
openc3-cosmos-gse % openc3.sh cli generate conversion
Usage: cli generate conversion <TARGET> <n> (--ruby or --python)

openc3-cosmos-gse % openc3.sh cli generate limits_response GSE double
Conversion targets/GSE/lib/double_conversion.rb successfully generated!
To use the conversion add the following to a telemetry item:
  READ_CONVERSION double_conversion.rb
```

これにより以下のファイルとディレクトリが作成されます：

| 名前                                 | 説明                                                                                                   |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| targets/GSE/lib/double_conversion.rb | 既存のCOSMOS値を変換するためのcall()メソッドの実装例を持つ完全に機能する変換                            |

ジェネレーターが述べているように、この変換コードを使用するにはテレメトリアイテムに追加する必要があります。例えば：

```ruby
TELEMETRY GSE STATUS BIG_ENDIAN "Telemetry description"
  # Keyword      Name  BitSize Type   ID Description
  APPEND_ID_ITEM ID    16      INT    1  "Identifier"
  APPEND_ITEM    VALUE 32      FLOAT     "Value"
    READ_CONVERSION double_conversion.rb
  APPEND_ITEM    BOOL  8       UINT      "Boolean"
    STATE FALSE 0
    STATE TRUE 1
  APPEND_ITEM    LABEL 0       STRING    "The label to apply"
```

## リミットレスポンスジェネレーター

リミットレスポンスジェネレーターは、新しいCOSMOS [リミットレスポンス](../configuration/telemetry#limits_response)の基本構造を作成します。既存のCOSMOSプラグイン内で動作する必要があり、ターゲット名とリミットレスポンス名の両方が必要です。例えば：

```bash
openc3-cosmos-gse % openc3.sh cli generate limits_response
Usage: cli generate limits_response <TARGET> <n> (--ruby or --python)

openc3-cosmos-gse % openc3.sh cli generate limits_response GSE safe
Limits response targets/GSE/lib/safe_limits_response.rb successfully generated!
To use the limits response add the following to a telemetry item:
  LIMITS_RESPONSE safe_limits_response.rb
```

これにより以下のファイルとディレクトリが作成されます：

| 名前                                    | 説明                                                                                                                        |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| targets/GSE/lib/safe_limits_response.rb | 特定のアイテムの現在のリミット状態に基づいてアクションを実行するcall()メソッドの実装例を持つ完全に機能するリミットレスポンス  |

ジェネレーターが述べているように、このリミットコードを使用するには、リミットが定義されているテレメトリアイテムに追加する必要があります。生成されたGSEターゲットでは、リミットが定義されているアイテムがないため、まずリミットを追加してからレスポンスを追加する必要があります。

```ruby
TELEMETRY GSE STATUS BIG_ENDIAN "Telemetry description"
  # Keyword      Name  BitSize Type   ID Description
  APPEND_ID_ITEM ID    16      INT    1  "Identifier"
  APPEND_ITEM    VALUE 32      FLOAT     "Value"
    LIMITS DEFAULT 1 ENABLED -80.0 -70.0 60.0 80.0 -20.0 20.0
    LIMITS_RESPONSE safe_limits_response.rb
  APPEND_ITEM    BOOL  8       UINT      "Boolean"
    STATE FALSE 0
    STATE TRUE 1
  APPEND_ITEM    LABEL 0       STRING    "The label to apply"
```

## ウィジェットジェネレーター

ウィジェットジェネレーターは、[テレメトリビューアー画面](../configuration/telemetry-screens)で使用するための新しいCOSMOSウィジェットの基本構造を作成します。詳細については、[カスタムウィジェット](../guides/custom-widgets)ガイドを参照してください。既存のCOSMOSプラグイン内で動作する必要があり、ウィジェット名が必要です。例えば：

```bash
openc3-cosmos-gse % openc3.sh cli generate widget
Usage: cli generate widget <SuperdataWidget>

openc3-cosmos-gse % openc3.sh cli generate widget HelloworldWidget
Widget HelloworldWidget successfully generated!
Please be sure HelloworldWidget does not overlap an existing widget: https://docs.openc3.com/docs/configuration/telemetry-screens
```

これにより以下のファイルとディレクトリが作成されます：

| 名前                     | 説明                                                                                                                                     |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| src/HelloworldWidget.vue | シンプルな値を表示する完全に機能するウィジェット。既存のCOSMOS Vue.jsコードを使用して拡張し、あらゆるデータ可視化を作成できます  |

また、新しいウィジェットを追加するためにplugin.txtファイルも更新されます：

```ruby
WIDGET Helloworld
```

## ツールジェネレーター

ツールジェネレーターは、新しいCOSMOSツールの基本構造を作成します。既存のCOSMOSプラグイン内で動作する必要があり、ツール名が必要です。カスタムツールの開発には、Vue.js、Angular、React、SvelteなどのJavascriptフレームワークに関する深い知識が必要です。すべてのCOSMOSツールはVue.jsで構築されているため、新しいツール開発には Vue.js が推奨されるフレームワークです。フロントエンド開発の詳細については、[フロントエンドアプリケーションの実行](../development/developing#フロントエンドアプリケーションの実行)を参照してください。

```bash
openc3-cosmos-gse % openc3.sh cli generate tool
Usage: cli generate tool 'Tool Name'

openc3-cosmos-gse % openc3.sh cli generate widget DataVis
Tool datavis successfully generated!
Please be sure datavis does not conflict with any other tools
```

これにより以下のファイルとディレクトリが作成されます：

| 名前                          | 説明                                                                                                                                                                                     |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| src/App.vue                   | アプリケーションをレンダリングするための基本的なVueテンプレート                                                                                                                            |
| src/main.js                   | Vue、Vuetify、その他のライブラリをロードする新しいツールのエントリーポイント                                                                                                               |
| src/router.js                 | Vueコンポーネントルーター                                                                                                                                                                |
| src/tools/datavis             | datavisという名前のウェブベースのツールを提供するために必要なすべてのファイルを含みます。名前は常に小文字で定義されます。技術的な制限により、ツール名は一意である必要があり、インストール時に名前を変更することはできません。 |
| src/tools/datavis/datavis.vue | シンプルなボタンを表示する完全に機能するツール。既存のCOSMOS Vue.jsコードを使用して拡張し、想像可能なあらゆるツールを作成できます                                                           |
| package.json                  | ビルドと依存関係の定義ファイル。npmまたはyarnがツールをビルドするために使用します                                                                                                          |
| vue.config.js                 | 開発環境でアプリケーションを提供し、アプリケーションをビルドするために使用されるVue設定ファイル                                                                                            |
| \<dotfiles\>                  | Javascriptフロントエンド開発用のフォーマッターやツールを設定するのに役立つ各種dotファイル                                                                                                   |

また、新しいツールを追加するためにplugin.txtファイルも更新されます。アイコンは[ここ](https://pictogrammers.com/library/mdi/)で見つかるマテリアルデザインアイコンの自由に変更できます。

```ruby
TOOL datavis "DataVis"
  INLINE_URL main.js
  ICON mdi-file-cad-box
```