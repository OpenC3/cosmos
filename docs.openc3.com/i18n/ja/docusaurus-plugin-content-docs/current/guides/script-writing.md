---
title: スクリプト作成ガイド
description: スクリプト作成のための主要概念とベストプラクティス
sidebar_custom_props:
  myEmoji: 🏃‍➡️
---

## はじめに

このガイドは、COSMOSが提供するスクリプト機能を使用するためのベストプラクティスを提供することを目的としています。スクリプトは、運用やテストのための一連の活動を自動化するために使用されます。このドキュメントの目的は、シンプルで理解しやすく、保守可能で正確なスクリプトを作成することです。COSMOSスクリプトランナーの使用に関する主要な詳細についてもガイダンスを提供します。

## 概念

COSMOSはスクリプト作成にRubyとPythonの両方をサポートしています。RubyとPythonは非常に似たスクリプト言語であり、このガイドのほとんどは両方に直接適用されます。例を使用する場合は、RubyとPythonの両方の例が示されています。

### COSMOSでのRuby対Python

COSMOSスクリプトを書く際のRubyとPythonの間には多くの類似点といくつかの主要な違いがあります。

1. 行の長さに80文字の制限はありません。行の長さは好きなだけ長くできますが、スクリプトの印刷レビューが難しくなるため、あまり長くしないように注意してください。
1. インデントの空白：
   1. Ruby: 重要ではありません。Rubyは`end`キーワードを使用して、2スペースを標準としたインデントされたコードブロックを決定します。
   1. Python: 重要です。Pythonはインデントを使用して、4スペースを標準としたコードブロックを決定します。
1. 変数は事前に宣言する必要がなく、後で再割り当てできます。つまり、RubyとPythonは動的型付けです。
1. 変数の補間：
   1. Ruby: 変数値は`"#{variable}"`構文を使用して文字列に配置できます。
   1. Python: 変数値は`f"{variable}"`構文を使用してf-stringに配置できます。
1. ブロックやループ内で宣言された変数は、すでに宣言されていない限り、そのブロックの外側には存在しません。

両言語はスクリプト作成者に多くの力を提供します。しかし、大きな力には大きな責任が伴います。スクリプトを書くときは、あなた自身や他の誰かが後でそれを理解する必要があることを忘れないでください。したがって、次のスタイルガイドラインを使用してください：

- インデントには一貫したスペースを使用し、タブを使用しないでください
- 定数はすべて大文字でアンダースコア付き
  - `SPEED_OF_LIGHT = 299792458 # meters per s`
- 変数名とメソッド名は小文字でアンダースコア付き
  - `last_name = "Smith"`
  - `perform_setup_operation()`
- クラス名（使用する場合）はキャメルケースで、それらを含むファイルは小文字とアンダースコアで一致する必要があります
  - `class DataUploader # in 'data_uploader.rb'`
  - `class CcsdsUtility: # in 'ccsds_utility.py'`
- 無意味なコメントを追加せず、代わりに意図を説明してください

<div style={{"clear": 'both'}}></div>

以下は良いRubyスタイルの例です：

```ruby
load 'TARGET/lib/upload_utility.rb' # 実行を表示したくないライブラリ
load_utility 'TARGET/lib/helper_utility.rb' # 実行を表示したいライブラリ

# 定数を宣言
OUR_TARGETS = ['INST','INST2']

# 渡されたターゲット名の収集カウンターをクリア
def clear_collects(target)
  cmd("#{target} CLEAR")
  wait_check("#{target} HEALTH_STATUS COLLECTS == 0", 5)
end

######################################
# 開始
######################################
helper = HelperUtility.new
helper.setup

# すべてのターゲットで収集を実行
OUR_TARGETS.each do |target|
  collects = tlm("#{target} HEALTH_STATUS COLLECTS")
  cmd("#{target} COLLECT with TYPE SPECIAL")
  wait_check("#{target} HEALTH_STATUS COLLECTS == #{collects + 1}", 5)
end

clear_collects('INST')
clear_collects('INST2')
```

以下は良いPythonスタイルの例です：

```python
from openc3.script import *

import TARGET.lib.upload_utility # 実行を表示したくないライブラリ
load_utility('TARGET/lib/helper_utility.rb') # 実行を表示したいライブラリ

# 定数を宣言
OUR_TARGETS = ['INST','INST2']

# 渡されたターゲット名の収集カウンターをクリア
def clear_collects(target):
    cmd(f"{target} CLEAR")
    wait_check(f"{target} HEALTH_STATUS COLLECTS == 0", 5)

######################################
# 開始
######################################
helper = HelperUtility()
helper.setup()

# すべてのターゲットで収集を実行
for target in OUR_TARGETS:
    collects = tlm(f"{target} HEALTH_STATUS COLLECTS")
    cmd(f"{target} COLLECT with TYPE SPECIAL")
    wait_check(f"{target} HEALTH_STATUS COLLECTS == {collects + 1}", 5)

clear_collects('INST')
clear_collects('INST2')
```

