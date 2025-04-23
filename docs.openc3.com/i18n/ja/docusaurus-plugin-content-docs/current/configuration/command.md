---
sidebar_position: 4
title: コマンド
description: コマンド定義ファイルのフォーマットとキーワード
sidebar_custom_props:
  myEmoji: 📡
---

<!-- Be sure to edit _command.md because command.md is a generated file -->

## コマンド定義ファイル

コマンド定義ファイルは、COSMOSターゲットに送信できるコマンドパケットを定義します。コマンドパケットの定義には、1つの大きなファイルを使用することも、ユーザーの判断で複数のファイルを使用することもできます。コマンド定義ファイルはターゲットのcmd_tlmディレクトリに配置され、アルファベット順に処理されます。そのため、他のコマンドファイルに依存するコマンドファイル（例：既存のコマンドをオーバーライドまたは拡張するファイル）は、最後に名前を付ける必要があります。最も簡単な方法は、既存のファイル名に拡張子を追加することです。例えば、既にcmd.txtがある場合、cmd.txtの定義に依存するコマンドにはcmd_override.txtを作成できます。また、[ASCII表](http://www.asciitable.com/)の構造上、大文字で始まるファイルは小文字で始まるファイルよりも先に処理されることに注意してください。

コマンドパラメータを定義する際は、次のデータ型から選択できます：INT、UINT、FLOAT、STRING、BLOCK。これらはそれぞれ整数、符号なし整数、浮動小数点数、文字列、バイナリデータブロックに対応しています。STRINGとBLOCKの唯一の違いは、COSMOSがバイナリコマンドログを読み取る際に、STRINGタイプはnullバイト（0）に遭遇すると読み取りを停止することです。これはData Extractorによって生成されるテキストログに表示されます。これはCOSMOSが書き込むデータには影響しないことに注意してください。STRINGパラメータにnullバイト（0）を渡すことは引き続き有効です。

<div style={{"clear": 'both'}}></div>

# コマンドキーワード


## COMMAND
**新しいコマンドパケットを定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target | このコマンドが関連付けられているターゲットの名前 | True |
| Command | このコマンドの名前。ニーモニックとも呼ばれます。このターゲットへのコマンド内で一意である必要があります。理想的には短く明確であることが望ましいです。 | True |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | True |
| Description | このコマンドの説明（引用符で囲む必要があります） | False |

使用例:
```ruby
COMMAND INST COLLECT BIG_ENDIAN "Start collect"
```

## COMMANDの修飾子
以下のキーワードはCOMMANDキーワードに続いて使用する必要があります。

### PARAMETER
**現在のコマンドパケット内のコマンドパラメータを定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | パラメータの名前。コマンド内で一意である必要があります。 | True |
| Bit Offset | このパラメータの最上位ビットのコマンドパケット内のビットオフセット。パケットの末尾からのオフセットを示すために負の値を使用することもできます。派生パラメータには常にビットオフセット0を使用してください。 | True |
| Bit Size | このパラメータのビットサイズ。ゼロまたは負の値を使用して、文字列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。Bit Offsetが0でBit Sizeが0の場合、これは派生パラメータであり、Data Typeは'DERIVED'に設定する必要があります。 | True |
| Data Type | このパラメータのデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, DERIVED, STRING, BLOCK</span> | True |

Data TypeがINT、UINT、FLOAT、DERIVEDの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Minimum Value | このパラメータに許可される最小値 | True |
| Maximum Value | このパラメータに許可される最大値 | True |
| Default Value | このパラメータのデフォルト値。デフォルト値を指定する必要がありますが、パラメータをREQUIREDとマークすると、スクリプトは値を指定するよう強制されます。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します。[リトルエンディアンビットフィールド](../guides/little-endian-bitfields.md)のガイドを参照してください。<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Data TypeがSTRING、BLOCKの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Default Value | このパラメータのデフォルト値。デフォルト値を指定する必要がありますが、パラメータをREQUIREDとマークすると、スクリプトは値を指定するよう強制されます。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

使用例:
```ruby
PARAMETER SYNC 0 32 UINT 0xDEADBEEF 0xDEADBEEF 0xDEADBEEF "Sync pattern"
PARAMETER DATA 32 32 INT MIN MAX 0 "Data value"
PARAMETER VALUE 64 32 FLOAT 0 10.5 2.5
PARAMETER LABEL 96 96 STRING "OPENC3" "The label to apply"
PARAMETER BLOCK 192 0 BLOCK 0x0 "Block of binary data"
```

### PARAMETERの修飾子
以下のキーワードはPARAMETERキーワードに続いて使用する必要があります。

#### FORMAT_STRING
**printfスタイルのフォーマットを追加する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Format | printf構文を使用してフォーマットする方法。例えば、'0x%0X'は値を16進数で表示します。 | True |

使用例:
```ruby
FORMAT_STRING "0x%0X"
```

#### UNITS
**表示単位を追加する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Full Name | 単位タイプのフルネーム（例：摂氏） | True |
| Abbreviated | 単位の略称（例：C） | True |

使用例:
```ruby
UNITS Celsius C
UNITS Kilometers KM
```

#### DESCRIPTION
**定義された説明をオーバーライドする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Value | 新しい説明 | True |

#### META
**カスタムユーザーメタデータを格納する**

メタデータは、カスタムツールがさまざまな目的で使用できるユーザー固有のデータです。一例として、ソースコードヘッダーファイルを生成するために必要な追加情報を格納するためのものがあります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Meta Name | 格納するメタデータの名前 | True |
| Meta Values | このMeta Nameに格納する1つ以上の値 | False |

使用例:
```ruby
META TEST "This parameter is for test purposes only"
```

#### OVERLAP
<div class="right">(Since 4.4.1)</div>**このアイテムはパケット内の他のアイテムと重複することが許可されています**

アイテムのビットオフセットが他のアイテムと重複する場合、OpenC3は警告を発します。このキーワードは、アイテムが他のアイテムと重複することを明示的に許可し、警告メッセージを抑制します。


#### KEY
<div class="right">(Since 5.0.10)</div>**パケット内のこの生の値にアクセスするために使用されるキーを定義します。**

キーは多くの場合、[JSONPath](https://en.wikipedia.org/wiki/JSONPath)や[XPath](https://en.wikipedia.org/wiki/XPath)文字列です。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Key string | このアイテムにアクセスするためのキー | True |

使用例:
```ruby
KEY $.book.title
```

#### VARIABLE_BIT_SIZE
<div class="right">(Since 5.18.0)</div>**アイテムのビットサイズが別の長さアイテムによって定義されていることを示す**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Length Item Name | 関連する長さアイテムの名前 | True |
| Length Bits Per Count | 長さアイテムのカウント当たりのビット数。デフォルトは8 | False |
| Length Value Bit Offset | 長さフィールド値に適用するビットオフセット。デフォルトは0 | False |

#### REQUIRED
**スクリプトでパラメータを必ず指定する必要がある**

Script Runner経由でコマンドを送信する際、現在のコマンドパラメータに常に値を指定する必要があります。これにより、ユーザーがデフォルト値に依存することを防ぎます。これはCommand Senderには影響せず、PARAMETER定義で提供されたデフォルト値でフィールドが入力されることに注意してください。


#### MINIMUM_VALUE
**定義された最小値をオーバーライドする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Value | パラメータの新しい最小値 | True |

#### MAXIMUM_VALUE
**定義された最大値をオーバーライドする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Value | パラメータの新しい最大値 | True |

#### DEFAULT_VALUE
**定義されたデフォルト値をオーバーライドする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Value | パラメータの新しいデフォルト値 | True |

#### STATE
**現在のコマンドパラメータのキー/値ペアを定義する**

キー値のペアにより、ユーザーフレンドリーな文字列が可能になります。例えば、ON = 1およびOFF = 0の状態を定義できます。これにより、コマンドパラメータを送信する際に、数字の1ではなく単語「ON」を使用できるようになり、より明確で、ユーザーエラーの可能性が低くなります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Key | 文字列の状態名 | True |
| Value | 数値の状態値 | True |
| Hazardous / Disable Messages | 状態が危険であることを示します。これにより、このコマンドを送信する際にユーザー確認を求めるポップアップが表示されます。危険でない状態の場合、DISABLE_MESSAGESを設定することもでき、その状態を使用する際にコマンドを表示しません。<br/><br/>有効な値: <span class="values">HAZARDOUS</span> | False |
| Hazardous Description | この状態が危険である理由を説明する文字列 | False |

使用例:
```ruby
APPEND_PARAMETER ENABLE 32 UINT 0 1 0 "Enable setting"
  STATE FALSE 0
  STATE TRUE 1
APPEND_PARAMETER STRING 1024 STRING "NOOP" "String parameter"
  STATE "NOOP" "NOOP" DISABLE_MESSAGES
  STATE "ARM LASER" "ARM LASER" HAZARDOUS "Arming the laser is an eye safety hazard"
  STATE "FIRE LASER" "FIRE LASER" HAZARDOUS "WARNING! Laser will be fired!"
```

#### WRITE_CONVERSION
**現在のコマンドパラメータに書き込み時の変換を適用する**

変換はカスタムRubyまたはPythonファイルで実装され、ターゲットのlibフォルダーに配置する必要があります。クラスはConversionを継承する必要があります。追加パラメータを取る場合は`initialize`（Ruby）または`__init__`（Python）メソッドを実装する必要があり、常に`call`メソッドを実装する必要があります。変換係数は、ユーザーが入力した値にバイナリコマンドパケットに書き込まれて送信される前に適用されます。

書き込み変換を適用する場合、データ型が変更されることがあります。例えば、入力STRING型からUINT型を作成する場合（この例については[ip_write_conversion.rb](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/conversions/ip_write_conversion.rb)または[ip_write_conversion.py](https://github.com/OpenC3/cosmos/blob/main/openc3/python/openc3/conversions/ip_write_conversion.py)を参照）。この場合、コマンド定義のデータ型はUINTであり、最小値・最大値は重要ではない（ただし指定する必要がある）ため、通常はMIN MAXに設定されます。デフォルト値は重要であり、文字列として指定する必要があります。完全な例については、COSMOS DemoのTIME_OFFSETコマンド定義のIP_ADDRESSパラメータを参照してください：[INST inst_cmds.txt](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST/cmd_tlm/inst_cmds.txt)または[INST2 inst_cmds.txt](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST2/cmd_tlm/inst_cmds.txt)。

:::info コマンドパラメータに対する複数の書き込み変換
コマンドが構築されると、各アイテムがデフォルト値を設定するために書き込まれ（このとき書き込み変換が実行されます）、その後、ユーザーが提供した値でアイテムが書き込まれます（ここでも書き込み変換が実行されます）。したがって、書き込み変換は2回実行される可能性があります。また、どのパラメータがすでに書き込まれたかについての保証はありません。パケット自体には、コマンドにユーザーが提供した値のハッシュを取得するためのgiven_values()メソッドがあります。これを使用して渡されたパラメータ値を確認できます。
:::


| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Class Filename | RubyまたはPythonクラスを含むファイル名。ファイル名はクラス名に基づいて命名する必要があり、クラスはアンダースコア付きのファイル名のCamelCase版である必要があります。例えば、'the_great_conversion.rb'は'class TheGreatConversion'を含んでいるべきです。 | True |
| Parameter | クラスコンストラクタに渡される変換の追加パラメータ値。 | False |

Ruby例:
```ruby
WRITE_CONVERSION the_great_conversion.rb 1000

Defined in the_great_conversion.rb:

require 'openc3/conversions/conversion'
module OpenC3
  class TheGreatConversion < Conversion
    def initialize(multiplier)
      super()
      @multiplier = multiplier.to_f
    end
    def call(value, packet, buffer)
      return value * multiplier
    end
  end
end
```

Python例:
```python
WRITE_CONVERSION the_great_conversion.py 1000

Defined in the_great_conversion.py:

from openc3.conversions.conversion import Conversion
class TheGreatConversion(Conversion):
    def __init__(self, multiplier):
        super().__init__()
        self.multiplier = float(multiplier)
    def call(self, value, packet, buffer):
        return value * self.multiplier
```

#### POLY_WRITE_CONVERSION
**現在のコマンドパラメータに多項式変換係数を追加する**

変換係数は、ユーザーが入力した値にバイナリコマンドパケットに書き込まれて送信される前に適用されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| C0 | 係数 | True |
| Cx | 変換の追加係数値。任意の次数の多項式変換を使用できるため、「x」の値は多項式の次数によって異なります。より高次の多項式は処理に時間がかかりますが、より精度が高くなることがあります。 | False |

使用例:
```ruby
POLY_WRITE_CONVERSION 10 0.5 0.25
```

#### SEG_POLY_WRITE_CONVERSION
**現在のコマンドパラメータに区分的多項式変換係数を追加する**

この変換係数は、ユーザーが入力した値にバイナリコマンドパケットに書き込まれて送信される前に適用されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Lower Bound | この区分的多項式が適用される値の範囲の下限を定義します。最小下限値のセグメントでは無視されます。 | True |
| C0 | 係数 | True |
| Cx | 変換の追加係数値。任意の次数の多項式変換を使用できるため、「x」の値は多項式の次数によって異なります。より高次の多項式は処理に時間がかかりますが、より精度が高くなることがあります。 | False |

使用例:
```ruby
SEG_POLY_WRITE_CONVERSION 0 10 0.5 0.25 # Apply the conversion to all values < 50
SEG_POLY_WRITE_CONVERSION 50 11 0.5 0.275 # Apply the conversion to all values >= 50 and < 100
SEG_POLY_WRITE_CONVERSION 100 12 0.5 0.3 # Apply the conversion to all values >= 100
```

#### GENERIC_WRITE_CONVERSION_START
**汎用書き込み変換を開始する**

現在のコマンドパラメータに汎用変換関数を追加します。
この変換係数は、ユーザーが入力した値にバイナリコマンドパケットに書き込まれて送信される前に適用されます。変換はRubyまたはPythonコードとして指定され、2つの暗黙のパラメータを受け取ります。'value'は書き込まれる生の値であり、'packet'はコマンドパケットクラスへの参照です（注：後方互換性のためにパケットを'myself'として参照することもサポートされています）。コードの最後の行は変換された値を返す必要があります。GENERIC_WRITE_CONVERSION_ENDキーワードは、変換のすべてのコード行が与えられたことを指定します。

:::info コマンドパラメータに対する複数の書き込み変換
コマンドが構築されると、各アイテムがデフォルト値を設定するために書き込まれ（このとき書き込み変換が実行されます）、その後、ユーザーが提供した値でアイテムが書き込まれます（ここでも書き込み変換が実行されます）。したがって、書き込み変換は2回実行される可能性があります。また、どのパラメータがすでに書き込まれたかについての保証はありません。パケット自体には、コマンドにユーザーが提供した値のハッシュを取得するためのgiven_values()メソッドがあります。これを使用して渡されたパラメータ値を確認できます。
:::


:::warning
汎用変換は長期的な解決策としては適していません。変換クラスを作成してWRITE_CONVERSIONを使用することを検討してください。WRITE_CONVERSIONはデバッグが容易で、パフォーマンスが高いです。
:::


Ruby例:
```ruby
APPEND_PARAMETER ITEM1 32 UINT 0 0xFFFFFFFF 0
  GENERIC_WRITE_CONVERSION_START
    return (value * 1.5).to_i # Convert the value by a scale factor
  GENERIC_WRITE_CONVERSION_END
```

Python例:
```python
APPEND_PARAMETER ITEM1 32 UINT 0 0xFFFFFFFF 0
  GENERIC_WRITE_CONVERSION_START
    return int(value * 1.5) # Convert the value by a scale factor
  GENERIC_WRITE_CONVERSION_END
```

#### GENERIC_WRITE_CONVERSION_END
**汎用書き込み変換を完了する**


#### OVERFLOW
**値を書き込む際に型のオーバーフローが発生した場合の動作を設定する**

デフォルトでは、OpenC3は指定された型をオーバーフローする値を書き込もうとするとエラーをスローします（例：8ビット符号付き値に255を書き込む場合）。オーバーフロー動作を設定することで、OpenC3に値を'TRUNCATE'（上位ビットを除外する）させることもできます。また、'SATURATE'を設定することもでき、これによりOpenC3はその型で許容される最大値または最小値に値を置き換えます。最後に、'ERROR_ALLOW_HEX'を指定することもでき、これにより最大16進値を書き込むことが可能になります（例：8ビット符号付き値に255を正常に書き込める）。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Behavior | OpenC3がオーバーフロー値をどのように扱うか。符号付きおよび符号なし整数データ型にのみ適用されます。<br/><br/>有効な値: <span class="values">ERROR, ERROR_ALLOW_HEX, TRUNCATE, SATURATE</span> | True |

使用例:
```ruby
OVERFLOW TRUNCATE
```

### APPEND_PARAMETER
**現在のコマンドパケット内のコマンドパラメータを定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | パラメータの名前。コマンド内で一意である必要があります。 | True |
| Bit Size | このパラメータのビットサイズ。ゼロまたは負の値を使用して、文字列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。Bit Offsetが0でBit Sizeが0の場合、これは派生パラメータであり、Data Typeは'DERIVED'に設定する必要があります。 | True |
| Data Type | このパラメータのデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, DERIVED, STRING, BLOCK</span> | True |

Data TypeがINT、UINT、FLOAT、DERIVEDの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Minimum Value | このパラメータに許可される最小値 | True |
| Maximum Value | このパラメータに許可される最大値 | True |
| Default Value | このパラメータのデフォルト値。デフォルト値を指定する必要がありますが、パラメータをREQUIREDとマークすると、スクリプトは値を指定するよう強制されます。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します。[リトルエンディアンビットフィールド](../guides/little-endian-bitfields.md)のガイドを参照してください。<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Data TypeがSTRING、BLOCKの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Default Value | このパラメータのデフォルト値。デフォルト値を指定する必要がありますが、パラメータをREQUIREDとマークすると、スクリプトは値を指定するよう強制されます。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

使用例:
```ruby
APPEND_PARAMETER SYNC 32 UINT 0xDEADBEEF 0xDEADBEEF 0xDEADBEEF "Sync pattern"
APPEND_PARAMETER VALUE 32 FLOAT 0 10.5 2.5
APPEND_PARAMETER LABEL 0 STRING "OPENC3" "The label to apply"
```

### ID_PARAMETER
**現在のコマンドパケット内の識別コマンドパラメータを定義する**

ID パラメータは、バイナリデータブロックを特定のコマンドとして識別するために使用されます。コマンドパケットには1つ以上のID_PARAMETERを含めることができ、コマンドを識別するにはすべてがバイナリデータと一致する必要があります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | パラメータの名前。コマンド内で一意である必要があります。 | True |
| Bit Offset | このパラメータの最上位ビットのコマンドパケット内のビットオフセット。パケットの末尾からのオフセットを示すために負の値を使用することもできます。 | True |
| Bit Size | このパラメータのビットサイズ。ゼロまたは負の値を使用して、文字列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。Bit Offsetが0でBit Sizeが0の場合、これは派生パラメータであり、Data Typeは'DERIVED'に設定する必要があります。 | True |
| Data Type | このパラメータのデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, DERIVED, STRING, BLOCK</span> | True |

Data TypeがINT、UINT、FLOAT、DERIVEDの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Minimum Value | このパラメータに許可される最小値 | True |
| Maximum Value | このパラメータに許可される最大値 | True |
| ID Value | このパラメータの識別値。バッファをこのパケットとして識別するには、バイナリデータがこの値と一致する必要があります。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します。[リトルエンディアンビットフィールド](../guides/little-endian-bitfields.md)のガイドを参照してください。<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Data TypeがSTRING、BLOCKの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Default Value | このパラメータのデフォルト値。デフォルト値を指定する必要がありますが、パラメータをREQUIREDとマークすると、スクリプトは値を指定するよう強制されます。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

使用例:
```ruby
ID_PARAMETER OPCODE 32 32 UINT 2 2 2 "Opcode identifier"
```

### APPEND_ID_PARAMETER
**現在のコマンドパケット内の識別コマンドパラメータを定義する**

ID パラメータは、バイナリデータブロックを特定のコマンドとして識別するために使用されます。コマンドパケットには1つ以上のID_PARAMETERを含めることができ、コマンドを識別するにはすべてがバイナリデータと一致する必要があります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | パラメータの名前。コマンド内で一意である必要があります。 | True |
| Bit Size | このパラメータのビットサイズ。ゼロまたは負の値を使用して、文字列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。Bit Offsetが0でBit Sizeが0の場合、これは派生パラメータであり、Data Typeは'DERIVED'に設定する必要があります。 | True |
| Data Type | このパラメータのデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, DERIVED, STRING, BLOCK</span> | True |

Data TypeがINT、UINT、FLOAT、DERIVEDの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Minimum Value | このパラメータに許可される最小値 | True |
| Maximum Value | このパラメータに許可される最大値 | True |
| ID Value | このパラメータの識別値。バッファをこのパケットとして識別するには、バイナリデータがこの値と一致する必要があります。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します。[リトルエンディアンビットフィールド](../guides/little-endian-bitfields.md)のガイドを参照してください。<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Data TypeがSTRING、BLOCKの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Default Value | このパラメータのデフォルト値。デフォルト値を指定する必要がありますが、パラメータをREQUIREDとマークすると、スクリプトは値を指定するよう強制されます。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

使用例:
```ruby
APPEND_ID_PARAMETER OPCODE 32 UINT 2 2 2 "Opcode identifier"
```

### ARRAY_PARAMETER
**現在のコマンドパケット内の配列であるコマンドパラメータを定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | パラメータの名前。コマンド内で一意である必要があります。 | True |
| Bit Offset | このパラメータの最上位ビットのコマンドパケット内のビットオフセット。パケットの末尾からのオフセットを示すために負の値を使用することもできます。派生パラメータには常にビットオフセット0を使用してください。 | True |
| Item Bit Size | 各配列アイテムのビットサイズ | True |
| Item Data Type | 各配列アイテムのデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, DERIVED</span> | True |
| Array Bit Size | 配列の合計ビットサイズ。ゼロまたは負の値を使用して、配列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。 | True |
| Description | 説明（引用符で囲む必要があります） | False |
| Endianness | データがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

使用例:
```ruby
ARRAY_PARAMETER ARRAY 64 64 FLOAT 640 "Array of 10 64bit floats"
```

### APPEND_ARRAY_PARAMETER
**現在のコマンドパケット内の配列であるコマンドパラメータを定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | パラメータの名前。コマンド内で一意である必要があります。 | True |
| Item Bit Size | 各配列アイテムのビットサイズ | True |
| Item Data Type | 各配列アイテムのデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, DERIVED</span> | True |
| Array Bit Size | 配列の合計ビットサイズ。ゼロまたは負の値を使用して、配列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。 | True |
| Description | 説明（引用符で囲む必要があります） | False |
| Endianness | データがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

使用例:
```ruby
APPEND_ARRAY_PARAMETER ARRAY 64 FLOAT 640 "Array of 10 64bit floats"
```

### SELECT_PARAMETER
**編集用に既存のコマンドパラメータを選択する**

最初にパケットを選択するためにSELECT_COMMANDと組み合わせて使用する必要があります。通常、生成された値をオーバーライドしたり、複数回使用されるターゲットの特定のインスタンスにのみ影響する特定の変更を行ったりするために使用されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Parameter | 変更のために選択するパラメータの名前 | True |

使用例:
```ruby
SELECT_COMMAND INST COLLECT
  SELECT_PARAMETER DURATION
    # Add units
    UNITS Seconds S
```

### DELETE_PARAMETER
<div class="right">(Since 4.4.1)</div>**既存のコマンドパラメータをパケット定義から削除する**

コマンド定義からパラメータを削除しても、そのパラメータの定義されたスペースは削除されません。したがって、新しいパラメータを再定義しない限り、データにアクセスできない「穴」がパケットに残ります。SELECT_COMMANDを使用してから、PARAMETERを使用して新しいパラメータを定義できます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Parameter | 削除するパラメータの名前 | True |

使用例:
```ruby
SELECT_COMMAND INST COLLECT
  DELETE_PARAMETER DURATION
```

### HIDDEN
**このコマンドをCommand SenderやHandbook CreatorなどすべてのOpenC3ツールから隠す**

隠されたコマンドはスクリプトを書くときにScript Runnerのポップアップヘルパーに表示されません。コマンドはシステムに存在し、スクリプトから送信できます。


### DISABLED
**このコマンドが送信されないようにする**

コマンドを隠し、スクリプトからの送信も無効にします。DISABLEDコマンドを送信しようとするとエラーメッセージが表示されます。


### DISABLE_MESSAGES
**サーバーがcmd(...)メッセージを表示しないようにする。コマンドは引き続き記録されます。**


### META
**現在のコマンドのメタデータを格納する**

メタデータは、カスタムツールがさまざまな目的で使用できるユーザー固有のデータです。一例として、ソースコードヘッダーファイルを生成するために必要な追加情報を格納するためのものがあります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Meta Name | 格納するメタデータの名前 | True |
| Meta Values | このMeta Nameに格納する1つ以上の値 | False |

使用例:
```ruby
META FSW_TYPE "struct command"
```

### HAZARDOUS
**現在のコマンドを危険として指定する**

危険なコマンドを送信すると、コマンドを送信する前に確認を求めるダイアログが表示されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Description | コマンドが危険である理由の説明（引用符で囲む必要があります） | False |

### ACCESSOR
<div class="right">(Since 5.0.10)</div>**パケットから生の値を読み書きするために使用されるクラスを定義する**

パケットから生の値を読み取るために使用されるクラスを定義します。デフォルトはBinaryAccessorです。詳細については、[アクセサー](accessors)を参照してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Accessor Class Name | アクセサークラスの名前 | True |
| Argument | アクセサークラスコンストラクタに渡される追加引数 | False |

### TEMPLATE
<div class="right">(Since 5.0.10)</div>**デフォルト値が入力される前にコマンドを初期化するために使用されるテンプレート文字列を定義する**

一般的に、テンプレート文字列はJSONまたはHTML形式で、コマンドパラメータで値が入力されます。UTF-8エンコードである必要があります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Template | 引用符で囲まれるべきテンプレート文字列 | True |

### TEMPLATE_FILE
<div class="right">(Since 5.0.10)</div>**デフォルト値が入力される前にコマンドを初期化するために使用されるテンプレートファイルを定義する**

一般的に、テンプレートファイルはJSONまたはHTML形式で、コマンドパラメータで値が入力されます。バイナリまたはUTF-8の場合があります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Template File Path | テンプレートファイルへの相対パス。ファイル名は一般的にアンダースコアで始まります。 | True |

### RESPONSE
<div class="right">(Since 5.14.0)</div>**このコマンドに対する予期されるテレメトリパケットレスポンスを示す**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | テレメトリレスポンスパケットのターゲット名 | True |
| Packet Name | テレメトリレスポンスパケットのパケット名 | True |

### ERROR_RESPONSE
<div class="right">(Since 5.14.0)</div>**このコマンドに対する予期されるテレメトリパケットエラーレスポンスを示す**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | テレメトリエラーレスポンスパケットのターゲット名 | True |
| Packet Name | テレメトリエラーレスポンスパケットのパケット名 | True |

### RELATED_ITEM
<div class="right">(Since 5.14.0)</div>**このコマンドに関連するテレメトリアイテムを定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | 関連するテレメトリアイテムのターゲット名 | True |
| Packet Name | 関連するテレメトリアイテムのパケット名 | True |
| Item Name | 関連するテレメトリアイテムのアイテム名 | True |

### SCREEN
<div class="right">(Since 5.14.0)</div>**このコマンドに関連するテレメトリ画面を定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | 関連するテレメトリ画面のターゲット名 | True |
| Screen Name | 関連するテレメトリ画面の画面名 | True |

### VIRTUAL
<div class="right">(Since 5.18.0)</div>**このパケットを仮想としてマークし、識別に参加しないようにする**

特定のパケットを持つアイテムの構造として使用できるパケット定義に使用されます。


### RESTRICTED
<div class="right">(Since 5.20.0)</div>**このパケットを制限付きとしてマークし、クリティカルコマンディングが有効な場合は承認が必要になる**

クリティカルコマンドの2種類のタイプ（HAZARDOUSとRESTRICTED）の1つとして使用されます。


### VALIDATOR
<div class="right">(Since 5.19.0)</div>**コマンドのバリデータクラスを定義する**

バリデータクラスは、pre_checkとpost_checkの両方のメソッドを持つコマンドの成功または失敗を検証するために使用されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Class Filename | RubyまたはPythonクラスを含むファイル名。ファイル名はクラス名に基づいて命名する必要があり、クラスはアンダースコア付きのファイル名のCamelCase版である必要があります。例えば、'command_validator.rb'は'class CommandValidator'を含んでいるべきです。 | True |
| Argument | バリデータクラスコンストラクタに渡される追加引数 | False |

Ruby例:
```ruby
VALIDATOR custom_validator.rb

Defined in custom_validator.rb:

require 'openc3/packets/command_validator'
class CustomValidator < OpenC3::CommandValidator
  # Both the pre_check and post_check are passed the command packet that was sent
  # You can inspect the command in your checks as follows:
  #   packet.target_name => target name
  #   packet.packet_name => packet name (command name)
  #   packet.read("ITEM") => converted value
  #   packet.read("ITEM", :RAW) => raw value
  def pre_check(packet)
    if tlm("TGT PKT ITEM") == 0
      return [false, "TGT PKT ITEM is 0"]
    end
    @cmd_acpt_cnt = tlm("TGT PKT CMD_ACPT_CNT")
    return [true, nil]
  end
  def post_check(packet)
    wait_check("TGT PKT CMD_ACPT_CNT > #{@cmd_acpt_cnt}", 10)
    return [true, nil]
  end
end
```

Python例:
```python
VALIDATOR custom_validator.rb

Defined in custom_validator.py:

class CustomValidator(CommandValidator):
    # Both the pre_check and post_check are passed the command packet that was sent
    # You can inspect the command in your checks as follows:
    #   packet.target_name => target name
    #   packet.packet_name => packet name (command name)
    #   packet.read("ITEM") => converted value
    #   packet.read("ITEM", :RAW) => raw value
    def pre_check(self, command):
        if tlm("TGT PKT ITEM") == 0:
            return [False, "TGT PKT ITEM is 0"]
        self.cmd_acpt_cnt = tlm("INST HEALTH_STATUS CMD_ACPT_CNT")
        return [True, None]

    def post_check(self, command):
        wait_check(f"INST HEALTH_STATUS CMD_ACPT_CNT > {self.cmd_acpt_cnt}", 10)
        return [True, None]
```

## SELECT_COMMAND
**編集用に既存のコマンドパケットを選択する**

通常、元のコマンドが定義されている場所とは別の設定ファイルで使用され、既存のコマンド定義をオーバーライドまたは追加します。個々のパラメータを変更するには、SELECT_PARAMETERと組み合わせて使用する必要があります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | このコマンドが関連付けられているターゲットの名前 | True |
| Command Name | 選択するコマンドの名前 | True |

使用例:
```ruby
SELECT_COMMAND INST COLLECT
  SELECT_PARAMETER DURATION
    # Add units
    UNITS Seconds S
```


## サンプルファイル

**サンプルファイル: TARGET/cmd_tlm/cmd.txt**

<!-- prettier-ignore -->
```ruby
COMMAND TARGET COLLECT_DATA BIG_ENDIAN "Commands my target to collect data"
  PARAMETER CCSDSVER 0 3 UINT 0 0 0 "CCSDS PRIMARY HEADER VERSION NUMBER"
  PARAMETER CCSDSTYPE 3 1 UINT 1 1 1 "CCSDS PRIMARY HEADER PACKET TYPE"
  PARAMETER CCSDSSHF 4 1 UINT 0 0 0 "CCSDS PRIMARY HEADER SECONDARY HEADER FLAG"
  ID_PARAMETER CCSDSAPID 5 11 UINT 0 2047 100 "CCSDS PRIMARY HEADER APPLICATION ID"
  PARAMETER CCSDSSEQFLAGS 16 2 UINT 3 3 3 "CCSDS PRIMARY HEADER SEQUENCE FLAGS"
  PARAMETER CCSDSSEQCNT 18 14 UINT 0 16383 0 "CCSDS PRIMARY HEADER SEQUENCE COUNT"
  PARAMETER CCSDSLENGTH 32 16 UINT 4 4 4 "CCSDS PRIMARY HEADER PACKET LENGTH"
  PARAMETER ANGLE 48 32 FLOAT -180.0 180.0 0.0 "ANGLE OF INSTRUMENT IN DEGREES"
    POLY_WRITE_CONVERSION 0 0.01745 0 0
  PARAMETER MODE 80 8 UINT 0 1 0 "DATA COLLECTION MODE"
    STATE NORMAL 0
    STATE DIAG 1
COMMAND TARGET NOOP BIG_ENDIAN "Do Nothing"
  PARAMETER CCSDSVER 0 3 UINT 0 0 0 "CCSDS PRIMARY HEADER VERSION NUMBER"
  PARAMETER CCSDSTYPE 3 1 UINT 1 1 1 "CCSDS PRIMARY HEADER PACKET TYPE"
  PARAMETER CCSDSSHF 4 1 UINT 0 0 0 "CCSDS PRIMARY HEADER SECONDARY HEADER FLAG"
  ID_PARAMETER CCSDSAPID 5 11 UINT 0 2047 101 "CCSDS PRIMARY HEADER APPLICATION ID"
  PARAMETER CCSDSSEQFLAGS 16 2 UINT 3 3 3 "CCSDS PRIMARY HEADER SEQUENCE FLAGS"
  PARAMETER CCSDSSEQCNT 18 14 UINT 0 16383 0 "CCSDS PRIMARY HEADER SEQUENCE COUNT"
  PARAMETER CCSDSLENGTH 32 16 UINT 0 0 0 "CCSDS PRIMARY HEADER PACKET LENGTH"
  PARAMETER DUMMY 48 8 UINT 0 0 0 "DUMMY PARAMETER BECAUSE CCSDS REQUIRES 1 BYTE OF DATA"
COMMAND TARGET SETTINGS BIG_ENDIAN "Set the Settings"
  PARAMETER CCSDSVER 0 3 UINT 0 0 0 "CCSDS PRIMARY HEADER VERSION NUMBER"
  PARAMETER CCSDSTYPE 3 1 UINT 1 1 1 "CCSDS PRIMARY HEADER PACKET TYPE"
  PARAMETER CCSDSSHF 4 1 UINT 0 0 0 "CCSDS PRIMARY HEADER SECONDARY HEADER FLAG"
  ID_PARAMETER CCSDSAPID 5 11 UINT 0 2047 102 "CCSDS PRIMARY HEADER APPLICATION ID"
  PARAMETER CCSDSSEQFLAGS 16 2 UINT 3 3 3 "CCSDS PRIMARY HEADER SEQUENCE FLAGS"
  PARAMETER CCSDSSEQCNT 18 14 UINT 0 16383 0 "CCSDS PRIMARY HEADER SEQUENCE COUNT"
  PARAMETER CCSDSLENGTH 32 16 UINT 0 0 0 "CCSDS PRIMARY HEADER PACKET LENGTH"
  <% 5.times do |x| %>
  APPEND_PARAMETER SETTING<%= x %> 16 UINT 0 5 0 "Setting <%= x %>"
  <% end %>
```