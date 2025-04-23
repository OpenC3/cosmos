---
sidebar_position: 9
title: テーブル
description: テーブル定義ファイルのフォーマットとキーワード
---

<!-- Be sure to edit _table.md because table.md is a generated file -->

## テーブル定義ファイル

テーブル定義ファイルは、COSMOS [テーブルマネージャー](../tools/table-manager.md)で表示できるバイナリテーブルを定義します。テーブル定義はターゲットのtables/configディレクトリで定義され、通常は`PPSSelectionTable_def.txt`のようにテーブル名に基づいて命名されます。`_def.txt`拡張子はそのファイルがテーブル定義であることを識別するのに役立ちます。テーブル定義は`TABLEFILE`キーワードを使用して組み合わせることができます。これにより、個々のテーブルコンポーネントをより大きなバイナリに構築することができます。

テーブル定義ファイルは[コマンド設定](command.md)と多くの類似点を共有しています。同じデータ型があります：INT、UINT、FLOAT、STRING、BLOCK。これらはそれぞれ整数、符号なし整数、浮動小数点数、文字列、およびバイナリデータブロックに対応しています。

<div style={{"clear": 'both'}}></div>

# テーブルキーワード


## TABLEFILE
**テーブル定義のために開いて処理する別のファイルを指定する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| File Name | ファイルの名前。ファイルは現在の定義ファイルのディレクトリで検索されます。 | True |

## TABLE
**新しいテーブル定義を開始する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | 引用符で囲まれたテーブルの名前。名前はGUIタブに表示されます。 | True |
| Endianness | このテーブル内のデータがビッグエンディアンまたはリトルエンディアン形式であるかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | True |
| Display | テーブルがKEY_VALUE行（各行が一意）を含むか、または同一の行に異なる値を含むROW_COLUMNテーブルであるかを示します。<br/><br/>有効な値: <span class="values">KEY_VALUE, ROW_COLUMN</span> | False |

DisplayがKEY_VALUEの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Description | 引用符で囲まれたテーブルの説明。説明はマウスオーバーポップアップとステータスライン情報で使用されます。 | False |

DisplayがROW_COLUMNの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Rows | テーブル内の行数 | False |
| Description | 引用符で囲まれたテーブルの説明。説明はマウスオーバーポップアップとステータスライン情報で使用されます。 | False |

## TABLE修飾子
次のキーワードはTABLEキーワードに続く必要があります。

### PARAMETER
**現在のテーブル内のパラメータを定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | パラメータの名前。テーブル内で一意である必要があります。 | True |
| Bit Offset | このパラメータの最上位ビットのテーブル内のビットオフセット。テーブルの末尾からのオフセットを示すために負の値を使用することもできます。派生パラメータには常にビットオフセット0を使用します。 | True |
| Bit Size | このパラメータのビットサイズ。ゼロまたは負の値を使用して、文字列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。Bit Offsetが0でBit Sizeが0の場合、これは派生パラメータであり、Data Typeは'DERIVED'に設定する必要があります。 | True |
| Data Type | このパラメータのデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, DERIVED, STRING, BLOCK</span> | True |

Data TypeがINT、UINT、FLOAT、DERIVEDの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Minimum Value | このパラメータに許可される最小値 | True |
| Maximum Value | このパラメータに許可される最大値 | True |
| Default Value | このパラメータのデフォルト値。デフォルト値を提供する必要がありますが、パラメータをREQUIREDとマークすると、スクリプトは値を指定するよう強制されます。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します。[リトルエンディアンビットフィールド](../guides/little-endian-bitfields.md)のガイドを参照してください。<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Data TypeがSTRING、BLOCKの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Default Value | このパラメータのデフォルト値。デフォルト値を提供する必要がありますが、パラメータをREQUIREDとマークすると、スクリプトは値を指定するよう強制されます。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

### PARAMETER修飾子
次のキーワードはPARAMETERキーワードに続く必要があります。

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
<div class="right">(Since 5.0.10)</div>**パケット内のこの生の値にアクセスするために使用されるキーを定義します**