両方の例はCOSMOSスクリプティングのいくつかの機能を示しています。'load'または'import'と'load_utility'の違いに注目してください。最初のものは実行時にScript Runnerで表示されない追加スクリプトを読み込むためのものです。これは画像分析や長時間実行するループコードなど、出力だけが欲しい場合に良い場所です。'load_utility'は何が起こっているかをユーザーに示すために、コードを1行ずつ視覚的に実行します。

次に定数を宣言し、OUR_TARGETSに文字列の配列を格納します。定数はすべて大文字でアンダースコア付きであることに注意してください。

次にclear_collectsという1つのローカルメソッドを宣言します。各メソッドの先頭には、それが何をするのか、およびそれが受け取るパラメータを説明するコメントを提供してください。

次に'helper_utility'が作成されます。クラス名と読み込んだファイル名の類似性に注意してください。

collect例では、以前に作成した文字列配列を反復処理し、コマンドやテレメトリをチェックする際に変数を使用する方法を示しています。Rubyのポンド括弧#\{\}記法とPythonのf文字列f"{}"記法は、変数が保持しているものを文字列に入れます。括弧内で追加のコードを実行することもできます。例えば、収集回数の増加をチェックするときのようにです。

最後に、ターゲット名を渡して各ターゲットに対して'clear_collects'メソッドを呼び出します。

## スクリプティングの哲学

### 基本的なスクリプト例

ほとんどのCOSMOSスクリプトは、システム/サブシステムにコマンドを送信し、そのコマンドが期待通りに機能したことを確認するという単純なパターンに分解できます。このパターンは通常、以下のようにcmd()の後にwait_check()を使用して実装されます：

```ruby
cmd("INST COLLECT with TYPE NORMAL, TEMP 10.0")
wait_check("INST HEALTH_STATUS TYPE == 'NORMAL'", 5)
```

または同様に、コマンドの前にサンプリングされるカウンターを使用します。

Ruby:

```ruby
count = tlm("INST HEALTH_STATUS COLLECTS")
cmd("INST COLLECT with TYPE NORMAL, TEMP 10.0")
wait_check("INST HEALTH_STATUS COLLECTS >= #{count + 1}", 5)
```

Python:

```python
count = tlm("INST HEALTH_STATUS COLLECTS")
cmd("INST COLLECT with TYPE NORMAL, TEMP 10.0")
wait_check(f"INST HEALTH_STATUS COLLECTS >= {count + 1}", 5)
```

作成するCOSMOSスクリプトの90%は、コマンドが期待通りに機能したことを確認するために各コマンドの後に複数の項目をチェックする必要がある場合を除いて、上記のような単純なパターンであるべきです。

### KISS（Keep It Simple Stupid）

RubyとPythonは非常に強力な言語であり、同じことを達成するための多くの方法があります。それを考慮すると、常に自分や他の人にとって最も理解しやすい方法を選択してください。複雑な1行コードや難解な正規表現を作成することも可能ですが、複雑な1行コードを展開し、正規表現を分解して文書化することで、後で自分自身に感謝することになるでしょう。

### DRY（Don't Repeat Yourself）

任意のコマンドと制御システム用に書かれたスクリプトでの広範な問題は、同じコードブロックが複数回繰り返されることです。極端な場合、これは保守やレビューが不可能な10万行以上のスクリプトにつながることがあります。

繰り返しが現れる一般的な方法は2つあります：サブシステムの電源を入れるなどの一般的なアクションを実行するための正確なコードブロック、およびチェックされる助記語の名前またはチェックされる値のみが異なるコードブロックです。どちらもメソッド（または関数）を使用して繰り返しを削除することで解決されます。

例えば、サブシステムの電源を入れて正しいテレメトリを確保するスクリプトは次のようになります：

Ruby:

```ruby
def power_on_subsystem
  # 100行のcmd()、wait_check()など
end
```

Python:

```python
def power_on_subsystem():
    # 100行のcmd()、wait_check()など
```

理想的には、上記のメソッドは他のスクリプトでも使用できるように別のファイルに保存されるべきです。それが真に1つのスクリプトでしか役に立たない場合は、ファイルの先頭に置くことができます。更新されたスクリプトは次のようになります：

```ruby
power_on_subsystem()
# 150行のサブシステム操作（例）
# cmd(...)
# wait_check(...)
#...
power_off_subystem()
# 関連のないアクティビティ
power_on_subsystem()
# など
```

唯一の変更が助記語またはチェックされる値であるコードブロックは、引数を持つメソッドで置き換えることができます。

Ruby:

