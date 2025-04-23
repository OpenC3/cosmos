---
sidebar_position: 1
title: ファイル形式
description: ERBの使用を含むCOSMOSファイルの構造
---

COSMOSの設定ファイルは単なるテキストファイルです。これらは構成管理システムにチェックインすべきであり、そのため履歴全体を通じて簡単に差分を確認することができます。これらはERB構文、パーシャル、さまざまな行継続をサポートしており、非常に柔軟性があります。

## キーワード / パラメータ

COSMOSの設定ファイルの各行には、単一のキーワードとそれに続くパラメータが含まれています。例えば：

```ruby
COMMAND TARGET COLLECT BIG_ENDIAN "Collect command"
```

キーワードは`COMMAND`で、パラメータは`TARGET`、`COLLECT`、`BIG_ENDIAN`、および`"Collect command"`です。キーワードはCOSMOSによって解析され、パラメータの有効性がチェックされます。パラメータは必須または任意ですが、必須パラメータは常に最初に来ます。いくつかのパラメータには有効な値の限定セットがあります。例えば、上記の`COMMAND`キーワードには以下のドキュメントがあります：

| パラメータ  | 説明                                                                                                                             | 必須 |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------- | ---- |
| Target      | このコマンドが関連するターゲットの名前                                                                                           | True |
| Command     | このコマンドの名前。ニーモニックとも呼ばれます。このターゲットへのコマンドに対して一意である必要があります。できるだけ短く明確であることが理想的です。 | True |
| Endianness  | このコマンド内のデータがビッグエンディアンまたはリトルエンディアン形式で送信されるかを示します<br/><br/>有効な値: `BIG_ENDIAN, LITTLE_ENDIAN` | True |
| Description | 引用符で囲む必要があるこのコマンドの説明                                                                                         | False |

TargetとCommandのパラメータは任意の文字列であり、必須です。Endiannessパラメータは必須で、`BIG_ENDIAN`または`LITTLE_ENDIAN`である必要があります。他の値は解析時にエラーを引き起こします。Descriptionパラメータは引用符で囲む必要があり、任意です。すべてのCOSMOS設定ファイルはこの方法でキーワードとパラメータを文書化しています。さらに、上記の例のような使用例も提供されています。

## ERB

ERBはEmbedded Rubyの略です。[ERB](https://github.com/ruby/erb)はRuby用のテンプレートシステムで、Rubyのロジックと変数を使用してテキストファイルを生成することができます。ERBには2つの基本的な形式があります：

```erb
<% Rubyコード -- 出力なし %>
<%= Ruby式 -- 結果を挿入 %>
```

COSMOS [Telemetry](telemetry.md)設定ファイルでは、次のように記述できます：

```erb
<% (1..5).each do |i| %>
  APPEND_ITEM VALUE<%= i %> 16 UINT "Value <%= i %> setting"
<% end %>
```

最初の行は、1から5までを繰り返し、その値を変数iに格納するRubyコードです。ブロック内のコードは、反復が実行されるたびにファイルに出力されます。APPEND_ITEM行は、`<%=`構文を使用してiの値を使用し、直接ファイルに出力します。解析結果は次のようになります：

```ruby
APPEND_ITEM VALUE1 16 UINT "Value 1 setting"
APPEND_ITEM VALUE2 16 UINT "Value 2 setting"
APPEND_ITEM VALUE3 16 UINT "Value 3 setting"
APPEND_ITEM VALUE4 16 UINT "Value 4 setting"
APPEND_ITEM VALUE5 16 UINT "Value 5 setting"
```

COSMOSはプラグインの[plugin.txt](plugins.md#plugintxt-configuration-file)設定ファイルでERB構文を広範囲に使用しています。

### render

COSMOSはERB内で使用される`render`というメソッドを提供しており、これは設定ファイルを別の設定ファイルにレンダリングします。例えば：

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
  <%= render "_ccsds_apid.txt", locals: {apid: 1} %>
  APPEND_ITEM COLLECTS     16 UINT   "Number of collects"
  ...
```

renderメソッドは、最上位ファイルに注入する設定ファイルの名前をパラメータとして取ります。このファイルは通常の設定ファイルとして処理されるのを避けるために、アンダースコアで始まる必要があります。このファイルはより大きなファイルの一部であるため、パーシャルと呼ばれています。例えば、\_ccsds_apid.txtは次のように定義されています：

```ruby
  APPEND_ID_ITEM CCSDSAPID 11 UINT <%= apid %> "CCSDS application process id"
```

これにより、出力は次のようになります：

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
  APPEND_ID_ITEM CCSDSAPID 11 UINT 1 "CCSDS application process id"
  APPEND_ITEM COLLECTS     16 UINT   "Number of collects"
  ...
```

`locals:`構文を使用して変数`apid`が1に設定されていることに注意してください。これは、すべてのパケット定義に共通のヘッダーとフッターを追加するための非常に強力な方法です。より包括的な例については、[Demo](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST/cmd_tlm)のINSTターゲットのcmd_tlm定義を参照してください。

## 行継続

COSMOSは設定ファイルで行継続文字をサポートしています。単純な行継続にはアンパサンド文字`&`を使用します。例えば：

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN &
  "Health and status"
```

これによりアンパサンド文字が削除され、2行が結合されて次のようになります：

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
```

2行目の周りのスペースは削除されるため、インデントは重要ではありません。

## 文字列連結

COSMOSは設定ファイルで2つの異なる文字列連結文字をサポートしています。改行付きで文字列を連結するには、プラス文字：`+`を使用します。例えば：

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status" +
  "Additional description"
```

文字列は改行付きで結合され、次のようになります：

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status\nAdditional description"
```

改行なしで文字列を連結するには、バックスラッシュ文字：`\`を使用します。例えば：

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN 'Health and status' \
  'Additional description'
```

文字列は改行なしで結合され、次のようになります：

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN 'Health and statusAdditional description'
```

文字列継続文字は単一引用符または二重引用符の文字列の両方で機能しますが、両方の行が同じ構文を使用する必要があることに注意してください。単一引用符の文字列と二重引用符の文字列を連結することはできません。また、2行目のインデントはホワイトスペースが削除されるため重要ではありません。