キーは多くの場合、[JSONPath](https://en.wikipedia.org/wiki/JSONPath)や[XPath](https://en.wikipedia.org/wiki/XPath)文字列です

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Key string | このアイテムにアクセスするためのキー | True |

使用例:
```ruby
KEY $.book.title
```

#### VARIABLE_BIT_SIZE
<div class="right">(Since 5.18.0)</div>**アイテムのビットサイズが別の長さアイテムによって定義されていることを示します**

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

#### HIDDEN
**パラメータがテーブルマネージャーGUIでユーザーに表示されないことを示す**

非表示パラメータは依然として存在し、結果のバイナリに保存されます。これはパディングや他の必須だがユーザーが編集できないフィールドに役立ちます。


#### UNEDITABLE
**パラメータがユーザーに表示されるが編集できないことを示す**

編集不可パラメータは、ユーザーが興味を持つかもしれないが編集できるべきではない制御フィールドに役立ちます。


### APPEND_PARAMETER
**現在のテーブル内のパラメータを定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | パラメータの名前。テーブル内で一意である必要があります。 | True |
| Bit Size | このパラメータのビットサイズ。ゼロまたは負の値を使用して、文字列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。Bit Offsetが0でBit Sizeが0の場合、これは派生パラメータであり、Data Typeは'DERIVED'に設定する必要があります。 | True |
| Data Type | このパラメータのデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, DERIVED, STRING, BLOCK</span> | True |

Data TypeがINT、UINT、FLOAT、DERIVEDの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Minimum Value | このパラメータに許可される最小値 | True |
| Maximum Value | このパラメータに許可される最大値 | True |
| Default Value | このパラメータのデフォルト値。デフォルト値を提供する必要がありますが、パラメータをREQUIREDとマークすると、スクリプトは値を指定するよう強制されます。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します。[リトルエンディアンビットフィールド](../guides/little-endian-bitfields.md)のガイドを参照してください。<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

Data TypeがSTRING、BLOCKの場合、残りのパラメータは次のとおりです：

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Default Value | このパラメータのデフォルト値。デフォルト値を提供する必要がありますが、パラメータをREQUIREDとマークすると、スクリプトは値を指定するよう強制されます。 | True |
| Description | このパラメータの説明（引用符で囲む必要があります） | False |
| Endianness | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | False |

## SELECT_TABLE
**既存のテーブルを編集用に選択する、通常は既存の定義をオーバーライドするために行われる**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Table | 既存のテーブルの名前 | True |

## DEFAULT
**マルチカラムテーブルの単一行のデフォルト値を指定する**

複数の行がある場合、各行にDEFAULT行が必要です。すべての行が同一の場合は、OpenC3デモで示されているようにERBの使用を検討してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Default values | データ型に対応するSTATE値またはデータ値 | False |


## サンプルファイル

**サンプルファイル: TARGET/tables/config/MCConfigurationTable_def.txt**

<!-- prettier-ignore -->
```ruby
TABLE "MC_Configuration" BIG_ENDIAN KEY_VALUE "Memory Control Configuration Table"
  APPEND_PARAMETER "Scrub_Region_1_Start_Addr" 32 UINT 0 0x03FFFFFB 0
    FORMAT_STRING "0x%0X"
  APPEND_PARAMETER "Scrub_Region_1_End_Addr" 32 UINT 0 0x03FFFFFF 0x03FFFFFF
    FORMAT_STRING "0x%0X"
  APPEND_PARAMETER "Scrub_Region_2_Start_Addr" 32 UINT 0 0x03FFFFB 0
    FORMAT_STRING "0x%0X"
  APPEND_PARAMETER "Scrub_Region_2_End_Addr" 32 UINT 0 0x03FFFFF 0x03FFFFF
    FORMAT_STRING "0x%0X"
  APPEND_PARAMETER "Dump_Packet_Throttle_(sec)" 32 UINT 0 0x0FFFFFFFF 2 "Number of seconds to wait between dumping large packets"
  APPEND_PARAMETER "Memory_Scrubbing" 8 UINT 0 1 1
    STATE DISABLE 0
    STATE ENABLE 1
  APPEND_PARAMETER "SIOC_Memory_Config" 8 UINT 1 3 3
  APPEND_PARAMETER "Uneditable_Text" 32 UINT MIN MAX 0xDEADBEEF "Uneditable field"
    FORMAT_STRING "0x%0X"
    UNEDITABLE
  APPEND_PARAMETER "Uneditable_State" 16 UINT MIN MAX 0 "Uneditable field"
    STATE DISABLE 0
    STATE ENABLE 1
    UNEDITABLE
  APPEND_PARAMETER "Uneditable_Check" 16 UINT MIN MAX 1 "Uneditable field"
    STATE UNCHECKED 0
    STATE CHECKED 1
    UNEDITABLE
  APPEND_PARAMETER "Binary" 32 STRING 0xDEADBEEF "Binary string"
  APPEND_PARAMETER "Pad" 16 UINT 0 0 0
    HIDDEN
```