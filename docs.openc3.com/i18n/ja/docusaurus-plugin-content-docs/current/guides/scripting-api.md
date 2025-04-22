---
title: スクリプティング API ガイド
description: スクリプティング API メソッド、非推奨機能および移行
sidebar_custom_props:
  myEmoji: 📝
---

このドキュメントでは、COSMOS スクリプティング API を使用してテスト手順を記述するために必要な情報を提供します。COSMOS でのスクリプティングはシンプルに設計されています。コマンドやテレメトリのニーモニックにコード補完機能があるため、Script Runner はプロシージャを作成するのに理想的な場所ですが、任意のテキストエディタでも作成できます。ここに記載されていない機能や、より簡単な構文が必要な場合は、チケットを送信してください。

## 概念

### プログラミング言語

COSMOS スクリプティングは Ruby または Python のいずれかを使って実装されています。Ruby と Python は非常に似たスクリプト言語であり、多くの場合、COSMOS API は両方で同一です。このガイドは両方をサポートするために書かれており、言語固有の追加情報は [スクリプト作成ガイド](../guides/script-writing.md) にあります。

### Script Runner の使用

Script Runner はテスト手順の実行と実装のための理想的な環境を提供するグラフィカルアプリケーションです。Script Runner ツールは主に 4 つのセクションに分かれています。ツールの上部にはメニューバーがあり、ファイルの開閉、構文チェック、スクリプトの実行などができます。

次に、現在実行中のスクリプトと「Start/Go」、「Pause/Retry」、「Stop」の 3 つのボタンを表示するツールバーがあります。Start/Go ボタンはスクリプトを開始し、エラーや待機を越えて継続するために使用されます。Pause/Retry ボタンは実行中のスクリプトを一時停止します。エラーが発生した場合、Pause ボタンは Retry に変わり、エラーが発生した行を再実行します。最後に、Stop ボタンはいつでも実行中のスクリプトを停止します。

