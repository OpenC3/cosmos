---
title: テーブルマネージャー
description: アップロード/ダウンロード機能付きバイナリファイルエディタ
sidebar_custom_props:
  myEmoji: 🛠️
---

## はじめに

テーブルマネージャーはバイナリファイルエディタです。COSMOSのコマンドパケット定義に似た[バイナリファイル定義](../configuration/table.md)を取り、バイナリファイル内のフィールドを編集するためのGUIです。

![テーブルマネージャー](/img/table_manager/table_manager.png)

### ファイルメニュー項目

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/table_manager/file_menu.png').default}
alt="ファイルメニュー"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 150 + 'px'}} />

- [定義](../configuration/table.md)に基づいた新しいバイナリを作成
- 既存のバイナリを開く
- 現在のバイナリを保存
- 現在のバイナリの名前を変更
- 現在のバイナリを削除

## ファイルダウンロード

ファイルダウンロードの横にある3つのボタンは、バイナリファイル、[定義](../configuration/table.md)ファイル、およびレポートファイルをダウンロードします。バイナリはテーブルで定義された生のビットです。[定義](../configuration/table.md)はこれらの生のビットの構造定義です。レポートファイルはテーブルマネージャーが生成したCSVで、バイナリ内のすべてのテーブル値を表示します。

## アップロード/ダウンロード

テーブルマネージャーには、バイナリファイルをターゲットにアップロードしたり、ファイルをテーブルマネージャーにダウンロードしたりするためにCOSMOSスクリプトを直接呼び出す機能があります。ターゲットのproceduresディレクトリに`upload.rb`というファイルが見つかると、アップロードボタン (Upload) がアクティブになります。ターゲットのproceduresディレクトリに`download.rb`というファイルが見つかると、ダウンロードボタン (Download) がアクティブになります。B/Gボタンはアップロード/ダウンロードスクリプトをバックグラウンドで実行するかどうかを示します。このボックスのチェックを外すと、新しいスクリプトランナーウィンドウがスクリプトの行ごとの実行を表示します。

### upload.rb

COSMOSデモは次の`upload.rb`スクリプトを作成します。`ENV['TBL_FILENAME']`がテーブルファイルの名前に設定され、スクリプトは`get_target_file`を使用してファイルにアクセスすることに注意してください。この時点で、ファイルをターゲットにアップロードするロジックはターゲットによって定義されたコマンドに固有ですが、例としてスクリプトが提供されています。

```ruby
# TBL_FILENAMEはテーブルファイルの名前に設定されます
puts "file:#{ENV['TBL_FILENAME']}"
# ファイルを開く
file = get_target_file(ENV['TBL_FILENAME'])
buffer = file.read
# puts buffer.formatted
# テーブルをアップロードするためのカスタムコマンドロジックを実装
# bufferはバイトのRuby文字列であることに注意
# おそらく次のようにしたいでしょう：
# buf_size = 512 # アップロードコマンドのバッファサイズ
# i = 0
# while i < buffer.length
#   # バッファの一部を送信
#   # 注意：三つのドットは開始インデックス、終了インデックスを含まない範囲を意味します
#   #   二つのドットは開始インデックス、終了インデックスを含む範囲を意味します
#   cmd("TGT", "UPLOAD", "DATA" => buffer[i...(i + buf_size)])
#   i += buf_size
# end
file.delete
```

### download.rb

COSMOSデモは次の`download.rb`スクリプトを作成します。`ENV['TBL_FILENAME']`が上書きするテーブルファイルの名前に設定され、スクリプトは`put_target_file`を使用してファイルにアクセスすることに注意してください。この時点で、ターゲットからファイルをダウンロードするロジックはターゲットによって定義されたコマンドに固有ですが、例としてスクリプトが提供されています。

```ruby
# TBL_FILENAMEは上書きするテーブルファイルの名前に設定されます
puts "file:#{ENV['TBL_FILENAME']}"
# ファイルをダウンロード
# テーブルをダウンロードするためのカスタムコマンドロジックを実装
# おそらく次のようにしたいでしょう：
buffer = ''
# i = 1
# num_segments = 5 # TBL_FILENAMEに基づいて計算
# table_id = 1  # TBL_FILENAMEに基づいて計算
# while i < num_segments
#   # テーブルバッファの一部をリクエスト
#   cmd("TGT DUMP with TABLE_ID #{table_id}, SEGMENT #{i}")
#   buffer += tlm("TGT DUMP_PKT DATA")
#   i += 1
# end
put_target_file(ENV['TBL_FILENAME'], buffer)
```