```ruby
def test_minimum_temp(enable_cmd_name, enable_tlm, temp_tlm, expected_temp)
  cmd("TARGET #{enable_cmd_name} with ENABLE TRUE")
  wait_check("TARGET #{enable_tlm} == 'TRUE'", 5)
  wait_check("TARGET #{temp_tlm} >= #{expected_temp}", 50)
end
```

Python:

```python
def test_minimum_temp(enable_cmd_name, enable_tlm, temp_tlm, expected_temp):
    cmd(f"TARGET {enable_cmd_name} with ENABLE TRUE")
    wait_check(f"TARGET {enable_tlm} == 'TRUE'", 5)
    wait_check(f"TARGET {temp_tlm} >= {expected_temp}", 50)
```

### コメントを適切に使用する

あなたが行っていることが不明確な場合や、一連の行に高レベルの目的がある場合は、コメントを使用してください。コメント内に数字やその他の詳細を入れないようにしてください。それらは基礎となるコードと同期が取れなくなる可能性があります。RubyとPythonのコメントは#ポンド記号で始まり、行のどこにでも配置できます。

```ruby
# このラインはアボートコマンドを送信します - 悪いコメント、不要
cmd("INST ABORT")
# キャリブレーションターゲットを見るためにジンバルを回転させる - 良いコメント
cmd("INST ROTATE with ANGLE 180.0") # 180度回転 - 悪いコメント
```

### スクリプトランナー

COSMOSはスクリプト（プロシージャとも呼ばれる）を実行するための2つのユニークな方法を提供します。スクリプトランナーはスクリプト実行環境とスクリプトエディタの両方を提供します。スクリプトエディタには、COSMOSメソッドとコマンド/テレメトリ項目名の両方のコード補完が含まれています。これはスクリプトを開発してテストするための優れた環境でもあります。スクリプトランナーは、長いスタイルのプロシージャを持つ従来のスクリプティングモデルに慣れているユーザーと、その場でスクリプトを編集できるようにしたいユーザーのためのフレームワークを提供します。

スイートファイル（'suite'という名前）を開くと、スクリプトランナーはより正式ですが、より強力なスクリプト実行環境を提供します。スイートファイルはスクリプトをスイート、グループ、およびスクリプト（個々のメソッド）に分割します。スイートは最高レベルの概念であり、通常、熱真空試験などの大規模な手順や、軌道上チェックアウトの実行などの大規模な運用シナリオをカバーします。グループは、特定のメカニズムに関するすべてのスクリプトなど、関連するスクリプトのセットをキャプチャします。グループはサブシステムに関連するスクリプトのコレクションや、RF検査などの特定の一連のテストである場合があります。スクリプトは合格または不合格のいずれかになる個々のアクティビティをキャプチャします。スクリプトランナーでは、スイート全体、1つ以上のグループ、または1つ以上のスクリプトを簡単に実行できます。また、タイミング、合格/不合格のカウントなどを含むレポートを自動的に生成します。

仕事に適した環境は個々のユーザー次第であり、多くのプログラムは両方のスクリプト形式を使用して目標を達成します。

### ループ vs アンロールされたループ

ループは、同じコードを何度も書き直す必要なく、同じ操作を複数回実行できる強力な構造です（DRYの概念を参照）。ただし、失敗した時点でCOSMOSスクリプトを再開するのが難しいか不可能になる場合があります。何かが失敗する可能性が低い場合、ループは優れた選択肢です。スクリプトがテレメトリポイントのリストでループを実行している場合、ループ本体をメソッドにしてから、発生するはずだったループの各繰り返しに対してそのメソッドを直接呼び出すことでループを「アンロール」する方が良い選択かもしれません。

Ruby:

```ruby
10.times do |temperature_number|
  check_temperature(temperature_number + 1)
end
```

Python:

```python
for temperature_number in range(1, 11):
    check_temperature(temperature_number)
```

上記のスクリプトが温度番号3の後に停止した場合、温度番号4でループを再開する方法はありません。ループカウントが少ない場合の良い解決策は、ループをアンロールすることです。

```ruby
check_temperature(1)
check_temperature(2)
check_temperature(3)
check_temperature(4)
check_temperature(5)
check_temperature(6)
check_temperature(7)
check_temperature(8)
check_temperature(9)
check_temperature(10)
```

上記のアンロールされたバージョンでは、COSMOSの「選択した行からスクリプトを開始」機能を使用して、任意の点でスクリプトを再開できます。

## スクリプトの構成

すべてのスクリプトは[プラグイン](../configuration/plugins.md)の一部である必要があります。SCRIPTSやPROCEDURESなどの単純なプラグインを作成して、スクリプトを保存するためのlibとproceduresディレクトリのみを含めることができます。COSMOSが定義されたcmd/tlmを持たないプラグインを検出すると、テレメトリ処理用のマイクロサービスを起動しません。