3 番目は実際のスクリプトの表示です。スクリプトが実行されていないとき、このエリアでスクリプトを編集・作成することができます。便利なコード補完機能があり、スクリプトを書いている時に利用可能なコマンドやテレメトリポイントのリストが表示されます。cmd( または tlm( の行を書き始めるだけでコード補完が表示されます。この機能により、コマンドとテレメトリのニーモニックでのタイプミスが大幅に減少します。

最後に、ディスプレイの一番下にはログメッセージがあります。送信されたコマンド、発生したエラー、ユーザーのプリント文がすべてこのエリアに表示されます。

### テレメトリタイプ

COSMOS ではテレメトリ値を取得する 4 つの異なる方法があります。以下の表ではその違いを説明しています。

| テレメトリタイプ     | 説明                                                                                                                                                                                                                                                                                                                                |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Raw                  | 生のテレメトリは、変換前のテレメトリパケットにあるまさにそのままの状態です。派生テレメトリポイント（パケット内に実際の位置を持たないもの）を除くすべてのテレメトリ項目は生の値を持ちます。派生項目に対して生のテレメトリを要求すると nil が返されます。                                                                        |
| Converted            | 変換されたテレメトリは、状態変換や多項式変換などの変換係数を通過した生のテレメトリです。テレメトリ項目に変換が定義されていない場合、変換されたテレメトリは生のテレメトリと同じになります。これはスクリプトで最も一般的に使用されるテレメトリのタイプです。                                                                      |
| Formatted            | フォーマットされたテレメトリは、printf スタイルの変換を経て文字列になった変換済みテレメトリです。フォーマットされたテレメトリは常に文字列表現を持ちます。テレメトリポイントにフォーマット文字列が定義されていない場合、フォーマットされたテレメトリは変換されたテレメトリと同じですが、文字列として表現されます。               |
| Formatted with Units | 単位付きでフォーマットされたテレメトリは、フォーマットされたテレメトリと同じですが、文字列の末尾にスペースとテレメトリ項目の単位が追加されます。テレメトリ項目に単位が定義されていない場合、このタイプはフォーマットされたテレメトリと同じになります。                                                                          |

## Script Runner API

以下のメソッドは Script Runner の手順で使用するために設計されています。多くは、カスタムビルドされた COSMOS ツールでも使用できます。カスタムツールでより効率的に使用するメソッドについては、COSMOS Tool API セクションを参照してください。

### COSMOS v5 から v6 への移行

以下の API メソッドは COSMOS v6 から削除されました。ほとんどの非推奨 API メソッドは後方互換性のために残っています。

| メソッド            | ツール                       | ステータス                               |
| ------------------- | ---------------------------- | ---------------------------------------- |
| get_all_target_info | Command and Telemetry Server | 削除、get_target_interfaces を使用       |
| play_wav_file       | Script Runner                | 削除                                     |
| status_bar          | Script Runner                | 削除                                     |

### COSMOS v4 から v5 への移行

以下の API メソッドはいずれも非推奨（COSMOS 5 に移植されません）、または現在未実装（最終的に COSMOS 5 に移植される予定）です：

| メソッド                                | ツール                       | ステータス                                                         |
| --------------------------------------- | ---------------------------- | ------------------------------------------------------------------ |
| clear                                   | Telemetry Viewer             | 非推奨、clear_screen を使用                                        |
| clear_all                               | Telemetry Viewer             | 非推奨、clear_all_screens を使用                                   |
| close_local_screens                     | Telemetry Viewer             | 非推奨、clear_screen を使用                                        |
| clear_disconnected_targets              | Script Runner                | 非推奨                                                             |
| cmd_tlm_clear_counters                  | Command and Telemetry Server | 非推奨                                                             |
| cmd_tlm_reload                          | Command and Telemetry Server | 非推奨                                                             |
| display                                 | Telemetry Viewer             | 非推奨、display_screen を使用                                      |
| get_all_packet_logger_info              | Command and Telemetry Server | 非推奨                                                             |
| get_all_target_info                     | Command and Telemetry Server | 非推奨、get_target_interfaces を使用                               |
| get_background_tasks                    | Command and Telemetry Server | 非推奨                                                             |
| get_all_cmd_info                        | Command and Telemetry Server | 非推奨、get_all_cmds を使用                                        |
| get_all_tlm_info                        | Command and Telemetry Server | 非推奨、get_all_tlm を使用                                         |
| get_cmd_list                            | Command and Telemetry Server | 非推奨、get_all_cmds を使用                                        |
| get_cmd_log_filename                    | Command and Telemetry Server | 非推奨                                                             |
| get_cmd_param_list                      | Command and Telemetry Server | 非推奨、get_cmd を使用                                             |
| get_cmd_tlm_disconnect                  | Script Runner                | 非推奨、$disconnect を使用                                         |
| get_disconnected_targets                | Script Runner                | 未実装                                                             |
| get_interface_info                      | Command and Telemetry Server | 非推奨、get_interface を使用                                       |
| get_interface_targets                   | Command and Telemetry Server | 非推奨                                                             |
| get_output_logs_filenames               | Command and Telemetry Server | 非推奨                                                             |
| get_packet                              | Command and Telemetry Server | 非推奨、get_packets を使用                                         |
| get_packet_data                         | Command and Telemetry Server | 非推奨、get_packets を使用                                         |
| get_packet_logger_info                  | Command and Telemetry Server | 非推奨                                                             |
| get_packet_loggers                      | Command and Telemetry Server | 非推奨                                                             |
| get_replay_mode                         | Replay                       | 非推奨                                                             |
| get_router_info                         | Command and Telemetry Server | 非推奨、get_router を使用                                          |
| get_scriptrunner_message_log_filename   | Command and Telemetry Server | 非推奨                                                             |
| get_server_message                      | Command and Telemetry Server | 非推奨                                                             |
| get_server_message_log_filename         | Command and Telemetry Server | 非推奨                                                             |
| get_server_status                       | Command and Telemetry Server | 非推奨                                                             |
| get_stale                               | Command and Telemetry Server | 非推奨                                                             |
| get_target_ignored_items                | Command and Telemetry Server | 非推奨、get_target を使用                                          |
| get_target_ignored_parameters           | Command and Telemetry Server | 非推奨、get_target を使用                                          |
| get_target_info                         | Command and Telemetry Server | 非推奨、get_target を使用                                          |
| get_target_list                         | Command and Telemetry Server | 非推奨、get_target_names を使用                                    |
| get_tlm_details                         | Command and Telemetry Server | 非推奨                                                             |
| get_tlm_item_list                       | Command and Telemetry Server | 非推奨                                                             |
| get_tlm_list                            | Command and Telemetry Server | 非推奨                                                             |
| get_tlm_log_filename                    | Command and Telemetry Server | 非推奨                                                             |
| interface_state                         | Command and Telemetry Server | 非推奨、get_interface を使用                                       |
| override_tlm_raw                        | Command and Telemetry Server | 非推奨、override_tlm を使用                                        |
| open_directory_dialog                   | Script Runner                | 非推奨                                                             |
| play_wav_file                           | Script Runner                | 非推奨                                                             |
| replay_move_end                         | Replay                       | 非推奨                                                             |
| replay_move_index                       | Replay                       | 非推奨                                                             |
| replay_move_start                       | Replay                       | 非推奨                                                             |
| replay_play                             | Replay                       | 非推奨                                                             |
| replay_reverse_play                     | Replay                       | 非推奨                                                             |
| replay_select_file                      | Replay                       | 非推奨                                                             |
| replay_set_playback_delay               | Replay                       | 非推奨                                                             |
| replay_status                           | Replay                       | 非推奨                                                             |
| replay_step_back                        | Replay                       | 非推奨                                                             |
| replay_step_forward                     | Replay                       | 非推奨                                                             |
| replay_stop                             | Replay                       | 非推奨                                                             |
| require_utility                         | Script Runner                | 非推奨ですが後方互換性のため存在、load_utility を使用             |
| router_state                            | Command and Telemetry Server | 非推奨、get_router を使用                                          |
| save_file_dialog                        | Script Runner                | 非推奨                                                             |
| save_setting                            | Command and Telemetry Server | 非推奨ですが後方互換性のため存在、set_setting を使用              |
| set_cmd_tlm_disconnect                  | Script Runner                | 非推奨、disconnect_script を使用                                   |
| set_disconnected_targets                | Script Runner                | 未実装                                                             |
| set_replay_mode                         | Replay                       | 非推奨                                                             |
| set_stdout_max_lines                    | Script Runner                | 非推奨                                                             |
| set_tlm_raw                             | Script Runner                | 非推奨、set_tlm を使用                                             |
| show_backtrace                          | Script Runner                | 非推奨、バックトレースは常に表示                                   |
| status_bar                              | Script Runner                | 非推奨                                                             |
| shutdown_cmd_tlm                        | Command and Telemetry Server | 非推奨                                                             |
| start_cmd_log                           | Command and Telemetry Server | 非推奨                                                             |
| start_logging                           | Command and Telemetry Server | 非推奨                                                             |
| start_new_scriptrunner_message_log      | Command and Telemetry Server | 非推奨                                                             |
| start_new_server_message_log            | Command and Telemetry Server | 非推奨                                                             |
| start_tlm_log                           | Command and Telemetry Server | 非推奨                                                             |
| stop_background_task                    | Command and Telemetry Server | 非推奨                                                             |
| stop_cmd_log                            | Command and Telemetry Server | 非推奨                                                             |
| stop_logging                            | Command and Telemetry Server | 非推奨                                                             |
| stop_tlm_log                            | Command and Telemetry Server | 非推奨                                                             |
| subscribe_limits_events                 | Command and Telemetry Server | 非推奨                                                             |
| subscribe_packet_data                   | Command and Telemetry Server | 非推奨、subscribe_packets を使用                                   |
| subscribe_server_messages               | Command and Telemetry Server | 未実装                                                             |
| tlm_variable                            | Script Runner                | 非推奨、tlm() を使用してタイプを渡す                               |
| unsubscribe_limits_events               | Command and Telemetry Server | 非推奨                                                             |
| unsubscribe_packet_data                 | Command and Telemetry Server | 非推奨                                                             |
| unsubscribe_server_messages             | Command and Telemetry Server | 非推奨                                                             |
| wait_raw                                | Script Runner                | 非推奨、wait(..., type: :RAW) を使用                               |
| wait_check_raw                          | Script Runner                | 非推奨、wait_check(..., type: :RAW) を使用                         |
| wait_tolerance_raw                      | Script Runner                | 非推奨、wait_tolerance(..., type: :RAW) を使用                     |
| wait_check_tolerance_raw                | Script Runner                | 非推奨、wait_check_tolerance(..., type: :RAW) を使用               |

## ユーザー入力の取得

これらのメソッドを使用すると、スクリプトに必要な値をユーザーが入力できます。

### ask

質問でユーザーに入力を促します。ユーザー入力は自動的に文字列から適切なデータ型に変換されます。例えば、ユーザーが「1」と入力すると、整数としての数値 1 が返されます。

Ruby / Python 構文：

```ruby
ask("<question>", <Blank or Default>, <Password>)
```

| パラメータ         | 説明                                                                                                                  |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| question           | ユーザーに表示する質問。                                                                                              |
| Blank or Default   | 空の応答を許可するかどうか（オプション - デフォルトは false）。ブール値でない値が渡された場合、デフォルト値として使用されます。 |
| Password           | 入力をパスワードとして扱うかどうか。パスワードはドットで表示され、ログに記録されません。デフォルトは false です。    |

Ruby の例：

```ruby
value = ask("整数を入力してください")
value = ask("値を入力するか何も入力しないでください", true)
value = ask("値を入力してください", 10)
password = ask("パスワードを入力してください", false, true)
```

Python の例：

```python
value = ask("整数を入力してください")
value = ask("値を入力するか何も入力しないでください", True)
value = ask("値を入力してください", 10)
password = ask("パスワードを入力してください", False, True)
```

### ask_string

質問でユーザーに入力を促します。ユーザー入力は常に文字列として返されます。例えば、ユーザーが「1」と入力すると、文字列「1」が返されます。

Ruby / Python 構文：

```ruby
ask_string("<question>", <Blank or Default>, <Password>)
```

| パラメータ         | 説明                                                                                                                  |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| question           | ユーザーに表示する質問。                                                                                              |
| Blank or Default   | 空の応答を許可するかどうか（オプション - デフォルトは false）。ブール値でない値が渡された場合、デフォルト値として使用されます。 |
| Password           | 入力をパスワードとして扱うかどうか。パスワードはドットで表示され、ログに記録されません。デフォルトは false です。    |

Ruby の例：

```rubystring = ask_string("文字列を入力してください")
string = ask_string("値を入力するか何も入力しないでください", true)
string = ask_string("値を入力してください", "test")
password = ask_string("パスワードを入力してください", false, true)
```

Python の例：

```python
string = ask_string("文字列を入力してください")
string = ask_string("値を入力するか何も入力しないでください", True)
string = ask_string("値を入力してください", "test")
password = ask_string("パスワードを入力してください", False, True)
```

### message_box

### vertical_message_box

### combo_box

message_box、vertical_message_box、および combo_box メソッドは、ユーザーがクリックできる任意のボタンまたは選択肢を持つメッセージボックスを作成します。クリックされたボタンのテキストが返されます。

Ruby / Python 構文：

```ruby
message_box("<Message>", "<button text 1>", ...)
vertical_message_box("<Message>", "<button text 1>", ...)
combo_box("<Message>", "<selection text 1>", ...)
```

| パラメータ            | 説明                           |
| --------------------- | ------------------------------ |
| Message               | ユーザーに表示するメッセージ。 |
| Button/Selection Text | ボタンまたは選択肢のテキスト   |

Ruby の例：

```ruby
value = message_box("センサー番号を選択してください", 'One', 'Two')
value = vertical_message_box("センサー番号を選択してください", 'One', 'Two')
value = combo_box("センサー番号を選択してください", 'One', 'Two')
case value
when 'One'
  puts 'センサー One'
when 'Two'
  puts 'センサー Two'
end
```

Python の例：

```python
value = message_box("センサー番号を選択してください", 'One', 'Two')
value = vertical_message_box("センサー番号を選択してください", 'One', 'Two')
value = combo_box("センサー番号を選択してください", 'One', 'Two')
match value:
    case 'One':
        print('センサー One')
    case 'Two':
        print('センサー Two')
```

### get_target_file

ターゲットディレクトリ内のファイルへのファイルハンドルを返します

Ruby 構文：

```ruby
get_target_file("<File Path>", original: false)
```

Python 構文：

```ruby
get_target_file("<File Path>", original=False)
```

| パラメータ | 説明                                                                                                                                                                                                                                               |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| File Path  | ターゲットディレクトリ内のファイルへのパス。TARGET 名で始まると想定されます。例：INST/procedures/proc.rb                                                                                                                                           |
| original   | プラグインから元のファイルを取得するか、ファイルへの変更を取得するかどうか。デフォルトは false で、これは変更されたファイルを取得することを意味します。変更されたファイルが存在しない場合、API は自動的に元のファイルを取得しようとします。 |

Ruby の例：

```ruby
file = get_target_file("INST/data/attitude.bin")
puts file.read().formatted # バイナリファイルをフォーマット
file.unlink # ファイルを削除
file = get_target_file("INST/procedures/checks.rb", original: true)
puts file.read()
file.unlink # ファイルを削除
```

Python の例：

```python
from openc3.utilities.string import formatted

file = get_target_file("INST/data/attitude.bin")
print(formatted(file.read())) # バイナリファイルをフォーマット
file.close() # ファイルを削除
file = get_target_file("INST/procedures/checks.rb", original=True)
print(file.read())
file.close() # ファイルを削除
```

### put_target_file

ターゲットディレクトリにファイルを書き込みます

Ruby / Python 構文：

```ruby
put_target_file("<File Path>", "IO or String")
```

| パラメータ    | 説明                                                                                                                                                                                                                                                                                                 |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| File Path     | ターゲットディレクトリ内のファイルへのパス。TARGET 名で始まると想定されます。例：INST/procedures/proc.rb。ファイルは以前に存在していてもしていなくても構いません。注意：プラグインの元のファイルは変更されませんが、既存の変更されたファイルは上書きされます。                                    |
| IO or String  | データは IO オブジェクトまたは文字列です                                                                                                                                                                                                                                                             |

Ruby の例：

```ruby
put_target_file("INST/test1.txt", "これは文字列テストです")
file = Tempfile.new('test')
file.write("これは Io テストです")
file.rewind
put_target_file("INST/test2.txt", file)
put_target_file("INST/test3.bin", "\x00\x01\x02\x03\xFF\xEE\xDD\xCC") # バイナリ
```

Python の例：

```python
put_target_file("INST/test1.txt", "これは文字列テストです")
file = tempfile.NamedTemporaryFile(mode="w+t")
file.write("これは Io テストです")
file.seek(0)
put_target_file("INST/test2.txt", file)
put_target_file("INST/test3.bin", b"\x00\x01\x02\x03\xFF\xEE\xDD\xCC") # バイナリ
```

### delete_target_file

ターゲットディレクトリ内のファイルを削除します

Ruby / Python 構文：

```ruby
delete_target_file("<File Path>")
```

| パラメータ | 説明                                                                                                                                                                                                                                 |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| File Path  | ターゲットディレクトリ内のファイルへのパス。TARGET 名で始まると想定されます。例：INST/procedures/proc.rb。注意：put_target_file で作成されたファイルのみ削除できます。プラグインのインストールからの元のファイルは残ります。 |

Ruby / Python の例：

```ruby
put_target_file("INST/delete_me.txt", "削除される予定")
delete_target_file("INST/delete_me.txt")
```

### open_file_dialog

### open_files_dialog

open_file_dialog および open_files_dialog メソッドは、ユーザーが単一または複数のファイルを選択できるファイルダイアログボックスを作成します。選択したファイルが返されます。

注意：COSMOS 5 では save_file_dialog および open_directory_dialog メソッドが非推奨になっています。ファイルをターゲットに書き戻したい場合は、save_file_dialog を put_target_file に置き換えることができます。新しいアーキテクチャでは open_directory_dialog は意味がないため、個々のファイルをリクエストする必要があります。

Ruby 構文：

```ruby
open_file_dialog("<Title>", "<Message>", filter: "<filter>")
open_files_dialog("<Title>", "<Message>", filter: "<filter>")
```

Python 構文：

```python
open_file_dialog("<Title>", "<Message>", filter="<filter>")
open_files_dialog("<Title>", "<Message>", filter="<filter>")
```

| パラメータ | 説明                                                                                                                                                                                                                             |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Title      | ダイアログに表示するタイトル。必須。                                                                                                                                                                                            |
| Message    | ダイアログボックスに表示するメッセージ。オプションのパラメータ。                                                                                                                                                                |
| filter     | 許可されるファイルタイプをフィルタリングするための名前付きパラメータ。オプションのパラメータで、コンマ区切りのファイルタイプで指定します。例：".txt,.doc"。詳細は https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input/file#accept を参照してください。 |

Ruby の例：

```ruby
file = open_file_dialog("単一ファイルを開く", "ファイルを選んでください", filter: ".txt")
puts file # Ruby File オブジェクト
puts file.read
file.delete

files = open_files_dialog("複数のファイルを開く") # メッセージはオプション
puts files # File オブジェクトの配列（1つだけ選択しても）
files.each do |file|
  puts file
  puts file.read
  file.delete
end
```

Python の例：

```python
file = open_file_dialog("単一ファイルを開く", "ファイルを選んでください", filter=".txt")
print(file)
print(file.read())
file.close()

files = open_files_dialog("複数のファイルを開く") # メッセージはオプション
print(files) # File オブジェクトの配列（1つだけ選択しても）
for file in files:
    print(file)
    print(file.read())
    file.close()
```

## ユーザーへの情報提供

これらのメソッドは、何かが発生したことをユーザーに通知します。

### prompt

ユーザーにメッセージを表示し、OKボタンを押すのを待ちます。

Ruby / Python 構文：

```ruby
prompt("<Message>")
```

| パラメータ | 説明                           |
| ---------- | ------------------------------ |
| Message    | ユーザーに表示するメッセージ。 |

Ruby / Python の例：

```ruby
prompt("続行するには OK を押してください")
```

## コマンド

これらのメソッドは、ターゲットにコマンドを送信し、システム内のコマンドに関する情報を受信する機能を提供します。

### cmd

指定されたコマンドを送信します。

Ruby 構文：

```ruby
cmd("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd("<Target Name>", "<Command Name>", "Param #1 Name" => <Param #1 Value>, "Param #2 Name" => <Param #2 Value>, ...)
```

Python 構文：

```python
cmd("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd("<Target Name>", "<Command Name>", {"Param #1 Name": <Param #1 Value>, "Param #2 Name": <Param #2 Value>, ...})
```

| パラメータ       | 説明                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| Target Name      | このコマンドに関連付けられているターゲットの名前。                                   |
| Command Name     | このコマンドの名前。ニーモニックとも呼ばれます。                                     |
| Param #x Name    | コマンドパラメータの名前。パラメータがない場合は 'with' キーワードを指定しないでください。 |
| Param #x Value   | コマンドパラメータの値。値は自動的に適切な型に変換されます。                         |
| timeout          | デフォルトのタイムアウト値（5秒）を変更するための名前付きパラメータ                   |
| log_message      | コマンドのログを防ぐための名前付きパラメータ                                         |

Ruby の例：

```ruby
cmd("INST COLLECT with DURATION 10, TYPE NORMAL")
# Ruby ではパラメータの周りの括弧はオプション
cmd("INST", "COLLECT", "DURATION" => 10, "TYPE" => "NORMAL")
cmd("INST", "COLLECT", { "DURATION" => 10, "TYPE" => "NORMAL" })
cmd("INST ABORT", timeout: 10, log_message: false)
```

Python の例：

```python
cmd("INST COLLECT with DURATION 10, TYPE NORMAL")
cmd("INST", "COLLECT", { "DURATION": 10, "TYPE": "NORMAL" })
cmd("INST ABORT", timeout=10, log_message=False)
```

### cmd_no_range_check

パラメータの範囲チェックを実行せずに指定したコマンドを送信します。これは、ターゲットをテストするために意図的に不正なコマンドパラメータを送信する必要がある場合にのみ使用してください。

Ruby 構文：

```ruby
cmd_no_range_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_range_check("<Target Name>", "<Command Name>", "Param #1 Name" => <Param #1 Value>, "Param #2 Name" => <Param #2 Value>, ...)
```

Python 構文：

```python
cmd_no_range_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_range_check("<Target Name>", "<Command Name>", {"Param #1 Name": <Param #1 Value>, "Param #2 Name": <Param #2 Value>, ...})
```

| パラメータ       | 説明                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| Target Name      | このコマンドに関連付けられているターゲットの名前。                                   |
| Command Name     | このコマンドの名前。ニーモニックとも呼ばれます。                                     |
| Param #x Name    | コマンドパラメータの名前。パラメータがない場合は 'with' キーワードを指定しないでください。 |
| Param #x Value   | コマンドパラメータの値。値は自動的に適切な型に変換されます。                         |
| timeout          | デフォルトのタイムアウト値（5秒）を変更するための名前付きパラメータ                   |
| log_message      | コマンドのログを防ぐための名前付きパラメータ                                         |

Ruby の例：

```ruby
cmd_no_range_check("INST COLLECT with DURATION 11, TYPE NORMAL")
cmd_no_range_check("INST", "COLLECT", "DURATION" => 11, "TYPE" => "NORMAL")
```

Python の例：

```python
cmd_no_range_check("INST COLLECT with DURATION 11, TYPE NORMAL")
cmd_no_range_check("INST", "COLLECT", {"DURATION": 11, "TYPE": "NORMAL"})
```

### cmd_no_hazardous_check

危険なコマンドである場合の通知を行わずに指定されたコマンドを送信します。これは、危険なコマンドを含むテストを完全に自動化する必要がある場合にのみ使用してください。

Ruby 構文：

```ruby
cmd_no_hazardous_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_hazardous_check("<Target Name>", "<Command Name>", "Param #1 Name" => <Param #1 Value>, "Param #2 Name" => <Param #2 Value>, ...)
```

Python 構文：

```python
cmd_no_hazardous_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_hazardous_check("<Target Name>", "<Command Name>", {"Param #1 Name": <Param #1 Value>, "Param #2 Name": <Param #2 Value>, ...})
```

| パラメータ       | 説明                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| Target Name      | このコマンドに関連付けられているターゲットの名前。                                   |
| Command Name     | このコマンドの名前。ニーモニックとも呼ばれます。                                     |
| Param #x Name    | コマンドパラメータの名前。パラメータがない場合は 'with' キーワードを指定しないでください。 |
| Param #x Value   | コマンドパラメータの値。値は自動的に適切な型に変換されます。                         |
| timeout          | デフォルトのタイムアウト値（5秒）を変更するための名前付きパラメータ                   |
| log_message      | コマンドのログを防ぐための名前付きパラメータ                                         |

Ruby / Python の例：

```ruby
cmd_no_hazardous_check("INST CLEAR")
cmd_no_hazardous_check("INST", "CLEAR")
```

### cmd_no_checks

パラメータの範囲チェックを実行せず、コマンドが危険なコマンドである場合の通知も行わずに指定されたコマンドを送信します。これは、意図的に無効なパラメータを持つ危険なコマンドを含むテストを完全に自動化する必要がある場合にのみ使用してください。

Ruby 構文：

```ruby
cmd_no_checks("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_checks("<Target Name>", "<Command Name>", "Param #1 Name" => <Param #1 Value>, "Param #2 Name" => <Param #2 Value>, ...)
```

Python 構文：

```python
cmd_no_checks("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_checks("<Target Name>", "<Command Name>", {"Param #1 Name": <Param #1 Value>, "Param #2 Name": <Param #2 Value>, ...})
```

| パラメータ       | 説明                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| Target Name      | このコマンドに関連付けられているターゲットの名前。                                   |
| Command Name     | このコマンドの名前。ニーモニックとも呼ばれます。                                     |
| Param #x Name    | コマンドパラメータの名前。パラメータがない場合は 'with' キーワードを指定しないでください。 |
| Param #x Value   | コマンドパラメータの値。値は自動的に適切な型に変換されます。                         |
| timeout          | デフォルトのタイムアウト値（5秒）を変更するための名前付きパラメータ                   |
| log_message      | コマンドのログを防ぐための名前付きパラメータ                                         |

Ruby の例：

```ruby
cmd_no_checks("INST COLLECT with DURATION 11, TYPE SPECIAL")
cmd_no_checks("INST", "COLLECT", "DURATION" => 11, "TYPE" => "SPECIAL")
```

Python の例：

```python
cmd_no_checks("INST COLLECT with DURATION 11, TYPE SPECIAL")
cmd_no_checks("INST", "COLLECT", {"DURATION": 11, "TYPE": "SPECIAL"})
```

### cmd_raw

変換を実行せずに指定されたコマンドを送信します。

Ruby 構文：

```ruby
cmd_raw("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw("<Target Name>", "<Command Name>", "<Param #1 Name>" => <Param #1 Value>, "<Param #2 Name>" => <Param #2 Value>, ...)
```

Python 構文：

```python
cmd_raw("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw("<Target Name>", "<Command Name>", {"<Param #1 Name>": <Param #1 Value>, "<Param #2 Name>": <Param #2 Value>, ...})
```

| パラメータ       | 説明                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| Target Name      | このコマンドに関連付けられているターゲットの名前。                                   |
| Command Name     | このコマンドの名前。ニーモニックとも呼ばれます。                                     |
| Param #x Name    | コマンドパラメータの名前。パラメータがない場合は 'with' キーワードを指定しないでください。 |
| Param #x Value   | コマンドパラメータの値。値は自動的に適切な型に変換されます。                         |
| timeout          | デフォルトのタイムアウト値（5秒）を変更するための名前付きパラメータ                   |
| log_message      | コマンドのログを防ぐための名前付きパラメータ                                         |

Ruby の例：

```ruby
cmd_raw("INST COLLECT with DURATION 10, TYPE 0")
cmd_raw("INST", "COLLECT", "DURATION" => 10, "TYPE" => 0)
```

Python の例：

```python
cmd_raw("INST COLLECT with DURATION 10, TYPE 0")
cmd_raw("INST", "COLLECT", {"DURATION": 10, "TYPE": 0})
```

### cmd_raw_no_range_check

変換を実行せず、パラメータの範囲チェックも実行せずに指定されたコマンドを送信します。これは、ターゲットをテストするために意図的に不正なコマンドパラメータを送信する必要がある場合にのみ使用してください。

Ruby 構文：

```ruby
cmd_raw_no_range_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_range_check("<Target Name>", "<Command Name>", "<Param #1 Name>" => <Param #1 Value>, "<Param #2 Name>" => <Param #2 Value>, ...)
```

Python 構文：

```python
cmd_raw_no_range_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_range_check("<Target Name>", "<Command Name>", {"<Param #1 Name>": <Param #1 Value>, "<Param #2 Name>": <Param #2 Value>, ...})
```

| パラメータ       | 説明                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| Target Name      | このコマンドに関連付けられているターゲットの名前。                                   |
| Command Name     | このコマンドの名前。ニーモニックとも呼ばれます。                                     |
| Param #x Name    | コマンドパラメータの名前。パラメータがない場合は 'with' キーワードを指定しないでください。 |
| Param #x Value   | コマンドパラメータの値。値は自動的に適切な型に変換されます。                         |
| timeout          | デフォルトのタイムアウト値（5秒）を変更するための名前付きパラメータ                   |
| log_message      | コマンドのログを防ぐための名前付きパラメータ                                         |

Ruby の例：

```ruby
cmd_raw_no_range_check("INST COLLECT with DURATION 11, TYPE 0")
cmd_raw_no_range_check("INST", "COLLECT", "DURATION" => 11, "TYPE" => 0)
```

Python の例：

```python
cmd_raw_no_range_check("INST COLLECT with DURATION 11, TYPE 0")
cmd_raw_no_range_check("INST", "COLLECT", {"DURATION": 11, "TYPE": 0})
```

### cmd_raw_no_hazardous_check

変換を実行せず、コマンドが危険なコマンドである場合の通知も行わずに指定されたコマンドを送信します。これは、危険なコマンドを含むテストを完全に自動化する必要がある場合にのみ使用してください。

Ruby 構文：

```ruby
cmd_raw_no_hazardous_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_hazardous_check("<Target Name>", "<Command Name>", "<Param #1 Name>" => <Param #1 Value>, "<Param #2 Name>" => <Param #2 Value>, ...)
```

Python 構文：

```python
cmd_raw_no_hazardous_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_hazardous_check("<Target Name>", "<Command Name>", {"<Param #1 Name>": <Param #1 Value>, "<Param #2 Name>": <Param #2 Value>, ...})
```

| パラメータ       | 説明                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| Target Name      | このコマンドに関連付けられているターゲットの名前。                                   |
| Command Name     | このコマンドの名前。ニーモニックとも呼ばれます。                                     |
| Param #x Name    | コマンドパラメータの名前。パラメータがない場合は 'with' キーワードを指定しないでください。 |
| Param #x Value   | コマンドパラメータの値。値は自動的に適切な型に変換されます。                         |
| timeout          | デフォルトのタイムアウト値（5秒）を変更するための名前付きパラメータ                   |
| log_message      | コマンドのログを防ぐための名前付きパラメータ                                         |

Ruby / Python の例：

```ruby
cmd_raw_no_hazardous_check("INST CLEAR")
cmd_raw_no_hazardous_check("INST", "CLEAR")
```

### cmd_raw_no_checks

変換、パラメータの範囲チェック、およびコマンドが危険なコマンドである場合の通知を実行せずに指定されたコマンドを送信します。これは、意図的に無効なパラメータを持つ危険なコマンドを含むテストを完全に自動化する必要がある場合にのみ使用してください。

Ruby 構文：

```ruby
cmd_raw_no_checks("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_checks("<Target Name>", "<Command Name>", "<Param #1 Name>" => <Param #1 Value>, "<Param #2 Name>" => <Param #2 Value>, ...)
```

Python 構文：

```python
cmd_raw_no_checks("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_checks("<Target Name>", "<Command Name>", {"<Param #1 Name>": <Param #1 Value>, "<Param #2 Name>": <Param #2 Value>, ...})
```

| パラメータ       | 説明                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------ |
| Target Name      | このコマンドに関連付けられているターゲットの名前。                                   |
| Command Name     | このコマンドの名前。ニーモニックとも呼ばれます。                                     |
| Param #x Name    | コマンドパラメータの名前。パラメータがない場合は 'with' キーワードを指定しないでください。 |
| Param #x Value   | コマンドパラメータの値。値は自動的に適切な型に変換されます。                         |
| timeout          | デフォルトのタイムアウト値（5秒）を変更するための名前付きパラメータ                   |
| log_message      | コマンドのログを防ぐための名前付きパラメータ                                         |

Ruby の例：

```ruby
cmd_raw_no_checks("INST COLLECT with DURATION 11, TYPE 1")
cmd_raw_no_checks("INST", "COLLECT", "DURATION" => 11, "TYPE" => 1)
```

Python の例：

```python
cmd_raw_no_checks("INST COLLECT with DURATION 11, TYPE 1")
cmd_raw_no_checks("INST", "COLLECT", {"DURATION": 11, "TYPE": 1})
```

### build_cmd

> 5.13.0 から、5.8.0 では build_command として

特定のコマンドの生のバイトを確認できるようにコマンドのバイナリ文字列を構築します。コマンドについてのエンディアン、説明、項目などの情報を取得するには [get_cmd](#get_cmd) を使用してください。

Ruby 構文：

```ruby
build_cmd(<ARGS>, range_check: true, raw: false)
```

Python 構文：

```python
build_cmd(<ARGS>, range_check=True, raw=False)
```

| パラメータ   | 説明                                                         |
| ------------ | ------------------------------------------------------------ |
| ARGS         | コマンドパラメータ（cmd を参照）                             |
| range_check  | コマンドの範囲チェックを実行するかどうか。デフォルトは true。 |
| raw          | コマンド引数を RAW または CONVERTED 値として書き込むかどうか。デフォルトは CONVERTED。 |

Ruby の例：

```ruby
x = build_cmd("INST COLLECT with DURATION 10, TYPE NORMAL")
puts x  #=> {"id"=>"1696437370872-0", "result"=>"SUCCESS", "time"=>"1696437370872305961", "received_time"=>"1696437370872305961", "target_name"=>"INST", "packet_name"=>"COLLECT", "received_count"=>"3", "buffer"=>"\x13\xE7\xC0\x00\x00\f\x00\x01\x00\x00A \x00\x00\xAB\x00\x00\x00\x00"}
```

Python の例：

```python
x = build_cmd("INST COLLECT with DURATION 10, TYPE NORMAL")
print(x)  #=> {'id': '1697298167748-0', 'result': 'SUCCESS', 'time': '1697298167749155717', 'received_time': '1697298167749155717', 'target_name': 'INST', 'packet_name': 'COLLECT', 'received_count': '2', 'buffer': bytearray(b'\x13\xe7\xc0\x00\x00\x0c\x00\x01\x00\x00A \x00\x00\xab\x00\x00\x00\x00')}
```

### enable_cmd

> 5.15.1 から

無効化されたコマンドを有効にします。無効化されたコマンドを送信すると、「INST ABORT is Disabled」のようなメッセージで `DisabledError` が発生します。

Ruby / Python 構文：

```ruby
buffer = enable_cmd("<Target Name> <Command Name>")
buffer = enable_cmd("<Target Name>", "<Command Name>")
```

| パラメータ   | 説明                        |
| ------------ | --------------------------- |
| Target Name  | ターゲットの名前。          |
| Packet Name  | コマンド（パケット）の名前。 |

Ruby / Python の例：

```ruby
enable_cmd("INST ABORT")
```

### disable_cmd

> 5.15.1 から

コマンドを無効にします。無効化されたコマンドを送信すると、「INST ABORT is Disabled」のようなメッセージで `DisabledError` が発生します。

Ruby / Python 構文：

```ruby
buffer = disable_cmd("<Target Name> <Command Name>")
buffer = disable_cmd("<Target Name>", "<Command Name>")
```

| パラメータ   | 説明                        |
| ------------ | --------------------------- |
| Target Name  | ターゲットの名前。          |
| Packet Name  | コマンド（パケット）の名前。 |

Ruby / Python の例：

```ruby
disable_cmd("INST ABORT")
```

### send_raw

インターフェース上で生のデータを送信します。

Ruby / Python 構文：

```ruby
send_raw(<Interface Name>, <Data>)
```

| パラメータ       | 説明                                         |
| ---------------- | -------------------------------------------- |
| Interface Name   | 生のデータを送信するインターフェースの名前。 |
| Data             | 送信する生のデータのRuby文字列。             |

Ruby / Python の例：

```ruby
send_raw("INST_INT", data)
```

### get_all_cmds

> 5.13.0 から、5.0.0 では get_all_commands として

特定のターゲットで利用可能なコマンドの配列を返します。返される配列は、コマンドパケットを完全に記述するハッシュの配列（Pythonではディクショナリのリスト）です。

Ruby / Python 構文：

```ruby
get_all_cmds("<Target Name>")
```

| パラメータ   | 説明                 |
| ------------ | -------------------- |
| Target Name  | ターゲットの名前。   |

Ruby の例：

```ruby
cmd_list = get_all_cmds("INST")
puts cmd_list  #=>
# [{"target_name"=>"INST",
#   "packet_name"=>"ABORT",
#   "endianness"=>"BIG_ENDIAN",
#   "description"=>"Aborts a collect on the instrument",
#   "items"=> [{"name"=>"CCSDSVER", "bit_offset"=>0, "bit_size"=>3, ... }]
# ...
# }]
```

Python の例：

```python
cmd_list = get_all_cmds("INST")
print(cmd_list)  #=>
# [{'target_name': 'INST',
#   'packet_name': 'ABORT',
#   'endianness': 'BIG_ENDIAN',
#   'description': 'Aborts a collect on the INST instrument',
#   'items': [{'name': 'CCSDSVER', 'bit_offset': 0, 'bit_size': 3, ... }]
# ...
# }]
```

### get_all_cmd_names

> 5.13.0 から、5.0.6 では get_all_command_names として

特定のターゲットのコマンド名の配列を返します。

Ruby / Python 構文：

```ruby
get_all_cmd_names("<Target Name>")
```

| パラメータ   | 説明                |
| ------------ | ------------------- |
| Target Name  | ターゲットの名前    |

Ruby の例：

```ruby
cmd_list = get_all_cmd_names("INST")
puts cmd_list  #=> ['ABORT', 'ARYCMD', 'ASCIICMD', ...]
```

Python の例：

```python
cmd_list = get_all_cmd_names("INST")
print(cmd_list)  #=> ['ABORT', 'ARYCMD', 'ASCIICMD', ...]
```

### get_cmd

> 5.13.0 から、5.0.0 では get_command として

コマンドパケットを完全に記述するコマンドハッシュを返します。構築済みコマンドのバイナリバッファを取得するには [build_cmd](#build_cmd) を使用してください。

Ruby / Python 構文：

```ruby
get_cmd("<Target Name> <Packet Name>")
get_cmd("<Target Name>", "<Packet Name>")
```

| パラメータ   | 説明                 |
| ------------ | -------------------- |
| Target Name  | ターゲットの名前。   |
| Packet Name  | パケットの名前。     |

Ruby / Python の例：

```ruby
abort_cmd = get_cmd("INST ABORT")
puts abort_cmd  #=>
# [{"target_name"=>"INST",
#   "packet_name"=>"ABORT",
#   "endianness"=>"BIG_ENDIAN",
#   "description"=>"Aborts a collect on the instrument",
#   "items"=> [{"name"=>"CCSDSVER", "bit_offset"=>0, "bit_size"=>3, ... }]
# ...
# }]
```

Python の例：

```python
abort_cmd = get_cmd("INST ABORT")
print(abort_cmd)  #=>
# [{'target_name': 'INST',
#   'packet_name': 'ABORT',
#   'endianness': 'BIG_ENDIAN',
#   'description': 'Aborts a collect on the INST instrument',
#   'items': [{'name': 'CCSDSVER', 'bit_offset': 0, 'bit_size': 3, ... }]
# ...
# }]
```

### get_param

> 5.13.0 から、5.0.0 では get_parameter として

指定されたコマンドパラメータのハッシュを返します

Ruby / Python 構文：

```ruby
get_param("<Target Name> <Command Name> <Parameter Name>")
get_param("<Target Name>", "<Command Name>", "<Parameter Name>")
```

| パラメータ      | 説明                    |
| --------------- | ----------------------- |
| Target Name     | ターゲットの名前。      |
| Command Name    | コマンドの名前。        |
| Parameter Name  | パラメータの名前。      |

Ruby の例：

```ruby
param = get_param("INST COLLECT TYPE")
puts param  #=>
# {"name"=>"TYPE", "bit_offset"=>64, "bit_size"=>16, "data_type"=>"UINT",
#  "description"=>"Collect type which can be normal or special", "default"=>0,
#  "minimum"=>0, "maximum"=>65535, "endianness"=>"BIG_ENDIAN", "required"=>true, "overflow"=>"ERROR",
#  "states"=>{"NORMAL"=>{"value"=>0}, "SPECIAL"=>{"value"=>1, "hazardous"=>""}}, "limits"=>{}}
```

Python の例：

```python
param = get_param("INST COLLECT TYPE")
print(param)  #=>
# {'name': 'TYPE', 'bit_offset': 64, 'bit_size': 16, 'data_type': 'UINT',
#  'description': 'Collect type which can be normal or special', 'default': 0,
#  'minimum': 0, 'maximum': 65535, 'endianness': 'BIG_ENDIAN', 'required': True, 'overflow': 'ERROR',
#  'states': {'NORMAL': {'value': 0}, 'SPECIAL': {'value': 1, 'hazardous': ''}}, 'limits': {}}
```

### get_cmd_buffer

Ruby文字列としての生のパケットバッファとともにパケットハッシュ（get_cmdと同様）を返します。

Ruby / Python 構文：

```ruby
buffer = get_cmd_buffer("<Target Name> <Packet Name>")['buffer']
buffer = get_cmd_buffer("<Target Name>", "<Packet Name>")['buffer']
```

| パラメータ   | 説明                 |
| ------------ | -------------------- |
| Target Name  | ターゲットの名前。   |
| Packet Name  | パケットの名前。     |

Ruby の例：

```ruby
packet = get_cmd_buffer("INST COLLECT")
puts packet  #=>
# {"time"=>"1697298846752053420", "received_time"=>"1697298846752053420",
#  "target_name"=>"INST", "packet_name"=>"COLLECT", "received_count"=>"20", "stored"=>"false",
#  "buffer"=>"\x13\xE7\xC0\x00\x00\f\x00\x01\x00\x00@\xE0\x00\x00\xAB\x00\x00\x00\x00"}
```

Python の例：

```python
packet = get_cmd_buffer("INST COLLECT")
print(packet)  #=>
# {'time': '1697298923745982470', 'received_time': '1697298923745982470',
#  'target_name': 'INST', 'packet_name': 'COLLECT', 'received_count': '21', 'stored': 'false',
#  'buffer': bytearray(b'\x13\xe7\xc0\x00\x00\x0c\x00\x01\x00\x00@\xe0\x00\x00\xab\x00\x00\x00\x00')}
```

### get_cmd_hazardous

特定のコマンドが危険としてフラグが立てられているかどうかを示すtrue/falseを返します。

Ruby / Python 構文：

```ruby
get_cmd_hazardous("<Target Name>", "<Command Name>", <Command Params - optional>)
```

| パラメータ      | 説明                                                                                                |
| --------------- | --------------------------------------------------------------------------------------------------- |
| Target Name     | ターゲットの名前。                                                                                  |
| Command Name    | コマンドの名前。                                                                                    |
| Command Params  | コマンドに渡されるパラメータのハッシュ（オプション）。一部のコマンドはパラメータの状態に基づいてのみ危険です。 |

Ruby の例：

```ruby
hazardous = get_cmd_hazardous("INST", "COLLECT", {'TYPE' => 'SPECIAL'})
puts hazardous  #=> true
```

Python の例：

```python
hazardous = get_cmd_hazardous("INST", "COLLECT", {'TYPE': 'SPECIAL'})
print(hazardous) #=> True
```

### get_cmd_value

最後に送信されたコマンドパケットから値を読み取ります。擬似パラメータの「PACKET_TIMESECONDS」、「PACKET_TIMEFORMATTED」、「RECEIVED_COUNT」、「RECEIVED_TIMEFORMATTED」、および「RECEIVED_TIMESECONDS」もサポートされています。

Ruby / Python 構文：

```ruby
get_cmd_value("<Target Name>", "<Command Name>", "<Parameter Name>", <Value Type - optional>)
```

| パラメータ      | 説明                                                                          |
| --------------- | ----------------------------------------------------------------------------- |
| Target Name     | ターゲットの名前。                                                            |
| Command Name    | コマンドの名前。                                                              |
| Parameter Name  | コマンドパラメータの名前。                                                    |
| Value Type      | 読み取る値のタイプ。RAW、CONVERTED、FORMATTED、または WITH_UNITS。注：Ruby ではシンボル、Python では文字列 |

Ruby の例：

```ruby
value = get_cmd_value("INST", "COLLECT", "TEMP", :RAW)
puts value  #=> 0.0
```

Python の例：

```python
value = get_cmd_value("INST", "COLLECT", "TEMP", "RAW")
print(value)  #=> 0.0
```

### get_cmd_time

最近送信されたコマンドの時間を返します。

Ruby / Python 構文：

```ruby
get_cmd_time("<Target Name - optional>", "<Command Name - optional>")
```

| パラメータ     | 説明                                                                                                |
| -------------- | --------------------------------------------------------------------------------------------------- |
| Target Name    | ターゲットの名前。指定されない場合、任意のターゲットへの最新のコマンド時間が返されます              |
| Command Name   | コマンドの名前。指定されない場合、指定されたターゲットへの最新のコマンド時間が返されます            |

Ruby / Python の例：

```ruby
target_name, command_name, time = get_cmd_time() # 任意のターゲットに送信された最新のコマンドの名前と時間
target_name, command_name, time = get_cmd_time("INST") # INSTターゲットに送信された最新のコマンドの名前と時間
target_name, command_name, time = get_cmd_time("INST", "COLLECT") # 最新のINST COLLECTコマンドの名前と時間
```

### get_cmd_cnt

指定されたコマンドが送信された回数を返します。

Ruby / Python 構文：

```ruby
get_cmd_cnt("<Target Name> <Command Name>")
get_cmd_cnt("<Target Name>", "<Command Name>")
```

| パラメータ     | 説明                |
| -------------- | ------------------- |
| Target Name    | ターゲットの名前。  |
| Command Name   | コマンドの名前。    |

Ruby / Python の例：

```ruby
cmd_cnt = get_cmd_cnt("INST COLLECT") # INST COLLECTコマンドが送信された回数
```

### get_cmd_cnts

指定されたコマンドが送信された回数を返します。

Ruby / Python 構文：

```ruby
get_cmd_cnts([["<Target Name>", "<Command Name>"], ["<Target Name>", "<Command Name>"], ...])
```

| パラメータ     | 説明                |
| -------------- | ------------------- |
| Target Name    | ターゲットの名前。  |
| Command Name   | コマンドの名前。    |

Ruby / Python の例：

```ruby
cmd_cnt = get_cmd_cnts([['INST', 'COLLECT'], ['INST', 'ABORT']]) # INST COLLECTとINST ABORTコマンドが送信された回数
```

### critical_cmd_status

クリティカルコマンドのステータスを返します。APPROVED、REJECTED、または WAITINGのいずれかです。

> 5.20.0 から

Ruby / Python 構文：

```ruby
critical_cmd_status(uuid)
```

| パラメータ | 説明                                                 |
| ---------- | ---------------------------------------------------- |
| uuid       | クリティカルコマンドのUUID（COSMOS GUIに表示されます） |

Ruby / Python の例：

```ruby
status = critical_cmd_status("2fa14183-3148-4399-9a74-a130257118f9") #=> WAITING
```

### critical_cmd_approve

現在のユーザーとしてクリティカルコマンドを承認します。

> 5.20.0 から

Ruby / Python 構文：

```ruby
critical_cmd_approve(uuid)
```

| パラメータ | 説明                                                 |
| ---------- | ---------------------------------------------------- |
| uuid       | クリティカルコマンドのUUID（COSMOS GUIに表示されます） |

Ruby / Python の例：

```ruby
critical_cmd_approve("2fa14183-3148-4399-9a74-a130257118f9")
```

### critical_cmd_reject

現在のユーザーとしてクリティカルコマンドを拒否します。

> 5.20.0 から

Ruby / Python 構文：

```ruby
critical_cmd_reject(uuid)
```

| パラメータ | 説明                                                 |
| ---------- | ---------------------------------------------------- |
| uuid       | クリティカルコマンドのUUID（COSMOS GUIに表示されます） |

Ruby / Python の例：

```ruby
critical_cmd_reject("2fa14183-3148-4399-9a74-a130257118f9")
```

### critical_cmd_can_approve

現在のユーザーがクリティカルコマンドを承認できるかどうかを返します。

> 5.20.0 から

Ruby / Python 構文：

```ruby
critical_cmd_can_approve(uuid)
```

| パラメータ | 説明                                                 |
| ---------- | ---------------------------------------------------- |
| uuid       | クリティカルコマンドのUUID（COSMOS GUIに表示されます） |

Ruby / Python の例：

```ruby
status = critical_cmd_can_approve("2fa14183-3148-4399-9a74-a130257118f9") #=> true / false
```

## テレメトリの処理

これらのメソッドを使用すると、ユーザーはテレメトリ項目を操作できます。

### check, check_raw, check_formatted, check_with_units

指定されたテレメトリタイプを使用してテレメトリ項目の検証を実行します。検証が失敗すると、スクリプトはエラーで一時停止します。検証するための比較が与えられていない場合、テレメトリ項目は単にスクリプト出力に表示されます。注意: ほとんどの場合、check よりも wait_check を使用する方が良い選択です。

Ruby / Python 構文：

```ruby
check("<Target Name> <Packet Name> <Item Name> <Comparison - optional>")
```

| パラメータ   | 説明                                                                                                           |
| ------------ | -------------------------------------------------------------------------------------------------------------- |
| Target Name  | テレメトリ項目のターゲットの名前。                                                                              |
| Packet Name  | テレメトリ項目のテレメトリパケットの名前。                                                                      |
| Item Name    | テレメトリ項目の名前。                                                                                          |
| Comparison   | テレメトリ項目に対して実行する比較。比較が与えられていない場合、テレメトリ項目はスクリプトログに表示されるだけです。 |

Ruby の例：

```ruby
check("INST HEALTH_STATUS COLLECTS > 1")
check_raw("INST HEALTH_STATUS COLLECTS > 1")
check_formatted("INST HEALTH_STATUS COLLECTS > 1")
check_with_units("INST HEALTH_STATUS COLLECTS > 1")
# Rubyではタイプをシンボルとして渡します
check("INST HEALTH_STATUS COLLECTS > 1", type: :RAW)
```

Python の例：

```python
check("INST HEALTH_STATUS COLLECTS > 1")
check_raw("INST HEALTH_STATUS COLLECTS > 1")
check_formatted("INST HEALTH_STATUS COLLECTS > 1")
check_with_units("INST HEALTH_STATUS COLLECTS > 1")
# Pythonではタイプを文字列として渡します
check("INST HEALTH_STATUS COLLECTS > 1", type='RAW')
```

### check_tolerance

変換されたテレメトリ項目を許容範囲内の期待値と比較します。検証が失敗すると、スクリプトはエラーで一時停止します。注意: ほとんどの場合、check_tolerance よりも wait_check_tolerance を使用する方が良い選択です。

Ruby / Python 構文：

```ruby
check_tolerance("<Target Name> <Packet Name> <Item Name>", <Expected Value>, <Tolerance>)
```

| パラメータ       | 説明                                                                 |
| ---------------- | -------------------------------------------------------------------- |
| Target Name      | テレメトリ項目のターゲットの名前。                                    |
| Packet Name      | テレメトリ項目のテレメトリパケットの名前。                            |
| Item Name        | テレメトリ項目の名前。                                                |
| Expected Value   | テレメトリ項目の期待値。                                              |
| Tolerance        | 期待値に対する±許容範囲。                                            |
| type             | CONVERTED（デフォルト）または RAW（Rubyではシンボル、Pythonでは文字列） |

Ruby の例：

```ruby
check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0)
check_tolerance("INST HEALTH_STATUS TEMP1", 50000, 20000, type: :RAW)
```

Python の例：

```python
check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0)
check_tolerance("INST HEALTH_STATUS TEMP1", 50000, 20000, type='RAW')
```

### check_expression

式を評価します。式が false と評価されると、スクリプトはエラーで一時停止します。この方法は、例に示すように check を使用するよりも複雑な比較を実行するために使用できます。注意: ほとんどの場合、check_expression よりも [wait_check_expression](#wait_check_expression) を使用するほうが良い選択です。

check_expression 文字列内のすべては直接評価されるため、有効な構文である必要があることに注意してください。よくある間違いは、変数を次のようにチェックすることです（Ruby変数の補間）：

`check_expression("#{answer} == 'yes'") # answerに'yes'が含まれている場合`

これは `yes == 'yes'` と評価されますが、yes 変数は（通常）定義されていないため、有効な構文ではありません。この式を書く正しい方法は次のとおりです：

`check_expression("'#{answer}' == 'yes'") # answerに'yes'が含まれている場合`

これにより、`'yes' == 'yes'` と評価され、true なのでチェックは合格します。

Ruby 構文：

```ruby
check_expression(exp_to_eval, context = nil)
```

Python 構文：

```python
check_expression(exp_to_eval, globals=None, locals=None)
```

| パラメータ              | 説明                                                                                                                             |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| exp_to_eval            | 評価する式。                                                                                                                       |
| context (rubyのみ)     | eval を呼び出すコンテキスト。デフォルトは nil。Ruby のコンテキストは通常 binding() であり、通常は必要ありません。                  |
| globals (pythonのみ)   | eval を呼び出すグローバル。デフォルトは None。tlm() などの COSMOS API を使用するには globals() を渡す必要があることに注意してください。 |
| locals (pythonのみ)    | eval を呼び出すローカル。デフォルトは None。メソッドでローカル変数を使用している場合は locals() を渡す必要があることに注意してください。 |

Ruby の例：

```ruby
check_expression("tlm('INST HEALTH_STATUS COLLECTS') > 5 and tlm('INST HEALTH_STATUS TEMP1') > 25.0")
```

Python の例：

```python
def check(value):
    # ここでは tlm() とローカル変数 'value' の両方を使用しているため、globals() と locals() を渡す必要があります
    check_expression("tlm('INST HEALTH_STATUS COLLECTS') > value", 5, 0.25, globals(), locals())
check(5)
```

### check_exception

メソッドを実行し、例外が発生することを期待します。メソッドが例外を発生させない場合、CheckError が発生します。

Ruby / Python 構文：

```ruby
check_exception("<Method Name>", "<Method Params - optional>")
```

| パラメータ     | 説明                                                |
| ------------- | --------------------------------------------------- |
| Method Name   | 実行するCOSMOSスクリプティングメソッド（例：'cmd'など）。 |
| Method Params | メソッドのパラメータ                                  |

Ruby の例：

```ruby
check_exception("cmd", "INST", "COLLECT", "TYPE" => "NORMAL")
```

Python の例：

```python
check_exception("cmd", "INST", "COLLECT", {"TYPE": "NORMAL"})
```

### tlm, tlm_raw, tlm_formatted, tlm_with_units

テレメトリ項目の指定された形式を読み取ります。

Ruby / Python 構文：

```ruby
tlm("<Target Name> <Packet Name> <Item Name>")
tlm("<Target Name>", "<Packet Name>", "<Item Name>")
```

| パラメータ   | 説明                                                                                                       |
| ------------ | ---------------------------------------------------------------------------------------------------------- |
| Target Name  | テレメトリ項目のターゲットの名前。                                                                          |
| Packet Name  | テレメトリ項目のテレメトリパケットの名前。                                                                  |
| Item Name    | テレメトリ項目の名前。                                                                                      |
| type         | タイプを指定する名前付きパラメータ。RAW、CONVERTED（デフォルト）、FORMATTED、WITH_UNITS（Rubyではシンボル、Pythonでは文字列）。 |

Ruby の例：

```ruby
value = tlm("INST HEALTH_STATUS COLLECTS")
value = tlm("INST", "HEALTH_STATUS", "COLLECTS")
value = tlm_raw("INST HEALTH_STATUS COLLECTS")
value = tlm_formatted("INST HEALTH_STATUS COLLECTS")
value = tlm_with_units("INST HEALTH_STATUS COLLECTS")
# tlm_raw と同等
raw_value = tlm("INST HEALTH_STATUS COLLECTS", type: :RAW)
```

Python の例：

```python
value = tlm("INST HEALTH_STATUS COLLECTS")
value = tlm("INST", "HEALTH_STATUS", "COLLECTS")
value = tlm_raw("INST HEALTH_STATUS COLLECTS")
value = tlm_formatted("INST HEALTH_STATUS COLLECTS")
value = tlm_with_units("INST HEALTH_STATUS COLLECTS")
# tlm_raw と同等
raw_value = tlm("INST HEALTH_STATUS COLLECTS", type='RAW')
```

### get_tlm_buffer

生のパケットバッファとともにパケットハッシュ（get_tlm と同様）を返します。

Ruby / Python 構文：

```ruby
buffer = get_tlm_buffer("<Target Name> <Packet Name>")['buffer']
buffer = get_tlm_buffer("<Target Name>", "<Packet Name>")['buffer']
```

| パラメータ   | 説明                 |
| ------------ | -------------------- |
| Target Name  | ターゲットの名前。   |
| Packet Name  | パケットの名前。     |

Ruby / Python の例：

```ruby
packet = get_tlm_buffer("INST HEALTH_STATUS")
packet['buffer']
```

### get_tlm_packet

指定されたパケット内のすべてのテレメトリ項目の名前、値、およびリミット状態を返します。値は [item_name, item_value, limits_state] を含む配列の配列として返されます。

Ruby / Python 構文：

```ruby
get_tlm_packet("<Target Name> <Packet Name>", <type>)
get_tlm_packet("<Target Name>", "<Packet Name>", <type>)
```

| パラメータ   | 説明                                                                                                           |
| ------------ | -------------------------------------------------------------------------------------------------------------- |
| Target Name  | ターゲットの名前。                                                                                             |
| Packet Name  | パケットの名前。                                                                                               |
| type         | タイプを指定する名前付きパラメータ。RAW、CONVERTED（デフォルト）、FORMATTED、または WITH_UNITS（Rubyではシンボル、Pythonでは文字列）。 |

Ruby の例：

```ruby
names_values_and_limits_states = get_tlm_packet("INST HEALTH_STATUS", type: :FORMATTED)
```

Python の例：

```python
names_values_and_limits_states = get_tlm_packet("INST HEALTH_STATUS", type='FORMATTED')
```

### get_tlm_values

指定されたテレメトリ項目のセットの値と現在のリミット状態を返します。項目はシステム内の任意のテレメトリパケットに含めることができます。すべて同じ値タイプを使用して取得することも、各項目に特定の値タイプを指定することもできます。

Ruby / Python 構文：

```ruby
values, limits_states, limits_settings, limits_set = get_tlm_values(<Items>)
```

| パラメータ | 説明                                                         |
| ---------- | ------------------------------------------------------------ |
| Items      | ['TGT__PKT__ITEM__TYPE', ... ] 形式の文字列の配列             |

Ruby / Python の例：

```ruby
values = get_tlm_values(["INST__HEALTH_STATUS__TEMP1__CONVERTED", "INST__HEALTH_STATUS__TEMP2__RAW"])
print(values) # [[-100.0, :RED_LOW], [0, :RED_LOW]]
```

### get_all_tlm

> 5.13.0 から、5.0.0 では get_all_telemetry として

すべてのターゲットパケットハッシュの配列を返します。

Ruby / Python 構文：

```ruby
get_all_tlm("<Target Name>")
```

| パラメータ   | 説明                 |
| ------------ | -------------------- |
| Target Name  | ターゲットの名前。   |

Ruby / Python の例：

```ruby
packets = get_all_tlm("INST")
print(packets)
#[{"target_name"=>"INST",
#  "packet_name"=>"ADCS",
#  "endianness"=>"BIG_ENDIAN",
#  "description"=>"Position and attitude data",
#  "stale"=>true,
#  "items"=>
#   [{"name"=>"CCSDSVER",
#     "bit_offset"=>0,
#     "bit_size"=>3,
#     ...
```

### get_all_tlm_names

> 5.13.0 から、5.0.6 では get_all_telemetry_names として

すべてのターゲットパケット名の配列を返します。

Ruby / Python 構文：

```ruby
get_all_tlm_names("<Target Name>")
```

| パラメータ   | 説明                 |
| ------------ | -------------------- |
| Target Name  | ターゲットの名前     |

Ruby / Python の例：

```ruby
get_all_tlm_names("INST")  #=> ["ADCS", "HEALTH_STATUS", ...]
```

### get_all_tlm_item_names

ターゲット内のすべてのパケットのすべての項目名を返します

Ruby / Python 構文：

```ruby
get_all_tlm_item_names("<Target Name>")
```

| パラメータ   | 説明                |
| ------------ | ------------------- |
| Target Name  | ターゲットの名前    |

Ruby / Python の例：

```ruby
get_all_tlm_item_names("INST")  #=> ["ARY", "ARY2", "ASCIICMD", "ATTPROGRESS", ...]
```

### get_tlm

> 5.13.0 から、5.0.0 では get_telemetry として

パケットハッシュを返します。

Ruby / Python 構文：

```ruby
get_tlm("<Target Name> <Packet Name>")
get_tlm("<Target Name>", "<Packet Name>")
```

| パラメータ   | 説明                 |
| ------------ | -------------------- |
| Target Name  | ターゲットの名前。   |
| Packet Name  | パケットの名前。     |

Ruby / Python の例：

```ruby
packet = get_tlm("INST HEALTH_STATUS")
print(packet)
#{"target_name"=>"INST",
# "packet_name"=>"HEALTH_STATUS",
# "endianness"=>"BIG_ENDIAN",
# "description"=>"Health and status from the instrument",
# "stale"=>true,
# "processors"=>
#  [{"name"=>"TEMP1STAT",
#    "class"=>"OpenC3::StatisticsProcessor",
#    "params"=>["TEMP1", 100, "CONVERTED"]},
#   {"name"=>"TEMP1WATER",
#    "class"=>"OpenC3::WatermarkProcessor",
#    "params"=>["TEMP1", "CONVERTED"]}],
# "items"=>
#  [{"name"=>"CCSDSVER",
#    "bit_offset"=>0,
#    "bit_size"=>3,
#    ...
```

### get_item

項目ハッシュを返します。

Ruby / Python 構文：

```ruby
get_item("<Target Name> <Packet Name> <Item Name>")
get_item("<Target Name>", "<Packet Name>", "<Item Name>")
```

| パラメータ   | 説明                 |
| ------------ | -------------------- |
| Target Name  | ターゲットの名前。   |
| Packet Name  | パケットの名前。     |
| Item Name    | 項目の名前。         |

Ruby / Python の例：

```ruby
item = get_item("INST HEALTH_STATUS CCSDSVER")
print(item)
#{"name"=>"CCSDSVER",
# "bit_offset"=>0,
# "bit_size"=>3,
# "data_type"=>"UINT",
# "description"=>"CCSDS packet version number (See CCSDS 133.0-B-1)",
# "endianness"=>"BIG_ENDIAN",
# "required"=>false,
# "overflow"=>"ERROR"}
```

### get_tlm_cnt

指定されたテレメトリパケットが受信された回数を返します。

Ruby / Python 構文：

```ruby
get_tlm_cnt("<Target Name> <Packet Name>")
get_tlm_cnt("<Target Name>", "<Packet Name>")
```

| パラメータ   | 説明                         |
| ------------ | ---------------------------- |
| Target Name  | ターゲットの名前。           |
| Packet Name  | テレメトリパケットの名前。   |

Ruby / Python の例：

```ruby
tlm_cnt = get_tlm_cnt("INST HEALTH_STATUS") # INST HEALTH_STATUS テレメトリパケットが受信された回数
```

### set_tlm

コマンドおよびテレメトリサーバーでテレメトリ項目の値を設定します。この値は、インターフェースから新しいパケットが受信されると上書きされます。そのため、このメソッドは、インターフェースが切断されている場合や、Script Runnerの切断モードを介したテストに最も役立ちます。テレメトリ値を手動で設定することで、スクリプト内の多くの論理パスを実行できます。

Ruby / Python 構文：

```ruby
set_tlm("<Target> <Packet> <Item> = <Value>", <type>)
```

| パラメータ | 説明                                                                                |
| ---------- | ----------------------------------------------------------------------------------- |
| Target     | ターゲット名                                                                        |
| Packet     | パケット名                                                                          |
| Item       | 項目名                                                                              |
| Value      | 設定する値                                                                          |
| type       | 値のタイプ RAW、CONVERTED（デフォルト）、FORMATTED、WITH_UNITS（Rubyではシンボル、Pythonでは文字列） |

Ruby の例：

```ruby
set_tlm("INST HEALTH_STATUS COLLECTS = 5") # type はデフォルトで :CONVERTED です
check("INST HEALTH_STATUS COLLECTS == 5")
set_tlm("INST HEALTH_STATUS COLLECTS = 10", type: :RAW)
check("INST HEALTH_STATUS COLLECTS == 10", type: :RAW)
```

Python の例：

```python
set_tlm("INST HEALTH_STATUS COLLECTS = 5") # type はデフォルトで CONVERTED です
check("INST HEALTH_STATUS COLLECTS == 5")
set_tlm("INST HEALTH_STATUS COLLECTS = 10", type='RAW')
check("INST HEALTH_STATUS COLLECTS == 10", type='RAW')
```

### inject_tlm

インターフェースから受信したかのようにパケットをシステムに注入します。

Ruby / Packet 構文：

```ruby
inject_tlm("<target_name>", "<packet_name>", <item_hash>, <type>)
```

| パラメータ  | 説明                                                                                                                                                                 |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Target      | ターゲット名                                                                                                                                                         |
| Packet      | パケット名                                                                                                                                                           |
| Item Hash   | 各項目の項目名/値のハッシュ。ハッシュで項目が指定されていない場合、現在の値テーブルの値が使用されます。オプションのパラメータ、デフォルトは nil。                  |
| type        | 項目ハッシュの値のタイプ、RAW、CONVERTED（デフォルト）、FORMATTED、WITH_UNITS（Rubyではシンボル、Pythonでは文字列）                                               |

Ruby の例：

```ruby
inject_tlm("INST", "PARAMS", {'VALUE1' => 5.0, 'VALUE2' => 7.0})
```

Python の例：

```python
inject_tlm("INST", "PARAMS", {'VALUE1': 5.0, 'VALUE2': 7.0})
```

### override_tlm

コマンドおよびテレメトリサーバーでテレメトリポイントの変換値を設定します。この値は、normalize_tlm メソッドでオーバーライドがキャンセルされない限り、インターフェース上で新しいパケットが受信されても維持されます。

Ruby / Python 構文：

```ruby
override_tlm("<Target> <Packet> <Item> = <Value>", <type>)
```

| パラメータ | 説明                                                                                         |
| ---------- | -------------------------------------------------------------------------------------------- |
| Target     | ターゲット名                                                                                |
| Packet     | パケット名                                                                                  |
| Item       | 項目名                                                                                      |
| Value      | 設定する値                                                                                  |
| type       | オーバーライドするタイプ、ALL（デフォルト）、RAW、CONVERTED、FORMATTED、WITH_UNITS（Rubyではシンボル、Pythonでは文字列） |

Ruby の例：

```ruby
override_tlm("INST HEALTH_STATUS TEMP1 = 5") # TEMP1に対するすべてのリクエストが5を返す
override_tlm("INST HEALTH_STATUS TEMP2 = 0", type: :RAW) # RAW tlmのみが0に設定される
```

Python の例：

```python
override_tlm("INST HEALTH_STATUS TEMP1 = 5") # TEMP1に対するすべてのリクエストが5を返す
override_tlm("INST HEALTH_STATUS TEMP2 = 0", type='RAW') # RAW tlmのみが0に設定される
```

### normalize_tlm

コマンドおよびテレメトリサーバーでのテレメトリポイントのオーバーライドをクリアします。

Ruby / Python 構文：

```ruby
normalize_tlm("<Target> <Packet> <Item>", <type>)
```

| パラメータ | 説明                                                                                          |
| ---------- | --------------------------------------------------------------------------------------------- |
| Target     | ターゲット名                                                                                 |
| Packet     | パケット名                                                                                   |
| Item       | 項目名                                                                                       |
| type       | 正規化するタイプ、ALL（デフォルト）、RAW、CONVERTED、FORMATTED、WITH_UNITS（Rubyではシンボル、Pythonでは文字列） |

Ruby の例：

```ruby
normalize_tlm("INST HEALTH_STATUS TEMP1") # すべてのオーバーライドをクリア
normalize_tlm("INST HEALTH_STATUS TEMP1", type: :RAW) # RAWオーバーライドのみをクリア
```

Python の例：

```python
normalize_tlm("INST HEALTH_STATUS TEMP1") # すべてのオーバーライドをクリア
normalize_tlm("INST HEALTH_STATUS TEMP1", type='RAW') # RAWオーバーライドのみをクリア
```

### get_overrides

override_tlm によって設定された現在オーバーライドされている値の配列を返します。注意：これはオーバーライドされているすべての値タイプを返します。デフォルトでは、override_tlm を使用する際にすべての 4 つの値タイプがオーバーライドされます。

Ruby / Python 構文：

```ruby
get_overrides()
```

Ruby の例：

```ruby
override_tlm("INST HEALTH_STATUS TEMP1 = 5")
puts get_overrides() #=>
# [ {"target_name"=>"INST", "packet_name"=>"HEALTH_STATUS", "item_name"=>"TEMP1", "value_type"=>"RAW", "value"=>5}
#   {"target_name"=>"INST", "packet_name"=>"HEALTH_STATUS", "item_name"=>"TEMP1", "value_type"=>"CONVERTED", "value"=>5}
#   {"target_name"=>"INST", "packet_name"=>"HEALTH_STATUS", "item_name"=>"TEMP1", "value_type"=>"FORMATTED", "value"=>"5"}
#   {"target_name"=>"INST", "packet_name"=>"HEALTH_STATUS", "item_name"=>"TEMP1", "value_type"=>"WITH_UNITS", "value"=>"5"} ]
```

Python の例：

```python
override_tlm("INST HEALTH_STATUS TEMP1 = 5")
print(get_overrides()) #=>
# [ {'target_name': 'INST', 'packet_name': 'HEALTH_STATUS', 'item_name': 'TEMP1', 'value_type': 'RAW', 'value': 5},
#   {'target_name': 'INST', 'packet_name': 'HEALTH_STATUS', 'item_name': 'TEMP1', 'value_type': 'CONVERTED', 'value': 5},
#   {'target_name': 'INST', 'packet_name': 'HEALTH_STATUS', 'item_name': 'TEMP1', 'value_type': 'FORMATTED', 'value': '5'},
#   {'target_name': 'INST', 'packet_name': 'HEALTH_STATUS', 'item_name': 'TEMP1', 'value_type': 'WITH_UNITS', 'value': '5'} ]
```

## パケットデータサブスクリプション

特定のデータパケットをサブスクライブするためのAPI。これは、ポーリングに依存して一部のデータが見逃される可能性がある代わりに、各テレメトリパケットが確実に受信および処理されるようにするインターフェースを提供します。

### subscribe_packets

ユーザーが1つ以上のテレメトリデータパケットの到着をリッスンできるようにします。データの取得に使用される一意のIDが返されます。

Ruby / Python 構文：

```ruby
subscribe_packets(packets)
```

| パラメータ | 説明                                                                   |
| ---------- | ---------------------------------------------------------------------- |
| packets    | ユーザーがサブスクライブしたいターゲット名/パケット名のペアのネスト配列。 |

Ruby / Python の例：

```ruby
id = subscribe_packets([['INST', 'HEALTH_STATUS'], ['INST', 'ADCS']])
```

### get_packets

以前のサブスクリプションからパケットデータをストリーミングします。

Ruby 構文：

```ruby
get_packets(id, block: nil, count: 1000)
```

Python 構文：

```python
get_packets(id, block=None, count=1000)
```

| パラメータ | 説明                                                                                                                        |
| ---------- | --------------------------------------------------------------------------------------------------------------------------- |
| id         | subscribe_packets によって返される一意の ID                                                                                 |
| block      | 任意のストリームからのパケットを待機している間ブロックするミリ秒数、デフォルトは nil / None（ブロックしない）                |
| count      | 各パケットストリームから返すパケットの最大数                                                                               |

Ruby の例：

```ruby
id = subscribe_packets([['INST', 'HEALTH_STATUS'], ['INST', 'ADCS']])
wait 0.1
id, packets = get_packets(id)
packets.each do |packet|
  puts "#{packet['PACKET_TIMESECONDS']}: #{packet['target_name']} #{packet['packet_name']}"
end
# 前回の呼び出しからIDを再利用し、1秒間の待機を許可し、1つのパケットのみを取得
id, packets = get_packets(id, block: 1000, count: 1)
packets.each do |packet|
  puts "#{packet['PACKET_TIMESECONDS']}: #{packet['target_name']} #{packet['packet_name']}"
end
```

Python の例：

```python
id = subscribe_packets([['INST', 'HEALTH_STATUS'], ['INST', 'ADCS']])
wait(0.1)
id, packets = get_packets(id)
for packet in packets:
    print(f"{packet['PACKET_TIMESECONDS']}: {packet['target_name']} {packet['packet_name']}")

# 前回の呼び出しからIDを再利用し、1秒間の待機を許可し、1つのパケットのみを取得
id, packets = get_packets(id, block=1000, count=1)
for packet in packets:
    print(f"{packet['PACKET_TIMESECONDS']}: {packet['target_name']} {packet['packet_name']}")
```

### get_tlm_cnt

テレメトリパケットの受信カウントを取得します

Ruby / Python 構文：

```ruby
get_tlm_cnt("<Target> <Packet>")
get_tlm_cnt("<Target>", "<Packet>")
```

| パラメータ | 説明         |
| ---------- | ------------ |
| Target     | ターゲット名 |
| Packet     | パケット名   |

Ruby / Python の例：

```ruby
get_tlm_cnt("INST HEALTH_STATUS")  #=> 10
```

### get_tlm_cnts

テレメトリパケットの配列の受信カウントを取得します

Ruby / Python 構文：

```ruby
get_tlm_cnts([["<Target>", "<Packet>"], ["<Target>", "<Packet>"]])
```

| パラメータ | 説明         |
| ---------- | ------------ |
| Target     | ターゲット名 |
| Packet     | パケット名   |

Ruby / Python の例：

```ruby
get_tlm_cnts([["INST", "ADCS"], ["INST", "HEALTH_STATUS"]])  #=> [100, 10]
```

### get_packet_derived_items

パケットの派生テレメトリ項目のリストを取得します

Ruby / Python 構文：

```ruby
get_packet_derived_items("<Target> <Packet>")
get_packet_derived_items("<Target>", "<Packet>")
```

| パラメータ | 説明         |
| ---------- | ------------ |
| Target     | ターゲット名 |
| Packet     | パケット名   |

Ruby / Python の例：

```ruby
get_packet_derived_items("INST HEALTH_STATUS")  #=> ['PACKET_TIMESECONDS', 'PACKET_TIMEFORMATTED', ...]
```

## 遅延

これらのメソッドを使用すると、テレメトリが変更されるのを待つか、または一定の時間が経過するのを待つためにスクリプトを一時停止できます。

### wait

設定可能な時間（最小10ms）だけスクリプトを一時停止するか、変換されたテレメトリ項目が指定された基準を満たすまで一時停止します。3つの異なる構文をサポートしています。パラメータが指定されていない場合、ユーザーがGoを押すまで無限に待機します。タイムアウト時に、waitはスクリプトを停止しないことに注意してください。通常、wait_check の方が良い選択です。

Ruby / Python 構文：

```ruby
elapsed = wait() #=> 実際に待機した時間を返す
elapsed = wait(<Time>) #=> 実際に待機した時間を返す
```

| パラメータ | 説明                           |
| ---------- | ------------------------------ |
| Time       | 遅延する時間（秒単位）。       |

Ruby / Python 構文：

```ruby
# 式が真か偽かに基づいて true または false を返す
success = wait("<Target Name> <Packet Name> <Item Name> <Comparison>", <Timeout>, <Polling Rate (optional)>, type, quiet)
```

| パラメータ      | 説明                                                                                                                   |
| --------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Target Name     | テレメトリ項目のターゲットの名前。                                                                                     |
| Packet Name     | テレメトリ項目のテレメトリパケットの名前。                                                                             |
| Item Name       | テレメトリ項目の名前。                                                                                                 |
| Comparison      | テレメトリ項目に対して実行する比較。                                                                                   |
| Timeout         | タイムアウト（秒）。比較が真になるのを待っている間にwait文がタイムアウトした場合、スクリプトは続行します。             |
| Polling Rate    | 比較が評価される頻度（秒単位）。指定されていない場合、デフォルトは0.25です。                                           |
| type            | タイプを指定する名前付きパラメータ。RAW、CONVERTED（デフォルト）、FORMATTED、WITH_UNITS（Rubyではシンボル、Pythonでは文字列）。 |
| quiet           | 結果をログに記録するかどうかを示す名前付きパラメータ。デフォルトはtrueです。                                           |

Ruby の例：

```ruby
elapsed = wait
elapsed = wait 5
success = wait("INST HEALTH_STATUS COLLECTS == 3", 10)
success = wait("INST HEALTH_STATUS COLLECTS == 3", 10, type: :RAW, quiet: false)
```

Python の例：

```python
elapsed = wait()
elapsed = wait(5)
success = wait("INST HEALTH_STATUS COLLECTS == 3", 10)
success = wait("INST HEALTH_STATUS COLLECTS == 3", 10, type='RAW', quiet=False)
```

### wait_tolerance

許容範囲内の期待値と等しくなるまで、指定可能な時間だけスクリプトを一時停止するか、変換されたテレメトリ項目を一時停止します。タイムアウト時に、wait_tolerance はスクリプトを停止しないことに注意してください。通常、wait_check_tolerance の方が良い選択です。

Ruby Python 構文：

```ruby
# 式が真か偽かに基づいて true または false を返す
success = wait_tolerance("<Target Name> <Packet Name> <Item Name>", <Expected Value>, <Tolerance>, <Timeout>, <Polling Rate (optional)>, type, quiet)
```

| パラメータ       | 説明                                                                                                                   |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Target Name      | テレメトリ項目のターゲットの名前。                                                                                     |
| Packet Name      | テレメトリ項目のテレメトリパケットの名前。                                                                             |
| Item Name        | テレメトリ項目の名前。                                                                                                 |
| Expected Value   | テレメトリ項目の期待値。                                                                                               |
| Tolerance        | 期待値に対する±許容範囲。                                                                                              |
| Timeout          | タイムアウト（秒）。比較が真になるのを待っている間にwait文がタイムアウトした場合、スクリプトは続行します。             |
| Polling Rate     | 比較が評価される頻度（秒単位）。指定されていない場合、デフォルトは0.25です。                                           |
| type             | タイプを指定する名前付きパラメータ。RAW、CONVERTED（デフォルト）、FORMATTED、WITH_UNITS（Rubyではシンボル、Pythonでは文字列）。 |
| quiet            | 結果をログに記録するかどうかを示す名前付きパラメータ。デフォルトはtrueです。                                           |

Ruby の例：

```ruby
success = wait_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10)
success = wait_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10, type: :RAW, quiet: true)
```

Python の例：

```python
success = wait_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10)
success = wait_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10, type='RAW', quiet=True)
```

### wait_expression

式が真と評価されるかタイムアウトが発生するまでスクリプトを一時停止します。タイムアウトが発生するとスクリプトは続行されます。このメソッドは、例に示すように、wait を使用するよりも複雑な比較を実行するために使用できます。タイムアウト時に、wait_expression はスクリプトを停止しないことに注意してください。通常は [wait_check_expression](#wait_check_expression) の方が良い選択です。

Ruby 構文：

```ruby
# 式の評価に基づいて true または false を返す
wait_expression(
  exp_to_eval,
  timeout,
  polling_rate = DEFAULT_TLM_POLLING_RATE,
  context = nil,
  quiet: false
) -> boolean
```

Python 構文：

```python
# 式の評価に基づいて True または False を返す
wait_expression(
    exp_to_eval,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    globals=None,
    locals=None,
    quiet=False,
) -> bool
```

| パラメータ              | 説明                                                                                                                             |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| expression              | 評価する式。                                                                                                                      |
| timeout                 | タイムアウト（秒）。比較が真になるのを待っている間にwait文がタイムアウトした場合、スクリプトは続行します。                       |
| polling_rate            | 比較が評価される頻度（秒単位）。指定されていない場合、デフォルトは0.25です。                                                     |
| context (ruby のみ)     | eval を呼び出すコンテキスト。デフォルトは nil。Ruby のコンテキストは通常 binding() であり、通常は必要ありません。                |
| globals (python のみ)   | eval を呼び出すグローバル。デフォルトは None。tlm() などの COSMOS API を使用するには globals() を渡す必要があることに注意してください。 |
| locals (python のみ)    | eval を呼び出すローカル。デフォルトは None。メソッドでローカル変数を使用している場合は locals() を渡す必要があることに注意してください。 |
| quiet                   | 結果をログに記録するかどうか。デフォルトは false で、ログに記録することを意味します。                                            |

Ruby の例：

```ruby
success = wait_expression("tlm('INST HEALTH_STATUS COLLECTS') > 5 and tlm('INST HEALTH_STATUS TEMP1') > 25.0", 10, 0.25, nil, quiet: true)
```

Python の例：

```python
def check(value):
    # ここでは tlm() とローカル変数 'value' の両方を使用しているため、globals() と locals() を渡す必要があります
    return wait_expression("tlm('INST HEALTH_STATUS COLLECTS') > value", 5, 0.25, globals(), locals(), quiet=True)
success = check(5)
```

### wait_packet

一定数のパケットが受信されるまでスクリプトを一時停止します。タイムアウトが発生するとスクリプトは続行されます。タイムアウト時に、wait_packet はスクリプトを停止しないことに注意してください。通常は wait_check_packet の方が良い選択です。

Ruby / Python 構文：

```ruby
# パケットが受信されたかどうかに基づいて true または false を返す
success = wait_packet("<Target>", "<Packet>", <Num Packets>, <Timeout>, <Polling Rate (optional)>, quiet)
```

| パラメータ      | 説明                                                                          |
| --------------- | ----------------------------------------------------------------------------- |
| Target          | ターゲット名                                                                  |
| Packet          | パケット名                                                                    |
| Num Packets     | 受信するパケット数                                                            |
| Timeout         | タイムアウト（秒）。                                                          |
| Polling Rate    | 比較が評価される頻度（秒単位）。指定されていない場合、デフォルトは0.25です。  |
| quiet           | 結果をログに記録するかどうかを示す名前付きパラメータ。デフォルトはtrueです。  |

Ruby / Python の例：

```ruby
success = wait_packet('INST', 'HEALTH_STATUS', 5, 10) # 10秒以内に5つのINST HEALTH_STATUSパケットを待つ
```

### wait_check

wait キーワードと check キーワードを1つに組み合わせます。これは、テレメトリ項目の変換値が指定された基準を満たすかタイムアウトするまでスクリプトを一時停止します。タイムアウト時にスクリプトは停止します。

Ruby / Python 構文：

```ruby
# 式を待っている間に経過した時間を返す
elapsed = wait_check("<Target Name> <Packet Name> <Item Name> <Comparison>", <Timeout>, <Polling Rate (optional)>, type)
```

| パラメータ      | 説明                                                                                                                   |
| --------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Target Name     | テレメトリ項目のターゲットの名前。                                                                                     |
| Packet Name     | テレメトリ項目のテレメトリパケットの名前。                                                                             |
| Item Name       | テレメトリ項目の名前。                                                                                                 |
| Comparison      | テレメトリ項目に対して実行する比較。                                                                                   |
| Timeout         | タイムアウト（秒）。比較が真になるのを待っている間にwait文がタイムアウトした場合、スクリプトは停止します。             |
| Polling Rate    | 比較が評価される頻度（秒単位）。指定されていない場合、デフォルトは0.25です。                                           |
| type            | タイプを指定する名前付きパラメータ。RAW、CONVERTED（デフォルト）、FORMATTED、WITH_UNITS（Rubyではシンボル、Pythonでは文字列）。 |

Ruby の例：

```ruby
elapsed = wait_check("INST HEALTH_STATUS COLLECTS > 5", 10)
elapsed = wait_check("INST HEALTH_STATUS COLLECTS > 5", 10, type: :RAW)
```

Python の例：

```python
elapsed = wait_check("INST HEALTH_STATUS COLLECTS > 5", 10)
elapsed = wait_check("INST HEALTH_STATUS COLLECTS > 5", 10, type='RAW')
```

### wait_check_tolerance

設定可能な時間だけスクリプトを一時停止するか、変換されたテレメトリ項目が許容範囲内の期待値と等しくなるまで一時停止します。タイムアウト時にスクリプトは停止します。

Ruby / Python 構文：

```ruby
# 式を待っている間に経過した時間を返す
elapsed = wait_check_tolerance("<Target Name> <Packet Name> <Item Name>", <Expected Value>, <Tolerance>, <Timeout>, <Polling Rate (optional)>, type)
```

| パラメータ       | 説明                                                                                                                   |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Target Name      | テレメトリ項目のターゲットの名前。                                                                                     |
| Packet Name      | テレメトリ項目のテレメトリパケットの名前。                                                                             |
| Item Name        | テレメトリ項目の名前。                                                                                                 |
| Expected Value   | テレメトリ項目の期待値。                                                                                               |
| Tolerance        | 期待値に対する±許容範囲。                                                                                              |
| Timeout          | タイムアウト（秒）。比較が真になるのを待っている間にwait文がタイムアウトした場合、スクリプトは停止します。             |
| Polling Rate     | 比較が評価される頻度（秒単位）。指定されていない場合、デフォルトは0.25です。                                           |
| type             | タイプを指定する名前付きパラメータ。RAW、CONVERTED（デフォルト）、FORMATTED、WITH_UNITS（Rubyではシンボル、Pythonでは文字列）。 |

Ruby の例：

```ruby
elapsed = wait_check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10)
elapsed = wait_check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10, type: :RAW)
```

Python の例：

```python
elapsed = wait_check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10)
elapsed = wait_check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10, type='RAW')
```

### wait_check_expression

式が真と評価されるかタイムアウトが発生するまでスクリプトを一時停止します。タイムアウトが発生するとスクリプトは停止します。このメソッドは、例に示すように、wait を使用するよりも複雑な比較を実行するために使用できます。[check_expression](#check_expression) の構文に関する注意事項も参照してください。

Ruby 構文：

```ruby
# 式が真と評価されるまで待つのに費やした時間を返す
wait_check_expression(
  exp_to_eval,
  timeout,
  polling_rate = DEFAULT_TLM_POLLING_RATE,
  context = nil
) -> int
```

Python 構文：

```python
# 式が真と評価されるまで待つのに費やした時間を返す
wait_check_expression(
    exp_to_eval,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    globals=None,
    locals=None
) -> int
```

| パラメータ              | 説明                                                                                                                             |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| expression             | 評価する式。                                                                                                                      |
| timeout                | タイムアウト（秒）。比較が真になるのを待っている間にwait文がタイムアウトした場合、スクリプトは続行します。                        |
| polling_rate           | 比較が評価される頻度（秒単位）。指定されていない場合、デフォルトは0.25です。                                                      |
| context (ruby のみ)    | eval を呼び出すコンテキスト。デフォルトは nil。Ruby のコンテキストは通常 binding() であり、通常は必要ありません。                 |
| globals (python のみ)  | eval を呼び出すグローバル。デフォルトは None。tlm() などの COSMOS API を使用するには globals() を渡す必要があることに注意してください。 |
| locals (python のみ)   | eval を呼び出すローカル。デフォルトは None。メソッドでローカル変数を使用している場合は locals() を渡す必要があることに注意してください。 |

Ruby の例：

```ruby
elapsed = wait_check_expression("tlm('INST HEALTH_STATUS COLLECTS') > 5 and tlm('INST HEALTH_STATUS TEMP1') > 25.0", 10)
```

Python の例：

```python
# PythonではCOSMOS APIメソッドのtlm()などを使用するためにglobals()を渡す必要があることに注意してください
elapsed = wait_check_expression("tlm('INST HEALTH_STATUS COLLECTS') > 5 and tlm('INST HEALTH_STATUS TEMP1') > 25.0", 10, 0.25, globals())
```

### wait_check_packet

一定数のパケットが受信されるまでスクリプトを一時停止します。タイムアウトが発生するとスクリプトは停止します。

Ruby / Python 構文：

```ruby
# パケットを待つのに費やした時間の量を返す
elapsed = wait_check_packet("<Target>", "<Packet>", <Num Packets>, <Timeout>, <Polling Rate (optional)>, quiet)
```

| パラメータ      | 説明                                                                                                |
| --------------- | --------------------------------------------------------------------------------------------------- |
| Target          | ターゲット名                                                                                        |
| Packet          | パケット名                                                                                          |
| Num Packets     | 受信するパケット数                                                                                  |
| Timeout         | タイムアウト（秒）。指定された数のパケットを待っている間にwait文がタイムアウトした場合、スクリプトは停止します。 |
| Polling Rate    | 比較が評価される頻度（秒単位）。指定されていない場合、デフォルトは0.25です。                         |
| quiet           | 結果をログに記録するかどうかを示す名前付きパラメータ。デフォルトはtrueです。                         |

Ruby / Python の例：

```ruby
elapsed = wait_check_packet('INST', 'HEALTH_STATUS', 5, 10) # 10秒以内に5つのINST HEALTH_STATUSパケットを待つ
```

## リミット

これらのメソッドは、テレメトリリミットの処理を扱います。

### limits_enabled?, limits_enabled

limits_enabled? メソッドは、テレメトリ項目のリミットが有効かどうかに応じて true/false を返します。

Ruby 構文：

```ruby
limits_enabled?("<Target Name> <Packet Name> <Item Name>")
```

Python 構文：

```python
limits_enabled("<Target Name> <Packet Name> <Item Name>")
```

| パラメータ   | 説明                                         |
| ------------ | -------------------------------------------- |
| Target Name  | テレメトリ項目のターゲットの名前。           |
| Packet Name  | テレメトリ項目のテレメトリパケットの名前。   |
| Item Name    | テレメトリ項目の名前。                       |

Ruby の例：

```ruby
enabled = limits_enabled?("INST HEALTH_STATUS TEMP1") #=> true または false
```

Python の例：

```python
enabled = limits_enabled("INST HEALTH_STATUS TEMP1") #=> True または False
```

### enable_limits

指定されたテレメトリ項目のリミットモニタリングを有効にします。

Ruby / Python 構文：

```ruby
enable_limits("<Target Name> <Packet Name> <Item Name>")
```

| パラメータ   | 説明                                         |
| ------------ | -------------------------------------------- |
| Target Name  | テレメトリ項目のターゲットの名前。           |
| Packet Name  | テレメトリ項目のテレメトリパケットの名前。   |
| Item Name    | テレメトリ項目の名前。                       |

Ruby / Python の例：

```ruby
enable_limits("INST HEALTH_STATUS TEMP1")
```

### disable_limits

指定されたテレメトリ項目のリミットモニタリングを無効にします。

Ruby / Python 構文：

```ruby
disable_limits("<Target Name> <Packet Name> <Item Name>")
```

| パラメータ   | 説明                                         |
| ------------ | -------------------------------------------- |
| Target Name  | テレメトリ項目のターゲットの名前。           |
| Packet Name  | テレメトリ項目のテレメトリパケットの名前。   |
| Item Name    | テレメトリ項目の名前。                       |

Ruby / Python の例：

```ruby
disable_limits("INST HEALTH_STATUS TEMP1")
```
### enable_limits_group

リミットグループで指定された一連のテレメトリ項目のリミットモニタリングを有効にします。

Ruby / Python 構文：

```ruby
enable_limits_group("<Limits Group Name>")
```

| パラメータ        | 説明                     |
| ----------------- | ------------------------ |
| Limits Group Name | リミットグループの名前。 |

Ruby / Python の例：

```ruby
enable_limits_group("SAFE_MODE")
```

### disable_limits_group

リミットグループで指定された一連のテレメトリ項目のリミットモニタリングを無効にします。

Ruby / Python 構文：

```ruby
disable_limits_group("<Limits Group Name>")
```

| パラメータ        | 説明                     |
| ----------------- | ------------------------ |
| Limits Group Name | リミットグループの名前。 |

Ruby / Python の例：

```ruby
disable_limits_group("SAFE_MODE")
```

### get_limits_groups

システム内のリミットグループのリストを返します。

Ruby / Python の例：

```ruby
limits_groups = get_limits_groups()
```

### set_limits_set

現在のリミットセットを設定します。デフォルトのリミットセットは DEFAULT です。

Ruby / Python 構文：

```ruby
set_limits_set("<Limits Set Name>")
```

| パラメータ      | 説明                   |
| --------------- | ---------------------- |
| Limits Set Name | リミットセットの名前。 |

Ruby / Python の例：

```ruby
set_limits_set("DEFAULT")
```

### get_limits_set

現在のリミットセットの名前を返します。デフォルトのリミットセットは DEFAULT です。

Ruby / Python の例：

```ruby
limits_set = get_limits_set()
```

### get_limits_sets

システム内のリミットセットのリストを返します。

Ruby / Python の例：

```ruby
limits_sets = get_limits_sets()
```

### get_limits

テレメトリポイントのすべてのリミット設定のハッシュ / 辞書を返します。

Ruby / Python 構文：

```ruby
get_limits(<Target Name>, <Packet Name>, <Item Name>)
```

| パラメータ   | 説明                                     |
| ------------ | ---------------------------------------- |
| Target Name  | テレメトリ項目のターゲットの名前         |
| Packet Name  | テレメトリ項目のテレメトリパケットの名前 |
| Item Name    | テレメトリ項目の名前                     |

Ruby の例：

```ruby
result = get_limits('INST', 'HEALTH_STATUS', 'TEMP1')
puts result #=> {"DEFAULT"=>[-80.0, -70.0, 60.0, 80.0, -20.0, 20.0], "TVAC"=>[-80.0, -30.0, 30.0, 80.0]}
puts result.keys #=> ['DEFAULT', 'TVAC']
puts result['DEFAULT'] #=> [-80.0, -70.0, 60.0, 80.0, -20.0, 20.0]
```

Python の例：

```python
result = get_limits('INST', 'HEALTH_STATUS', 'TEMP1')
print(result) #=> {'DEFAULT'=>[-80.0, -70.0, 60.0, 80.0, -20.0, 20.0], 'TVAC'=>[-80.0, -30.0, 30.0, 80.0]}
print(result.keys()) #=> dict_keys(['DEFAULT', 'TVAC'])
print(result['DEFAULT']) #=> [-80.0, -70.0, 60.0, 80.0, -20.0, 20.0]
```

### set_limits

set_limits メソッドはテレメトリポイントのリミット設定を設定します。注意：ほとんどの場合、設定ファイルを更新するか、異なるリミットセットを使用する方が、リアルタイムでリミット設定を変更するよりも良いでしょう。

Ruby / Python 構文：

```ruby
set_limits(<Target Name>, <Packet Name>, <Item Name>, <Red Low>, <Yellow Low>, <Yellow High>, <Red High>, <Green Low (オプション)>, <Green High (オプション)>, <Limits Set (オプション)>, <Persistence (オプション)>, <Enabled (オプション)>)
```

| パラメータ   | 説明                                                                                                                                       |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Target Name  | テレメトリ項目のターゲットの名前。                                                                                                         |
| Packet Name  | テレメトリ項目のテレメトリパケットの名前。                                                                                                 |
| Item Name    | テレメトリ項目の名前。                                                                                                                     |
| Red Low      | このリミットセットの Red Low 設定。この値より下の値はすべて項目を赤にします。                                                              |
| Yellow Low   | このリミットセットの Yellow Low 設定。この値より下で Red Low より大きい値はすべて項目を黄色にします。                                      |
| Yellow High  | このリミットセットの Yellow High 設定。この値より上で Red High より小さい値はすべて項目を黄色にします。                                    |
| Red High     | このリミットセットの Red High 設定。この値より上の値はすべて項目を赤にします。                                                             |
| Green Low    | オプション。指定された場合、Green Low より大きく Green High より小さい値は、良好な動作値を示す青色で項目を表示します。                     |
| Green High   | オプション。指定された場合、Green Low より大きく Green High より小さい値は、良好な動作値を示す青色で項目を表示します。                     |
| Limits Set   | オプション。特定のリミットセットのリミットを設定します。指定されない場合、デフォルトで CUSTOM リミットセットのリミットを設定します。       |
| Persistence  | オプション。リミット状態を変更する前に、この項目がリミット範囲外でなければならないサンプル数を設定します。デフォルトは変更なしです。注意：これはリミットセット全体のすべてのリミット設定に影響します。 |
| Enabled      | オプション。この項目のリミットが有効かどうか。デフォルトは true です。注意：これはリミットセット全体のすべてのリミット設定に影響します。  |

Ruby / Python の例：

```ruby
set_limits('INST', 'HEALTH_STATUS', 'TEMP1', -10.0, 0.0, 50.0, 60.0, 30.0, 40.0, 'TVAC', 1, true)
```

### get_out_of_limits

リミット範囲外のすべての項目の target_name、packet_name、item_name、および limits_state を含む配列を返します。

Ruby / Python の例：

```ruby
out_of_limits_items = get_out_of_limits()
```

### get_overall_limits_state

COSMOS システムの全体的なリミット状態を返します。'GREEN'、'YELLOW'、または 'RED' を返します。

Ruby / Python 構文：

```ruby
get_overall_limits_state(<Ignored Items> (オプション))
```

| パラメータ     | 説明                                                                                                                   |
| -------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Ignored Items  | 全体的なリミット状態を決定する際に無視する項目の配列の配列。[['TARGET_NAME', 'PACKET_NAME', 'ITEM_NAME'], ...] の形式 |

Ruby / Python の例：

```ruby
overall_limits_state = get_overall_limits_state()
overall_limits_state = get_overall_limits_state([['INST', 'HEALTH_STATUS', 'TEMP1']])
```

### get_limits_events

前回呼び出された時から返されたオフセットに基づいてリミットイベントを返します。

Ruby / Python 構文：

```ruby
get_limits_event(<Offset>, count)
```

| パラメータ | 説明                                                                               |
| ---------- | ---------------------------------------------------------------------------------- |
| Offset     | get_limits_event への前回の呼び出しによって返されたオフセット。初回呼び出しのデフォルトは nil |
| count      | 返すリミットイベントの最大数を指定する名前付きパラメータ。デフォルトは 100               |
Ruby / Python の例：

```ruby
events = get_limits_event()
print(events)
#[["1613077715557-0",
#  {"type"=>"LIMITS_CHANGE",
#   "target_name"=>"TGT",
#   "packet_name"=>"PKT",
#   "item_name"=>"ITEM",
#   "old_limits_state"=>"YELLOW_LOW",
#   "new_limits_state"=>"RED_LOW",
#   "time_nsec"=>"1",
#   "message"=>"message"}],
# ["1613077715557-1",
#  {"type"=>"LIMITS_CHANGE",
#   "target_name"=>"TGT",
#   "packet_name"=>"PKT",
#   "item_name"=>"ITEM",
#   "old_limits_state"=>"RED_LOW",
#   "new_limits_state"=>"YELLOW_LOW",
#   "time_nsec"=>"2",
#   "message"=>"message"}]]
# 最後のオフセットは最後のイベント([-1])の最初の項目([0])です
events = get_limits_event(events[-1][0])
print(events)
#[["1613077715657-0",
#  {"type"=>"LIMITS_CHANGE",
#   ...
```

## プラグイン / パッケージ

プラグインとパッケージに関する情報を取得するためのAPI。

### plugin_list

インストールされているすべてのプラグインを返します。

Ruby 構文：

```ruby
plugin_list(default: false)
```

Python 構文：

```ruby
plugin_list(default = False)
```

| パラメータ | 説明                                                             |
| ---------- | ---------------------------------------------------------------- |
| default    | デフォルトのCOSMOSプラグイン（すべての通常のアプリケーション）を含めるかどうか |

Ruby / Python の例：

```ruby
plugins = plugin_list() #=> ['openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem__20250116214539']
plugins = plugin_list(default: true) #=>
# ['openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem__20250116214539',
#  'openc3-cosmos-tool-admin-6.0.3.pre.beta0.20250115200004.gem__20250116211504',
#  'openc3-cosmos-tool-bucketexplorer-6.0.3.pre.beta0.20250115200008.gem__20250116211525',
#  'openc3-cosmos-tool-cmdsender-6.0.3.pre.beta0.20250115200012.gem__20250116211515',
#  'openc3-cosmos-tool-cmdtlmserver-6.0.3.pre.beta0.20250115200015.gem__20250116211512',
#  'openc3-cosmos-tool-dataextractor-6.0.3.pre.beta0.20250115200005.gem__20250116211521',
#  'openc3-cosmos-tool-dataviewer-6.0.3.pre.beta0.20250115200009.gem__20250116211522',
#  'openc3-cosmos-tool-docs-6.0.3.pre.beta0.20250117042104.gem__20250117042154',
#  'openc3-cosmos-tool-handbooks-6.0.3.pre.beta0.20250115200014.gem__20250116211523',
#  'openc3-cosmos-tool-iframe-6.0.3.pre.beta0.20250115200011.gem__20250116211503',
#  'openc3-cosmos-tool-limitsmonitor-6.0.3.pre.beta0.20250115200017.gem__20250116211514',
#  'openc3-cosmos-tool-packetviewer-6.0.3.pre.beta0.20250115200004.gem__20250116211518',
#  'openc3-cosmos-tool-scriptrunner-6.0.3.pre.beta0.20250115200012.gem__20250116211517',
#  'openc3-cosmos-tool-tablemanager-6.0.3.pre.beta0.20250115200018.gem__20250116211524',
#  'openc3-cosmos-tool-tlmgrapher-6.0.3.pre.beta0.20250115200005.gem__20250116211520',
#  'openc3-cosmos-tool-tlmviewer-6.0.3.pre.beta0.20250115200008.gem__20250116211519',
#  'openc3-tool-base-6.0.3.pre.beta0.20250115195959.gem__20250116211459']
```

### plugin_get

インストールされたプラグインに関する情報を返します。

Ruby / Python 構文：

```ruby
plugin_get(<Plugin Name>)
```

| パラメータ   | 説明                                                  |
| ------------ | ---------------------------------------------------- |
| Plugin Name  | プラグインの完全な名前（通常は plugin_list() から取得） |

Ruby / Python の例：

```ruby
plugin_get('openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem__20250116214539') #=>
# { "name"=>"openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem__20250116214539",
#   "variables"=>{"inst_target_name"=>"INST", ...},
#   "plugin_txt_lines"=>["# Note: This plugin includes 4 targets ..."],
#   "needs_dependencies"=>true,
#   "updated_at"=>1737063941094624764 }
```

### package_list

COSMOSにインストールされているすべてのパッケージをリストします。

Ruby の例：

```ruby
package_list() #=> {"ruby"=>["openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem", ..., "openc3-tool-base-6.0.3.pre.beta0.20250115195959.gem"],
               #    "python"=>["numpy-2.1.1", "pip-24.0", "setuptools-65.5.0"]}
```

Python の例：

```python
package_list() #=> {'ruby': ['openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem', ..., 'openc3-tool-base-6.0.3.pre.beta0.20250115195959.gem'],
               #    'python': ['numpy-2.1.1', 'pip-24.0', 'setuptools-65.5.0']}
```

## ターゲット

ターゲットに関する情報を取得するためのAPI。

### get_target_names

システム内のターゲットのリストを配列で返します。

Ruby の例：

```ruby
targets = get_target_names() #=> ['INST', 'INST2', 'EXAMPLE', 'TEMPLATED']
```

### get_target

ターゲットに関するすべての情報を含むターゲットハッシュを返します。

Ruby 構文：

```ruby
get_target("<Target Name>")
```

| パラメータ   | 説明               |
| ------------ | ------------------ |
| Target Name  | ターゲットの名前。 |

Ruby の例：

```ruby
target = get_target("INST")
print(target)
# {"name"=>"INST",
#  "folder_name"=>"INST",
#  "requires"=>[],
#  "ignored_parameters"=>
#   ["CCSDSVER",
#    "CCSDSTYPE",
#    "CCSDSSHF",
#    "CCSDSAPID",
#    "CCSDSSEQFLAGS",
#    "CCSDSSEQCNT",
#    "CCSDSLENGTH",
#    "PKTID"],
#  "ignored_items"=>
#   ["CCSDSVER",
#    "CCSDSTYPE",
#    "CCSDSSHF",
#    "CCSDSAPID",
#    "CCSDSSEQFLAGS",
#    "CCSDSSEQCNT",
#    "CCSDSLENGTH",
#    "RECEIVED_COUNT",
#    "RECEIVED_TIMESECONDS",
#    "RECEIVED_TIMEFORMATTED"],
#  "limits_groups"=>[],
#  "cmd_tlm_files"=>
#   [".../targets/INST/cmd_tlm/inst_cmds.txt",
#    ".../targets/INST/cmd_tlm/inst_tlm.txt"],
#  "cmd_unique_id_mode"=>false,
#  "tlm_unique_id_mode"=>false,
#  "id"=>nil,
#  "updated_at"=>1613077058266815900,
#  "plugin"=>nil}
```

### get_target_interfaces

すべてのターゲットのインターフェースを返します。戻り値は配列の配列で、各サブ配列にはターゲット名とすべてのインターフェース名の文字列が含まれています。

Ruby / Python の例：

```ruby
target_ints = get_target_interfaces()
target_ints.each do |target_name, interfaces|
  puts "Target: #{target_name}, Interfaces: #{interfaces}"
end
```

## インターフェース

これらのメソッドを使用すると、ユーザーはCOSMOSインターフェースを操作できます。

### get_interface

ビルド済みのインターフェースとその現在のステータス（コマンド/テレメトリカウンターなど）を含むインターフェースのステータスを返します。

Ruby / Python 構文：

```
get_interface("<Interface Name>")
```

| パラメータ      | 説明                     |
| --------------- | ------------------------ |
| Interface Name  | インターフェースの名前。 |

Ruby / Python の例：

```ruby
interface = get_interface("INST_INT")
print(interface)
# {"name"=>"INST_INT",
#  "config_params"=>["interface.rb"],
#  "target_names"=>["INST"],
#  "connect_on_startup"=>true,
#  "auto_reconnect"=>true,
#  "reconnect_delay"=>5.0,
#  "disable_disconnect"=>false,
#  "options"=>[],
#  "protocols"=>[],
#  "log"=>true,
#  "log_raw"=>false,
#  "plugin"=>nil,
#  "updated_at"=>1613076213535979900,
#  "state"=>"CONNECTED",
#  "clients"=>0,
#  "txsize"=>0,
#  "rxsize"=>0,
#  "txbytes"=>0,
#  "rxbytes"=>0,
#  "txcnt"=>0,
#  "rxcnt"=>0}
```

### get_interface_names

システム内のインターフェースのリストを配列で返します。

Ruby / Python の例：

```ruby
interface_names = get_interface_names() #=> ['INST_INT', 'INST2_INT', 'EXAMPLE_INT', 'TEMPLATED_INT']
```

### connect_interface

COSMOSインターフェースに関連付けられたターゲットに接続します。

Ruby / Python 構文：

```ruby
connect_interface("<Interface Name>", <Interface Parameters (オプション)>)
```

| パラメータ            | 説明                                                                                                   |
| --------------------- | ------------------------------------------------------------------------------------------------------ |
| Interface Name        | インターフェースの名前。                                                                               |
| Interface Parameters  | インターフェースの初期化に使用されるパラメータ。指定されない場合、インターフェースはサーバー構成ファイルで指定されたパラメータを使用します。 |

Ruby / Python の例：

```ruby
connect_interface("INT1")
connect_interface("INT1", hostname, port)
```

### disconnect_interface

COSMOSインターフェースに関連付けられたターゲットから切断します。

Ruby / Python 構文：

```ruby
disconnect_interface("<Interface Name>")
```

| パラメータ      | 説明                     |
| --------------- | ------------------------ |
| Interface Name  | インターフェースの名前。 |

Ruby / Python の例：

```ruby
disconnect_interface("INT1")
```

### start_raw_logging_interface

1つまたはすべてのインターフェースでの生データのロギングを開始します。これはデバッグ目的のみです。

Ruby / Python 構文：

```ruby
start_raw_logging_interface("<Interface Name (オプション)>")
```

| パラメータ      | 説明                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Interface Name  | 生データロギングを開始するように命令するインターフェースの名前。デフォルトは 'ALL' で、生データロギングをサポートするすべてのインターフェースで生データのロギングを開始します。 |

Ruby / Python の例：

```ruby
start_raw_logging_interface("int1")
```

### stop_raw_logging_interface

1つまたはすべてのインターフェースでの生データのロギングを停止します。これはデバッグ目的のみです。

Ruby / Python 構文：

```ruby
stop_raw_logging_interface("<Interface Name (オプション)>")
```

| パラメータ      | 説明                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Interface Name  | 生データロギングを停止するように命令するインターフェースの名前。デフォルトは 'ALL' で、生データロギングをサポートするすべてのインターフェースで生データのロギングを停止します。 |

Ruby / Python の例：

```ruby
stop_raw_logging_interface("int1")
```

### get_all_interface_info

すべてのインターフェースに関する情報を返します。戻り値は配列の配列で、各サブ配列にはインターフェース名、接続状態、接続クライアント数、送信キューサイズ、受信キューサイズ、送信バイト数、受信バイト数、コマンド数、テレメトリ数が含まれています。

Ruby の例：

```ruby
interface_info = get_all_interface_info()
interface_info.each do |interface_name, connection_state, num_clients, tx_q_size, rx_q_size, tx_bytes, rx_bytes, cmd_count, tlm_count|
  puts "Interface: #{interface_name}, Connection state: #{connection_state}, Num connected clients: #{num_clients}"
  puts "Transmit queue size: #{tx_q_size}, Receive queue size: #{rx_q_size}, Bytes transmitted: #{tx_bytes}, Bytes received: #{rx_bytes}"
  puts "Cmd count: #{cmd_count}, Tlm count: #{tlm_count}"
end
```

Python の例：

```python
interface_info = get_all_interface_info()
for interface in interface_info():
    # [interface_name, connection_state, num_clients, tx_q_size, rx_q_size, tx_bytes, rx_bytes, cmd_count, tlm_count]
    print(f"Interface: {interface[0]}, Connection state: {interface[1]}, Num connected clients: {interface[2]}")
    print(f"Transmit queue size: {interface[3]}, Receive queue size: {interface[4]}, Bytes transmitted: {interface[5]}, Bytes received: {interface[6]}")
    print(f"Cmd count: {interface[7]}, Tlm count: {interface[8]}")
```

### map_target_to_interface

ターゲットをインターフェースにマップして、ターゲットコマンドとテレメトリがそのインターフェースによって処理されるようにします。

Ruby / Python 構文：

```ruby
map_target_to_interface("<Target Name>", "<Interface Name>", cmd_only, tlm_only, unmap_old)
```

| パラメータ      | 説明                                                                                         |
| --------------- | -------------------------------------------------------------------------------------------- |
| Target Name     | ターゲットの名前                                                                             |
| Interface Name  | インターフェースの名前                                                                       |
| cmd_only        | ターゲットコマンドのみをインターフェースにマップするかどうかを指定する名前付きパラメータ（デフォルト：false） |
| tlm_only        | ターゲットテレメトリのみをインターフェースにマップするかどうかを指定する名前付きパラメータ（デフォルト：false） |
| unmap_old       | ターゲットをすべての既存のインターフェースから削除するかどうかを指定する名前付きパラメータ（デフォルト：true） |

Ruby の例：

```ruby
map_target_to_interface("INST", "INST_INT", unmap_old: false)
```

Python の例：

```python
map_target_to_interface("INST", "INST_INT", unmap_old=False)
```

### interface_cmd

コマンドを直接インターフェースに送信します。これは標準のCOSMOSインターフェースでは効果がありませんが、動作を変更するためにカスタムインターフェースで実装できます。
Ruby / Python 構文：

```ruby
interface_cmd("<Interface Name>", "<Command Name>", "<Command Parameters>")
```

| パラメータ         | 説明                                 |
| ------------------ | ------------------------------------ |
| Interface Name     | インターフェースの名前               |
| Command Name       | 送信するコマンドの名前               |
| Command Parameters | コマンドと共に送信するパラメータ     |

Ruby / Python の例：

```ruby
interface_cmd("INST", "DISABLE_CRC")
```

### interface_protocol_cmd

コマンドを直接インターフェースプロトコルに送信します。これは標準のCOSMOSプロトコルでは効果がありませんが、動作を変更するためにカスタムプロトコルで実装できます。

Ruby / Python 構文：

```ruby
interface_protocol_cmd("<Interface Name>", "<Command Name>", "<Command Parameters>")
```

| パラメータ         | 説明                                                                                                                                                             |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interface Name     | インターフェースの名前                                                                                                                                           |
| Command Name       | 送信するコマンドの名前                                                                                                                                           |
| Command Parameters | コマンドと共に送信するパラメータ                                                                                                                                 |
| read_write         | コマンドが送信される読み取りまたは書き込みプロトコル。READ、WRITE、または READ_WRITE（Rubyではシンボル、Pythonでは文字列）のいずれかである必要があります。デフォルトは READ_WRITE です。 |
| index              | スタック内のどのプロトコルにコマンドが適用されるか。デフォルトは -1 で、すべてにコマンドを適用します。                                                           |

Ruby の例：

```ruby
interface_protocol_cmd("INST", "DISABLE_CRC", read_write: :READ_WRITE, index: -1)
```

Python の例：

```python
interface_protocol_cmd("INST", "DISABLE_CRC", read_write='READ_WRITE', index=-1)
```

## ルーター

これらのメソッドを使用すると、ユーザーはCOSMOSルーターを操作できます。

### connect_router

COSMOSルーターを接続します。

Ruby / Python 構文：

```ruby
connect_router("<Router Name>", <Router Parameters (オプション)>)
```

| パラメータ         | 説明                                                                                             |
| ------------------ | ------------------------------------------------------------------------------------------------ |
| Router Name        | ルーターの名前。                                                                                 |
| Router Parameters  | ルーターの初期化に使用されるパラメータ。指定されない場合、ルーターはサーバー構成ファイルで指定されたパラメータを使用します。 |

Ruby / Python の例：

```ruby
connect_ROUTER("INST_ROUTER")
connect_router("INST_ROUTER", 7779, 7779, nil, 10.0, 'PREIDENTIFIED')
```

### disconnect_router

COSMOSルーターを切断します。

Ruby / Python 構文：

```ruby
disconnect_router("<Router Name>")
```

| パラメータ   | 説明             |
| ------------ | ---------------- |
| Router Name  | ルーターの名前。 |

Ruby / Python の例：

```ruby
disconnect_router("INT1_ROUTER")
```

### get_router_names

システム内のルーターのリストを配列で返します。

Ruby / Python の例：
```ruby
router_names = get_router_names() #=> ['ROUTER_INT']
```

### get_router

ビルド済みのルーターとその現在のステータス（コマンド/テレメトリカウンターなど）を含むルーターのステータスを返します。

Ruby / Python 構文：

```ruby
get_router("<Router Name>")
```

| パラメータ   | 説明             |
| ------------ | ---------------- |
| Router Name  | ルーターの名前。 |

Ruby / Python の例：

```ruby
router = get_router("ROUTER_INT")
print(router)
#{"name"=>"ROUTER_INT",
# "config_params"=>["router.rb"],
# "target_names"=>["INST"],
# "connect_on_startup"=>true,
# "auto_reconnect"=>true,
# "reconnect_delay"=>5.0,
# "disable_disconnect"=>false,
# "options"=>[],
# "protocols"=>[],
# "log"=>true,
# "log_raw"=>false,
# "plugin"=>nil,
# "updated_at"=>1613076213535979900,
# "state"=>"CONNECTED",
# "clients"=>0,
# "txsize"=>0,
# "rxsize"=>0,
# "txbytes"=>0,
# "rxbytes"=>0,
# "txcnt"=>0,
# "rxcnt"=>0}
```

### get_all_router_info

すべてのルーターに関する情報を返します。戻り値は配列の配列で、各サブ配列にはルーター名、接続状態、接続クライアント数、送信キューサイズ、受信キューサイズ、送信バイト数、受信バイト数、受信パケット数、送信パケット数が含まれています。

Ruby の例：

```ruby
router_info = get_all_router_info()
router_info.each do |router_name, connection_state, num_clients, tx_q_size, rx_q_size, tx_bytes, rx_bytes, pkts_rcvd, pkts_sent|
  puts "Router: #{router_name}, Connection state: #{connection_state}, Num connected clients: #{num_clients}"
  puts "Transmit queue size: #{tx_q_size}, Receive queue size: #{rx_q_size}, Bytes transmitted: #{tx_bytes}, Bytes received: #{rx_bytes}"
  puts "Packets received: #{pkts_rcvd}, Packets sent: #{pkts_sent}"
end
```

Python の例：

```python
router_info = get_all_router_info()
# router_name, connection_state, num_clients, tx_q_size, rx_q_size, tx_bytes, rx_bytes, pkts_rcvd, pkts_sent
for router in router_info:
    print(f"Router: {router[0]}, Connection state: {router[1]}, Num connected clients: {router[2]}")
    print(f"Transmit queue size: {router[3]}, Receive queue size: {router[4]}, Bytes transmitted: {router[5]}, Bytes received: {router[6]}")
    print(f"Packets received: {router[7]}, Packets sent: {router[8]}")
```

### start_raw_logging_router

1つまたはすべてのルーターでの生データのロギングを開始します。これはデバッグ目的のみです。

Ruby / Python 構文：

```ruby
start_raw_logging_router("<Router Name (オプション)>")
```

| パラメータ   | 説明                                                                                                                 |
| ------------ | -------------------------------------------------------------------------------------------------------------------- |
| Router Name  | 生データロギングを開始するように命令するルーターの名前。デフォルトは 'ALL' で、生データロギングをサポートするすべてのルーターで生データのロギングを開始します。 |

Ruby / Python の例：

```ruby
start_raw_logging_router("router1")
```

### stop_raw_logging_router

1つまたはすべてのルーターでの生データのロギングを停止します。これはデバッグ目的のみです。

Ruby / Python 構文：

```ruby
stop_raw_logging_router("<Router Name (オプション)>")
```

| パラメータ   | 説明                                                                                                                 |
| ------------ | -------------------------------------------------------------------------------------------------------------------- |
| Router Name  | 生データロギングを停止するように命令するルーターの名前。デフォルトは 'ALL' で、生データロギングをサポートするすべてのルーターで生データのロギングを停止します。 |

Ruby / Python の例：

```ruby
stop_raw_logging_router("router1")
```

### router_cmd

コマンドを直接ルーターに送信します。これは標準のCOSMOSルーターでは効果がありませんが、動作を変更するためにカスタムルーターで実装できます。

Ruby / Python 構文：

```ruby
router_cmd("<Router Name>", "<Command Name>", "<Command Parameters>")
```

| パラメータ         | 説明                             |
| ------------------ | -------------------------------- |
| Router Name        | ルーターの名前                   |
| Command Name       | 送信するコマンドの名前           |
| Command Parameters | コマンドと共に送信するパラメータ |

Ruby / Python の例：

```ruby
router_cmd("INST", "DISABLE_CRC")
```

### router_protocol_cmd

コマンドを直接ルータープロトコルに送信します。これは標準のCOSMOSプロトコルでは効果がありませんが、動作を変更するためにカスタムプロトコルで実装できます。

Ruby / Python 構文：

```ruby
router_protocol_cmd("<Router Name>", "<Command Name>", "<Command Parameters>", read_write, index)
```

| パラメータ         | 説明                                                                                                                                                             |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Router Name        | ルーターの名前                                                                                                                                                   |
| Command Name       | 送信するコマンドの名前                                                                                                                                           |
| Command Parameters | コマンドと共に送信するパラメータ                                                                                                                                 |
| read_write         | コマンドが送信される読み取りまたは書き込みプロトコル。READ、WRITE、または READ_WRITE（Rubyではシンボル、Pythonでは文字列）のいずれかである必要があります。デフォルトは READ_WRITE です。 |
| index              | スタック内のどのプロトコルにコマンドが適用されるか。デフォルトは -1 で、すべてにコマンドを適用します。                                                           |

Ruby の例：

```ruby
router_protocol_cmd("INST", "DISABLE_CRC", read_write: :READ_WRITE, index: -1)
```

Python の例：

```python
router_protocol_cmd("INST", "DISABLE_CRC", read_write='READ_WRITE', index=-1)
```

## テーブル

これらのメソッドを使用すると、ユーザーはTable Managerをスクリプト化できます。

### table_create_binary

> バージョン 6.1.0 以降

テーブル定義ファイルに基づいてテーブルバイナリを作成します。Table Manager GUIの「ファイル (File)->新規ファイル (New File)」と同じ結果を得ることができます。作成されたバイナリファイルへのパスを返します。

Ruby / Python 構文：

```ruby
table_create_binary(<Table Definition File>)
```

| パラメータ             | 説明                                                             |
| ---------------------- | ---------------------------------------------------------------- |
| Table Definition File  | テーブル定義ファイルへのパス（例：INST/tables/config/ConfigTables_def.txt） |

Ruby の例：

```ruby
# table_create_binaryを使用してからバイナリを編集する完全な例
require 'openc3/tools/table_manager/table_config'
# これはハッシュを返します: {"filename"=>"INST/tables/bin/MCConfigurationTable.bin"}
table = table_create_binary("INST/tables/config/MCConfigurationTable_def.txt")
file = get_target_file(table['filename'])
table_binary = file.read()

# バイナリを処理するために定義ファイルを取得
def_file = get_target_file("INST/tables/config/MCConfigurationTable_def.txt")
# 定義を処理するために内部TableConfigにアクセス
config = OpenC3::TableConfig.process_file(def_file.path())
# 定義名でテーブルを取得（例：TABLE "MC_Configuration"）
table = config.table('MC_CONFIGURATION')
# これでテーブル内の個々の項目を読み書きできます
table.write("MEMORY_SCRUBBING", "DISABLE")
# 最後にtable.buffer（バイナリ）をストレージに書き戻します
put_target_file("INST/tables/bin/MCConfigurationTable_NoScrub.bin", table.buffer)
```

Python の例：

```python
# table_create_binaryを使用してからバイナリを編集する完全な例
from openc3.tools.table_manager.table_config import TableConfig
# 辞書を返します: {'filename': 'INST/tables/bin/ConfigTables.bin'}
table = table_create_binary("INST2/tables/config/ConfigTables_def.txt")
file = get_target_file(table['filename'])
table_binary = file.read()

# バイナリを処理するために定義ファイルを取得
def_file = get_target_file("INST2/tables/config/MCConfigurationTable_def.txt")
# 定義を処理するために内部TableConfigにアクセス
config = TableConfig.process_file(def_file.name)
# 定義名でテーブルを取得（例：TABLE "MC_Configuration"）
table = config.table('MC_CONFIGURATION')
# これでテーブル内の個々の項目を読み書きできます
table.write("MEMORY_SCRUBBING", "DISABLE")
# 最後にtable.buffer（バイナリ）をストレージに書き戻します
put_target_file("INST2/tables/bin/MCConfigurationTable_NoScrub.bin", table.buffer)
```

### table_create_report

> バージョン 6.1.0 以降

テーブル定義ファイルに基づいてテーブルバイナリを作成します。Table Manager GUIの「ファイル->新規ファイル」と同じ結果を得ることができます。作成されたバイナリファイルへのパスを返します。

Ruby / Python 構文：

```ruby
table_create_report(<Table Binary Filename>, <Table Definition File>, <Table Name (オプション)>)
```

filename, definition, table_name

| パラメータ             | 説明                                                                                                                                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Table Binary File      | テーブルバイナリファイルへのパス（例：INST/tables/bin/ConfigTables.bin）                                                                                                                                 |
| Table Definition File  | テーブル定義ファイルへのパス（例：INST/tables/config/ConfigTables_def.txt）                                                                                                                              |
| Table Name             | レポートを作成するテーブルの名前。これはテーブルバイナリとテーブル定義が複数のテーブルで構成されている場合にのみ適用されます。デフォルトでは、レポートはすべてのテーブルで構成され、バイナリファイルにちなんで名前が付けられます。テーブル名が指定されている場合、レポートは指定されたテーブルのみで構成され、テーブルにちなんで名前が付けられます。 |

Ruby の例：

```ruby
table = table_create_report("INST/tables/bin/ConfigTables.bin", "INST/tables/config/ConfigTables_def.txt") #=>
# {"filename"=>"INST/tables/bin/ConfigTables.csv", "contents"=>"MC_CONFIGURATION\nLabel, ...
table = table_create_report("INST/tables/bin/ConfigTables.bin", "INST/tables/config/ConfigTables_def.txt", table_name: "MC_CONFIGURATION") #=>
# {"filename"=>"INST/tables/bin/McConfiguration.csv", "contents"=>"MC_CONFIGURATION\nLabel, ...
```

Python の例：

```python
table = table_create_report("INST/tables/bin/ConfigTables.bin", "INST/tables/config/ConfigTables_def.txt") #=>
# {'filename': 'INST/tables/bin/ConfigTables.csv', 'contents': 'MC_CONFIGURATION\nLabel, ...
table = table_create_report("INST/tables/bin/ConfigTables.bin", "INST/tables/config/ConfigTables_def.txt", table_name="MC_CONFIGURATION") #=>
# {'filename': 'INST/tables/bin/ConfigTables.csv', 'contents': 'MC_CONFIGURATION\nLabel, ...
```

## データのスタッシュ

これらのメソッドを使用すると、ユーザーは一時的なデータをCOSMOSに保存して取得できます。ストレージはキー/値ストレージ（Rubyのハッシュまたはpythonの辞書）として実装されています。これは、複数のスクリプトや単一スクリプトの複数の実行にまたがって適用される情報を保存するためにスクリプトで使用できます。

### stash_set

スタッシュアイテムを設定します。

Ruby / Python 構文：

```ruby
stash_set("<Stash Key>", <Stash Value>)
```

| パラメータ   | 説明                          |
| ------------ | ----------------------------- |
| Stash Key    | 設定するスタッシュキーの名前        |
| Stash Value  | 設定する値                    |

Ruby / Python の例：

```ruby
stash_set('run_count', 5)
stash_set('setpoint', 23.4)
```

### stash_get

指定されたスタッシュアイテムを返します。

Ruby / Python 構文：

```ruby
stash_get("<Stash Key>")
```

| パラメータ | 説明                    |
| ---------- | ----------------------- |
| Stash Key  | 返すスタッシュキーの名前      |

Ruby / Python の例：

```ruby
stash_get('run_count')  #=> 5
```

### stash_all

すべてのスタッシュアイテムをRubyのハッシュまたはPythonの辞書として返します。

Ruby の例：

```ruby
stash_all()  #=> ['run_count' => 5, 'setpoint' => 23.4]
```

Python の例：

```ruby
stash_all()  #=> ['run_count': 5, 'setpoint': 23.4]
```

### stash_keys

すべてのスタッシュキーを返します。

Ruby / Python の例：

```ruby
stash_keys()  #=> ['run_count', 'setpoint']
```

### stash_delete

スタッシュアイテムを削除します。この操作は永続的であることに注意してください！

Ruby / Python 構文：

```ruby
stash_delete("<Stash Key>")
```

| パラメータ | 説明                    |
| ---------- | ----------------------- |
| Stash Key  | 削除するスタッシュキーの名前  |

Ruby / Python の例：

```ruby
stash_delete("run_count")
```

## テレメトリ画面

これらのメソッドを使用すると、ユーザーはテスト手順内からテレメトリ画面を開いたり、閉じたり、一意のテレメトリ画面を作成したりできます。

### display_screen

指定された位置にテレメトリ画面を開きます。

Ruby / Python 構文：

```ruby
display_screen("<Target Name>", "<Screen Name>", <X Position (オプション)>, <Y Position (オプション)>)
```

| パラメータ   | 説明                                 |
| ------------ | ------------------------------------ |
| Target Name  | テレメトリ画面のターゲット名         |
| Screen Name  | 指定されたターゲット内の画面名       |
| X Position   | 画面の左上隅のX座標                  |
| Y Position   | 画面の左上隅のY座標                  |

Ruby / Python の例：

```ruby
display_screen("INST", "ADCS", 100, 200)
```

### clear_screen

開いているテレメトリ画面を閉じます。

Ruby / Python 構文：

```ruby
clear_screen("<Target Name>", "<Screen Name>")
```

| パラメータ   | 説明                               |
| ------------ | ---------------------------------- |
| Target Name  | テレメトリ画面のターゲット名       |
| Screen Name  | 指定されたターゲット内の画面名     |
Ruby / Python の例：

```ruby
clear_screen("INST", "ADCS")
```

### clear_all_screens

開いているすべての画面を閉じます。

Ruby / Python の例：

```ruby
clear_all_screens()
```

### delete_screen

既存のTelemetry Viewer画面を削除します。

Ruby / Python 構文：

```ruby
delete_screen("<Target Name>", "<Screen Name>")
```

| パラメータ   | 説明                             |
| ------------ | -------------------------------- |
| Target Name  | テレメトリ画面のターゲット名     |
| Screen Name  | 指定されたターゲット内の画面名   |

Ruby / Python の例：

```ruby
delete_screen("INST", "ADCS")
```

### get_screen_list

利用可能なテレメトリ画面のリストを返します。

Ruby / Python の例：

```ruby
get_screen_list() #=> ['INST ADCS', 'INST COMMANDING', ...]
```

### get_screen_definition

テレメトリ画面定義のテキストファイルの内容を返します。

構文：

```ruby
get_screen_definition("<Target Name>", "<Screen Name>")
```

| パラメータ   | 説明                             |
| ------------ | -------------------------------- |
| Target Name  | テレメトリ画面のターゲット名     |
| Screen Name  | 指定されたターゲット内の画面名   |

Ruby / Python の例：

```ruby
screen_definition = get_screen_definition("INST", "HS")
```

### create_screen

スクリプトから直接画面を作成することができます。この画面は、そのアプリケーションで未来に使用するためにTelemetry Viewerに保存されます。

Ruby / Python 構文：

```ruby
create_screen("<Target Name>", "<Screen Name>" "<Definition>")
```

| パラメータ   | 説明                                |
| ------------ | ----------------------------------- |
| Target Name  | テレメトリ画面のターゲット名        |
| Screen Name  | 指定されたターゲット内の画面名      |
| Definition   | 画面定義全体を文字列として          |

Ruby の例：

```ruby
screen_def = '
  SCREEN AUTO AUTO 0.1 FIXED
  VERTICAL
    TITLE "New Screen"
    VERTICALBOX
      LABELVALUE INST HEALTH_STATUS TEMP1
    END
  END
'
# ここでは画面定義を文字列として渡します
create_screen("INST", "LOCAL", screen_def)
```
Python の例：

```python
screen_def = '
  SCREEN AUTO AUTO 0.1 FIXED
  VERTICAL
    TITLE "New Screen"
    VERTICALBOX
      LABELVALUE INST HEALTH_STATUS TEMP1
    END
  END
'
# ここでは画面定義を文字列として渡します
create_screen("INST", "LOCAL", screen_def)
```

### local_screen

スクリプトから直接ローカル画面を作成することができます。この画面はTelemetry Viewerの画面リストに永続的に保存されません。これは、スクリプトとのユーザー対話を支援する一度限りの画面に役立ちます。

Ruby / Python 構文：

```ruby
local_screen("<Screen Name>", "<Definition>", <X Position (オプション)>, <Y Position (オプション)>)
```

| パラメータ   | 説明                                 |
| ------------ | ------------------------------------ |
| Screen Name  | 指定されたターゲット内の画面名       |
| Definition   | 画面定義全体を文字列として           |
| X Position   | 画面の左上隅のX座標                  |
| Y Position   | 画面の左上隅のY座標                  |

注意：表示可能な画面の外にX、Y位置を指定することも可能です。そうして画面を再作成しようとすると表示されません（すでに表示されているため）。まず `clear_all_screens()` を発行して、表示可能な画面スペースから画面をクリアしてみてください。

Ruby の例：

```ruby
screen_def = '
  SCREEN AUTO AUTO 0.1 FIXED
  VERTICAL
    TITLE "Local Screen"
    VERTICALBOX
      LABELVALUE INST HEALTH_STATUS TEMP1
    END
  END
'
# ここでは画面定義を文字列として渡します
local_screen("TESTING", screen_def, 600, 75)
```

Python の例：

```python
screen_def = """
  SCREEN AUTO AUTO 0.1 FIXED
  VERTICAL
    TITLE "Local Screen"
    VERTICALBOX
      LABELVALUE INST HEALTH_STATUS TEMP1
    END
  END
"""
# ここでは画面定義を文字列として渡します
local_screen("TESTING", screen_def, 600, 75)
```

## Script Runner スクリプト

これらのメソッドを使用すると、ユーザーはScript Runnerスクリプトを制御できます。

### start

高レベルテスト手順の実行を開始します。Script Runnerはファイルをロードし、呼び出し元の手順に戻る前に直ちに実行を開始します。高レベルテスト手順にパラメータを渡すことはできません。パラメータが必要な場合は、サブルーチンの使用を検討してください。

Ruby / Python 構文：

```ruby
start("<Procedure Filename>")
```

| パラメータ         | 説明                                                                                                                             |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| Procedure Filename | テスト手順ファイルの名前。これらのファイルは通常、proceduresフォルダにありますが、Rubyの検索パスのどこにでも配置できます。さらに、絶対パスもサポートされています。 |

Ruby / Python の例：

```ruby
start("test1.rb")
```

### load_utility

テスト手順で使用するための便利なサブルーチンを含むスクリプトファイルを読み込みます。これらのサブルーチンがScriptRunnerまたはTestRunnerで実行されると、それらの行が強調表示されます。サブルーチンをインポートしたいが、ScriptRunnerまたはTestRunnerでそれらの行を強調表示したくない場合は、標準のRubyの 'load' または 'require' ステートメント、またはPythonの 'import' ステートメントを使用してください。

Ruby / Python 構文：

```ruby
load_utility("TARGET/lib/<Utility Filename>")
```

| パラメータ        | 説明                                                                                                                                     |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Utility Filename  | .rb または .py 拡張子を含むサブルーチンを含むスクリプトファイルの名前。TARGET/lib/utility.rb のような完全なターゲット名とパスを含める必要があります |

Ruby / Python の例：

```ruby
load_utility("TARGET/lib/mode_changes.rb") # Ruby
load_utility("TARGET/lib/mode_changes.py") # Python
```

### script_list

COSMOSで使用可能なすべてのファイルを配列/リストとして返します。これには、ユーザーがすべてのファイルにアクセスできるように、あらゆるディレクトリレベルの設定ファイルが含まれます。必要に応じて、クライアント側でリストを 'lib' や 'procedures' ディレクトリのみにフィルタリングすることができます。注意：スクリプト名には、変更を示す '*' は含まれません。

Ruby の例：

```ruby
scripts = script_list()
puts scripts.length #=> 139
puts scripts.select {|script| script.include?('/lib/') || script.include?('/procedures/')} #=>
# [EXAMPLE/lib/example_interface.rb, INST/lib/example_limits_response.rb, ...]
```

Python の例：

```python
scripts = script_list()
print(len(scripts))
print(list(script for script in scripts if '/lib/' in script or '/procedures/' in script)) #=>
# [EXAMPLE/lib/example_interface.rb, INST/lib/example_limits_response.rb, ...]
```

### script_create

指定された内容で新しいスクリプトを作成します。

Ruby / Python 構文：

```ruby
script_create("<Script Name>", "<Script Contents>")
```

| パラメータ       | 説明                                             |
| ---------------- | ------------------------------------------------ |
| Script Name      | ターゲットから始まるスクリプトの完全なパス名     |
| Script Contents  | テキストとしてのスクリプトの内容                 |

Ruby の例：

```ruby
contents = 'puts "Hello from Ruby"'
script_create("INST/procedures/new_script.rb", contents)
```

Python の例：

```python
contents = 'print("Hello from Python")'
script_create("INST2/procedures/new_script.py", contents)
```

### script_body

スクリプトの内容を返します。

Ruby / Python 構文：

```ruby
script_body("<Script Name>")
```

| パラメータ    | 説明                                           |
| ------------- | ---------------------------------------------- |
| Script Name   | ターゲットから始まるスクリプトの完全なパス名   |

Ruby の例：

```ruby
script = script_body("INST/procedures/checks.rb")
puts script #=> # Display all environment variables\nputs ENV.inspect ...
```

Python の例：

```python
script = script_body("INST2/procedures/checks.py")
print(script) #=> # import os\n\n# Display the environment variables ...
```

### script_delete

COSMOSからスクリプトを削除します。注意：実際に削除できるのはTEMPスクリプトと変更されたスクリプトのみです。インストールされたCOSMOSプラグインの一部であるスクリプトは、インストールされたままの状態を維持します。

Ruby / Python 構文：

```ruby
script_delete("<Script Name>")
```

| パラメータ    | 説明                                           |
| ------------- | ---------------------------------------------- |
| Script Name   | ターゲットから始まるスクリプトの完全なパス名   |

Ruby / Python の例：

```ruby
script_delete("INST/procedures/checks.rb")
```

### script_run

Script Runnerでスクリプトを実行します。スクリプトはバックグラウンドで実行され、Script Runnerの「Script->Execution Status」を選択して接続することで開くことができます。

注意：Enterpriseでは、このメソッドを呼び出すユーザーに対して initialize_offline_access が少なくとも1回呼び出されている必要があります。

Ruby / Python 構文：

```ruby
script_run("<Script Name>")
```

| パラメータ    | 説明                                           |
| ------------- | ---------------------------------------------- |
| Script Name   | ターゲットから始まるスクリプトの完全なパス名   |

Ruby の例：

```ruby
id = script_run("INST/procedures/checks.rb")
puts id
```

Python の例：

```python
id = script_run("INST2/procedures/checks.py")
print(id)
```

### script_lock

編集のためにスクリプトをロックします。このスクリプトを後続のユーザーが開くと、スクリプトが現在ロックされているという警告が表示されます。

Ruby / Python 構文：

```ruby
script_lock("<Script Name>")
```

| パラメータ    | 説明                                           |
| ------------- | ---------------------------------------------- |
| Script Name   | ターゲットから始まるスクリプトの完全なパス名   |

Ruby / Python の例：

```ruby
script_lock("INST/procedures/checks.rb")
```

### script_unlock

編集のためにスクリプトのロックを解除します。スクリプトが以前にロックされていなかった場合、何も行いません。

Ruby / Python 構文：

```ruby
script_unlock("<Script Name>")
```

| パラメータ    | 説明                                           |
| ------------- | ---------------------------------------------- |
| Script Name   | ターゲットから始まるスクリプトの完全なパス名   |

Ruby / Python の例：

```ruby
script_unlock("INST/procedures/checks.rb")
```

### script_syntax_check

指定されたスクリプトに対してRubyまたはPython構文チェックを実行します。

Ruby / Python 構文：

```ruby
script_syntax_check("<Script Name>")
```

| パラメータ    | 説明                                           |
| ------------- | ---------------------------------------------- |
| Script Name   | ターゲットから始まるスクリプトの完全なパス名   |

Ruby の例：

```ruby
result = script_syntax_check("INST/procedures/checks.rb")
puts result #=> {"title"=>"Syntax Check Successful", "description"=>"[\"Syntax OK\\n\"]", "success"=>true}
```

Python の例：

```python
result = script_syntax_check("INST2/procedures/checks.py")
print(result) #=> {'title': 'Syntax Check Successful', 'description': '["Syntax OK"]', 'success': True}
```

### script_instrumented

COSMOSスクリプトランナーが実行を監視し、行ごとの視覚化を提供できるようにする計装済みスクリプトを返します。これは主にCOSMOS開発者によって使用される低レベルのデバッグメソッドです。

Ruby / Python 構文：

```ruby
script_instrumented("<Script Name>")
```

| パラメータ    | 説明                                           |
| ------------- | ---------------------------------------------- |
| Script Name   | ターゲットから始まるスクリプトの完全なパス名   |

Ruby の例：

```ruby
script = script_instrumented("INST/procedures/checks.rb")
puts script #=> private; __return_val = nil; begin; RunningScript.instance.script_binding = binding(); ...
```

Python の例：

```python
script = script_instrumented("INST2/procedures/checks.py")
print(script) #=> while True:\ntry:\nRunningScript.instance.pre_line_instrumentation ...
```

### script_delete_all_breakpoints

すべてのスクリプトに関連付けられたすべてのブレークポイントを削除します。

Ruby / Python の例：

```ruby
script_delete_all_breakpoints()
```

### step_mode

ScriptRunnerをステップモードにします。次の行に進むには「Go」をクリックする必要があります。

Ruby / Python の例：

```ruby
step_mode()
```

### run_mode

ScriptRunnerを実行モードにします。次の行は自動的に実行されます。

Ruby / Python の例：

```ruby
run_mode()
```

### disconnect_script

スクリプトを切断モードにします。切断モードでは、コマンドはターゲットに送信されず、すべてのチェックは成功し、待機は即座に期限切れになります。テレメトリのリクエスト（tlm()）は通常0を返します。切断モードは、接続されていないターゲットでスクリプトをドライランするのに役立ちます。

Ruby / Python の例：

```ruby
disconnect_script()
```

### running_script_list

現在実行中のスクリプトをリストします。注意：このメソッドを呼び出しているスクリプトも含まれます。したがって、リストは決して空にならず、常に少なくとも1つの項目が含まれます。ハッシュの配列/辞書のリストを返します（ハッシュ/辞書の内容については[running_script_get](#running_script_get)を参照）。

Ruby の例：

```ruby
running_script_list() #=> [{"id"=>5, "scope"=>"DEFAULT", "name"=>"__TEMP__/2025_01_15_13_16_26_210_temp.rb", "user"=>"Anonymous", "start_time"=>"2025-01-15 20:16:52 +0000", "disconnect"=>false, "environment"=>[]}]
```

Python の例：

```python
running_script_list() #=> [{'id': 15, 'scope': 'DEFAULT', 'name': 'INST2/procedures/scripting.py', 'user': 'Anonymous', 'start_time': '2025-01-16 17:36:22 +0000', 'disconnect': False, 'environment': []}]
```

### running_script_get

指定されたIDで現在実行中のスクリプトを取得します。返される情報は、スクリプトID、スコープ、名前、ユーザー、開始時間、切断状態、環境変数、ホスト名、状態、行番号、更新時間です。

Ruby / Python 構文：
```ruby
running_script_get("<Script Id>")
```

| パラメータ | 説明                                          |
| ---------- | --------------------------------------------- |
| Script Id  | [script_run](#script_run)によって返されるスクリプトID |

Ruby の例：

```ruby
running_script_get(15) #=> {"id"=>15, "scope"=>"DEFAULT", "name"=>"INST/procedures/new_script.rb", "user"=>"Anonymous", "start_time"=>"2025-01-16 00:28:44 +0000", "disconnect"=>false, "environment"=>[], "hostname"=>"ac9dde3c59c1", "state"=>"spawning", "line_no"=>1, "update_time"=>"2025-01-16 00:28:44 +0000"}
```

Python の例：

```python
running_script_get(15) #=> {'id': 15, 'scope': 'DEFAULT', 'name': 'INST2/procedures/new_script.py', 'user': 'Anonymous', 'start_time': '2025-01-16 18:04:03 +0000', 'disconnect': False, 'environment': [], 'hostname': 'b84dbcee54ad', 'state': 'running', 'line_no': 3, 'update_time': '2025-01-16T18:04:05.255638Z'}
```

### running_script_stop

指定されたIDの実行中のスクリプトを停止します。これはScript Runner GUIの「Stop」ボタンをクリックするのと同じです。

Ruby / Python 構文：

```ruby
running_script_stop("<Script Id>")
```

| パラメータ | 説明                                          |
| ---------- | --------------------------------------------- |
| Script Id  | [script_run](#script_run)によって返されるスクリプトID |

Ruby / Python の例：

```ruby
running_script_stop(15)
```

### running_script_pause

指定されたIDの実行中のスクリプトを一時停止します。これはScript Runner GUIの「Pause」ボタンをクリックするのと同じです。

Ruby / Python 構文：

```ruby
running_script_pause("<Script Id>")
```

| パラメータ | 説明                                          |
| ---------- | --------------------------------------------- |
| Script Id  | [script_run](#script_run)によって返されるスクリプトID |

Ruby / Python の例：

```ruby
running_script_pause(15)
```

### running_script_retry

指定されたIDの実行中のスクリプトの現在の行を再試行します。これはScript Runner GUIの「Retry」ボタンをクリックするのと同じです。

Ruby / Python 構文：

```ruby
running_script_retry("<Script Id>")
```

| パラメータ | 説明                                          |
| ---------- | --------------------------------------------- |
| Script Id  | [script_run](#script_run)によって返されるスクリプトID |

Ruby / Python の例：

```ruby
running_script_retry(15)
```

### running_script_go

指定されたIDの実行中のスクリプトの一時停止を解除します。これはScript Runner GUIの「Go」ボタンをクリックするのと同じです。

Ruby / Python 構文：

```ruby
running_script_go("<Script Id>")
```

| パラメータ | 説明                                          |
| ---------- | --------------------------------------------- |
| Script Id  | [script_run](#script_run)によって返されるスクリプトID |

Ruby / Python の例：

```ruby
running_script_go(15)
```
### running_script_step

指定されたIDの実行中のスクリプトをステップ実行します。これはScript Runner GUIのDebugウィンドウの「Step」ボタンをクリックするのと同じです。

Ruby / Python 構文：

```ruby
running_script_step("<Script Id>")
```

| パラメータ | 説明                                          |
| ---------- | --------------------------------------------- |
| Script Id  | [script_run](#script_run)によって返されるスクリプトID |

Ruby / Python の例：

```ruby
running_script_step(15)
```

### running_script_delete

指定されたIDの実行中のスクリプトを強制終了します。これはScript Runner GUIのScript -> Execution Statusページの「Running Scripts」の下にある「Delete」ボタンをクリックするのと同じです。注意：まず「stop」信号が指定されたスクリプトに送信され、その後スクリプトが強制的に削除されます。通常は[running_script_stop](#running_script_stop)メソッドを使用する必要があります。

Ruby / Python 構文：

```ruby
running_script_delete("<Script Id>")
```

| パラメータ | 説明                                          |
| ---------- | --------------------------------------------- |
| Script Id  | [script_run](#script_run)によって返されるスクリプトID |

Ruby / Python の例：

```ruby
running_script_delete(15)
```

### completed_script_list

完了したスクリプトをリストします。id、ユーザー名、スクリプト名、スクリプトログ、開始時間を含むハッシュの配列/辞書のリストを返します。

Ruby の例：

```ruby
completed_script_list() #=> [{"id"=>"15", "user"=>"Anonymous", "name"=>"__TEMP__/2025_01_15_17_07_51_568_temp.rb", "log"=>"DEFAULT/tool_logs/sr/20250116/2025_01_16_00_28_43_sr_2025_01_15_17_07_51_568_temp.txt", "start"=>"2025-01-16 00:28:43 +0000"}, ...]
```

Python の例：

```ruby
completed_script_list() #=> [{'id': 16, 'user': 'Anonymous', 'name': 'INST2/procedures/new_script.py', 'log': 'DEFAULT/tool_logs/sr/20250116/2025_01_16_17_46_22_sr_new_script.txt', 'start': '2025-01-16 17:46:22 +0000'}, ...]
```

## Script Runner 設定

これらのメソッドを使用すると、ユーザーはさまざまなScript Runner設定を制御できます。

### set_line_delay

このメソッドはスクリプトランナーの行遅延を設定します。

Ruby / Python 構文：

```ruby
set_line_delay(<Delay>)
```

| パラメータ | 説明                                                                           |
| ---------- | ------------------------------------------------------------------------------ |
| Delay      | スクリプトを実行するときにスクリプトランナーが行間で待機する時間（秒）。 ≥ 0.0でなければなりません |

Ruby / Python の例：

```ruby
set_line_delay(0.0)
```

### get_line_delay

このメソッドはスクリプトランナーが現在使用している行遅延を取得します。

Ruby / Python の例：

```ruby
curr_line_delay = get_line_delay()
```

### set_max_output

このメソッドは、切り捨てる前にScript Runner出力に表示する最大文字数を設定します。デフォルトは50,000文字です。

Ruby / Python 構文：

```ruby
set_max_output(<Characters>)
```
| パラメータ  | 説明                                |
| ----------- | ----------------------------------- |
| Characters  | 切り捨てる前に出力する文字数        |

Ruby / Python の例：

```ruby
set_max_output(100)
```

### get_max_output

このメソッドは、切り捨てる前にScript Runner出力に表示する最大文字数を取得します。デフォルトは50,000文字です。

Ruby / Python の例：

```ruby
print(get_max_output()) #=> 50000
```

### disable_instrumentation

コードブロックの計装（行の強調表示と例外のキャッチ）を無効にします。これは特に、行が計装されていると非常に遅くなるループを高速化するのに役立ちます。
このようなコードを別のファイルに分割して、require/loadを使用してファイルを読み込むことで、同じ効果を得ながらスクリプトでエラーをキャッチできるようにすることを検討してください。

:::warning 注意して使用してください
計装を無効にすると、無効中に発生したエラーによって、スクリプトが完全に停止します。
:::

Ruby の例：

```ruby
disable_instrumentation do
  1000.times do
    # 1000回強調表示する必要がないようにする
  end
end
```

Python の例：

```python
with disable_instrumentation():
    for x in range(1000):
        # 1000回強調表示する必要がないようにする
```

## Script Runner スイート

Script Runnerスイートの作成には、定義されたスイートにグループを追加するAPIを利用します。詳細については[スクリプトスイートの実行](../tools/script-runner.md#running-script-suites)を参照してください。

### add_group, add_group_setup, add_group_teardown, add_script

グループのメソッドをスイートに追加します。add_groupメソッドは、setup、teardown、および 'script\_' または 'test\_' で始まるすべてのメソッドを含むグループメソッド全体を追加します。add_group_setupメソッドは、グループクラスで定義されたsetupメソッドのみを追加します。add_group_teardownメソッドは、グループクラスで定義されたteardownメソッドのみを追加します。add_scriptメソッドは、個々のメソッドをスイートに追加します。注意：add_scriptは、'script\_' または 'test\_' という名前が付いていないメソッドを含む任意のメソッドを追加できます。

Ruby / Python 構文：

```ruby
add_group(<Group Class>)
add_group_setup(<Group Class>)
add_group_teardown(<Group Class>)
add_script(<Group Class>, <Method>)
```

| パラメータ   | 説明                                                                                                                                                                 |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Group Class  | OpenC3 Groupクラスを継承する、以前に定義されたクラスの名前。Ruby APIはグループの名前を持つ文字列を渡します。Python APIはGroupクラスを直接渡します。                 |
| Method       | OpenC3 Groupクラスのメソッドの名前。Ruby APIはメソッドの名前を持つ文字列を渡します。Python APIはGroupクラスを直接渡します。                                         |

Ruby の例：

```ruby
load 'openc3/script/suite.rb'

class ExampleGroup < OpenC3::Group
  def script_1
    # テストコードをここに挿入...
  end
end
class WrapperGroup < OpenC3::Group
  def setup
    # テストコードをここに挿入...
  end
  def my_method
    # テストコードをここに挿入...
  end
  def teardown
    # テストコードをここに挿入...
  end
end

class MySuite < OpenC3::Suite
  def initialize
    super()
    add_group('ExampleGroup')
    add_group_setup('WrapperGroup')
    add_script('WrapperGroup', 'my_method')
    add_group_teardown('WrapperGroup')
  end
end
```

Python の例：

```python
from openc3.script import *
from openc3.script.suite import Group, Suite

class ExampleGroup(Group):
    def script_1(self):
        # テストコードをここに挿入...
        pass
class WrapperGroup(Group):
    def setup(self):
        # テストコードをここに挿入...
        pass
    def my_method(self):
        # テストコードをここに挿入...
        pass
    def teardown(self):
        # テストコードをここに挿入...
        pass
class MySuite(Suite):
    def __init__(self):
        super().__init__()
        self.add_group(ExampleGroup)
        self.add_group_setup(WrapperGroup)
        self.add_script(WrapperGroup, 'my_method')
        self.add_group_teardown(WrapperGroup)
```

## タイムライン

タイムラインAPIを使用すると、カレンダータイムラインを操作できます。カレンダーはCOSMOS Enterpriseツールです。

### list_timelines

すべてのタイムラインをハッシュの配列/辞書のリストとして返します。

Ruby の例：

```ruby
timelines = list_timelines() #=>
# [{"name"=>"Mine", "color"=>"#e67643", "execute"=>true, "shard"=>0, "scope"=>"DEFAULT", "updated_at"=>1737124024123643504}]
```

Python の例：

```python
timelihes = list_timelines() #=>
# [{'name': 'Mine', 'color': '#e67643', 'execute': True, 'shard': 0, 'scope': 'DEFAULT', 'updated_at': 1737124024123643504}]
```

### create_timeline

アクティビティを保持できるカレンダーに新しいタイムラインを作成します。

Ruby 構文：

```ruby
create_timeline(name, color: nil)
```

Python 構文：

```python
create_timeline(name, color=None)
```

| パラメータ | 説明                                                                                |
| ---------- | ----------------------------------------------------------------------------------- |
| name       | タイムラインの名前                                                                  |
| color      | タイムラインの色。16進値として指定する必要があります（例：#FF0000）。デフォルトはランダムな色です。 |

Ruby の例：

```ruby
tl = create_timeline("Mine") #=>
# {"name"=>"Mine", "color"=>"#e67643", "execute"=>true, "shard"=>0, "scope"=>"DEFAULT", "updated_at"=>1737124024123643504}
```
Python の例：

```python
tl = create_timeline("Other", color="#FF0000") #=>
# {'name': 'Other', 'color': '#FF0000', 'execute': True, 'shard': 0, 'scope': 'DEFAULT', 'updated_at': 1737126348971941923}
```

### get_timeline

既存のタイムラインに関する情報を取得します。

Ruby / Python 構文：

```ruby
get_timeline(name)
```

| パラメータ | 説明               |
| ---------- | ------------------ |
| name       | タイムラインの名前 |

Ruby の例：

```ruby
tl = get_timeline("Mine") #=>
# {"name"=>"Mine", "color"=>"#e67643", "execute"=>true, "shard"=>0, "scope"=>"DEFAULT", "updated_at"=>1737124024123643504}
```

Python の例：

```python
tl = get_timeline("Other") #=>
# {'name': 'Other', 'color': '#FF0000', 'execute': True, 'shard': 0, 'scope': 'DEFAULT', 'updated_at': 1737126348971941923}
```

### set_timeline_color

既存のタイムラインの表示色を設定します。

Ruby / Python 構文：

```ruby
set_timeline_color(name, color)
```

| パラメータ | 説明                                                        |
| ---------- | ----------------------------------------------------------- |
| name       | タイムラインの名前                                          |
| color      | タイムラインの色。16進値として指定する必要があります（例：#FF0000）。 |

Ruby / Python の例：

```ruby
set_timeline_color("Mine", "#4287f5")
```

### delete_timeline

既存のタイムラインを削除します。アクティビティを持つタイムラインは、force = true を渡すことでのみ削除できます。

Ruby 構文：

```ruby
delete_timeline(name, force: false)
```

Python 構文：

```python
delete_timeline(name, force=False)
```

| パラメータ | 説明                                                               |
| ---------- | ------------------------------------------------------------------ |
| name       | タイムラインの名前                                                 |
| force      | タイムラインにアクティビティがある場合に削除するかどうか。デフォルトは false です。 |

Ruby の例：

```ruby
delete_timeline("Mine", force: true)
```

Python の例：

```python
delete_timeline("Other", force=True)
```

### create_timeline_activity

既存のタイムラインにアクティビティを作成します。アクティビティは COMMAND、SCRIPT、または RESERVE のいずれかです。アクティビティには開始時間と終了時間があり、コマンドとスクリプトは実行するコマンドまたはスクリプトに関するデータを取ります。

Ruby 構文：

```ruby
create_timeline_activity(name, kind:, start:, stop:, data: {})
```
Python 構文：

```python
create_timeline_activity(name, kind, start, stop, data={})
```

| パラメータ | 説明                                                                 |
| ---------- | -------------------------------------------------------------------- |
| name       | タイムラインの名前                                                   |
| kind       | アクティビティの種類。COMMAND、SCRIPT、またはRESERVEのいずれか。     |
| start      | アクティビティの開始時間。Time / datetimeインスタンス。              |
| stop       | アクティビティの終了時間。Time / datetimeインスタンス。              |
| data       | COMMANDまたはSCRIPT型のデータのハッシュ/辞書。デフォルトは空のハッシュ/辞書です。 |

Ruby の例：

```ruby
now = Time.now()
start = now + 3600
stop = start + 3600
act = create_timeline_activity("RubyTL", kind: "RESERVE", start: start, stop: stop) #=>
# { "name"=>"RubyTL", "updated_at"=>1737128705034982375, "start"=>1737132303, "stop"=>1737135903,
#   "kind"=>"reserve", "data"=>{"username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"5f373846-eb6c-43cd-97bd-cca19a8ffb04",
#   "events"=>[{"time"=>1737128705, "event"=>"created"}], "recurring"=>{}}
act = create_timeline_activity("RubyTL", kind: "COMMAND", start: start, stop: stop,
    data: {command: "INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10"}) #=>
# { "name"=>"RubyTL", "updated_at"=>1737128761316084471, "start"=>1737132303, "stop"=>1737135903,
#   "kind"=>"command", "data"=>{"command"=>"INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10", "username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"cdb661b4-a65b-44e7-95e2-5e1dba80c782",
#   "events"=>[{"time"=>1737128761, "event"=>"created"}], "recurring"=>{}}
act = create_timeline_activity("RubyTL", kind: "SCRIPT", start: start, stop: stop,
  data: {environment: [{key: "USER", value: "JASON"}], script: "INST/procedures/checks.rb"}) #=>
# { "name"=>"RubyTL", "updated_at"=>1737128791047885970, "start"=>1737135903, "stop"=>1737139503,
#   "kind"=>"script", "data"=>{"environment"=>[{"key"=>"USER", "value"=>"JASON"}], "script"=>"INST/procedures/checks.rb", "username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"70426e3d-6313-4897-b159-6e5cd94ace1d",
#   "events"=>[{"time"=>1737128791, "event"=>"created"}], "recurring"=>{}}
```

Python の例：

```python
now = datetime.now(timezone.utc)
start = now + timedelta(hours=1)
stop = start + timedelta(hours=1)
act = create_timeline_activity("PythonTL", kind="RESERVE", start=start, stop=stop) #=>
# {'name': 'PythonTL', 'updated_at': 1737129305507111708, 'start': 1737132902, 'stop': 1737136502,
#  'kind': 'reserve', 'data': {'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': '46328378-ed78-4719-ad70-e84951a196fd',
#  'events': [{'time': 1737129305, 'event': 'created'}], 'recurring': {}}
act = create_timeline_activity("PythonTL", kind="COMMAND", start=start, stop=stop,
    data={'command': "INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10"}) #=>
# {'name': 'PythonTL', 'updated_at': 1737129508886643928, 'start': 1737133108, 'stop': 1737136708,
#  'kind': 'command', 'data': {'command': 'INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10', 'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': 'cddbf034-ccdd-4c36-91c2-2653a39b06a5',
#  'events': [{'time': 1737129508, 'event': 'created'}], 'recurring': {}}
start = now + timedelta(hours=2)
stop = start + timedelta(hours=1)
act = create_timeline_activity("PythonTL", kind="SCRIPT", start=start, stop=stop,
  data={'environment': [{'key': "USER", 'value': "JASON"}], 'script': "INST2/procedures/checks.py"}) #=>
# {'name': 'PythonTL', 'updated_at': 1737129509288571345, 'start': 1737136708, 'stop': 1737140308,
#  'kind': 'script', 'data': {'environment': [{'key': 'USER', 'value': 'JASON'}], 'script': 'INST2/procedures/checks.py', 'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': '4f8d791b-b138-4383-b5ec-85c28b2bea20',
#  'events': [{'time': 1737129509, 'event': 'created'}], 'recurring': {}}
```

### get_timeline_activity

既存のタイムラインアクティビティを取得します。

Ruby / Python 構文：

```ruby
get_timeline_activity(name, start, uuid)
```

| パラメータ | 説明                                            |
| ---------- | ----------------------------------------------- |
| name       | タイムラインの名前                              |
| start      | アクティビティの開始時間。Time / datetimeインスタンス。 |
| uuid       | アクティビティのUUID                            |

Ruby の例：

```ruby
act = get_timeline_activity("RubyTL", 1737132303, "cdb661b4-a65b-44e7-95e2-5e1dba80c782") #=>
# { "name"=>"RubyTL", "updated_at"=>1737128761316084471, "start"=>1737132303, "stop"=>1737135903,
#   "kind"=>"command", "data"=>{"command"=>"INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10", "username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"cdb661b4-a65b-44e7-95e2-5e1dba80c782",
#   "events"=>[{"time"=>1737128761, "event"=>"created"}], "recurring"=>{}}
```

Python の例：

```python
act = get_timeline_activity("PythonTL", 1737133108, "cddbf034-ccdd-4c36-91c2-2653a39b06a5") #=>
# {'name': 'PythonTL', 'updated_at': 1737129508886643928, 'start': 1737133108, 'stop': 1737136708,
#  'kind': 'command', 'data': {'command': 'INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10', 'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': 'cddbf034-ccdd-4c36-91c2-2653a39b06a5',
#  'events': [{'time': 1737129508, 'event': 'created'}], 'recurring': {}}
```

### get_timeline_activities

開始時間と終了時間の間のタイムラインアクティビティの範囲を取得します。開始/終了時間なしで呼び出された場合、デフォルトは「現在」の1週間前から「現在」の1週間後までです（合計2週間）。

Ruby 構文：

```ruby
get_timeline_activities(name, start: nil, stop: nil, limit: nil)
```

Python 構文：

```python
get_timeline_activities(name, start=None, stop=None, limit=None)
```

| パラメータ | 説明                                                                    |
| ---------- | ----------------------------------------------------------------------- |
| name       | タイムラインの名前                                                      |
| start      | アクティビティの開始時間。Time / datetimeインスタンス。デフォルトは7日前。  |
| stop       | アクティビティの終了時間。Time / datetimeインスタンス。デフォルトは今から7日後。 |
| limit      | 返すアクティビティの最大数。デフォルトは時間範囲の1分あたり1つです。   |

Ruby の例：

```ruby
acts = get_timeline_activities("RubyTL", start: Time.now() - 3600, stop: Time.now(), limit: 1000) #=>
# [{ "name"=>"RubyTL", ... }, { "name"=>"RubyTL", ... }]
```

Python の例：

```python
now = datetime.now(timezone.utc)
acts = get_timeline_activities("PythonTL", start=now - timedelta(hours=2), stop=now, limit=1000) #=>
# [{ "name"=>"PythonTL", ... }, { "name"=>"PythonTL", ... }]
```

### delete_timeline_activity

既存のタイムラインアクティビティを削除します。

Ruby / Python 構文：

```ruby
delete_timeline_activity(name, start, uuid)
```

| パラメータ | 説明                                            |
| ---------- | ----------------------------------------------- |
| name       | タイムラインの名前                              |
| start      | アクティビティの開始時間。Time / datetimeインスタンス。 |
| uuid       | アクティビティのUUID                            |

Ruby の例：

```ruby
delete_timeline_activity("RubyTL", 1737132303, "cdb661b4-a65b-44e7-95e2-5e1dba80c782")
```

Python の例：

```python
delete_timeline_activity("PythonTL", 1737133108, "cddbf034-ccdd-4c36-91c2-2653a39b06a5")
```

## メタデータ

メタデータを使用すると、COSMOSに記録された通常のターゲット/パケットデータに独自のフィールドをマークできます。このメタデータは、他のCOSMOSツールを使用する際に検索したり、データをフィルタリングしたりするために使用できます。

### metadata_all

以前に設定されたすべてのメタデータを返します。

Ruby / Python 構文：

```ruby
metadata_all()
```

| パラメータ | 説明                                         |
| ---------- | -------------------------------------------- |
| limit      | 返すメタデータ項目の数。デフォルトは100です。 |

Ruby の例：

```ruby
metadata_all(limit: 500)
```

Python の例：

```python
metadata_all(limit='500')
```

### metadata_get
以前に設定されたメタデータを返します

Ruby / Python 構文：

```ruby
metadata_get(start)
```

| パラメータ | 説明                                                                     |
| ---------- | ------------------------------------------------------------------------ |
| start      | 名前付きパラメータ、エポックからの整数秒としてメタデータを取得する時間  |

Ruby の例：

```ruby
metadata_get(start: 500)
```

Python の例：

```python
metadata_get(start='500')
```

### metadata_set

以前に設定されたメタデータを返します

Ruby / Python 構文：

```ruby
metadata_set(<Metadata>, start, color)
```

| パラメータ | 説明                                                                    |
| ---------- | ----------------------------------------------------------------------- |
| Metadata   | メタデータとして保存するキーと値のペアのハッシュまたは辞書。           |
| start      | 名前付きパラメータ、メタデータを保存する時間。デフォルトは現在です。   |
| color      | 名前付きパラメータ、カレンダーにメタデータを表示する色。デフォルトは #003784 です。 |

Ruby の例：

```ruby
metadata_set({ 'key' => 'value' })
metadata_set({ 'key' => 'value' }, color: '#ff5252')
```

Python の例：

```python
metadata_set({ 'key': 'value' })
metadata_set({ 'key': 'value' }, color='ff5252')
```

### metadata_update

以前に設定されたメタデータを更新します

Ruby / Python 構文：

```ruby
metadata_update(<Metadata>, start, color)
```

| パラメータ | 説明                                                                     |
| ---------- | ------------------------------------------------------------------------ |
| Metadata   | メタデータとして更新するキーと値のペアのハッシュまたは辞書。            |
| start      | 名前付きパラメータ、メタデータを更新する時間。デフォルトは最新のメタデータです。 |
| color      | 名前付きパラメータ、カレンダーにメタデータを表示する色。デフォルトは #003784 です。 |

Ruby の例：

```ruby
metadata_update({ 'key' => 'value' })
```

Python の例：

```python
metadata_update({ 'key': 'value' })
```

### metadata_input

ユーザーに既存のメタデータ値を設定するか、新しい値を作成するように促します。

Ruby / Python の例：

```ruby
metadata_input()
```

## 設定

COSMOSには、通常、Admin Settingsタブを通じてアクセスされるいくつかの設定があります。これらのAPIを使用すると、同じ設定にプログラムでアクセスできます。

### list_settings

現在のCOSMOS設定名をすべて返します。これらは他のAPIで使用する名前です。
Ruby の例：

```ruby
puts list_settings() #=> ["pypi_url", "rubygems_url", "source_url", "version"]
```

Python の例：

```python
print(list_settings()) #=> ['pypi_url', 'rubygems_url', 'source_url', 'version']
```

### get_all_settings

現在のCOSMOS設定とその値をすべて返します。

Ruby の例：

```ruby
settings = get_all_settings() #=>
# { "version"=>{"name"=>"version", "data"=>"5.11.4-beta0", "updated_at"=>1698074299509456507},
#   "pypi_url"=>{"name"=>"pypi_url", "data"=>"https://pypi.org/simple", "updated_at"=>1698026776574347007},
#   "rubygems_url"=>{"name"=>"rubygems_url", "data"=>"https://rubygems.org", "updated_at"=>1698026776574105465},
#   "source_url"=>{"name"=>"source_url", "data"=>"https://github.com/OpenC3/cosmos", "updated_at"=>1698026776573904132} }
```

Python の例：

```python
settings = get_all_settings() #=>
# { 'version': {'name': 'version', 'data': '5.11.4-beta0', 'updated_at': 1698074299509456507},
#   'pypi_url': {'name': 'pypi_url', 'data': 'https://pypi.org/simple', 'updated_at': 1698026776574347007},
#   'rubygems_url': {'name': 'rubygems_url', 'data': 'https://rubygems.org', 'updated_at': 1698026776574105465},
#   'source_url': {'name': 'source_url', 'data': 'https://github.com/OpenC3/cosmos', 'updated_at': 1698026776573904132} }
```

### get_setting, get_settings

指定されたCOSMOS設定からデータを返します。設定が存在しない場合は、nil（Ruby）またはNone（Python）を返します。

Ruby / Python 構文：

```ruby
get_setting(<Setting Name>)
get_settings(<Setting Name1>, <Setting Name2>, ...)
```

| パラメータ    | 説明                      |
| ------------- | ------------------------- |
| Setting Name  | 返す設定の名前            |

Ruby の例：

```ruby
setting = get_setting('version') #=> "5.11.4-beta0"
setting = get_settings('version', 'rubygems_url') #=> ["5.11.4-beta0", "https://rubygems.org"]
```

Python の例：

```python
setting = get_setting('version') #=> '5.11.4-beta0'
setting = get_setting('version', 'rubygems_url') #=> ['5.11.4-beta0', 'https://rubygems.org']
```

### set_setting

指定された設定値を設定します。

:::note 管理者パスワードが必要
このAPIは外部からのみアクセス可能（Script Runner内ではない）で、管理者パスワードが必要です。
:::

Ruby / Python 構文：

```ruby
set_setting(<Setting Name>, <Setting Value>)
```

| パラメータ     | 説明                      |
| -------------- | ------------------------- |
| Setting Name   | 変更する設定の名前        |
| Setting Value  | 設定する値                |

Ruby の例：

```ruby
set_setting('rubygems_url', 'https://mygemserver')
```

Python の例：

```python
set_setting('pypi_url', 'https://mypypiserver')
```

## 構成

多くのCOSMOSツールには、構成をロードして保存する機能があります。これらのAPIを使用すると、構成をプログラムでロードして保存できます。
### config_tool_names

他のAPIの最初のパラメータとして使用されるすべての構成ツール名をリストします。

Ruby の例：

```ruby
names = config_tool_names() #=> ["telemetry_grapher", "data_viewer"]
```

Python の例：

```python
names = config_tool_names() #=> ['telemetry_grapher', 'data_viewer']
```

### list_configs

指定されたツール名の下に保存されているすべての構成名をリストします。

Ruby / Python 構文：

```ruby
list_configs(<Tool Name>)
```

| パラメータ | 説明                                |
| ---------- | ----------------------------------- |
| Tool Name  | 構成名を取得するツールの名前        |

Ruby の例：

```ruby
configs = list_configs('telemetry_grapher') #=> ['adcs', 'temps']
```

Python の例：

```python
configs = list_configs('telemetry_grapher') #=> ['adcs', 'temps']
```

### load_config

特定のツール構成をロードします。

:::note ツール構成
ツール構成は完全に文書化されておらず、リリース間で変更される可能性があります。load_configによって返される値のみを変更し、キーは変更しないでください。
:::

Ruby / Python 構文：

```ruby
load_config(<Tool Name>, <Configuration Name>)
```

| パラメータ          | 説明               |
| ------------------- | ------------------ |
| Tool Name           | ツールの名前       |
| Configuration Name  | 構成の名前         |

Ruby / Python の例：

```ruby
config = load_config('telemetry_grapher', 'adcs') #=>
# [ {
#   "items": [
#     {
#       "targetName": "INST",
#       "packetName": "ADCS",
#       "itemName": "CCSDSVER",
# ...
```

### save_config

特定のツール構成を保存します。

Ruby / Python 構文：

```ruby
save_config(<Tool Name>, <Configuration Name>, local_mode)
```

| パラメータ          | 説明                                       |
| ------------------- | ------------------------------------------ |
| Tool Name           | ツールの名前                               |
| Configuration Name  | 構成の名前                                 |
| local_mode          | 構成をローカルモードで保存するかどうか     |

Ruby / Python の例：

```ruby
save_config('telemetry_grapher', 'adcs', config)
```

### delete_config

特定のツール構成を削除します。
Ruby / Python 構文：

```ruby
delete_config(<Tool Name>, <Configuration Name>, local_mode)
```

| パラメータ          | 説明                                         |
| ------------------- | -------------------------------------------- |
| Tool Name           | ツールの名前                                 |
| Configuration Name  | 構成の名前                                   |
| local_mode          | 構成をローカルモードで削除するかどうか       |

Ruby / Python の例：

```ruby
delete_config('telemetry_grapher', 'adcs')
```

## オフラインアクセス

COSMOS Enterpriseでスクリプトを実行するには、オフラインアクセストークンが必要です。これらのメソッドは、offline_access_tokenのクライアント側での作成、テスト、および設定をサポートします。

### initialize_offline_access

ユーザー用のオフラインアクセストークンを作成して設定します。注意：このメソッドは、script_run（Enterprise限定）のようなオフラインアクセストークンを必要とするAPIメソッドを実行する前に呼び出す必要があります。このメソッドは、最初にスクリプトを開始するために必要なため、ScriptRunnerの外部で呼び出す必要があります。

Ruby の例：

```ruby
# 最初に環境変数を設定します。examples/external_script.rbを参照してください
initialize_offline_access()
script_run("INST/procedures/collect.rb")
```

Python の例：

```python
# 最初に環境変数を設定します。examples/external_script.pyを参照してください
initialize_offline_access()
script_run("INST2/procedures/collect.py")
```

### offline_access_needed

ユーザーがオフラインアクセストークンを生成する必要がある場合はtrueを返します。注意：これは、ユーザーがスクリプトを表示する権限を少なくとも持っている場合にのみtrueになります。それ以外の場合、ユーザーがscript_view権限を持っていなければ、常にfalseになります。

Ruby の例：

```ruby
result = offline_access_needed() #=> true
```

Python の例：

```python
result = offline_access_needed() #=> False
```

### set_offline_access

バックエンドでオフラインアクセストークンを設定します。注意：initialize_offline_access()によって呼び出されるため、このメソッドを直接呼び出す必要はおそらくありません。

Ruby / Python 構文：

```ruby
set_offline_access(offline_access_token)
```

| パラメータ            | 説明                                                                      |
| --------------------- | ------------------------------------------------------------------------- |
| offline_access_token  | offline_access openidスコープを含むKeycloakによって生成されたリフレッシュトークン |

Ruby / Python の例：

```ruby
set_offline_access(offline_access_token)
```
