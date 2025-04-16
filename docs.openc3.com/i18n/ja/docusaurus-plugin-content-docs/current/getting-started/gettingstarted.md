---
sidebar_position: 3
title: はじめに
description: COSMOSを初める
sidebar_custom_props:
  myEmoji: 🧑‍💻
---

OpenC3 COSMOSシステムへようこそ... さっそく始めましょう！このガイドは、最初のCOSMOSプロジェクトのセットアップに役立つ概要です。

1. [インストールガイド](installation)に従って、コンピュータにCOSMOSをインストールします。
   - これでCOSMOSがインストールされ、変更可能なデモプロジェクトが利用できるようになりました。
1. http://localhost:2900 にブラウザでアクセスします
   - COSMOS コマンド＆テレメトリサーバーが表示されます。このツールは、システム内の各「ターゲット」に関するリアルタイム情報を提供します。ターゲットとは、コマンドを受信してテレメトリを生成する外部システムで、多くの場合、イーサネットやシリアル接続を介して通信します。
1. 他のCOSMOSツールを試してみましょう。これはデモ環境なので、何も壊すことはありません。試してみることの例：
   - コマンドセンダーを使用して個々のコマンドを送信する
   - リミットモニターを使用してテレメトリの制限違反を監視する
   - スクリプトランナーとテストランナーでサンプルスクリプトを実行する
   - パケットビューアーで個々のテレメトリパケットを表示する
   - テレメトリビューアーで詳細なテレメトリ表示を見る
   - テレメトリグラファーでデータをグラフ化する
   - データビューアーでログタイプのデータを表示する
   - データエクストラクターでログデータを処理する

:::info ブラウザバージョンの問題