### スクリプトをプラグインに整理する

スクリプトが多くのメソッドを持つ大きなものになるにつれて、それらをプラグイン内の複数のファイルに分割することが理にかなっています。以下はプラグインのスクリプト/プロシージャの推奨される構成です。

| フォルダ                        | 説明                                                                |
| ------------------------------ | ------------------------------------------------------------------ |
| targets/TARGET_NAME/lib        | 再利用可能なターゲット固有のメソッドを含むスクリプトファイルをここに配置 |
| targets/TARGET_NAME/procedures | 1つの特定のターゲットを中心とした単純なプロシージャをここに配置        |

メインプロシージャでは、通常、load_utilityを使用してインストルメンテーションで他のファイルを取り込みます。

```ruby
# Ruby:
load_utility('TARGET/lib/my_other_script.rb')
# Python:
load_utility('TARGET/procedures/my_other_script.py')
```

### スクリプトをメソッドに整理する

各アクティビティを異なるメソッドに入れてください。スクリプトをメソッドに入れると、整理が簡単になり、全体的なスクリプトが何をするかについての優れた高レベルの概要が得られます（メソッドに適切な名前を付ける場合）。曖昧で短いメソッド名にはボーナスポイントはありません。メソッド名は長く明確にしてください。

Ruby:

```ruby
def test_1_heater_zone_control
  puts "Verifies requirements 304, 306, and 310"
  # テストコードをここに
end

def script_1_heater_zone_control
  puts "Verifies requirements 304, 306, and 310"
  # テストコードをここに
end
```

Python:

```python
def test_1_heater_zone_control():
    print("Verifies requirements 304, 306, and 310")
    # テストコードをここに

def script_1_heater_zone_control():
    print("Verifies requirements 304, 306, and 310")
    # テストコードをここに
```

### クラス vs 非スコープメソッドの使用

オブジェクト指向プログラミングのクラスを使用すると、関連するメソッドのセットと関連する状態を整理できます。最も重要な側面は、メソッドが何らかの共有状態で動作することです。例えば、ジンバルを動かすコードがあり、メソッド間で移動または手順の数を追跡する必要がある場合、これはクラスを使用するのに最適な場所です。スクリプト内で複数回発生する処理をコピー＆ペーストせずに実行するためのヘルパーメソッドが必要な場合は、おそらくクラスに入れる必要はありません。

注：COSMOSの規則では、TARGET名に基づいて名付けられたTARGET/lib/target.[rb/py]ファイルがあり、Targetと呼ばれるクラスが含まれています。この議論はTARGET/proceduresディレクトリのスクリプトを指しています。

Ruby:

```ruby
class Gimbal
  attr_accessor :gimbal_steps
  def initialize()
    @gimbal_steps = 0
  end
  def move(steps_to_move)
    # ジンバルを動かす
    @gimbal_steps += steps_to_move
  end
  def home_gimbal
    # ジンバルをホームポジションに
    @gimbal_steps = 0
  end
end

def perform_common_math(x, y)
  x + y
end

gimbal = Gimbal.new
gimbal.home_gimbal
gimbal.move(100)
gimbal.move(200)
puts "Moved gimbal #{gimbal.gimbal_steps}"
result = perform_common_math(gimbal.gimbal_steps, 10)
puts "Math:#{result}"
```

Python:

```python
class Gimbal:
    def __init__(self):
        self.gimbal_steps = 0

    def move(self, steps_to_move):
        # ジンバルを動かす
        self.gimbal_steps += steps_to_move

    def home_gimbal(self):
        # ジンバルをホームポジションに
        self.gimbal_steps = 0

def perform_common_math(x, y):
    return x + y

gimbal = Gimbal()
gimbal.home_gimbal()
gimbal.move(100)
gimbal.move(200)
print(f"Moved gimbal {gimbal.gimbal_steps}")
result = perform_common_math(gimbal.gimbal_steps, 10)
print(f"Math:{result}")
```

### インストルメント化された行と非インストルメント化された行（requireとload）

COSMOSスクリプトは通常「インストルメント化」されています。これは、各行に主に現在実行中の行をハイライトし、wait_checkのような何かが失敗した場合に例外をキャッチするコードが裏側で追加されていることを意味します。スクリプトで他のファイルのコードを使用する必要がある場合、そのコードを取り込むためにいくつかの方法があります。一部の手法はインストルメント化されたコードを取り込み、他の手法は非インストルメント化されたコードを取り込みます。両方を使用する理由があります。

load_utility（および非推奨のrequire_utility）は、他のファイルからインストルメント化されたコードを取り込みます。COSMOSが他のファイルのコードを実行するとき、Script Runnerは他のファイルに移動し、実行時に各行をハイライト表示します。これは他のファイルを取り込むためのデフォルトの方法であるべきです。何かが失敗した場合に継続することができ、オペレーターによりよい可視性を提供するためです。

