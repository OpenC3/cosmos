---
title: ロギング
description: COSMOSのログファイル
sidebar_custom_props:
  myEmoji: 🪵
---

COSMOS [バケットエクスプローラ](../tools/bucket-explorer.md)ツールは、ローカルで実行している場合でもクラウド環境で実行している場合でも、COSMOSのバケットストレージバックエンドを閲覧する方法を提供します。http://localhost:2900/tools/bucketexplorer に移動すると、上部にバケットのリストが表示されます：

![バケットエクスプローラ](pathname:///img/guides/logging/logs.png)

configとlogsバケットはスコープによって整理されており、初期状態では「DEFAULT」というスコープが一つだけあります。logsバケット内のDEFAULTフォルダをクリックすると、decom_logs、raw_logs、reduced_xxx_logs、text_logs、tool_logsが表示されます。

### decom_logs & raw_logs

decom_logsとraw_logsフォルダには、デコミュテーション（復調）された、および生のコマンドとテレメトリデータが含まれています。どちらもさらにターゲット、パケット、そして日付ごとに分けられています。例えば、DEFAULT/raw_logs/tlm/INST2/&lt;YYYYMMDD&gt;/ディレクトリを閲覧すると：

![raw_tlm_logs](pathname:///img/guides/logging/raw_tlm_logs.png)

生のバイナリデータを含むgzip圧縮された.binファイルが存在していることに注目してください。これらのファイルの構造について詳しくは、[ログ構造](../development/log-structure.md)の開発者ドキュメントを参照してください。

ロギングマイクロサービスのデフォルト設定では、10分ごとまたは50MBごとにいずれか早い方で新しいログファイルを開始します。低データレートのデモの場合、10分の区切りが先に来ます。

ロギング設定を変更するには、plugin.txtファイル内の宣言された[TARGET](../configuration/plugins.md#target-1)名の下に、様々なCYCLE_TIME [ターゲット修飾子](../configuration/plugins.md#target-modifiers)を追加します。

### text_logs

text_logsフォルダにはopenc3_log_messagesが含まれており、これには再び日付順にソートされタイムスタンプが付けられたテキストファイルが含まれています。これらのログメッセージは、サーバーやターゲットマイクロサービスを含む様々なマイクロサービスから生成されます。したがって、これらのログには送信されたすべてのコマンド（プレーンテキスト形式）と、チェックされたテレメトリが含まれています。これらのログメッセージファイルは、CmdTlmServerのログメッセージウィンドウに表示されるメッセージの長期的な記録です：

![log_messages](pathname:///img/guides/logging/log_messages.png)

### tool_logs

tool_logsディレクトリには、様々なCOSMOSツールからのログが含まれています。まだツールを実行していない場合、このディレクトリは必要に応じて作成されるため表示されない場合があることに注意してください。ツールのサブディレクトリも必要に応じて作成されます。例えば、Script Runnerでスクリプトを実行した後、スクリプト実行の結果としてのスクリプトランナーログを含む新しい「sr」サブディレクトリが表示されます。場合によっては、このディレクトリ内のログはツール自体から直接利用できることもあります。Script Runnerの場合、スクリプトの下にあるScript Messagesペインには、最後のスクリプトからの出力メッセージが表示されます。Downloadリンクをクリックすると、これらのメッセージをファイルとしてダウンロードできます。

![log_messages](pathname:///img/guides/logging/script_messages.png)