---
sidebar_position: 5
title: テレメトリ
description: テレメトリ定義ファイルの形式とキーワード
sidebar_custom_props:
  myEmoji: 📡
---

<!-- Be sure to edit _telemetry.md because telemetry.md is a generated file -->

## テレメトリ定義ファイル

テレメトリ定義ファイルは、COSMOSターゲットから受信および処理できるテレメトリパケットを定義します。テレメトリパケットを定義するために1つの大きなファイルを使用することも、ユーザーの判断で複数のファイルを使用することもできます。テレメトリ定義ファイルはターゲットのcmd_tlmディレクトリに配置され、アルファベット順に処理されます。したがって、既存のテレメトリをオーバーライドまたは拡張するなど、他のテレメトリファイルに依存するテレメトリファイルがある場合は、最後に名前を付ける必要があります。最も簡単な方法は、既存のファイル名に拡張子を追加することです。例えば、すでにtlm.txtがある場合、tlm.txtの定義に依存するテレメトリにはtlm_override.txtを作成できます。[ASCII表](http://www.asciitable.com/)の構造上、大文字で始まるファイルは小文字で始まるファイルよりも先に処理されることに注意してください。

テレメトリ項目を定義する際、以下のデータ型から選択できます：INT、UINT、FLOAT、STRING、BLOCK。これらはそれぞれ整数、符号なし整数、浮動小数点数、文字列、データのバイナリブロックに対応します。COSMOSでは、STRINGとBLOCKの唯一の違いは、COSMOSがSTRINGタイプを読み取るとき、ヌルバイト（0）に遭遇すると読み取りを停止することです。これはPacket ViewerやTlm Viewerで値を表示する際や、Data Extractorの出力に表示されます。非ASCII文字データはBLOCK項目内に、ASCII文字列はSTRING項目内に保存するよう努めてください。

:::info データの表示

ほとんどのデータ型は、COSMOSスクリプトで <code>print(tlm("TGT PKT ITEM"))</code> とするだけで表示できます。ただし、ITEMがBLOCKデータ型でバイナリ（非ASCII）データを含む場合は、これは機能しません。COSMOSにはバイナリデータを表示するための <code>formatted</code> という組み込みメソッドがあります。ITEMがバイナリを含むBLOCKタイプの場合は、<code>puts tlm("TGT PKT ITEM").formatted</code>（Ruby）や<code>print(formatted(tlm("TGT PKT ITEM")))</code>（Python）を試してください。これによりバイトが16進数として表示されます。
:::

### ID項目

すべてのパケットには識別項目が必要で、受信データをパケット構造に一致させることができます。これらの項目は[ID_ITEM](telemetry.md#id_item)と[APPEND_ID_ITEM](telemetry.md#append_id_item)を使用して定義します。データがインターフェースから読み取られ、プロトコルによって精製されると、すべてのIDフィールドを一致させることで結果のパケットが識別されます。理想的には、特定のターゲット内のすべてのパケットは、識別に全く同じビットオフセット、ビットサイズ、データ型を使用する必要があります。そうでない場合は、target.txtファイルに[TLM_UNIQUE_ID_MODE](target.md#tlm_unique_id_mode)を設定する必要がありますが、これはすべてのパケット識別でパフォーマンスペナルティが発生します。

### 可変サイズ項目

COSMOSはビットサイズが0の可変サイズ項目を指定します。パケットが識別されると、明示的に定義されていない他のすべてのデータは可変サイズ項目に格納されます。これらの項目は通常、ダンプされるバイト数に応じてサイズが変化するメモリダンプを含むパケットに使用されます。パケットごとに可変サイズの項目は1つしか存在できないことに注意してください。

### 派生項目

COSMOSには、実際にはバイナリデータに存在しないテレメトリ項目である派生項目の概念があります。派生項目は通常、他のテレメトリ項目に基づいて計算されます。COSMOS派生項目は実際の項目と非常に似ていますが、特別なDERIVEDデータ型を使用します。テレメトリ定義での派生項目の例を以下に示します。

```ruby
ITEM TEMP_AVERAGE 0 0 DERIVED "Average of TEMP1, TEMP2, TEMP3, TEMP4"
```

ビットオフセットとビットサイズが0で、データ型がDERIVEDであることに注意してください。このため、派生項目はAPPEND_ITEMではなくITEMを使用して宣言する必要があります。派生項目はパケット定義のどこにでも定義できますが、通常は末尾に配置されます。ITEM定義の後には、値を生成するための[READ_CONVERSION](telemetry.md#read_conversion)などの変換キーワードが続く必要があります。

### 受信時間とパケット時間

COSMOSは自動的にすべてのパケットに以下のテレメトリ項目を作成します：PACKET_TIMESECONDS、PACKET_TIMEFORMATTED、RECEIVED_COUNT、RECEIVED_TIMEFORMATTED、RECEIVED_TIMESECONDS。

RECEIVED_TIMEはCOSMOSがパケットを受信した時間です。これはターゲットに接続し、生データを受信しているインターフェースによって設定されます。生データからパケットが作成されると、時間が設定されます。

PACKET_TIMEはデフォルトでRECEIVED_TIMEですが、テレメトリ設定ファイルで時間オブジェクトを持つ派生項目として設定できます。これは保存されたテレメトリパケットをサポートし、Telemetry GrapherやData Extractorなどの他のCOSMOSツールでより合理的に処理できるようにします。インターフェースに「stored」フラグを設定すると、現在の値テーブルに影響はありません。

\_TIMEFORMATTED項目は日付と時刻をYYYY/MM/DD HH:MM:SS.sss形式で返し、\_TIMESECONDSは時間のUnix秒を返します。内部的には、これらはどちらもRuby TimeオブジェクトまたはPython dateオブジェクトとして格納されています。

#### 例

COSMOSは、Unix epochからの秒数と（オプションで）マイクロ秒に基づいてRuby TimeオブジェクトまたはPython dateオブジェクトを返すUnix時間変換クラスを提供します。注意：これはfloatや文字列ではなく、ネイティブオブジェクトを返します！

Rubyの例：

```ruby
ITEM PACKET_TIME 0 0 DERIVED "Ruby time based on TIMESEC and TIMEUS"
    READ_CONVERSION unix_time_conversion.rb TIMESEC TIMEUS
```

Pythonの例：

```python
ITEM PACKET_TIME 0 0 DERIVED "Python time based on TIMESEC and TIMEUS"
    READ_CONVERSION openc3/conversions/unix_time_conversion.py TIMESEC TIMEUS
```

PACKET_TIMEを定義することで、COSMOSがパケットを受信した時間ではなく、内部パケット時間に対してPACKET_TIMESECONDSとPACKET_TIMEFORMATTEDを計算できるようになります。

<div style={{"clear": 'both'}}></div>

# テレメトリキーワード


## TELEMETRY
**新しいテレメトリパケットを定義します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target | このテレメトリパケットに関連付けられたターゲットの名前 | はい |
| Command | このテレメトリパケットの名前。ニーモニックとも呼ばれます。このターゲット内のテレメトリパケットに対して一意である必要があります。理想的には短く明確であるべきです。 | はい |
| Endianness | このパケット内のデータがビッグエンディアンかリトルエンディアン形式かを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | はい |
| Description | このテレメトリパケットの説明（引用符で囲む必要があります） | いいえ |

使用例：
```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Instrument health and status"
```

## TELEMETRY Modifiers
以下のキーワードはTELEMETRYキーワードの後に続く必要があります。

### ITEM
**現在のテレメトリパケット内のテレメトリ項目を定義します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | テレメトリ項目の名前。パケット内で一意である必要があります。 | はい |
| Bit Offset | この項目の最上位ビットのテレメトリパケットへのビットオフセット。パケットの末尾からのオフセットを示すために負の値を使用できます。派生項目には常にビットオフセット0を使用します。 | はい |
| Bit Size | このテレメトリ項目のビットサイズ。ゼロまたは負の値を使用して、文字列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。ビットオフセットが0でビットサイズが0の場合、これは派生パラメータであり、データ型は「DERIVED」に設定する必要があります。 | はい |
| Data Type | このテレメトリ項目のデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, DERIVED</span> | はい |
| Description | このテレメトリ項目の説明（引用符で囲む必要があります） | いいえ |
| Endianness | 項目をビッグエンディアンまたはリトルエンディアン形式で解釈するかどうかを示します。[リトルエンディアンビットフィールド](../guides/little-endian-bitfields.md)のガイドを参照してください。<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | いいえ |

使用例：
```ruby
ITEM PKTID 112 16 UINT "Packet ID"
ITEM DATA 0 0 DERIVED "Derived data"
```

### ITEM Modifiers
以下のキーワードはITEMキーワードの後に続く必要があります。

#### FORMAT_STRING
**printf形式のフォーマットを追加します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Format | printf構文を使用してフォーマットする方法。例えば、「0x%0X」は値を16進数で表示します。 | はい |

使用例：
```ruby
FORMAT_STRING "0x%0X"
```

#### UNITS
**表示単位を追加します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Full Name | 単位タイプのフルネーム（例：摂氏） | はい |
| Abbreviated | 単位の略語（例：C） | はい |

使用例：
```ruby
UNITS Celsius C
UNITS Kilometers KM
```

#### DESCRIPTION
**定義された説明を上書きします**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Value | 新しい説明 | はい |

#### META
**カスタムユーザーメタデータを格納します**

メタデータは、カスタムツールがさまざまな目的で使用できるユーザー固有のデータです。一例として、ソースコードヘッダーファイルを生成するために必要な追加情報を保存することができます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Meta Name | 保存するメタデータの名前 | はい |
| Meta Values | このMeta Nameに保存される1つ以上の値 | いいえ |

使用例：
```ruby
META TEST "This parameter is for test purposes only"
```

#### OVERLAP
<div class="right">(Since 4.4.1)</div>**この項目はパケット内の他の項目と重複することが許可されています**

項目のビットオフセットが別の項目と重複する場合、OpenC3は警告を発します。このキーワードは明示的に項目が別の項目と重複することを許可し、警告メッセージを抑制します。


#### KEY
<div class="right">(Since 5.0.10)</div>**パケット内の生の値にアクセスするために使用されるキーを定義します。**

キーは多くの場合、[JSONPath](https://en.wikipedia.org/wiki/JSONPath)や[XPath](https://en.wikipedia.org/wiki/XPath)文字列です

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Key string | この項目にアクセスするためのキー | はい |

使用例：
```ruby
KEY $.book.title
```

#### VARIABLE_BIT_SIZE
<div class="right">(Since 5.18.0)</div>**項目のビットサイズが別の長さ項目によって定義されていることを示します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Length Item Name | 関連する長さ項目の名前 | はい |
| Length Bits Per Count | 長さ項目のカウントあたりのビット数。デフォルトは8 | いいえ |
| Length Value Bit Offset | 長さフィールド値に適用するビットオフセット。デフォルトは0 | いいえ |

#### STATE
**現在の項目のキー/値ペアを定義します**

キー/値ペアにより、ユーザーフレンドリーな文字列が可能になります。例えば、ON = 1およびOFF = 0の状態を定義することができます。これにより、テレメトリ項目を送信する際に数字の1ではなく単語「ON」を使用でき、明確さが大幅に向上し、ユーザーエラーの可能性が低減します。ANYのキャッチオール値は、すでに状態値として定義されていない他のすべての値に適用されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Key | 文字列状態名 | はい |
| Value | 数値状態値、またはANYですべての他の値に状態を適用 | はい |
| Color | 状態が表示される色<br/><br/>有効な値: <span class="values">GREEN, YELLOW, RED</span> | いいえ |

使用例：
```ruby
APPEND_ITEM ENABLE 32 UINT "Enable setting"
  STATE FALSE 0
  STATE TRUE 1
  STATE ERROR ANY # 他のすべての値をERRORに一致させる
APPEND_ITEM STRING 1024 STRING "String"
  STATE "NOOP" "NOOP" GREEN
  STATE "ARM LASER" "ARM LASER" YELLOW
  STATE "FIRE LASER" "FIRE LASER" RED
```

#### READ_CONVERSION
**現在のテレメトリ項目に変換を適用します**

変換はターゲットのlibフォルダに配置されたカスタムRubyまたはPythonファイルで実装されます。クラスはConversionを継承する必要があります。追加パラメータを取る場合は `initialize`（Ruby）または `__init__`（Python）メソッドを実装する必要があり、常に `call` メソッドを実装する必要があります。変換係数は、テレメトリパケット内の生の値にユーザーに表示される前に適用されます。ユーザーは詳細ダイアログで生の未変換値を見ることができます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Class Filename | RubyまたはPythonクラスを含むファイル名。ファイル名はクラスに合わせて名付ける必要があり、クラスはアンダースコア付きファイル名のCamelCase版である必要があります。例えば、「the_great_conversion.rb」には「class TheGreatConversion」が含まれている必要があります。 | はい |
| Parameter | 変換のための追加パラメータ値。クラスコンストラクタに渡されます。 | いいえ |

Rubyの例：
```ruby
READ_CONVERSION the_great_conversion.rb 1000

Defined in the_great_conversion.rb:

require 'openc3/conversions/conversion'
module OpenC3
  class TheGreatConversion < Conversion
    def initialize(multiplier)
      super()
      @multiplier = multiplier.to_f
    end
    def call(value, packet, buffer)
      return value * @multiplier
    end
  end
end
```

Pythonの例：
```python
READ_CONVERSION the_great_conversion.py 1000

Defined in the_great_conversion.py:

from openc3.conversions.conversion import Conversion
class TheGreatConversion(Conversion):
    def __init__(self, multiplier):
        super().__init__()
        self.multiplier = float(multiplier)
    def call(self, value, packet, buffer):
        return value * self.multiplier
```

#### POLY_READ_CONVERSION
**現在のテレメトリ項目に多項式変換係数を追加します**

変換係数は、テレメトリパケット内の生の値にユーザーに表示される前に適用されます。ユーザーは詳細ダイアログで生の未変換値を見ることができます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| C0 | 係数 | はい |
| Cx | 変換のための追加係数値。任意の次数の多項式変換が使用できるため、「x」の値は多項式の次数によって異なります。高次の多項式は低次の多項式よりも処理に時間がかかりますが、より正確な場合があります。 | いいえ |

使用例：
```ruby
POLY_READ_CONVERSION 10 0.5 0.25
```

#### SEG_POLY_READ_CONVERSION
**現在のテレメトリ項目にセグメント化された多項式変換係数を追加します**

この変換係数は、テレメトリパケット内の生の値にユーザーに表示される前に適用されます。ユーザーは詳細ダイアログで生の未変換値を見ることができます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Lower Bound | このセグメント化された多項式が適用される値の範囲の下限を定義します。最小の下限を持つセグメントでは無視されます。 | はい |
| C0 | 係数 | はい |
| Cx | 変換のための追加係数値。任意の次数の多項式変換が使用できるため、「x」の値は多項式の次数によって異なります。高次の多項式は低次の多項式よりも処理に時間がかかりますが、より正確な場合があります。 | いいえ |

使用例：
```ruby
SEG_POLY_READ_CONVERSION 0 10 0.5 0.25 # すべての値 < 50 に変換を適用
SEG_POLY_READ_CONVERSION 50 11 0.5 0.275 # すべての値 >= 50 かつ < 100 に変換を適用
SEG_POLY_READ_CONVERSION 100 12 0.5 0.3 # すべての値 >= 100 に変換を適用
```

#### GENERIC_READ_CONVERSION_START
**一般的な読み取り変換を開始します**

現在のテレメトリ項目に一般的な変換関数を追加します。この変換係数は、テレメトリパケット内の生の値にユーザーに表示される前に適用されます。ユーザーは詳細ダイアログで生の未変換値を見ることができます。変換はRubyまたはPythonコードとして指定され、2つの暗黙的なパラメータを受け取ります。「value」は読み取られる生の値、「packet」はテレメトリパケットクラスへの参照です（注：後方互換性のためにパケットを「myself」として参照することもサポートされています）。コードの最後の行は変換された値を返す必要があります。GENERIC_READ_CONVERSION_ENDキーワードは、変換のためのすべてのコード行が与えられたことを指定します。

:::warning
一般的な変換は長期的なソリューションとしては良くありません。変換クラスを作成して代わりにREAD_CONVERSIONを使用することを検討してください。READ_CONVERSIONはデバッグが容易で、パフォーマンスが高いです。
:::

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Converted Type | 変換された値の型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, STRING, BLOCK</span> | いいえ |
| Converted Bit Size | 変換された値のビットサイズ | いいえ |

Rubyの例：
```ruby
APPEND_ITEM ITEM1 32 UINT
  GENERIC_READ_CONVERSION_START
    return (value * 1.5).to_i # スケールファクターで値を変換
  GENERIC_READ_CONVERSION_END
```

Pythonの例：
```python
APPEND_ITEM ITEM1 32 UINT
  GENERIC_READ_CONVERSION_START
    return int(value * 1.5) # スケールファクターで値を変換
  GENERIC_READ_CONVERSION_END
```

#### GENERIC_READ_CONVERSION_END
**一般的な読み取り変換を完了します**


#### LIMITS
**テレメトリ項目の制限セットを定義します**

制限に違反した場合、項目が制限を超えたことを示すメッセージがCommand and Telemetry Serverに表示されます。他のツールもこの情報を使用して、異なる色のテレメトリ項目や他の有用な情報でディスプレイを更新します。「制限セット」の概念は、異なる環境で異なる制限値を持つことができるように定義されています。例えば、熱真空試験中など、環境が変化した場合に、テレメトリに対するより厳しいまたはより緩い制限を設定したい場合があります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Limits Set | 制限セットの名前。固有の制限セットがない場合は、キーワードDEFAULTを使用します。 | はい |
| Persistence | テレメトリ項目が制限状態を変更する前に、異なる制限範囲内である必要がある連続回数。 | はい |
| Initial State | このテレメトリ項目の制限監視が最初に有効か無効かを示します。複数のLIMITS項目がある場合、すべて同じ初期状態であるべきことに注意してください。<br/><br/>有効な値: <span class="values">ENABLED, DISABLED</span> | はい |
| Red Low Limit | テレメトリ値がこの値以下の場合、Red Low状態が検出されます | はい |
| Yellow Low Limit | テレメトリ値がこの値以下で、Red Low Limitより大きい場合、Yellow Low状態が検出されます | はい |
| Yellow High Limit | テレメトリ値がこの値以上で、Red High Limitより小さい場合、Yellow High状態が検出されます | はい |
| Red High Limit | テレメトリ値がこの値以上の場合、Red High状態が検出されます | はい |
| Green Low Limit | Green LowとGreen High制限を設定すると、OpenC3で青色表示される「運用制限」が定義されます。これにより、緑の安全制限よりも狭い、望ましい運用範囲を区別できます。テレメトリ値がこの値以上で、Green High Limitより小さい場合、青い運用状態が検出されます。 | いいえ |
| Green High Limit | Green LowとGreen High制限を設定すると、OpenC3で青色表示される「運用制限」が定義されます。これにより、緑の安全制限よりも狭い、望ましい運用範囲を区別できます。テレメトリ値がこの値以下で、Green Low Limitより大きい場合、青い運用状態が検出されます。 | いいえ |

使用例：
```ruby
LIMITS DEFAULT 3 ENABLED -80.0 -70.0 60.0 80.0 -20.0 20.0
LIMITS TVAC 3 ENABLED -80.0 -30.0 30.0 80.0
```

#### LIMITS_RESPONSE
**現在の項目の制限状態が変化したときに呼び出される応答クラスを定義します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Response Class Filename | 制限応答を実装するRubyまたはPythonファイルの名前。このファイルはターゲットのlibディレクトリにある必要があります。 | はい |
| Response Specific Options | クラスコンストラクタに渡される変数長のオプション | いいえ |

Rubyの例：
```ruby
LIMITS_RESPONSE example_limits_response.rb 10
```

Pythonの例：
```python
LIMITS_RESPONSE example_limits_response.py 10
```

### APPEND_ITEM
**現在のテレメトリパケット内のテレメトリ項目を定義します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | テレメトリ項目の名前。パケット内で一意である必要があります。 | はい |
| Bit Size | このテレメトリ項目のビットサイズ。ゼロまたは負の値を使用して、文字列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。ビットオフセットが0でビットサイズが0の場合、これは派生パラメータであり、データ型は「DERIVED」に設定する必要があります。 | はい |
| Data Type | このテレメトリ項目のデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, DERIVED</span> | はい |
| Description | このテレメトリ項目の説明（引用符で囲む必要があります） | いいえ |
| Endianness | 項目をビッグエンディアンまたはリトルエンディアン形式で解釈するかどうかを示します。[リトルエンディアンビットフィールド](../guides/little-endian-bitfields.md)のガイドを参照してください。<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | いいえ |

使用例：
```ruby
APPEND_ITEM PKTID 16 UINT "Packet ID"
```

### ID_ITEM
**現在のテレメトリパケット内のテレメトリ項目を定義します。注意：1つ以上のID_ITEMなしで定義されたパケットは、すべての受信データに一致する「キャッチオール」パケットです。通常、これはUNKNOWNパケットの役割です。**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | テレメトリ項目の名前。パケット内で一意である必要があります。 | はい |
| Bit Offset | この項目の最上位ビットのテレメトリパケットへのビットオフセット。パケットの末尾からのオフセットを示すために負の値を使用できます。 | はい |
| Bit Size | このテレメトリ項目のビットサイズ。ゼロまたは負の値を使用して、文字列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。 | はい |
| Data Type | このテレメトリ項目のデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, STRING, BLOCK</span> | はい |
| ID Value | このテレメトリパケットを一意に識別するこのテレメトリ項目の値 | はい |
| Description | このテレメトリ項目の説明（引用符で囲む必要があります） | いいえ |
| Endianness | 項目をビッグエンディアンまたはリトルエンディアン形式で解釈するかどうかを示します。[リトルエンディアンビットフィールド](../guides/little-endian-bitfields.md)のガイドを参照してください。<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | いいえ |

使用例：
```ruby
ID_ITEM PKTID 112 16 UINT 1 "Packet ID which must be 1"
```

### APPEND_ID_ITEM
**現在のテレメトリパケット内のテレメトリ項目を定義します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | テレメトリ項目の名前。パケット内で一意である必要があります。 | はい |
| Bit Size | このテレメトリ項目のビットサイズ。ゼロまたは負の値を使用して、文字列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。 | はい |
| Data Type | このテレメトリ項目のデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, STRING, BLOCK</span> | はい |
| ID Value | このテレメトリパケットを一意に識別するこのテレメトリ項目の値 | はい |
| Description | このテレメトリ項目の説明（引用符で囲む必要があります） | いいえ |
| Endianness | 項目をビッグエンディアンまたはリトルエンディアン形式で解釈するかどうかを示します。[リトルエンディアンビットフィールド](../guides/little-endian-bitfields.md)のガイドを参照してください。<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | いいえ |

使用例：
```ruby
APPEND_ID_ITEM PKTID 16 UINT 1 "Packet ID which must be 1"
```

### ARRAY_ITEM
**配列である現在のテレメトリパケット内のテレメトリ項目を定義します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | テレメトリ項目の名前。パケット内で一意である必要があります。 | はい |
| Bit Offset | この項目の最上位ビットのテレメトリパケットへのビットオフセット。パケットの末尾からのオフセットを示すために負の値を使用できます。派生項目には常にビットオフセット0を使用します。 | はい |
| Item Bit Size | 各配列項目のビットサイズ | はい |
| Item Data Type | 各配列項目のデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, DERIVED</span> | はい |
| Array Bit Size | 配列の合計ビットサイズ。ゼロまたは負の値を使用して、配列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。 | はい |
| Description | 説明（引用符で囲む必要があります） | いいえ |
| Endianness | データをビッグエンディアンまたはリトルエンディアン形式で送信するかどうかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | いいえ |

使用例：
```ruby
ARRAY_ITEM ARRAY 64 32 FLOAT 320 "Array of 10 floats"
```

### APPEND_ARRAY_ITEM
**配列である現在のテレメトリパケット内のテレメトリ項目を定義します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Name | テレメトリ項目の名前。パケット内で一意である必要があります。 | はい |
| Item Bit Size | 各配列項目のビットサイズ | はい |
| Item Data Type | 各配列項目のデータ型<br/><br/>有効な値: <span class="values">INT, UINT, FLOAT, STRING, BLOCK, DERIVED</span> | はい |
| Array Bit Size | 配列の合計ビットサイズ。ゼロまたは負の値を使用して、配列がこの値で指定されたパケットの末尾からのオフセットまでパケットを埋めることを示すことができます。 | はい |
| Description | 説明（引用符で囲む必要があります） | いいえ |
| Endianness | データをビッグエンディアンまたはリトルエンディアン形式で送信するかどうかを示します<br/><br/>有効な値: <span class="values">BIG_ENDIAN, LITTLE_ENDIAN</span> | いいえ |

使用例：
```ruby
APPEND_ARRAY_ITEM ARRAY 32 FLOAT 320 "Array of 10 floats"
```

### SELECT_ITEM
**編集のために既存のテレメトリ項目を選択します**

パケットを最初に選択するためにSELECT_TELEMETRYと併用する必要があります。通常、生成された値をオーバーライドしたり、複数回使用されるターゲットの特定のインスタンスにのみ影響するテレメトリに特定の変更を加えたりするために使用されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Item | 変更するために選択する項目の名前 | はい |

使用例：
```ruby
SELECT_TELEMETRY INST HEALTH_STATUS
  SELECT_ITEM TEMP1
    # この項目の制限を定義し、既存のものをオーバーライドまたは置換します
    LIMITS DEFAULT 3 ENABLED -90.0 -80.0 80.0 90.0 -20.0 20.0
```

### DELETE_ITEM
<div class="right">(Since 4.4.1)</div>**パケット定義から既存のテレメトリ項目を削除します**

パケット定義から項目を削除しても、その項目のための定義されたスペースは削除されません。したがって、新しい項目を再定義しない限り、データにアクセスできない「穴」がパケットに残ります。SELECT_TELEMETRYを使用し、その後ITEMを使用して新しい項目を定義できます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Item | 削除する項目の名前 | はい |

使用例：
```ruby
SELECT_TELEMETRY INST HEALTH_STATUS
  DELETE_ITEM TEMP4
```

### META
**現在のテレメトリパケットのメタデータを格納します**

メタデータは、カスタムツールがさまざまな目的で使用できるユーザー固有のデータです。一例として、ソースコードヘッダーファイルを生成するために必要な追加情報を保存することができます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Meta Name | 保存するメタデータの名前 | はい |
| Meta Values | このMeta Nameに保存される1つ以上の値 | いいえ |

使用例：
```ruby
META FSW_TYPE "struct tlm_packet"
```

### PROCESSOR
**パケットが受信されるたびにコードを実行するプロセッサクラスを定義します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Processor Name | プロセッサの名前 | はい |
| Processor Class Filename | プロセッサを実装するRubyまたはPythonファイルの名前。このファイルはターゲットのlibディレクトリにある必要があります。 | はい |
| Processor Specific Options | クラスコンストラクタに渡される変数長のオプション。 | いいえ |

Rubyの例：
```ruby
PROCESSOR TEMP1HIGH watermark_processor.rb TEMP1
```

Pythonの例：
```python
PROCESSOR TEMP1HIGH watermark_processor.py TEMP1
```

### ALLOW_SHORT
**定義された長さより短いテレメトリパケットを処理します**

テレメトリパケットが定義されたサイズよりも小さいデータ部分を持っていても警告なしに受信できるようにします。パケット内の余分なスペースはOpenC3によってゼロで埋められます。


### HIDDEN
**このテレメトリパケットをすべてのOpenC3ツールから非表示にします**

このパケットはPacket Viewer、Telemetry Grapher、Handbook Creatorに表示されません。また、スクリプトを書く際にScript Runnerのポップアップヘルパーにもこのテレメトリが表示されなくなります。テレメトリはシステム内に存在し、スクリプトによって受信およびチェックできます。


### ACCESSOR
<div class="right">(Since 5.0.10)</div>**パケットから生の値を読み書きするために使用されるクラスを定義します**

パケットから生の値を読み取るために使用されるクラスを定義します。デフォルトはBinaryAccessorです。詳細については[アクセサ](accessors)を参照してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Accessor Class Name | アクセサクラスの名前 | はい |

### TEMPLATE
<div class="right">(Since 5.0.10)</div>**文字列バッファからテレメトリ値を取得するために使用されるテンプレート文字列を定義します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Template | 引用符で囲まれるべきテンプレート文字列 | はい |

### TEMPLATE_FILE
<div class="right">(Since 5.0.10)</div>**文字列バッファからテレメトリ値を取得するために使用されるテンプレートファイルを定義します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Template File Path | テンプレートファイルへの相対パス。ファイル名は一般的にアンダースコアで始まるべきです。 | はい |

### IGNORE_OVERLAP
<div class="right">(Since 5.16.0)</div>**重複するパケット項目を無視します**

重複するパケット項目は通常、各項目がOVERLAPキーワードを持っていない限り警告を生成します。これはパケット全体で重複を無視します。


### VIRTUAL
<div class="right">(Since 5.18.0)</div>**このパケットを仮想としてマークし、識別に参加しないようにします**

与えられたパケットの項目の構造として使用できるパケット定義に使用されます。


## SELECT_TELEMETRY
**編集のために既存のテレメトリパケットを選択します**

通常、元のテレメトリが定義されている場所とは別の設定ファイルで使用され、既存のテレメトリ定義をオーバーライドまたは追加します。個々の項目を変更するにはSELECT_ITEMと併用する必要があります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | このテレメトリパケットに関連付けられたターゲットの名前 | はい |
| Packet Name | 選択するテレメトリパケットの名前 | はい |

使用例：
```ruby
SELECT_TELEMETRY INST HEALTH_STATUS
  SELECT_ITEM TEMP1
    # この項目の制限を定義し、既存のものをオーバーライドまたは置換します
    LIMITS DEFAULT 3 ENABLED -90.0 -80.0 80.0 90.0 -20.0 20.0
```

## LIMITS_GROUP
**関連する制限項目のグループを定義します**

制限グループには、一緒に有効または無効にできるテレメトリ項目が含まれています。例えば特定のサブシステムが電源投入されたときに有効または無効にできるサブシステムとして関連する制限をグループ化するために使用できます。グループを有効にするには、Script Runnerでenable_limits_group("NAME")メソッドを呼び出します。グループを無効にするには、Script Runnerでdisable_limits_group("NAME")を呼び出します。項目は複数のグループに属することができますが、最後に有効または無効にされたグループが「勝ち」ます。例えば、項目がGROUP1とGROUP2に属していて、最初にGROUP1を有効にし、次にGROUP2を無効にすると、項目は無効になります。その後、再びGROUP1を有効にすると、項目は有効になります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Group Name | 制限グループの名前 | はい |

## LIMITS_GROUP_ITEM
**指定されたテレメトリ項目を最後に定義されたLIMITS_GROUPに追加します**

制限グループ情報は通常、config/TARGET/cmd_tlmフォルダ内の別の設定ファイル（limits_groups.txt）に保管されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Target Name | ターゲットの名前 | はい |
| Packet Name | パケットの名前 | はい |
| Item Name | グループに追加するテレメトリ項目の名前 | はい |

使用例：
```ruby
LIMITS_GROUP SUBSYSTEM
  LIMITS_GROUP_ITEM INST HEALTH_STATUS TEMP1
  LIMITS_GROUP_ITEM INST HEALTH_STATUS TEMP2
  LIMITS_GROUP_ITEM INST HEALTH_STATUS TEMP3
```


## 例ファイル

**例ファイル: TARGET/cmd_tlm/tlm.txt**

<!-- prettier-ignore -->
```ruby
TELEMETRY TARGET HS BIG_ENDIAN "Health and Status for My Target"
  ITEM CCSDSVER 0 3 UINT "CCSDS PACKET VERSION NUMBER (SEE CCSDS 133.0-B-1)"
  ITEM CCSDSTYPE 3 1 UINT "CCSDS PACKET TYPE (COMMAND OR TELEMETRY)"
    STATE TLM 0
    STATE CMD 1
  ITEM CCSDSSHF 4 1 UINT "CCSDS SECONDARY HEADER FLAG"
    STATE FALSE 0
    STATE TRUE 1
  ID_ITEM CCSDSAPID 5 11 UINT 102 "CCSDS APPLICATION PROCESS ID"
  ITEM CCSDSSEQFLAGS 16 2 UINT "CCSDS SEQUENCE FLAGS"
    STATE FIRST 0
    STATE CONT 1
    STATE LAST 2
    STATE NOGROUP 3
  ITEM CCSDSSEQCNT 18 14 UINT "CCSDS PACKET SEQUENCE COUNT"
  ITEM CCSDSLENGTH 32 16 UINT "CCSDS PACKET DATA LENGTH"
  ITEM CCSDSDAY 48 16 UINT "DAYS SINCE EPOCH (JANUARY 1ST, 1958, MIDNIGHT)"
  ITEM CCSDSMSOD 64 32 UINT "MILLISECONDS OF DAY (0 - 86399999)"
  ITEM CCSDSUSOMS 96 16 UINT "MICROSECONDS OF MILLISECOND (0-999)"
  ITEM ANGLEDEG 112 16 INT "Instrument Angle in Degrees"
    POLY_READ_CONVERSION 0 57.295
  ITEM MODE 128 8 UINT "Instrument Mode"
    STATE NORMAL 0 GREEN
    STATE DIAG 1 YELLOW
  ITEM TIMESECONDS 0 0 DERIVED "DERIVED TIME SINCE EPOCH IN SECONDS"
    GENERIC_READ_CONVERSION_START FLOAT 32
      ((packet.read('ccsdsday') * 86400.0) + (packet.read('ccsdsmsod') / 1000.0) + (packet.read('ccsdsusoms') / 1000000.0)  )
    GENERIC_READ_CONVERSION_END
  ITEM TIMEFORMATTED 0 0 DERIVED "DERIVED TIME SINCE EPOCH AS A FORMATTED STRING"
    GENERIC_READ_CONVERSION_START STRING 216
      time = Time.ccsds2mdy(packet.read('ccsdsday'), packet.read('ccsdsmsod'), packet.read('ccsdsusoms'))
      sprintf('%04u/%02u/%02u %02u:%02u:%02u.%06u', time[0], time[1], time[2], time[3], time[4], time[5], time[6])
    GENERIC_READ_CONVERSION_END
```