しかし、時には他のファイルからのコード実行を表示したくない場合もあります。外部で開発されたライブラリは一般的にインストルメント化されることを好まず、大きなループを含むコードや行のハイライト表示時に時間がかかるコードは、インストルメント化されていないメソッドに含めるとはるかに高速になります。Rubyは非インストルメント化されたコードを取り込むための2つの方法を提供しています。1つ目は「load」キーワードです。loadは別のファイルからコードを取り込み、ファイルが更新された場合は次のload呼び出し時にその変更を取り込みます。「require」はloadに似ていますが、別のファイルからコードを一度だけ取り込むように最適化されています。したがって、requireを使用してからrequireするファイルを変更する場合、ファイルを再度requireして変更を取り込むためにはScript Runnerを再起動する必要があります。一般的に、COSMOSスクリプティングではrequireよりもloadが推奨されます。loadの1つの注意点は、拡張子を含む完全なファイル名が必要なのに対し、requireキーワードはそれを必要としないことです。

Pythonでは、ライブラリはimport構文を使用して含まれます。importを使用してインポートされたコードはインストルメント化されません。load_utilityを使用してインポートされたコードのみがインストルメント化されます。

最後に、COSMOSスクリプティングには、インストルメント化されたスクリプトの途中でインストルメント化を無効にするための特別な構文があり、それはdisable_instrumentationメソッドです。これにより、インストルメント化された状態で実行すると遅すぎる大きなループやその他のアクティビティのインストルメント化を無効にすることができます。

Ruby:

```ruby
temp = 0
disable_instrumentation do
  # ここでは例外を投げる可能性のあるものが何もないことを確認してください！
  5000000.times do
    temp += 1
  end
end
puts temp
```

Python:

```python
temp = 0
with disable_instrumentation():
    # ここでは例外を投げる可能性のあるものが何もないことを確認してください！
    for x in range(0,5000000):
        temp += 1
print(temp)
```

:::warning 非インストルメント化されたコードを実行する際
コードが例外を発生させたり、チェックが失敗したりしないことを確認してください。非インストルメント化されたコードから例外が発生した場合、スクリプト全体が停止します。
:::

## デバッグと監査

### 組み込みデバッグ機能

Script Runnerには、スクリプトが特定の動作をしている理由を判断するのに役立つ組み込みのデバッグ機能があります。特に重要なのは、スクリプト変数を検査して設定する能力です。

デバッグ機能を使用するには、まずスクリプトメニューから「Toggle Debug」オプションを選択します。これにより、ツールの下部に小さなDebug:プロンプトが追加されます。このプロンプトに入力されたコードは、Enterが押されると実行されます。実行中のスクリプトの変数を検査するには、スクリプトを一時停止してから、変数名を入力して変数の値をデバッグプロンプトに表示します。

```ruby
variable_name
```

変数は単に等号を使用して設定することもできます。

```ruby
variable_name = 5
```

必要に応じて、デバッグプロンプトから通常のコマンディングメソッドを使用してコマンドを挿入することもできます。これらのコマンドはScript Runnerメッセージログに記録されます。これは、CmdSender（コマンドはCmdTlmServerメッセージログにのみ記録される）のような別のCOSMOSツールを使用するよりも有利かもしれません。

```ruby
cmd("INST COLLECT with TYPE NORMAL")
```

デバッグプロンプトはコマンド履歴を保持し、上下の矢印を使用して履歴をスクロールできることに注意してください。

### ブレークポイント

Script Runnerで行番号（左側のガター）をクリックしてブレークポイントを追加できます。スクリプトはブレークポイントに到達すると自動的に一時停止します。ブレークポイントで停止したら、Debug行を使用して変数を評価できます。

### 切断モードの使用

切断モードは、実際のハードウェアがループに入っていない環境でスクリプトをテストできるScript Runnerの機能です。切断モードはスクリプト -> Toggle Disconnectを選択して開始します。選択すると、ユーザーは切断するターゲットを選択するよう求められます。デフォルトでは、すべてのターゲットが切断され、実際のハードウェアなしでスクリプトをテストできます。オプションで、ターゲットのサブセットのみを選択することができ、これは部分的に統合された環境でスクリプトを試すのに役立ちます。

切断モードでは、切断されたターゲットへのコマンドは常に成功します。さらに、切断されたターゲットのテレメトリのすべてのチェックはすぐに成功します。これにより、ハードウェアの動作や適切な機能を心配することなく、論理エラーやその他のスクリプト固有のエラーについてプロシージャを素早く実行できます。

### スクリプトの監査

