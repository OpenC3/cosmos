---
sidebar_position: 8
title: アクセサー
description: バッファへのデータの読み書きを担当
sidebar_custom_props:
  myEmoji: ✏️
---

アクセサーは、バッファにデータを読み書きする方法を知っている低レベルコードです。バッファデータはその後、ターゲットに送信される前にデータを変更する可能性のあるプロトコルを使用するインターフェースに書き込まれます。アクセサーは、バイナリ（CCSDS）、JSON、CBOR、XML、HTML、Protocol Buffersなどのさまざまなシリアル化形式を処理します。

アクセサーがインターフェースやプロトコルとどのように適合するかについての詳細は、[標準なしの相互運用性](https://www.openc3.com/news/interoperability-without-standards)を参照してください。

COSMOSは以下の組み込みアクセサーを提供しています：Binary、CBOR、Form、HTML、HTTP、JSON、Template、XML。

COSMOS Enterpriseは以下のアクセサーを提供しています：GEMS Ascii、Prometheus、Protocol Buffer。

### バイナリアクセサー

バイナリアクセサーは、バッファに書き込む際にデータをバイナリ形式にシリアル化します。これは、CCSDSスタンダードに従うものを含む多くのデバイスがデータを期待する方法です。COSMOSは、符号付きおよび符号なし整数、浮動小数点、文字列などをバッファ内のバイナリ表現に変換します。これにはビッグエンディアンとリトルエンディアン、ビットフィールド、可変長フィールドの処理が含まれます。バイナリは非常に一般的であるため、これはデフォルトのアクセサーであり、他のアクセサーが指定されていない場合に使用されます。

#### コマンド

```ruby
COMMAND INST COLLECT BIG_ENDIAN "Starts a collect"
  ACCESSOR BinaryAccessor # デフォルトであるため通常は明示的に定義されません
  PARAMETER TYPE       64  16  UINT MIN MAX 0 "Collect type"
  PARAMETER DURATION   80  32  FLOAT 0.0 10.0 1.0 "Collect duration"
  PARAMETER OPCODE    112   8  UINT 0x0 0xFF 0xAB "Collect opcode"
```

#### テレメトリ

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
  ACCESSOR BinaryAccessor # デフォルトであるため通常は明示的に定義されません
  APPEND_ITEM CMD_ACPT_CNT   32 UINT  "Command accept count"
  APPEND_ITEM COLLECTS       16 UINT  "Number of collects"
  APPEND_ITEM DURATION       32 FLOAT "Most recent collect duration"
```

### CBORアクセサー

Concise Binary Object Representation（[CBOR](https://en.wikipedia.org/wiki/CBOR)）アクセサーは、ゆるくJSONに基づいたバイナリ形式にデータをシリアル化します。これはJSONアクセサーのサブクラスであり、COSMOSがログファイルを保存するためにネイティブに使用するものです。

#### コマンド

[コマンド定義](command)でCBORアクセサーを使用するには、[TEMPLATE_FILE](command#template_file)と[KEY](command#key)を使用して、ユーザーがCBORデータ内の値を設定できるようにする必要があります。KEYの値は[JSONPath](https://en.wikipedia.org/wiki/JSONPath)を使用していることに注意してください。

```ruby
COMMAND CBOR CBORCMD BIG_ENDIAN "CBOR Accessor Command"
  ACCESSOR CborAccessor
  TEMPLATE_FILE _cbor_template.bin
  APPEND_ID_PARAMETER ID_ITEM 32 INT 2 2 2 "Int Item"
    KEY $.id_item
  APPEND_PARAMETER ITEM1 16 UINT MIN MAX 101 "Int Item 2"
    KEY $.item1
    UNITS CELSIUS C
  APPEND_PARAMETER ITEM2 16 UINT MIN MAX 12 "Int Item 3"
    KEY $.more.item2
    FORMAT_STRING "0x%X"
  APPEND_PARAMETER ITEM3 64 FLOAT MIN MAX 3.14 "Float Item"
    KEY $.more.item3
  APPEND_PARAMETER ITEM4 128 STRING "Example" "String Item"
    KEY $.more.item4
  APPEND_ARRAY_PARAMETER ITEM5 8 UINT 0 "Array Item"
    KEY $.more.item5
```

テンプレートファイルを作成するには、RubyまたはPythonのCBORライブラリを使用する必要があります。Rubyからの例を以下に示します：

```ruby
require 'cbor'
data = {"id_item" : 2, "item1" : 101, "more" : { "item2" : 12, "item3" : 3.14, "item4" : "Example", "item5" : [4, 3, 2, 1] } }
File.open("_cbor_template.bin", 'wb') do |file|
  file.write(data.to_cbor)
end
```

#### テレメトリ

[テレメトリ定義](telemetry)でCBORアクセサーを使用するには、[KEY](command#key)を使用してCBORデータから値を取得するだけで済みます。KEYの値は[JSONPath](https://en.wikipedia.org/wiki/JSONPath)を使用していることに注意してください。

```ruby
TELEMETRY CBOR CBORTLM BIG_ENDIAN "CBOR Accessor Telemetry"
  ACCESSOR CborAccessor
  APPEND_ID_ITEM ID_ITEM 32 INT 2 "Int Item"
    KEY $.id_item
  APPEND_ITEM ITEM1 16 UINT "Int Item 2"
    KEY $.item1
    GENERIC_READ_CONVERSION_START UINT 16
      value * 2
    GENERIC_READ_CONVERSION_END
    UNITS CELSIUS C
  APPEND_ITEM ITEM2 16 UINT "Int Item 3"
    KEY $.more.item2
    FORMAT_STRING "0x%X"
  APPEND_ITEM ITEM3 64 FLOAT "Float Item"
    KEY $.more.item3
  APPEND_ITEM ITEM4 128 STRING "String Item"
    KEY $.more.item4
  APPEND_ARRAY_ITEM ITEM5 8 UINT 0 "Array Item"
    KEY $.more.item5
```

### フォームアクセサー

フォームアクセサーは通常、[HTTPクライアント](interfaces#httpクライアントインターフェース)インターフェースで使用され、リモートHTTPサーバーにフォームを送信します。

#### コマンド

[コマンド定義](command)でフォームアクセサーを使用するには、[KEY](command#key)を使用して、ユーザーがHTTPフォーム内の値を設定できるようにする必要があります。KEYの値は[XPath](https://en.wikipedia.org/wiki/XPath)を使用していることに注意してください。

```ruby
COMMAND FORM FORMCMD BIG_ENDIAN "Form Accessor Command"
  ACCESSOR FormAccessor
  APPEND_ID_PARAMETER ID_ITEM 32 INT 2 2 2 "Int Item"
    KEY $.id_item
  APPEND_PARAMETER ITEM1 16 UINT MIN MAX 101 "Int Item 2"
    KEY $.item1
    UNITS CELSIUS C
```

#### テレメトリ

[テレメトリ定義](telemetry)でフォームアクセサーを使用するには、[KEY](command#key)を使用してHTTPレスポンスデータから値を取得するだけで済みます。KEYの値は[XPath](https://en.wikipedia.org/wiki/XPath)を使用していることに注意してください。

```ruby
TELEMETRY FORM FORMTLM BIG_ENDIAN "Form Accessor Telemetry"
  ACCESSOR FormAccessor
  APPEND_ID_ITEM ID_ITEM 32 INT 1 "Int Item"
    KEY $.id_item
  APPEND_ITEM ITEM1 16 UINT "Int Item 2"
    KEY $.item1
```

### HTMLアクセサー

HTMLアクセサーは通常、[HTTPクライアント](interfaces#httpクライアントインターフェース)インターフェースでウェブページを解析するために使用されます。

完全な例については、[openc3-cosmos-http-get](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-http-get)を参照してください。

#### コマンド

HTMLアクセサーは通常コマンドには使用されませんが、XPathキーを使用するテレメトリと同様になります。

#### テレメトリ

```ruby
TELEMETRY HTML RESPONSE BIG_ENDIAN "Search results"
  # 通常、返されるページを解析するためにHtmlAccessorを使用します
  # HtmlAccessorはHttpAccessorに渡され、内部で使用されます
  ACCESSOR HttpAccessor HtmlAccessor
  APPEND_ITEM NAME 240 STRING
    # キーは手動検索を行い、ページを調査して見つけました
    # 探しているテキストを右クリックし、コピー -> XPathをコピー
    KEY normalize-space(//main/div/a[2]/span/h2/text())
  APPEND_ITEM DESCRIPTION 480 STRING
    KEY //main/div/a[2]/span/p/text()
  APPEND_ITEM VERSION 200 STRING
    KEY //main/div/a[2]/span/h2/span/text()
  APPEND_ITEM DOWNLOADS 112 STRING
    KEY normalize-space(//main/div/a[2]/p/text())
```

### HTTPアクセサー {#http-accessor}

HTTPアクセサーは通常、[HTTPクライアント](interfaces#httpクライアントインターフェース)または[HTTPサーバー](interfaces#httpサーバーインターフェース)インターフェースでウェブページを解析するために使用されます。アイテムの低レベルの読み書きを行うために別のアクセサーを取ります。デフォルトのアクセサーはFormAccessorです。HtmlAccessor、XmlAccessor、JsonAccessorもHTML、XML、JSONをそれぞれ操作するために一般的です。

完全な例については、[openc3-cosmos-http-get](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-http-get)を参照してください。

#### コマンド

HTTPクライアントインターフェースで使用する場合、HTTPアクセサーは以下のコマンドパラメータを利用します：

| パラメータ         | 説明                                                                                                |
| ----------------- | -------------------------------------------------------------------------------------------------- |
| HTTP_PATH         | このパスでリクエスト                                                                                 |
| HTTP_METHOD       | リクエストメソッド（GET、POST、DELETE）                                                               |
| HTTP_PACKET       | レスポンスを格納するテレメトリパケット                                                                |
| HTTP_ERROR_PACKET | エラーレスポンス（ステータスコード >= 300）を格納するテレメトリパケット                               |
| HTTP_QUERY_XXX    | リクエストに渡されるパラメータに値を設定（XXX => 値、またはKEY => 値）、下の例を参照                   |
| HTTP_HEADER_XXX   | リクエストに渡されるヘッダーに値を設定（XXX => 値、またはKEY => 値）、下の例を参照                    |

HTTPサーバーインターフェースで使用する場合、HTTPアクセサーは以下のコマンドパラメータを利用します：

| パラメータ       | 説明                                                                                   |
| --------------- | ------------------------------------------------------------------------------------- |
| HTTP_STATUS     | クライアントに返すステータス                                                            |
| HTTP_PATH       | サーバーのマウントポイント                                                              |
| HTTP_PACKET     | リクエストを格納するテレメトリパケット                                                   |
| HTTP_HEADER_XXX | レスポンスヘッダーに値を設定（XXX => 値、またはKEY => 値）、下の例を参照                 |

```ruby
COMMAND HTML SEARCH BIG_ENDIAN "Searches Rubygems.org"
  # FormAccessorはHttpAccessorのデフォルト引数であるため、通常は指定されません
  ACCESSOR HttpAccessor
  PARAMETER HTTP_PATH 0 0 DERIVED nil nil "/search"
  PARAMETER HTTP_METHOD 0 0 DERIVED nil nil "GET"
  PARAMETER HTTP_PACKET 0 0 DERIVED nil nil "RESPONSE"
  PARAMETER HTTP_ERROR_PACKET 0 0 DERIVED nil nil "ERROR"
  # これはパラメータquery=openc3+cosmosを設定します
  # HTTP_QUERY_QUERYに基づいてパラメータ名「query」に注目
  PARAMETER HTTP_QUERY_QUERY 0 0 DERIVED nil nil "openc3 cosmos"
    GENERIC_READ_CONVERSION_START
      value.split.join('+')
    GENERIC_READ_CONVERSION_END
  # これはヘッダーContent-Type=text/htmlを設定します
  # KEYが指定されているためTYPEは使用されません
  PARAMETER HTTP_HEADER_TYPE 0 0 DERIVED nil nil "text/html"
    KEY Content-Type
```

#### テレメトリ

HTTPアクセサーは以下のテレメトリアイテムを利用します：

| パラメータ     | 説明                                                                                                    |
| ------------- | ------------------------------------------------------------------------------------------------------- |
| HTTP_STATUS   | リクエストステータス                                                                                     |
| HTTP_HEADERS  | レスポンスヘッダーのハッシュ                                                                             |
| HTTP_REQUEST  | すべてのリクエストパラメータを返すオプショナルハッシュ、[HTTPクライアントインターフェース](interfaces#httpクライアントインターフェース)を参照 |

```ruby
TELEMETRY HTML RESPONSE BIG_ENDIAN "Search results"
  # 通常、返されるページを解析するためにHtmlAccessorを使用します
  ACCESSOR HttpAccessor HtmlAccessor
  APPEND_ITEM NAME 240 STRING
    # キーは手動検索を行い、ページを調査して見つけました
    # 探しているテキストを右クリックし、コピー -> XPathをコピー
    KEY normalize-space(//main/div/a[2]/span/h2/text())
  APPEND_ITEM DESCRIPTION 480 STRING
    KEY //main/div/a[2]/span/p/text()
  APPEND_ITEM VERSION 200 STRING
    KEY //main/div/a[2]/span/h2/span/text()
  APPEND_ITEM DOWNLOADS 112 STRING
    KEY normalize-space(//main/div/a[2]/p/text())
```

### JSONアクセサー {#json-accessor}

JSONアクセサーは、JavaScript Object Notation（[JSON](https://en.wikipedia.org/wiki/JSON)）形式にデータをシリアル化します。JSONは、キーと値のペアや配列からなるデータを送信するために、人間が読める形式のテキストを使用するデータ交換形式です。

完全な例については、[openc3-cosmos-accessor-test](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-accessor-test)を参照してください。

#### コマンド

[コマンド定義](command)でJSONアクセサーを使用するには、[TEMPLATE](command#template)と[KEY](command#key)を使用して、ユーザーがJSONデータ内の値を設定できるようにする必要があります。KEYの値は[JSONPath](https://en.wikipedia.org/wiki/JSONPath)を使用していることに注意してください。

```ruby
COMMAND JSON JSONCMD BIG_ENDIAN "JSON Accessor Command"
  ACCESSOR JsonAccessor
  TEMPLATE '{"id_item":1, "item1":101, "more": { "item2":12, "item3":3.14, "item4":"Example", "item5":[4, 3, 2, 1] } }'
  APPEND_ID_PARAMETER ID_ITEM 32 INT 2 2 2 "Int Item"
    KEY $.id_item
  APPEND_PARAMETER ITEM1 16 UINT MIN MAX 101 "Int Item 2"
    KEY $.item1
    UNITS CELSIUS C
  APPEND_PARAMETER ITEM2 16 UINT MIN MAX 12 "Int Item 3"
    KEY $.more.item2
    FORMAT_STRING "0x%X"
  APPEND_PARAMETER ITEM3 64 FLOAT MIN MAX 3.14 "Float Item"
    KEY $.more.item3
  APPEND_PARAMETER ITEM4 128 STRING "Example" "String Item"
    KEY $.more.item4
  APPEND_ARRAY_PARAMETER ITEM5 8 UINT 0 "Array Item"
    KEY $.more.item5
```

#### テレメトリ

[テレメトリ定義](telemetry)でJSONアクセサーを使用するには、[KEY](command#key)を使用してJSONデータから値を取得するだけで済みます。KEYの値は[JSONPath](https://en.wikipedia.org/wiki/JSONPath)を使用していることに注意してください。

```ruby
TELEMETRY JSON JSONTLM BIG_ENDIAN "JSON Accessor Telemetry"
  ACCESSOR JsonAccessor
  APPEND_ID_ITEM ID_ITEM 32 INT 1 "Int Item"
    KEY $.id_item
  APPEND_ITEM ITEM1 16 UINT "Int Item 2"
    KEY $.item1
    GENERIC_READ_CONVERSION_START UINT 16
      value * 2
    GENERIC_READ_CONVERSION_END
    UNITS CELSIUS C
  APPEND_ITEM ITEM2 16 UINT "Int Item 3"
    KEY $.more.item2
    FORMAT_STRING "0x%X"
  APPEND_ITEM ITEM3 64 FLOAT "Float Item"
    KEY $.more.item3
  APPEND_ITEM ITEM4 128 STRING "String Item"
    KEY $.more.item4
  APPEND_ARRAY_ITEM ITEM5 8 UINT 0 "Array Item"
    KEY $.more.item5
```

### テンプレートアクセサー

テンプレートアクセサーは、[CmdResponseProtocol](protocols#cmdresponseプロトコル)などの文字列ベースのコマンド/レスポンスプロトコルでよく使用されます。

完全な例については、COSMOS Enterprise Pluginsの[openc3-cosmos-scpi-power-supply](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-scpi-power-supply)を参照してください。

#### コマンド

[コマンド定義](command)でテンプレートアクセサーを使用するには、[TEMPLATE](command#template)を使用して、コマンドパラメータを使用して入力されるオプションパラメータを持つ文字列テンプレートを定義する必要があります。

```ruby
# 一部のコマンドにはパラメータがなく、テンプレートがそのまま送信されます
COMMAND SCPI_PS RESET BIG_ENDIAN "Reset the power supply state"
  ACCESSOR TemplateAccessor
  TEMPLATE "*RST"

# このコマンドには<XXX>で定義された2つのパラメータがテンプレートにあります
COMMAND SCPI_PS VOLTAGE BIG_ENDIAN "Sets the voltage of a power supply channel"
  ACCESSOR TemplateAccessor
  # <VOLTAGE>と<CHANNEL>はパラメータ値に置き換えられます
  TEMPLATE "VOLT <VOLTAGE>, (@<CHANNEL>)"
  APPEND_PARAMETER VOLTAGE 32 FLOAT MIN MAX 0.0 "Voltage Setting"
    UNITS VOLTS V
  APPEND_PARAMETER CHANNEL 8 UINT 1 2 1 "Output Channel"
```

#### テレメトリ

[テレメトリ定義](telemetry)でテンプレートアクセサーを使用するには、[TEMPLATE](telemetry#template)を使用して、テレメトリ値が文字列バッファから取得されるテンプレートを定義する必要があります。

```ruby
TELEMETRY SCPI_PS STATUS BIG_ENDIAN "Power supply status"
  ACCESSOR TemplateAccessor
  # ターゲットからの生の文字列は "1.234,2.345"のようなものです
  # 文字列はカンマで分割され、MEAS_VOLTAGE_1、MEAS_VOLTAGE_2に入れられます
  TEMPLATE "<MEAS_VOLTAGE_1>,<MEAS_VOLTAGE_2>"
  APPEND_ITEM MEAS_VOLTAGE_1 32 FLOAT "Current Reading for Channel 1"
  APPEND_ITEM MEAS_VOLTAGE_2 32 FLOAT "Current Reading for Channel 2"
```

### XMLアクセサー

XMLアクセサーは通常、[HTTPクライアント](interfaces#httpクライアントインターフェース)インターフェースでウェブサーバーとXMLを送受信するために使用されます。

完全な例については、[openc3-cosmos-accessor-test](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-accessor-test)を参照してください。

#### コマンド

[コマンド定義](command)でXMLアクセサーを使用するには、[TEMPLATE](command#template)と[KEY](command#key)を使用して、ユーザーがXMLデータ内の値を設定できるようにする必要があります。KEYの値は[XPath](https://en.wikipedia.org/wiki/XPath)を使用していることに注意してください。

```ruby
COMMAND XML XMLCMD BIG_ENDIAN "XML Accessor Command"
  ACCESSOR XmlAccessor
  TEMPLATE '<html><head><script src="3"></script><noscript>101</noscript></head><body><img src="12"/><div><ul><li>3.14</li><li>Example</li></ul></div><div></div></body></html>'
  APPEND_ID_PARAMETER ID_ITEM 32 INT 3 3 3 "Int Item"
    KEY "/html/head/script/@src"
  APPEND_PARAMETER ITEM1 16 UINT MIN MAX 101 "Int Item 2"
    KEY "/html/head/noscript/text()"
    UNITS CELSIUS C
  APPEND_PARAMETER ITEM2 16 UINT MIN MAX 12 "Int Item 3"
    KEY "/html/body/img/@src"
    FORMAT_STRING "0x%X"
  APPEND_PARAMETER ITEM3 64 FLOAT MIN MAX 3.14 "Float Item"
    KEY "/html/body/div/ul/li[1]/text()"
  APPEND_PARAMETER ITEM4 128 STRING "Example" "String Item"
    KEY "/html/body/div/ul/li[2]/text()"
```

#### テレメトリ

[テレメトリ定義](telemetry)でXMLアクセサーを使用するには、[KEY](command#key)を使用してXMLデータから値を取得するだけで済みます。KEYの値は[XPath](https://en.wikipedia.org/wiki/XPath)を使用していることに注意してください。

```ruby
TELEMETRY XML XMLTLM BIG_ENDIAN "XML Accessor Telemetry"
  ACCESSOR XmlAccessor
  # テンプレートはテレメトリには必須ではありませんが、シミュレーションに役立ちます
  TEMPLATE '<html><head><script src="3"></script><noscript>101</noscript></head><body><img src="12"/><div><ul><li>3.14</li><li>Example</li></ul></div><div></div></body></html>'
  APPEND_ID_ITEM ID_ITEM 32 INT 3 "Int Item"
    KEY "/html/head/script/@src"
  APPEND_ITEM ITEM1 16 UINT "Int Item 2"
    KEY "/html/head/noscript/text()"
    GENERIC_READ_CONVERSION_START UINT 16
      value * 2
    GENERIC_READ_CONVERSION_END
    UNITS CELSIUS C
  APPEND_ITEM ITEM2 16 UINT "Int Item 3"
    KEY "/html/body/img/@src"
    FORMAT_STRING "0x%X"
  APPEND_ITEM ITEM3 64 FLOAT "Float Item"
    KEY "/html/body/div/ul/li[1]/text()"
  APPEND_ITEM ITEM4 128 STRING "String Item"
    KEY "/html/body/div/ul/li[2]/text()"
```

### GEMS Ascii (Enterprise)

GemsAsciiAccessorは[TemplateAccessor](accessors#テンプレートアクセサー)を継承して、送信コマンドの以下の文字をエスケープします：「&」=>「&a」、「|」=>「&b」、「,」=>「&c」、「;」=>「&d」、そしてテレメトリではその逆変換を行います。詳細については[GEMSの仕様](https://www.omg.org/spec/GEMS/1.3/PDF)を参照してください。

完全な例については、COSMOS Enterprise Pluginsの[openc3-cosmos-gems-interface](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-gems-interface)を参照してください。

### Prometheus (Enterprise)

PrometheusAccessorはPrometheusエンドポイントから読み取り、結果を自動的にパケットに解析することができます。PrometheusAccessorは現在Rubyでのみ実装されています。

完全な例については、COSMOS Enterprise Pluginsの[openc3-cosmos-prometheus-metrics](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-prometheus-metrics)を参照してください。

### Protocol Buffer (Enterprise)

ProtoAccessorはプロトコルバッファの読み書きに使用されます。主に[GrpcInterface](interfaces#grpc-interface-enterprise)と組み合わせて使用されます。ProtoAccessorは現在Rubyでのみ実装されています。

| パラメータ | 説明                                           | 必須 |
| --------- | ---------------------------------------------- | ---- |
| Filename  | プロトコルバッファコンパイラによって生成されたファイル | はい  |
| Class     | バッファのエンコードとデコードに使用するクラス     | はい  |

完全な例については、COSMOS Enterprise Pluginsの[openc3-cosmos-proto-target](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-proto-target)を参照してください。