ページを読み込もうとして失敗する場合は、ブラウザの開発者ツール（DevTools）で確認してください。ブラウザのバージョンによっては奇妙な問題が発生することがあります。必要に応じて、[browserslist](https://github.com/browserslist/browserslist)について読むことで、特定のブラウザバージョン向けにビルドすることができます。典型的な失敗例は以下のようになります：

```
unexpected token ||=
```

これを修正するには、お使いのブラウザが[.browserlistrc](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/openc3-tool-base/.browserslistrc)ファイルの現在の設定に準拠していることを確認してください。これを変更してイメージを再ビルドすることができます。注意：これによりビルド速度が速くなったり遅くなったりする可能性があります。

:::

## ハードウェアとのインターフェース

COSMOSデモで遊ぶのは楽しいですが、ここからは実際のハードウェアと通信したいですよね？さっそくやってみましょう！

:::info インストールとプラットフォーム
このガイドでは、WindowsでCOSMOSがC:\COSMOSにインストールされていることを前提としています。MacまたはLinuxでは、openc3.batをopenc3.shに変更し、インストールディレクトリに合わせて必要に応じてパスを調整してください。
:::

1. 独自の設定を作成する前に、COSMOSデモをアンインストールして、クリーンなCOSMOSシステムで作業するようにしましょう。Adminボタンをクリックし、PLUGINSタブをクリックします。次に、openc3-cosmos-demoの横にあるゴミ箱アイコンをクリックして削除します。コマンド＆テレメトリサーバーに戻ると、インターフェースのない空のテーブルが表示されるはずです。

1. [インストールガイド](installation)に従った場合、すでにクローンした[openc3-project](https://github.com/OpenC3/cosmos-project)内にいるはずです。これはパス（PATH）に含まれており、openc3.bat / openc3.shが解決されるために必要です。このプロジェクト内では、README.md（[Markdown](https://www.markdownguide.org/)）を編集して、プログラムやプロジェクトについて説明することをお勧めします。

1. 次に、プラグインを作成する必要があります。プラグインは、ターゲットとマイクロサービスをCOSMOSに追加する方法です。プラグインには、ターゲットと通信するために必要なパケット（コマンドとテレメトリ）を定義するすべての情報を含む単一のターゲットが含まれます。COSMOSプラグインジェネレーターを使用して、正しい構造を作成しましょう。

:::info PythonとRuby
各CLIコマンドでは、OPENC3_LANGUAGE環境変数を'python'または'ruby'に設定していない限り、`--python`または`--ruby`の使用が必要です。
:::

```batch
C:\openc3-project> openc3.bat cli generate plugin BOB --python
Plugin openc3-cosmos-bob successfully generated!
```

これにより、「openc3-cosmos-bob」という新しいディレクトリが作成され、多くのファイルが含まれるはずです。すべてのファイルの詳細な説明は、[プラグインジェネレーター](generators#plugin-generator)ページで説明されています。

:::info ルートユーザーとして実行する
CLIはデフォルトのCOSMOSコンテナユーザーとして実行されます。これが推奨される方法です。そのユーザーとして実行する際に問題がある場合は、例のいずれかで`cli`の代わりに`cliroot`を実行することで、ルートユーザーとして実行できます（実質的に`docker run --user=root`と同じ）。
:::

1. [COSMOS v5.5.0](https://openc3.com/news/2023/02/23/openc3-cosmos-5-5-0-released/)以降では、プラグインジェネレーターはプラグインフレームワークのみを作成します（以前はターゲットも作成していました）。新しく作成されたプラグインディレクトリ内から、ターゲットを生成します。

   ```batch
   C:\openc3-project> cd openc3-cosmos-bob
   openc3-cosmos-bob> openc3.bat cli generate target BOB --python
   Target BOB successfully generated!
   ```

:::info ジェネレーター
利用可能なジェネレーターがいくつかあります。`openc3.bat cli generate`を実行して、利用可能なすべてのオプションを確認してください。
:::

1. ターゲットジェネレーターは、BOBという名前の単一のターゲットを作成します。ベストプラクティスは、プラグインごとに単一のターゲットを作成することで、ターゲットの共有と個別のアップグレードが容易になります。ターゲットジェネレーターが何を作成したのか見てみましょう。openc3-cosmos-bob/targets/BOB/cmd_tlm/cmd.txtを開きます：

   ```ruby
   COMMAND BOB EXAMPLE BIG_ENDIAN "Packet description"
     # Keyword           Name  BitSize Type   Min Max  Default  Description
     APPEND_ID_PARAMETER ID    16      INT    1   1    1        "Identifier"
     APPEND_PARAMETER    VALUE 32      FLOAT  0   10.5 2.5      "Value"
     APPEND_PARAMETER    BOOL  8       UINT   MIN MAX  0        "Boolean"
       STATE FALSE 0
       STATE TRUE 1
     APPEND_PARAMETER    LABEL 0       STRING          "OpenC3" "The label to apply"
   ```

   これはどういう意味でしょうか？

   - ターゲットBOBに対して、EXAMPLEという名前のCOMMAND（コマンド）を作成しました。
   - このコマンドはBIG_ENDIANパラメータで構成され、「Packet description」（パケットの説明）という説明がついています。ここでは、パラメータを定義するためにappend（追加）形式を使用しています。これは、パケットを構築する際にパラメータを連続して配置するため、パケット内のビットオフセットを定義する心配がありません。
   - 最初にAPPEND_ID_PARAMETERで、パケットを識別するために使用される「ID」というパラメータを追加しています。これは16ビット符号付き整数（INT）で、最小値は1、最大値は1、デフォルト値は1で、「Identifier」（識別子）と説明されています。
   - 次にAPPEND_PARAMETERで、「VALUE」という名前のパラメータを追加しています。これは32ビット浮動小数点数（FLOAT）で、最小値は0、最大値は10.5、デフォルト値は2.5です。
   - 次にAPPEND_PARAMETERで、3番目のパラメータ「BOOL」を追加しています。これは8ビット符号なし整数（UINT）で、最小値はMIN（UINTがサポートする最小値、例えば0を意味）、最大値はMAX（UINTがサポートする最大値、例えば255）、デフォルト値は0です。BOOLには2つの状態があり、これは整数値0と1に意味を持たせる方法です。状態FALSEは値0、状態TRUEは値1を持ちます。
   - 最後にAPPEND_PARAMETERで、「LABEL」というパラメータを追加しています。これは0ビット（パケット内の残りのすべてのスペースを占めることを意味）の文字列（STRING）で、デフォルト値は「OpenC3」です。文字列（STRING）には最小値や最大値はありません。

   詳細については、完全な[Command](../configuration/command)ドキュメントをご覧ください。

1. 次に、openc3-cosmos-bob/targets/BOB/cmd_tlm/tlm.txtを開きます：

   ```ruby
   TELEMETRY BOB STATUS BIG_ENDIAN "Telemetry description"
     # Keyword      Name  BitSize Type   ID Description
     APPEND_ID_ITEM ID    16      INT    1  "Identifier"
     APPEND_ITEM    VALUE 32      FLOAT     "Value"
     APPEND_ITEM    BOOL  8       UINT      "Boolean"
       STATE FALSE 0
       STATE TRUE 1
     APPEND_ITEM    LABEL 0       STRING    "The label to apply"
   ```

   - 今回は、ターゲットBOB用の「STATUS」という名前のTELEMETRY（テレメトリ）パケットを作成しました。このパケットはBIG_ENDIANアイテムを含み、「Telemetry description」（テレメトリの説明）という説明がついています。
   - まず、「ID」というID_ITEMを定義しています。これは16ビット符号付き整数（INT）で、ID値は1、説明は「Identifier」（識別子）です。IDアイテムは、未識別のバイトの塊（blob）を取り、それがどのパケットであるかを判断するために使用されます。この場合、値1のblobがビットオフセット0（このアイテムを最初にAPPENDするため）で入ってきた場合、16ビット整数として解釈され、このパケットは「STATUS」として「識別」されます。ID_ITEMなしで定義された最初のパケットは、すべての受信データに一致する「キャッチオール」パケットであることに注意してください（データの長さが一致しない場合でも）。
   - 次に、上記のコマンド定義と同様の3つのアイテムを定義します。

   詳細については、完全な[Telemetry](../configuration/telemetry)ドキュメントをご覧ください。

1. COSMOSは、ターゲット用のサンプルコマンドとテレメトリパケットを定義しました。ほとんどのターゲットは複数のコマンドとテレメトリパケットを持ちます。さらに追加するには、テキストファイルに追加のCOMMANDとTELEMETRY行を作成するだけです。実際のパケットは、コマンドとテレメトリの構造と一致する必要があります。パケットを互いに区別できるように、少なくとも1つの固有の[ID_PARAMETER](../configuration/command#id_parameter)と[ID_ITEM](../configuration/telemetry#id_item)を追加してください。

1. 次に、COSMOSにBOBターゲットへの接続方法を伝える必要があります。openc3-cosmos-bob/plugin.txtファイルを開きます：

   ```ruby
   # Set VARIABLEs here to allow variation in your plugin
   # See [Plugins](../configuration/plugins) for more information
   VARIABLE bob_target_name BOB

   # Modify this according to your actual target connection
   # See [Interfaces](../configuration/interfaces) for more information
   TARGET BOB <%= bob_target_name %>
   INTERFACE <%= bob_target_name %>_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 None BURST
      MAP_TARGET <%= bob_target_name %>
   ```

   - これにより、デフォルト値が「BOB」のbob_target_nameというVARIABLEを持つプラグインが設定されます。このプラグインをインストールする際に、このターゲットの名前を「BOB」以外のものに変更することができます。これは名前の競合を避け、COSMOSシステム内にBOBターゲットの複数のコピーを持つことができるため便利です。
   - TARGETラインは、変数から名前を使用して新しいBOBターゲットを宣言します。\<%= %>構文はERB（Embedded (埋め込み) Ruby）と呼ばれ、テキストファイルに変数を入れることができます。この場合、bob_target_nameを参照しています。
   - 最後の行は、（デフォルトで）BOB_INTと呼ばれる新しいINTERFACEを宣言します。これはTCP/IPクライアントとして接続し、tcpip_client_interface.pyのコードを使用してhost.docker.internal（これはホストのゲートウェイに対する正しいIPアドレスに/etc/hostsエントリを追加します）に接続します。書き込みにはポート8080、読み取りにはポート8081を使用します。また、書き込みタイムアウトは10秒で、読み取りはタイムアウトしません（None）。TCP/IPストリームはCOSMOS [BURST](../configuration/protocols#burst-protocol)プロトコルを使用して解釈され、これはインターフェースからできるだけ多くのデータを読み取ることを意味します。COSMOSインターフェースの設定方法の詳細については、[インターフェースガイド](../configuration/interfaces)をご覧ください。MAP_TARGETラインは、COSMOSがBOB_INTインターフェースを使用してBOBターゲットからテレメトリを受信し、コマンドを送信することを示しています。

:::note 変数は再利用性をサポートします

再利用する予定のプラグインでは、ホスト名やポートなどを変数にするのを推奨します
:::

## プラグインのビルド

1. 次に、プラグインをビルドしてCOSMOSにアップロードします。

   ```batch
   openc3-cosmos-bob> openc3.bat cli rake build VERSION=1.0.0
     Successfully built RubyGem
     Name: openc3-cosmos-bob
     Version: 1.0.0
     File: openc3-cosmos-bob-1.0.0.gem
   ```

   - ビルドするバージョンを指定するためにVERSIONが必要であることに注意してください。プラグインをビルドする際には[セマンティックバージョニング](https://semver.org/)をお勧めします。これにより、プラグインを使用する人々は、重大な変更がいつあるかを知ることができます。

1. プラグインがビルドされたら、COSMOSにアップロードします。Adminページに戻り、「Plugins」タブをクリックします。「Click to install plugin」をクリックし、openc3-cosmos-bob-1.0.0.gemファイルを選択します。次に「Upload」をクリックします。CmdTlmServerに戻ると、プラグインがデプロイされ、BOB_INTインターフェースが表示され、接続を試みるはずです。ポート8080で何かがリッスンしているのでなければ接続されることはないので、「Cancel」をクリックしてください。この時点で、他のCmdTlmServerタブや他のツールを調べて、新しく定義したBOBターゲットを確認できます。

1. BOBターゲットを変更して、COSMOS内のコピーを更新してみましょう。COSMOSのCommand SenderでBOB EXAMPLEを開くと、VALUEパラメータの値が2.5であることが分かります。openc3-cosmos-bob/targets/BOB/cmd_tlm/cmd.txtを開いて、VALUEのデフォルト値を5に、説明を「New Value」に変更します。

   ```ruby
   COMMAND BOB EXAMPLE BIG_ENDIAN "Packet description"
     # Keyword           Name  BitSize Type   Min Max  Default  Description
     APPEND_ID_PARAMETER ID    16      INT    1   1    1        "Identifier"
     APPEND_PARAMETER    VALUE 32      FLOAT  0   10.5 5        "New Value"
     APPEND_PARAMETER    BOOL  8       UINT   MIN MAX  0        "Boolean"
       STATE FALSE 0
       STATE TRUE 1
     APPEND_PARAMETER    LABEL 0       STRING          "OpenC3" "The label to apply"
   ```

1. 新しいVERSION番号でプラグインを再ビルドします。重大な変更を行っていないので、パッチリリース番号を単純に上げるだけです：

   ```batch
   openc3-cosmos-bob> openc3.bat cli rake build VERSION=1.0.1
     Successfully built RubyGem
     Name: openc3-cosmos-bob
     Version: 1.0.1
     File: openc3-cosmos-bob-1.0.1.gem
   ```

1. Adminページに戻り、「Plugins」タブをクリックします。今回は、openc3-cosmos-bob-1.0.0の横にある時計アイコンをクリックして、プラグインをアップグレードします。新しくビルドしたプラグインgemを参照して選択します。これにより、プラグイン変数（bob_target_name）の再入力が求められますが、名前を変更せずに「OK」をクリックしてください。プラグインがインストールされるというメッセージが表示され、プラグインリストがopenc3-cosmos-bob-1.0.1.gemに変更されるはずです。Command Senderに戻ると、VALUEの新しいデフォルト値が5、説明が「New Value」になっているはずです。これでプラグインをアップグレードしました！

1. この時点で、実際のターゲットにちなんだ名前の新しいプラグインを作成し、インターフェースとコマンド＆テレメトリの定義を変更して、COSMOSがターゲットに接続して制御できるようにすることができます。問題が発生した場合は、[Github Issues](https://github.com/OpenC3/cosmos/issues)ページで解決策を探してください。サポート契約や専門的なCOSMOS開発についてお問い合わせがある場合は、support@openc3.comまでご連絡ください。