Script Runnerには、実行前後にスクリプトを監査するためのいくつかのツールが含まれています。

#### Ruby構文チェック

Ruby構文チェックツールはスクリプトメニューにあります。このツールは-cフラグを付けたruby実行可能ファイルを使用して、スクリプトの構文チェックを実行します。構文エラーが見つかった場合、Rubyインタープリタが提示する正確なメッセージがユーザーに表示されます。これらは暗号のように見えることがありますが、最も一般的な問題は、引用符で囲まれた文字列を閉じていない、「end」キーワードを忘れている、またはブロックを使用しているが前の「do」キーワードを忘れているなどです。

## 一般的なシナリオ

### ユーザー入力のベストプラクティス

COSMOSはスクリプトで手動ユーザー入力を収集するためのいくつかの異なるメソッドを提供しています。任意の値を許可するユーザー入力メソッド（ask()やask_string()など）を使用する場合は、先に進む前にスクリプトで与えられた値を検証することが非常に重要です。テキスト入力を求める場合は、大文字小文字の可能性に対処し、無効な入力でユーザーに再度プロンプトを表示するか安全なパスを取ることを確実にすることが特に重要です。

Ruby:

```ruby
answer = ask_string("続行しますか (y/n)?")
if answer != 'y' and answer != 'Y'
  raise "ユーザーが入力: #{answer}"
end

temp = 0.0
while temp < 10.0 or temp > 50.0
  temp = ask("10.0から50.0の間の希望温度を入力してください")
end
```

Python:

```python
answer = ask_string("続行しますか (y/n)?")
if answer != 'y' and answer != 'Y':
    raise RuntimeError(f"ユーザーが入力: {answer}")

temp = 0.0
while temp < 10.0 or temp > 50.0:
    temp = ask("10.0から50.0の間の希望温度を入力してください")
```

可能な場合は、常にユーザーに制約された選択肢のリストを持つ他のユーザー入力メソッド（message_box、vertical_message_box、combo_box）を使用してください。

これらのすべてのユーザー入力メソッドは、ユーザーに「キャンセル (Cancel)」オプションを提供することに注意してください。キャンセルがクリックされると、スクリプトは一時停止しますが、ユーザー入力行に留まります。「Go」を押して続行すると、ユーザーは値を入力するよう再度求められます。

### 条件付きで手動ユーザー入力ステップを要求する

可能な場合、ユーザー入力を求めることなく実行できるようにスクリプトを書くことは有用な設計パターンです。これにより、スクリプトがより簡単にテストでき、ユーザー入力の選択や値に対して文書化されたデフォルト値が提供されます。このパターンを実装するには、ask()、prompt()、無限wait()ステートメントなどのすべての手動ステップを、RubyではRuby $manual、Pythonでは RunningScript.manual の値をチェックするif文でラップする必要があります。変数が設定されている場合は手動ステップを実行し、そうでない場合はデフォルト値を使用します。

Ruby例:

```ruby
if $manual
  temp = ask("温度を入力してください")
else
  temp = 20.0
end
if !$manual
  puts "自動モードでは無限待機をスキップします"
else
  wait
end
```

Python例:

```python
if RunningScript.manual:
    temp = ask("温度を入力してください")
else:
    temp = 20.0
if not RunningScript.manual:
    print("自動モードでは無限待機をスキップします")
else:
    wait()
```

スイートを実行する場合、ツールの上部に「手動 (Manual)」というチェックボックスがあり、この$manual変数に直接影響します。

### レポートに追加情報を出力する

COSMOSスクリプトランナーは、スクリプトスイートで動作する際に、各スクリプトのPASS/FAILED/SKIPPEDの状態を示すレポートを自動的に生成します。以下の例のように、このレポートに任意のテキストを挿入することもできます。あるいは、シンプルにprintを使用してScript Runnerメッセージログにテキストを出力することもできます。

Ruby:

```ruby
class MyGroup < OpenC3::Group
  def script_1
    # 以下のテキストはレポートに配置されます
    OpenC3::Group.puts "要件304、306、310を検証します"
    # このputs行はsr_messagesログファイルに表示されます
    puts "script_1完了"
  end
end
```

Python:

```python
from openc3.script.suite import Group
class MyGroup(Group):
    def script_1():
        # 以下のテキストはレポートに配置されます
        Group.print("要件304、306、310を検証します")
        # このputs行はsr_messagesログファイルに表示されます
        print("script_1完了")
```

### 複数のパケットからテレメトリポイントの最新値を取得する

一部のシステムには、すべてのパケットに同じ名前の高レートデータポイントが含まれています。COSMOSは、LATESTという特別なパケット名を使用して、複数のパケットに含まれるテレメトリポイントの最新値を取得することをサポートしています。ターゲットINSTにPACKET1とPACKET2の2つのパケットがあるとします。両方のパケットにはTEMPというテレメトリポイントがあります。

```ruby
# 最も最近受信したPACKET1からTEMPの値を取得
value = tlm("INST PACKET1 TEMP")
# 最も最近受信したPACKET2からTEMPの値を取得
value = tlm("INST PACKET2 TEMP")
# 最も最近受信したPACKET1またはPACKET2からTEMPの値を取得
value = tlm("INST LATEST TEMP")
```

### テレメトリポイントのすべてのサンプルをチェックする

COSMOSスクリプトを書く際、テレメトリポイントの最新の値をチェックすることで通常は仕事が完了します。tlm()、tlm_raw()などのメソッドはすべて、テレメトリポイントの最新の値を取得します。テレメトリポイントのすべてのサンプルに対して分析を実行する必要がある場合もあります。これはCOSMOSパケットサブスクリプションシステムを使用して行うことができます。パケットサブスクリプションシステムでは、1つまたは複数のパケットを選択し、それらをすべてキューから受信することができます。その後、各パケットから関心のある特定のテレメトリポイントを選び出すことができます。

Ruby:

```ruby
id = subscribe_packets([['INST', 'HEALTH_STATUS'], ['INST', 'ADCS']])
wait 1.5
id, packets = get_packets(id)
packets.each do |packet|
  puts "#{packet['PACKET_TIMESECONDS']}: #{packet['target_name']} #{packet['packet_name']}"
end
# しばらく待ってから、最後に返されたIDを再利用
id, packets = get_packets(id)
```

Python:

```python
id = subscribe_packets([['INST', 'HEALTH_STATUS'], ['INST', 'ADCS']])
wait(1.5)
id, packets = get_packets(id)
for packet in packets:
    print(f"{packet['PACKET_TIMESECONDS']}: {packet['target_name']} {packet['packet_name']}")
# しばらく待ってから、最後に返されたIDを再利用
id, packets = get_packets(id)
```

### ニーモニックで変数を使用する

コマンドとテレメトリのニーモニックはCOSMOSスクリプトの単なる文字列なので、一部のコンテキストでは変数を利用して再利用可能なコードを作成できます。例えば、メソッドはターゲット名を入力として受け取り、ターゲットの複数のインスタンスをサポートできます。番号付きテレメトリポイントのセットの値を渡すこともできます。

Ruby:

```ruby
def example(target_name, temp_number)
  cmd("#{target_name} COLLECT with TYPE NORMAL")
  wait_check("#{target_name} TEMP#{temp_number} > 50.0")
end
```

Python:

```python
def example(target_name, temp_number):
    cmd(f"{target_name} COLLECT with TYPE NORMAL")
    wait_check(f"{target_name} TEMP{temp_number} > 50.0")
```

これは、番号付けされたテレメトリポイントのセットをループ処理する場合にも役立ちますが、[ループ vs アンロールされたループ](#ループ-vs-アンロールされたループ)セクションで説明したループのデメリットに注意してください。

### カスタムwait_check_expressionの使用

COSMOSのwait_check_expression（およびcheck_expression）を使用すると、より複雑なチェックを実行し、それでも何かがうまくいかなかった場合にCHECKエラーメッセージでスクリプトを停止させることができます。例えば、変数同士をチェックしたり、テレメトリポイントを範囲に対してチェックしたりできます。wait_check_expressionに渡される正確なテキスト文字列は、パスするか、タイムアウトが発生するまで繰り返し評価されます。実際の式内で文字列補間を使用しないことが重要です。そうしないと、文字列補間構文内の値は文字列に変換されるときに1回だけ評価されます。

Ruby:

```ruby
one = 1
two = 2

wait_check_expression("one == two", 1)
# エラー: CHECK: one == two は 1.017035 秒待機後にFALSEです

# 整数範囲のチェック
wait_check_expression("one > 0 and one < 10 # 初期値 one = #{one}", 1)
```

Python:

```python
one = 1
two = 2

wait_check_expression("one == two", 1, 0.25, locals())
# エラー: CHECK: one == two は 1.017035 秒待機後にFALSEです

# 整数範囲のチェック
wait_check_expression("one > 0 and one < 10", 1, 0.25, locals())
```

### 通常のRubyスクリプティングとCOSMOSスクリプティングの違い

#### 単一行のif文を使用しないでください

COSMOSスクリプティングは、何かがうまくいかなかった場合に例外をキャッチするために各行をインストルメント化します。単一行のif文では、例外処理がステートメントのどの部分が失敗したかを知ることができず、適切に継続できません。単一行のif文で例外が発生すると、スクリプト全体が停止し、継続できなくなります。COSMOSスクリプトでは単一行のif文を使用しないでください（ただし、インターフェースやその他のRubyコードでは使用しても問題ありません。COSMOSスクリプトだけでは使用しないでください）。

次のようにしないでください：

```ruby
run_method() if tlm("INST HEALTH_STATUS TEMP1") > 10.0
```

代わりに次のようにしてください：

```ruby
# if文の中で失敗する可能性のあるコードを実行しないのがベストです
# tlm()は、CmdTlmServerが実行されていなかったり、ニーモニックのスペルが間違っていたりすると失敗する可能性があります
temp1 = tlm("INST HEALTH_STATUS TEMP1")
if temp1 > 10.0
  run_method()
end
```

## 問題が発生した場合

### チェックが失敗する一般的な理由

COSMOSスクリプトでチェックが失敗する一般的な理由は3つあります：

1. 遅延が短すぎた

   wait_check()メソッドは、参照されるテレメトリポイントがチェックに合格するまで待機する時間を示すタイムアウトを取ります。タイムアウトは、テスト対象のシステムがアクションを完了し、更新されたテレメトリを受信するのに十分な長さである必要があります。チェックが正常に完了するとすぐにスクリプトが続行されることに注意してください。したがって、より長いタイムアウトの唯一のペナルティは、失敗条件での追加の待機時間です。

2. チェックされた範囲または値が不正確または厳しすぎた

   実際のテレメトリ値は問題ないが、チェックされた期待値が厳しすぎることがよくあります。意味のある場合はチェックの範囲を緩めてください。浮動小数点数をチェックする場合は、スクリプトがwait_check_tolerance()ルーチンを使用していることを確認し、適切な許容値を使用していることを確認してください。

3. チェックが本当に失敗した

   もちろん、実際の失敗が発生することもあります。次のセクションでは、それらを処理して回復する方法を説明します。

### 異常からの回復方法

何かが失敗し、スクリプトがピンク色でハイライトされた行で停止した後、どのように回復できますか？幸いなことに、COSMOSはスクリプトで何かが失敗した後に回復するために使用できるいくつかのメカニズムを提供しています。

1. 再試行

   失敗後、Script Runnerの「一時停止 (Pause)」ボタンは「再試行 (Retry)」に変わります。「再試行 (Retry)」ボタンをクリックすると、失敗した行が再実行されます。タイミングの問題による失敗の場合、これにより問題が解決され、スクリプトを続行できることがよくあります。失敗に注意し、次回の実行前にスクリプトを更新するようにしてください。

1. デバッグプロンプトの使用

   Script -> Toggle Debugを選択することで、実行中のスクリプトを停止せずに状況を修正するために必要な任意のアクションを実行できます。また、なぜ何かが失敗したかを判断するために変数を検査することもできます。

1. 選択実行

   スクリプトの一部のみを実行する必要がある場合は、「選択実行 (Execute Selection)」を使用してスクリプトの一部のみを実行できます。これはスクリプトが一時停止しているか、エラーで停止している場合にも使用できます。

1. ここから実行

   スクリプトをクリックし、右クリックして「ここから実行 (Run from here)」を選択することで、ユーザーは任意の点からスクリプトを再開できます。これは、スクリプトの前半に必要な変数定義が存在しない場合に適しています。

## 高度なトピック

### CSVまたはExcelを使用した高度なスクリプト設定

スプレッドシートを使用してスクリプトで使用する値を保存することは、CM制御されたスクリプトがあるがテストのために一部の値を調整する必要がある場合や、異なるシリアル番号に対して異なる値を使用する必要がある場合に優れたオプションとなります。

Ruby CSVクラスを使用すると、CSVファイルからデータを簡単に読み取ることができます（クロスプラットフォームプロジェクトに推奨）。

```ruby
require 'csv'
values = CSV.read('test.csv')
puts values[0][0]
```

Windowsのみを使用している場合、COSMOSにはExcelファイルを読み取るためのライブラリも含まれています。

```ruby
require 'openc3/win32/excel'
ss = ExcelSpreadsheet.new('C:/git/cosmos/test.xlsx')
puts ss[0][0][0]
```

### Rubyモジュールの使用タイミング

Rubyのモジュールには2つの目的があります：名前空間とミックスイン。名前空間は、同じ名前で意味の異なるクラスやメソッドを持つことを可能にします。例えば、名前空間を使用すれば、COSMOSはPacketクラスを持ち、別のRubyライブラリもPacketクラスを持つことができます。ただし、これはCOSMOSスクリプティングには通常役立ちません。

ミックスインは継承を使用せずにクラスに共通のメソッドを追加することを可能にします。ミックスインは、一部のクラスに共通の機能を追加し、他のクラスには追加しない場合や、クラスを複数のファイルに分割する場合に役立ちます。

```ruby
module MyModule
  def module_method
  end
end
class MyTest < OpenC3::Group
  include MyModule
  def test_1
    module_method()
  end
end
```