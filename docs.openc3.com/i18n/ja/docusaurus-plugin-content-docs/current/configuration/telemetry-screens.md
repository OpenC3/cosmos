---
sidebar_position: 10
title: スクリーン
description: テレメトリビューアの画面定義とウィジェットのドキュメント
sidebar_custom_props:
  myEmoji: 🖥️
---

このドキュメントでは、COSMOS テレメトリビューアアプリケーションによって表示される COSMOS テレメトリスクリーンを生成して使用するために必要な情報を提供します。

<div style={{"clear": 'both'}}></div>

## 定義

| 名前                   | 定義                                                                                                                                                                                                                                  |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ウィジェット             | ウィジェットは、COSMOS テレメトリ画面上のグラフィック要素です。テキストの表示、データのグラフ化、ボタンの提供、またはその他の表示/ユーザー入力タスクを実行することができます。                                                                           |
| スクリーン               | スクリーンは、有用な方法で整理・配置された任意の数のウィジェットを含む単一のウィンドウです。                                                                                                                     |
| スクリーン定義ファイル     | スクリーン定義ファイルは、テレメトリビューアにスクリーンの描画方法を指示するASCIIファイルです。画面に表示されるテレメトリポイントとその表示方法を定義するキーワード/パラメータ行のシリーズで構成されています。 |

## テレメトリスクリーン定義ファイル

テレメトリスクリーン定義ファイルは、テレメトリスクリーンの内容を定義します。SCREENキーワードに続いて、テレメトリスクリーンを定義する一連のウィジェットキーワードという一般的な形式を取ります。特定のターゲットに固有のスクリーン定義ファイルは、そのターゲットのscreensディレクトリに格納されます。例：TARGET/screens/version.txt。スクリーン定義ファイルは小文字でなければなりません。

## 新しいウィジェット

テレメトリスクリーン定義が解析され、認識されないキーワードに遭遇した場合、widgetname_widget.rbという形式のファイルが存在し、WidgetnameWidgetと呼ばれるクラスが含まれていると仮定されます。この規則のおかげで、テレメトリスクリーン定義フォーマットを変更することなく、新しいウィジェットをシステムに追加することができます。カスタムウィジェットの作成に関する詳細については、[カスタムウィジェット](../guides/custom-widgets.md)ガイドをお読みください。

# スクリーンキーワード


## SCREEN
**テレメトリビューアスクリーンを定義する**

SCREENキーワードは、すべてのテレメトリスクリーン定義の最初のキーワードです。スクリーンの名前と、スクリーン全体に影響するパラメータを定義します。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 幅 | ピクセル単位の幅、またはAUTOを指定してテレメトリビューアに自動的に画面レイアウトを行わせる | True |
| 高さ | ピクセル単位の高さ、またはAUTOを指定してテレメトリビューアに自動的に画面レイアウトを行わせる | True |
| ポーリング周期 | 画面更新間の秒数 | True |

使用例：
```ruby
SCREEN AUTO AUTO 1.0 FIXED
```

## END
**レイアウトウィジェットの終了を示す**

すべてのレイアウトウィジェットは、その停止位置を正しく識別するために、終了キーワードで閉じる必要があります。例えば、VERTICALBOXキーワードは、VERTICALBOXの終了位置を示すためにENDキーワードと一致しなければなりません。


## STALE_TIME
<div class="right">(5.1.0以降)</div>**パケット時間が過去のStale Time秒以上である場合、値は古いとマークされる**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| value | RECEIVED_TIMESECONDSが過去のこの値より大きいパケットからのアイテムは古いとマークされます。デフォルトは30秒です。競合状態による誤検出を避けるため、最低でも2秒を推奨します。 | True |

使用例：
```ruby
STALE_TIME 5 # データを古いとマークするまでの待機秒数
```

## GLOBAL_SETTING
**特定タイプのすべてのウィジェットにウィジェット設定を適用する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ウィジェットクラス名 | この設定が適用されるウィジェットのクラスの名前。例えば、LABELやBUTTONなど。 | True |
| 設定名 | 詳細はSETTINGを参照してください。 | True |
| 設定値 | 詳細はSETTINGを参照してください。 | False |

使用例：
```ruby
GLOBAL_SETTING LABELVALUELIMITSBAR TEXTCOLOR BLACK
```

## GLOBAL_SUBSETTING
**特定のタイプのすべてのウィジェットにウィジェットのサブ設定を適用する**

サブ設定は、複数のサブウィジェットで構成されるウィジェットにのみ有効です。例えば、LABELVALUEは、サブウィジェットインデックス0のLABELとサブウィジェットインデックス1のVALUEで構成されています。これにより、特定のサブウィジェットに設定を渡すことができます。LABELVALUELIMITSBARなど、一部のウィジェットは複数のサブウィジェットで構成されています。Labelウィジェットを設定するには、サブウィジェットインデックスとして0を、Valueウィジェットには1を、LimitsBarウィジェットには2を渡します。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ウィジェットクラス名 | この設定が適用されるウィジェットのクラスの名前。例えば、LABELVALUEなど。 | True |
| サブウィジェットインデックス | 目的のサブウィジェットへのインデックス | True |
| 設定名 | 詳細はSETTINGを参照してください。 | True |
| 設定値 | 詳細はSETTINGを参照してください。 | False |

使用例：
```ruby
# labelvaluelimitsbarsのすべてのテキスト色を白に設定
GLOBAL_SUBSETTING LABELVALUELIMITSBAR 0 TEXTCOLOR white
```

## SETTING
**直前に定義されたウィジェットにウィジェット設定を適用する**

設定により、パラメータでは利用できない追加の調整やオプションをウィジェットに
適用することができます。これらの設定はすべて、SETTING、SUBSETTING、GLOBAL_SETTING、
およびGLOBAL_SUBSETTINGキーワードを通じて構成されます。
SETTINGとSUBSETTINGは、直前に定義されたウィジェットにのみ適用されます。
GLOBAL_SETTINGとGLOBAL_SUBSETTINGはすべてのウィジェットに適用されます。

一般的なウィジェット設定はここで定義されています。一部のウィジェットは独自の
固有の設定を定義しており、それらは特定のウィジェットの下にドキュメント化されています。



### WIDTH
**ウィジェットの幅を設定する**

WIDTHは[cssユニット](https://www.w3schools.com/cssref/css_units.php)をサポートしており、デフォルト（単位なし）はpx（ピクセル）です

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Width | ピクセル単位の幅、または明示的に単位を宣言 | True |

使用例：
```ruby
LABEL "THIS IS A TEST"
  SETTING WIDTH 50
LABEL "THIS IS A TEST"
  SETTING WIDTH 20em
```
![WIDTH](/img/telemetry_viewer/widgets/width.png)


### HEIGHT
**ウィジェットの高さを設定する**

HEIGHTは[cssユニット](https://www.w3schools.com/cssref/css_units.php)をサポートしており、デフォルト（単位なし）はpx（ピクセル）です

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Height | ピクセル単位の高さ、または明示的に単位を宣言 | True |

使用例：
```ruby
LABEL "THIS IS A TEST"
  SETTING BACKCOLOR BLUE
  SETTING HEIGHT 50
LABEL "THIS IS A TEST"
  SETTING BACKCOLOR GREY
  SETTING HEIGHT 2em
```
![HEIGHT](/img/telemetry_viewer/widgets/height.png)


### MARGIN
**ウィジェットのマージンを設定する**

MARGINは[cssユニット](https://www.w3schools.com/cssref/css_units.php)をサポートしており、デフォルト（単位なし）はpx（ピクセル）です

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Size | ピクセル単位のサイズ、または明示的に単位を宣言 | True |

使用例：
```ruby
LABEL "THIS IS A TEST"
  SETTING BACKCOLOR BLUE
LABEL "THIS IS A TEST"
  SETTING BACKCOLOR GREY
  SETTING MARGIN 10
LABEL "THIS IS A TEST"
  SETTING BACKCOLOR GREEN
```
![MARGIN](/img/telemetry_viewer/widgets/margin.png)


### PADDING
**ウィジェットのパディングを設定する**

PADDINGは[cssユニット](https://www.w3schools.com/cssref/css_units.php)をサポートしており、デフォルト（単位なし）はpx（ピクセル）です

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Size | ピクセル単位のサイズ、または明示的に単位を宣言 | True |

使用例：
```ruby
LABEL "THIS IS A TEST"
  SETTING BACKCOLOR BLUE
LABEL "THIS IS A TEST"
  SETTING BACKCOLOR GREY
  SETTING PADDING 10
LABEL "THIS IS A TEST"
  SETTING BACKCOLOR GREEN
```
![PADDING](/img/telemetry_viewer/widgets/padding.png)


### BACKCOLOR
**BACKCOLOR設定はウィジェットの背景色を設定します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 色名または赤の値 | 色の一般的な名前（例：'black'、'red'など）。または、さらに2つのパラメータが渡された場合、これはRGB値の赤の値です | True |
| 緑の値 | RGB値の緑の値 | False |
| 青の値 | RGB値の青の値 | False |

使用例：
```ruby
LABEL "THIS IS A TEST"
  SETTING BACKCOLOR red
LABEL "THIS IS A TEST"
  SETTING BACKCOLOR 155 50 155
```
![BACKCOLOR](/img/telemetry_viewer/widgets/backcolor.png)


### TEXTCOLOR
**TEXTCOLOR設定はウィジェットのテキスト色を設定します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 色名または赤の値 | 色の一般的な名前（例：'black'、'red'など）。または、さらに2つのパラメータが渡された場合、これはRGB値の赤の値です | True |
| 緑の値 | RGB値の緑の値 | False |
| 青の値 | RGB値の青の値 | False |

使用例：
```ruby
LABEL "THIS IS A TEST"
  SETTING TEXTCOLOR red
LABEL "THIS IS A TEST"
  SETTING TEXTCOLOR 155 50 155
```
![TEXTCOLOR](/img/telemetry_viewer/widgets/textcolor.png)


### BORDERCOLOR
**BORDERCOLOR設定はレイアウトウィジェットの枠線の色を設定します**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 色名または赤の値 | 色の一般的な名前（例：'black'、'red'など）。または、さらに2つのパラメータが渡された場合、これはRGB値の赤の値です | True |
| 緑の値 | RGB値の緑の値 | False |
| 青の値 | RGB値の青の値 | False |

使用例：
```ruby
HORIZONTAL
  LABEL "Label 1"
END
SETTING BORDERCOLOR red
VERTICAL
  LABEL "Label 2"
END
SETTING BORDERCOLOR 155 50 155
```
![BORDERCOLOR](/img/telemetry_viewer/widgets/bordercolor.png)


### RAW
**生のCSSスタイルシートのキーと値を適用する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| Key | font-size、max-widthなどのCSSキー | True |
| Value | CSS値 | True |

使用例：
```ruby
LABEL "Label 1"
  SETTING RAW font-size 30px
```
![RAW](/img/telemetry_viewer/widgets/raw.png)


## SUBSETTING
**直前に定義されたウィジェットにウィジェットのサブ設定を適用する**

サブ設定は、複数のサブウィジェットで構成されるウィジェットにのみ有効です。例えば、LABELVALUEは、サブウィジェットインデックス0のLABELとサブウィジェットインデックス1のVALUEで構成されています。これにより、特定のサブウィジェットに設定を渡すことができます。LABELVALUELIMITSBARなど、一部のウィジェットは複数のサブウィジェットで構成されています。Labelウィジェットを設定するには、サブウィジェットインデックスとして0を、Valueウィジェットには1を、LimitsBarウィジェットには2を渡します。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| サブウィジェットインデックス | 目的のサブウィジェットへのインデックス、または'ALL'を指定してこの複合ウィジェットのすべてのサブウィジェットに設定を適用します。 | True |
| 設定名 | 詳細はSETTINGを参照してください。 | True |
| 設定値 | 詳細はSETTINGを参照してください。 | False |

使用例：
```ruby
VERTICALBOX
  LABELVALUE INST HEALTH_STATUS TEMP1
    SUBSETTING 0 TEXTCOLOR blue # ラベルのテキストを青に変更
  LABELVALUELIMITSBAR INST HEALTH_STATUS TEMP1
    SUBSETTING 0 TEXTCOLOR green # ラベルのテキストを緑に変更
END
```
![SUBSETTING](/img/telemetry_viewer/widgets/subsetting.png)


## NAMED_WIDGET
**ウィジェットに名前を付けて、getNamedWidgetメソッドを通じてアクセスできるようにする**

テレメトリ画面の一部にプログラムでアクセスするには、ウィジェットに名前を付ける必要があります。これは、他のウィジェットから値を読み取るボタンを持つ画面を作成する際に便利です。

:::warning
getNamedWidgetはウィジェット自体を返すため、そのウィジェット固有のメソッドを使用して操作する必要があります
:::

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ウィジェット名 | 次のウィジェットインスタンスに適用される一意の名前。名前は画面ごとに一意でなければなりません。 | True |
| ウィジェットタイプ | ウィジェットの説明に記載されているウィジェットタイプのいずれか | True |
| ウィジェットパラメータ | 指定されたウィジェットタイプの固有パラメータ | True |

使用例：
```ruby
NAMED_WIDGET DURATION TEXTFIELD
BUTTON "Push" "screen.getNamedWidget('DURATION').text()"
```
![NAMED_WIDGET](/img/telemetry_viewer/widgets/named_widget.png)


## レイアウトウィジェット
****

レイアウトウィジェットは、他のウィジェットを画面上に配置するために使用されます。例えば、HORIZONTALレイアウトウィジェットは、それがカプセル化するウィジェットを画面上に水平に配置します。


### VERTICAL
**カプセル化したウィジェットを垂直に配置する**

画面はデフォルトで垂直レイアウトになっているため、レイアウトウィジェットが指定されていない場合、すべてのウィジェットは自動的にVERTICALレイアウトウィジェット内に配置されます。VERTICALウィジェットは、その内容に合わせてサイズが調整されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| マージン | ウィジェット間のマージン（デフォルト = 0px） | False |

使用例：
```ruby
VERTICAL 5px
  LABEL "TEST"
  LABEL "SCREEN"
END
```
![VERTICAL](/img/telemetry_viewer/widgets/vertical.png)


### VERTICALBOX
**カプセル化したウィジェットを薄い境界線の中に垂直に配置する**

VERTICALBOXウィジェットは、その内容に合わせて垂直方向にサイズ調整し、画面に合わせて水平方向にサイズ調整します

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| タイトル | ボックスにラベルを付けるために境界内に配置するテキスト | False |
| マージン | ウィジェット間のマージン（デフォルト = 0px） | False |

使用例：
```ruby
VERTICALBOX Info
  SUBSETTING 1 RAW border "1px dashed green"
  LABEL "TEST"
  LABEL "SCREEN"
END
```
![VERTICALBOX](/img/telemetry_viewer/widgets/verticalbox.png)


### HORIZONTAL
**カプセル化したウィジェットを水平に配置する**

HORIZONTALウィジェットは、その内容に合わせてサイズ調整します

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| マージン | ウィジェット間のマージン（デフォルト = 0px） | False |

使用例：
```ruby
HORIZONTAL 100
  LABEL "TEST"
  LABEL "SCREEN"
END
```
![HORIZONTAL](/img/telemetry_viewer/widgets/horizontal.png)


### HORIZONTALBOX
**カプセル化したウィジェットを薄い境界線の中に水平に配置する**

HORIZONTALBOXウィジェットは、その内容に合わせてサイズ調整します

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| タイトル | ボックスにラベルを付けるために境界内に配置するテキスト | False |
| マージン | ウィジェット間のマージン（デフォルト = 0px） | False |

使用例：
```ruby
HORIZONTALBOX Info 10
  SUBSETTING 0 RAW text-align CENTER
  SUBSETTING 1 RAW border "1px solid blue"
  LABEL "TEST"
  LABEL "SCREEN"
END
```
![HORIZONTALBOX](/img/telemetry_viewer/widgets/horizontalbox.png)


### MATRIXBYCOLUMNS
**ウィジェットをテーブルのようなマトリックスに配置する**

MATRIXBYCOLUMNSウィジェットは、その内容に合わせてサイズ調整します

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 列 | 作成する列の数 | True |
| マージン | ウィジェット間のマージン（デフォルト = 0px） | False |

使用例：
```ruby
MATRIXBYCOLUMNS 3 10
  LABEL "COL 1"
  LABEL "COL 2"
  LABEL "COL 3"
  LABEL "100"
  LABEL "200"
  LABEL "300"
END
```
![MATRIXBYCOLUMNS](/img/telemetry_viewer/widgets/matrixbycolumns.png)


### SCROLLWINDOW
**内部のウィジェットをスクロール可能なエリアに配置する**

SCROLLWINDOWウィジェットは、それが含まれる画面に合わせてサイズ調整します

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 高さ | スクロールウィンドウの最大高さ（ピクセル単位、デフォルト = 200） | False |
| マージン | ウィジェット間のマージン（デフォルト = 0px） | False |

使用例：
```ruby
SCROLLWINDOW 100 10
  VERTICAL
    LABEL "100"
    LABEL "200"
    LABEL "300"
    LABEL "400"
    LABEL "500"
    LABEL "600"
    LABEL "700"
    LABEL "800"
    LABEL "900"
  END
END
```
![SCROLLWINDOW](/img/telemetry_viewer/widgets/scrollwindow.png)


### TABBOOK
**TABITEMウィジェットを配置するためのタブ付きエリアを作成する**


### TABITEM
**ウィジェットを配置するためのVERTICALレイアウトタブを作成する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| タブテキスト | タブに表示するテキスト | True |

使用例：
```ruby
TABBOOK
  TABITEM "Tab 1"
    LABEL "100"
    LABEL "200"
  END
  TABITEM "Tab 2"
    LABEL "300"
    LABEL "400"
  END
END
```
![TABITEM](/img/telemetry_viewer/widgets/tabitem.png)


### IFRAME
**OpenC3内のIframe内で外部ツールを開く**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| URL | iframe内に表示するページのパス | True |
| 幅 | ウィジェットの幅 | False |
| 高さ | ウィジェットの高さ | False |

使用例：
```ruby
IFRAME https://openc3.com 900 450
```
![IFRAME](/img/telemetry_viewer/widgets/iframe.png)


## 装飾ウィジェット
****

装飾ウィジェットは、画面の外観を向上させるために使用されます。これらは入力に応答せず、出力もテレメトリによって変化しません。


### LABEL
**画面上にテキストを表示する**

一般に、ラベルウィジェットにはテレメトリニーモニックが含まれ、テレメトリVALUEウィジェットの隣に配置されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| テキスト | ラベルに表示するテキスト | True |

使用例：
```ruby
LABEL "注意：これは警告のみです"
```
![LABEL](/img/telemetry_viewer/widgets/label.png)


### HORIZONTALLINE
<div class="right">(5.5.1以降)</div>**区切り線として使える水平線を画面上に表示する**


使用例：
```ruby
LABEL Over
HORIZONTALLINE
LABEL Under
```
![HORIZONTALLINE](/img/telemetry_viewer/widgets/horizontalline.png)


### TITLE
**画面上に大きな中央揃えのタイトルを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| テキスト | 表示するテキスト | True |

使用例：
```ruby
TITLE "タイトル"
HORIZONTALLINE
LABEL "ラベル"
```
![TITLE](/img/telemetry_viewer/widgets/title.png)


### SPACER
**ウィジェット間に固定サイズのスペーサーを配置する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 幅 | スペーサーの幅（ピクセル単位） | True |
| 高さ | スペーサーの高さ（ピクセル単位） | True |

使用例：
```ruby
VERTICAL 3
  LABEL "スペーサー下部"
  SPACER 0 100
  LABEL "スペーサー上部"
END
```
![SPACER](/img/telemetry_viewer/widgets/spacer.png)


## テレメトリウィジェット
****

テレメトリウィジェットは、テレメトリ値を表示するために使用されます。これらのウィジェットの最初のパラメータはテレメトリニーモニックです。テレメトリ項目の種類と目的に応じて、画面設計者は最も有用な形式で値を表示するために、幅広いウィジェットから選択することができます。


### ARRAY
**行に整理され、スペースで区切られた配列データを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 幅 | ウィジェットの幅（デフォルト = 200） | False |
| 高さ | ウィジェットの高さ（デフォルト = 100） | False |
| フォーマット文字列 | 各配列アイテムに適用されるフォーマット文字列（デフォルト = nil） | False |
| 行あたりのアイテム数 | 1行あたりの配列アイテム数（デフォルト = 4） | False |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |

使用例：
```ruby
ARRAY INST HEALTH_STATUS ARY 250 80 "0x%x" 6 FORMATTED
ARRAY INST HEALTH_STATUS ARY2 200 100 nil 4 WITH_UNITS
```
![ARRAY](/img/telemetry_viewer/widgets/array.png)


### ARRAYPLOT
**配列の値をプロットする**

アイテムは単純な配列またはx値とy値の2D配列（例：[[x1, x2, x3], [y1, y2, y3]]）のいずれかです。X_AXIS設定が指定されていない場合、X軸は0から始まり1ずつ増加します。X_AXIS設定が使用されている場合、2D配列のx値は無視されます。


使用例：
```ruby
ARRAYPLOT
  SETTING TITLE "配列データ"
  SETTING ITEM INST HEALTH_STATUS ARY
  SETTING ITEM INST HEALTH_STATUS ARY2
  SETTING SIZE 600 400
  SETTING X_AXIS 10 10
```
![ARRAYPLOT](/img/telemetry_viewer/widgets/arrayplot.png)

以下の設定はARRAYPLOTに適用されます。これらはSETTINGキーワードを使用して適用されます。
#### TITLE
**プロットのタイトル**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| タイトル | プロットのタイトル | True |

#### X_AXIS
**プロットのx軸パラメータを定義する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 開始値 | x軸の開始値 | True |
| ステップ値 | x軸のステップ値 | True |

#### ITEM
**グラフにテレメトリアイテムを追加する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED</span> | False |
| 縮小 | 縮小データを表示するかどうか。デフォルトはDECOM。<br/><br/>有効な値: <span class="values">DECOM, REDUCED_MINUTE, REDUCED_HOUR, REDUCED_DAY</span> | False |
| 縮小タイプ | 表示する縮小データのタイプ。縮小がDECOMでない場合にのみ適用されます。<br/><br/>有効な値: <span class="values">MIN, MAX, AVG, STDDEV</span> | False |

#### STARTTIME
<div class="right">(5.5.1以降)</div>**指定された時間からグラフ履歴を開始する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 開始時間 | 'YYYY/MM/DD HH:MM:SS'形式の開始時間 | True |

#### HISTORY
<div class="right">(5.5.1以降)</div>**データの初期履歴を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 値 | 値(d,h,m,s)。例えば1d、2h、30m、15s | True |

#### SECONDSGRAPHED
**グラフに指定された秒数を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | 表示する秒数 | True |

#### POINTSSAVED
**グラフメモリに秒数を保存する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | 保存する秒数 | True |

#### POINTSGRAPHED
**グラフに表示するポイント数**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | グラフ化するポイント数 | True |

#### SIZE
**グラフのサイズ**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 幅 | ピクセル単位の幅 | True |
| 高さ | ピクセル単位の高さ | True |

### BLOCK
**行に整理され、スペースで区切られたBLOCKデータを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 幅 | ウィジェットの幅（デフォルト = 200） | False |
| 高さ | ウィジェットの高さ（デフォルト = 100） | False |
| フォーマット文字列 | 各配列アイテムに適用されるフォーマット文字列（デフォルト = nil） | False |
| ワードあたりのバイト数 | 1ワードあたりのバイト数（デフォルト = 4） | False |
| 行あたりのワード数 | 1行あたりのワード数（デフォルト = 4） | False |
| アドレスフォーマット | 各行の先頭に印刷されるアドレスのフォーマット（デフォルト = nil、アドレスを印刷しないことを意味します） | False |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |

使用例：
```ruby
BLOCK INST IMAGE IMAGE 620 200 "%02X" 4 4 "0x%08X:"
```
![BLOCK](/img/telemetry_viewer/widgets/block.png)


### FORMATVALUE
**フォーマットされた値を持つボックスを表示する**

データは、テレメトリ定義ファイルで指定されたフォーマット文字列ではなく、指定された文字列によってフォーマットされます。値が停滞している間、ボックスの白い部分は灰色に暗くなり、値が変更されるたびに白く明るくなります。さらに、値はアイテムの制限状態に基づいて色付けされます（例えば、制限を超えている場合は赤色）。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| フォーマット文字列 | テレメトリ項目に適用するPrintf形式のフォーマット文字列 | False |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 文字数 | 値ボックスの幅とする文字数（デフォルト = 12） | False |

使用例：
```ruby
FORMATVALUE INST LATEST TIMESEC %012u CONVERTED 20
FORMATVALUE INST LATEST TEMP1 %.2f CONVERTED 20
```
![FORMATVALUE](/img/telemetry_viewer/widgets/formatvalue.png)


### LABELLED
**LABELの後にLEDを表示する**

詳細についてはLEDウィジェットを参照してください

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 幅 | LED円の幅（デフォルト = 15） | False |
| 高さ | LED円の高さ（デフォルト = 15） | False |
| 揃え方 | ラベルとLEDを一緒に揃える方法。デフォルトの「SPLIT」はラベルを左に、LEDを右に揃え、追加のスペースをその間に配置します。「CENTER」はラベルとLEDを一緒に押し、追加のスペースは左右に配置します。「LEFT」または「RIGHT」はそれぞれの側に押し、スペースは反対側に配置します。<br/><br/>有効な値: <span class="values">SPLIT, CENTER, LEFT, RIGHT</span> | False |

使用例：
```ruby
LABELLED INST PARAMS VALUE1
  SETTING LED_COLOR GOOD GREEN
  SETTING LED_COLOR BAD RED
```
![LABELLED](/img/telemetry_viewer/widgets/labelled.png)

以下の設定はLABELLEDに適用されます。これらはSETTINGキーワードを使用して適用されます。
#### LED_COLOR
**状態または値を色にマッピングする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 値 | 状態または値。ANYは宣言されていない任意の値または状態に一致するために使用されます。 | True |
| LED色 | LEDの色 | True |

### LABELPROGRESSBAR
**アイテム名の後にPROGRESSBARが続くLABELを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| スケールファクター | プログレスバーに表示する前にテレメトリ項目に掛ける値。最終値は0から100の範囲内であるべきです。デフォルトは1.0です。 | False |
| 幅 | プログレスバーの幅（デフォルト = 80ピクセル） | False |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |

使用例：
```ruby
LABELPROGRESSBAR INST ADCS POSPROGRESS 2 200 RAW
LABELPROGRESSBAR INST ADCS POSPROGRESS
```
![LABELPROGRESSBAR](/img/telemetry_viewer/widgets/labelprogressbar.png)


### LABELVALUE
**アイテム名の後にVALUEが続くLABELを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 文字数 | 値ボックスの幅とする文字数（デフォルト = 12） | False |

使用例：
```ruby
LABELVALUE INST LATEST TIMESEC CONVERTED 18
LABELVALUE INST LATEST COLLECT_TYPE
```
![LABELVALUE](/img/telemetry_viewer/widgets/labelvalue.png)


### LABELVALUEDESC
**アイテムの説明の後にVALUEが続くLABELを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 説明 | ラベルに表示する説明（デフォルトはテレメトリ項目に関連付けられた説明テキストを表示） | False |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 文字数 | 値ボックスの幅とする文字数（デフォルト = 12） | False |

使用例：
```ruby
LABELVALUEDESC INST HEALTH_STATUS TEMP1 "温度番号1" RAW 18
LABELVALUEDESC INST HEALTH_STATUS COLLECT_TYPE
```
![LABELVALUEDESC](/img/telemetry_viewer/widgets/labelvaluedesc.png)


### LABELVALUELIMITSBAR
**アイテム名の後にVALUEとLIMITSBARウィジェットが続くLABELを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 文字数 | 値ボックスの幅とする文字数（デフォルト = 12） | False |

### LABELVALUELIMITSCOLUMN
**アイテム名の後にVALUEとLIMITSCOLUMNウィジェットが続くLABELを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 文字数 | 値ボックスの幅とする文字数（デフォルト = 12） | False |

使用例：
```ruby
LABELVALUELIMITSCOLUMN INST HEALTH_STATUS TEMP1 CONVERTED 18
LABELVALUELIMITSCOLUMN INST HEALTH_STATUS TEMP1
```
![LABELVALUELIMITSCOLUMN](/img/telemetry_viewer/widgets/labelvaluelimitscolumn.png)


### LABELVALUERANGEBAR
**アイテム名の後にVALUEとRANGEBARウィジェットが続くLABELを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 最小値 | レンジバーに表示する最小値. | True |
| 最大値 | レンジバーに表示する最大値. | True |
| 値タイプ | 表示する値のタイプ. デフォルトは CONVERTED.<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 文字数 | 値ボックスの幅とする文字数 (デフォルト = 12) | False |
| 幅 | レンジバーの幅 (デフォルト = 160) | False |
| 高さ | レンジバーの高さ (デフォルト = 25) | False |

使用例:
```ruby
LABELVALUERANGEBAR INST HEALTH_STATUS TEMP1 0 100000 RAW 18 200 40
LABELVALUERANGEBAR INST HEALTH_STATUS TEMP1 -120 120
```
![LABELVALUERANGEBAR](/img/telemetry_viewer/widgets/labelvaluerangebar.png)


### LED
**テレメトリ値に基づいて色が変わるLEDを表示する**

デフォルトでは、TRUEは緑色、FALSEは赤色、その他の値はすべて黒色です。LED_COLOR設定を使用して追加の値を追加できます。例えば、LED INST PARAMS VALUE3 RAWの後に、SETTING LED_COLOR 0 GREEN、SETTING LED_COLOR 1 RED、およびSETTING LED_COLOR ANY ORANGEを続けることができます。項目の制限色を示す円を表示するウィジェットについては、LIMITSCOLORを参照してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 幅 | LED円の幅（デフォルト = 15） | False |
| 高さ | LED円の高さ（デフォルト = 15） | False |

使用例：
```ruby
LED INST PARAMS VALUE5 RAW 25 20 # 楕円
  SETTING LED_COLOR 0 GREEN
  SETTING LED_COLOR 1 RED
  SETTING LED_COLOR ANY YELLOW
```
![LED](/img/telemetry_viewer/widgets/led.png)

以下の設定はLEDに適用されます。これらはSETTINGキーワードを使用して適用されます。
#### LED_COLOR
**状態または値を色にマッピングする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 値 | 状態または値。ANYは宣言されていない任意の値または状態に一致するために使用されます。 | True |
| LED色 | LEDの色 | True |

### LIMITSBAR
**アイテムの現在の値を色付けされた制限内に水平に表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 幅 | レンジバーの幅（デフォルト = 160） | False |
| 高さ | レンジバーの高さ（デフォルト = 25） | False |

Example Usage:
```ruby
LIMITSBAR INST HEALTH_STATUS TEMP1 CONVERTED 200 50
LIMITSBAR INST HEALTH_STATUS TEMP1
```
![LIMITSBAR](/img/telemetry_viewer/widgets/limitsbar.png)


### LIMITSCOLUMN
**アイテムの現在の値を色付けされた制限内に垂直に表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 幅 | レンジバーの幅（デフォルト = 160） | False |
| 高さ | レンジバーの高さ（デフォルト = 25） | False |

使用例:
```ruby
LIMITSCOLUMN INST HEALTH_STATUS TEMP1 CONVERTED 50 200
LIMITSCOLUMN INST HEALTH_STATUS TEMP1
```
![LIMITSCOLUMN](/img/telemetry_viewer/widgets/limitscolumn.png)


### LIMITSCOLOR
**アイテムの制限色を示す円を表示する。テレメトリ値に基づいて任意の色に変化する円を表示するウィジェットについては、LEDを参照してください。**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 半径 | 円の半径（デフォルトは10） | False |
| アイテム名表示 | 完全なアイテム名を表示（例：TGT PKT ITEM）(true)、アイテム名なし（nil または none）、またはアイテム名のみ（false）。デフォルトはfalse。 | False |

使用例:
```ruby
HORIZONTAL
  LIMITSCOLOR INST HEALTH_STATUS TEMP1 CONVERTED 10 NIL # ラベルなし
  LABEL '1st Temp'
END
LIMITSCOLOR INST HEALTH_STATUS TEMP2 # デフォルトはアイテム名のみのラベル
LIMITSCOLOR INST HEALTH_STATUS TEMP3 CONVERTED 20 TRUE # 完全なTGT/PKT/ITEMラベル
```
![LIMITSCOLOR](/img/telemetry_viewer/widgets/limitscolor.png)


### VALUELIMITSBAR
**アイテムの値に続いてLIMITSBARを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 文字数 | 値ボックスの幅（文字数）（デフォルト = 12） | False |

使用例:
```ruby
VALUELIMITSBAR INST HEALTH_STATUS TEMP1 CONVERTED 18
VALUELIMITSBAR INST HEALTH_STATUS TEMP1
```
![VALUELIMITSBAR](/img/telemetry_viewer/widgets/valuelimitsbar.png)


### VALUELIMITSCOLUMN
**アイテムの値に続いてLIMITSCOLUMNを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 文字数 | 値ボックスの幅（文字数）（デフォルト = 8） | False |

使用例:
```ruby
VALUELIMITSCOLUMN INST HEALTH_STATUS TEMP1 CONVERTED 18
VALUELIMITSCOLUMN INST HEALTH_STATUS TEMP1
```
![VALUELIMITSCOLUMN](/img/telemetry_viewer/widgets/valuelimitscolumn.png)


### VALUERANGEBAR
**アイテムの値に続いてRANGEBARを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 最小値 | レンジバーに表示する最小値。 | True |
| 最大値 | レンジバーに表示する最大値。 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 文字数 | 値ボックスの幅（文字数）（デフォルト = 12） | False |
| 幅 | レンジバーの幅（デフォルト = 160） | False |
| 高さ | レンジバーの高さ（デフォルト = 25） | False |

使用例:
```ruby
VALUERANGEBAR INST HEALTH_STATUS TEMP1 0 100000 RAW 18 200 40
VALUERANGEBAR INST HEALTH_STATUS TEMP1 -120 120
```
![VALUERANGEBAR](/img/telemetry_viewer/widgets/valuerangebar.png)


### LINEGRAPH
**テレメトリアイテムの折れ線グラフを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED</span> | False |
| 減少データ | 減少データを表示するかどうか。デフォルトはDECOM。<br/><br/>有効な値: <span class="values">DECOM, REDUCED_MINUTE, REDUCED_HOUR, REDUCED_DAY</span> | False |
| 減少データタイプ | 表示する減少データのタイプ。ReducedがDECOMでない場合にのみ適用されます。<br/><br/>有効な値: <span class="values">MIN, MAX, AVG, STDDEV</span> | False |

使用例:
```ruby
LINEGRAPH INST HEALTH_STATUS TEMP1
  SETTING ITEM INST ADCS Q1 # グラフに追加アイテムを追加
```
![LINEGRAPH](/img/telemetry_viewer/widgets/linegraph.png)

以下の設定はLINEGRAPHに適用されます。これらはSETTINGキーワードを使用して適用されます。
#### ITEM
**グラフにテレメトリアイテムを追加する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED</span> | False |
| 減少データ | 減少データを表示するかどうか。デフォルトはDECOM。<br/><br/>有効な値: <span class="values">DECOM, REDUCED_MINUTE, REDUCED_HOUR, REDUCED_DAY</span> | False |
| 減少データタイプ | 表示する減少データのタイプ。ReducedがDECOMでない場合にのみ適用されます。<br/><br/>有効な値: <span class="values">MIN, MAX, AVG, STDDEV</span> | False |

#### STARTTIME
<div class="right">(5.5.1以降)</div>**指定された時間からグラフ履歴を開始する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 開始時間 | 'YYYY/MM/DD HH:MM:SS'形式の開始時間 | True |

#### HISTORY
<div class="right">(5.5.1以降)</div>**データの初期履歴を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 値 | 値(d,h,m,s)。例えば1d、2h、30m、15s | True |

#### SECONDSGRAPHED
**グラフに指定された秒数を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | 表示する秒数 | True |

#### POINTSSAVED
**グラフメモリに秒数を保存する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | 保存する秒数 | True |

#### POINTSGRAPHED
**グラフに表示するポイント数**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | グラフ化するポイント数 | True |

#### SIZE
**グラフのサイズ**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 幅 | ピクセル単位の幅 | True |
| 高さ | ピクセル単位の高さ | True |

### SPARKLINE
**テレメトリアイテムのスパークライングラフ（カーソル、スケール、凡例なし）を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED</span> | False |
| 減少データ | 減少データを表示するかどうか。デフォルトはDECOM。<br/><br/>有効な値: <span class="values">DECOM, REDUCED_MINUTE, REDUCED_HOUR, REDUCED_DAY</span> | False |
| 減少データタイプ | 表示する減少データのタイプ。ReducedがDECOMでない場合にのみ適用されます。<br/><br/>有効な値: <span class="values">MIN, MAX, AVG, STDDEV</span> | False |

使用例:
```ruby
SPARKLINE INST HEALTH_STATUS TEMP1
  SETTING SIZE 400 50
  SETTING HISTORY 30s # グラフに30秒のデータを追加
```
![SPARKLINE](/img/telemetry_viewer/widgets/sparkline.png)

以下の設定はSPARKLINEに適用されます。これらはSETTINGキーワードを使用して適用されます。
#### ITEM
**グラフにテレメトリアイテムを追加する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED</span> | False |
| 減少データ | 減少データを表示するかどうか。デフォルトはDECOM。<br/><br/>有効な値: <span class="values">DECOM, REDUCED_MINUTE, REDUCED_HOUR, REDUCED_DAY</span> | False |
| 減少データタイプ | 表示する減少データのタイプ。ReducedがDECOMでない場合にのみ適用されます。<br/><br/>有効な値: <span class="values">MIN, MAX, AVG, STDDEV</span> | False |

#### STARTTIME
<div class="right">(5.5.1以降)</div>**指定された時間からグラフ履歴を開始する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 開始時間 | 'YYYY/MM/DD HH:MM:SS'形式の開始時間 | True |

#### HISTORY
<div class="right">(5.5.1以降)</div>**データの初期履歴を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 値 | 値(d,h,m,s)。例えば1d、2h、30m、15s | True |

#### SECONDSGRAPHED
**グラフに指定された秒数を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | 表示する秒数 | True |

#### POINTSSAVED
**グラフメモリに秒数を保存する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | 保存する秒数 | True |

#### POINTSGRAPHED
**グラフに表示するポイント数**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | グラフ化するポイント数 | True |

#### SIZE
**グラフのサイズ**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 幅 | ピクセル単位の幅 | True |
| 高さ | ピクセル単位の高さ | True |

### LABELSPARKLINE
**アイテム名のLABELに続いてSPARKLINEを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED</span> | False |
| 減少データ | 減少データを表示するかどうか。デフォルトはDECOM。<br/><br/>有効な値: <span class="values">DECOM, REDUCED_MINUTE, REDUCED_HOUR, REDUCED_DAY</span> | False |
| 減少データタイプ | 表示する減少データのタイプ。ReducedがDECOMでない場合にのみ適用されます。<br/><br/>有効な値: <span class="values">MIN, MAX, AVG, STDDEV</span> | False |

使用例:
```ruby
LABELSPARKLINE INST HEALTH_STATUS TEMP1
  SETTING HISTORY 5m # グラフに5分のデータを追加
```
![LABELSPARKLINE](/img/telemetry_viewer/widgets/labelsparkline.png)

以下の設定はLABELSPARKLINEに適用されます。これらはSETTINGキーワードを使用して適用されます。
#### ITEM
**グラフにテレメトリアイテムを追加するh**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| Value type | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED</span> | False |
| 減少データ | 減少データを表示するかどうか。デフォルトはDECOM。<br/><br/>有効な値: <span class="values">DECOM, REDUCED_MINUTE, REDUCED_HOUR, REDUCED_DAY</span> | False |
| 減少データタイプ | 表示する減少データのタイプ。ReducedがDECOMでない場合にのみ適用されます。<br/><br/>有効な値: <span class="values">MIN, MAX, AVG, STDDEV</span> | False |

#### STARTTIME
<div class="right">(5.5.1以降)</div>**指定された時間からグラフ履歴を開始する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 開始時間 | 'YYYY/MM/DD HH:MM:SS'形式の開始時間 | True |

#### HISTORY
<div class="right">(5.5.1以降)</div>**データの初期履歴を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 値 | 値(d,h,m,s)。例えば1d、2h、30m、15s | True |

#### SECONDSGRAPHED
**グラフに指定された秒数を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | 表示する秒数 | True |

#### POINTSSAVED
**グラフメモリに秒数を保存する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | 保存する秒数 | True |

#### POINTSGRAPHED
**グラフに表示するポイント数**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間 | グラフ化するポイント数 | True |

#### SIZE
**グラフのサイズ**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 幅 | ピクセル単位の幅 | True |
| 高さ | ピクセル単位の高さ | True |

### IMAGEVIEWER
**TLMパケットからbase64画像を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | CONVERTED値を取得するアイテム名。追加処理（base64エンコーディング）が必要な場合は、DERIVEDアイテムの使用を検討してください。 | True |
| フォーマット | base64データの画像フォーマット（例：jpg、pngなど） | True |

使用例:
```ruby
IMAGEVIEWER INST IMAGE IMAGE jpg
```
![IMAGEVIEWER](/img/telemetry_viewer/widgets/imageviewer.png)


### PROGRESSBAR
**パーセンテージの表示に便利なプログレスバーを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| スケールファクター | プログレスバーに表示する前にテレメトリアイテムに掛ける値。最終値は0から100の範囲である必要があります。デフォルトは1.0です。 | False |
| 幅 | プログレスバーの幅（デフォルト = 100ピクセル） | False |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |

使用例:
```ruby
PROGRESSBAR INST ADCS POSPROGRESS 0.5 200
PROGRESSBAR INST ADCS POSPROGRESS
```
![PROGRESSBAR](/img/telemetry_viewer/widgets/progressbar.png)


### RANGEBAR
**アイテムの値を表示するカスタムレンジバーを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 最小値 | レンジバーに表示する最小値。 | True |
| 最大値 | レンジバーに表示する最大値。 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 幅 | レンジバーの幅（デフォルト = 100） | False |
| 高さ | レンジバーの高さ（デフォルト = 25） | False |

使用例:
```ruby
RANGEBAR INST HEALTH_STATUS TEMP1 0 100000 RAW 200 50
RANGEBAR INST HEALTH_STATUS TEMP1 -100 100
```
![RANGEBAR](/img/telemetry_viewer/widgets/rangebar.png)


### ROLLUP
<div class="right">(Since 5.17.1)</div>**ロールアップテレメトリに基づいて色が変化する通知アイコンを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| アイコン名 | 表示するastro UXアイコン。有効な選択肢はhttps://github.com/RocketCommunicationsInc/astro-components/blob/master/static/json/rux-icons.jsonから取得した'astro'アイコンです。 | True |
| アイコンラベル | アイコンラベルに適用するテキスト | False |
| アイコンサブラベル | アイコンサブラベルに適用するテキスト | False |

使用例:
```ruby
ROLLUP satellite-transmit "SAT 1" "Details"
  # クリック時に開くスクリーン
  SETTING SCREEN INST HS
  # ロールアップステータスのテレメトリアイテム
  SETTING TLM INST HEALTH_STATUS TEMP1
  SETTING TLM INST HEALTH_STATUS TEMP2
ROLLUP antenna "GND 2" "Location"
  # クリック時に開くスクリーン
  SETTING SCREEN INST HS
  # ロールアップステータスのテレメトリアイテム
  SETTING TLM INST HEALTH_STATUS TEMP3
  SETTING TLM INST HEALTH_STATUS TEMP4
```
![ROLLUP](/img/telemetry_viewer/widgets/rollup.png)


### SIGNAL
<div class="right">(Since 5.17.2)</div>**テレメトリ値に基づいて変化するセルラー信号アイコンを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED</span> | False |

使用例:
```ruby
SIGNAL INST HEALTH_STATUS TEMP1
  # クリック時に開くスクリーン
  SETTING SCREEN INST HS
  # 1バー、2バー、3バーアイコンを設定するときに比較する値
  # デフォルトは30、60、90（0から100の範囲）
  # 値 < -50 の場合、バーは表示されません
  # 値 >= -50 かつ < 0 の場合、1バー表示
  # 値 >= 0 かつ < 50 の場合、2バー表示
  # 値 >= 50 の場合、5バー表示
  SETTING RANGE -50 0 50
```
![SIGNAL](/img/telemetry_viewer/widgets/signal.png)


### TEXTBOX
**複数行のテキスト用の大きなボックスを提供する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 幅 | テキストボックスの幅（ピクセル単位）（デフォルト = 200） | False |
| 高さ | テキストボックスの高さ（ピクセル単位）（デフォルト = 200） | False |

使用例:
```ruby
TEXTBOX INST HEALTH_STATUS PACKET_TIMEFORMATTED 150 70
```
![TEXTBOX](/img/telemetry_viewer/widgets/textbox.png)


### VALUE
**テレメトリアイテムの値を持つボックスを表示する**

ボックスの白い部分は値が変化しない間はグレーに暗くなり、値が変わるたびに白く明るくなります。さらに、値はアイテムの制限状態に基づいて色付けされます（例えば、制限を超えている場合は赤色）。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |
| 文字数 | 値ボックスの幅（文字数）（デフォルト = 12） | False |

使用例:
```ruby
VALUE INST HEALTH_STATUS TEMP1 CONVERTED 18
VALUE INST HEALTH_STATUS TEMP1
```
![VALUE](/img/telemetry_viewer/widgets/value.png)


## インタラクティブウィジェット
****

インタラクティブウィジェットはユーザーからの入力を収集するために使用されます。何らかのグラフィカルな表現を出力するだけの他のすべてのウィジェットとは異なり、インタラクティブウィジェットはキーボードまたはマウスからの入力を許可します。


### BUTTON
**クリック可能な長方形のボタンを表示する**

クリックすると、ボタンは割り当てられたJavaScriptコードを実行します。ボタンは
コマンドの送信や他のタスクの実行に使用できます。ボタンに
他のウィジェットからの値を使用させたい場合は、それらを名前付きウィジェットとして定義し、
`screen.getNamedWidget("WIDGET_NAME").text()`メソッドを使用して値を読み取ります。
CHECKBUTTONの例を参照してください。

ボタンコードはかなり複雑になることがあるので、文字列連結を使用して
読みやすくすることを忘れないでください。`+`を使用すると、文字列連結中に
改行が自動的に挿入されます。`\`を使用する場合は、行を
単一のセミコロン`;`で区切る必要があります。COSMOSは二重セミコロン`;;`を使用して、行が
別々に評価されるべきであることを示します。すべてのOpenC3コマンド（api.cmdを使用）は
`;;`で区切る必要があることに注意してください。

api.cmd()を使用してボタンでコマンドを送信できます。cmd()構文は
標準のCOSMOSスクリプト構文と全く同じです。また、JavaScript Promisesを使用して
画面でテレメトリをリクエストして使用することもできます。

`api.tlm('INST PARAMS VALUE3', 'RAW').then(dur => api.cmd('INST COLLECT with TYPE NORMAL, DURATION '+dur))"`

api.tlm()関数はPromiseを返し、then()で解決され、
その時点で受け取ったテレメトリ値でコマンドを送信します。

`runScript()`メソッドを使用してBUTTONからスクリプトを起動できます。`runScript()`は3つのパラメータを取ります：
スクリプト名、Script Runnerのフォアグラウンドでスクリプトを開くかどうか（デフォルト = true）、
環境変数のハッシュです。例：`runScript('INST/procedures/script.rb', false, {'VAR': 'VALUE'})`


| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ボタンテキスト | ボタンに表示されるテキスト | True |
| ボタンコード | ボタンが押されたときに実行されるJavaScriptコード | True |

使用例:
```ruby
BUTTON 'Start Collect' 'api.cmd("INST COLLECT with TYPE NORMAL, DURATION 5")'
BUTTON 'Run Checks' 'runScript("INST/procedures/checks.rb")'
# バックグラウンドチェックボックスと環境変数を使用したより複雑な例
NAMED_WIDGET SCRIPTNAME COMBOBOX collect.rb checks.rb
NAMED_WIDGET BG CHECKBUTTON 'Background'
BUTTON 'Run Script' "var script=screen.getNamedWidget('SCRIPTNAME').text();" \
  # スクリプトでENV['TYPE']として使用される環境変数を設定
  "var env = {}; env['TYPE'] = 'TEST';" \
  "runScript('INST/procedures/'+script, !screen.getNamedWidget('BG').checked(), env)"
```
![BUTTON](/img/telemetry_viewer/widgets/button.png)


### CHECKBUTTON
**チェックボックスを表示する**

これは単独では使用が限られており、主にNAMED_WIDGETと組み合わせて使用されることに注意してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| チェックボックステキスト | チェックボックスの横に表示されるテキスト | True |
| チェック済み | チェックボックスの初期状態がチェックされているかどうか（デフォルト = false）。チェックボックスをチェックしない場合は値を与えないでください。 | False |

使用例:
```ruby
NAMED_WIDGET UNCHECKED CHECKBUTTON 'Default Unchecked'
NAMED_WIDGET CHECK CHECKBUTTON 'Ignore Hazardous Checks' CHECKED
BUTTON 'Send' 'screen.getNamedWidget("CHECK").checked() ? ' \
  'api.cmd_no_hazardous_check("INST CLEAR") : api.cmd("INST CLEAR")'
# プログラムでチェックボックスをチェックまたはチェック解除できます
BUTTON 'Check' 'screen.getNamedWidget("CHECK").value = true'
BUTTON 'Uncheck' 'screen.getNamedWidget("CHECK").value = false'
```
![CHECKBUTTON](/img/telemetry_viewer/widgets/checkbutton.png)


### COMBOBOX
**テキストアイテムのドロップダウンリストを表示する**

これは単独では使用が限られており、主にNAMED_WIDGETと組み合わせて使用されることに注意してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| オプションテキスト1 | 選択ドロップダウンに表示するテキスト | True |
| オプションテキストn | 選択ドロップダウンに表示するテキスト | False |

使用例:
```ruby
BUTTON 'Start Collect' 'var type = screen.getNamedWidget("COLLECT_TYPE").text();' +
  'api.cmd("INST COLLECT with TYPE "+type+", DURATION 10.0")'
NAMED_WIDGET COLLECT_TYPE COMBOBOX NORMAL SPECIAL
```
![COMBOBOX](/img/telemetry_viewer/widgets/combobox.png)


### DATE
**日付ピッカーを表示する**

これは単独では使用が限られており、主にNAMED_WIDGETと組み合わせて使用されることに注意してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 日付ラベル | データ選択にラベル付けするテキスト（デフォルトは'Date'） | False |

使用例:
```ruby
BUTTON 'Alert Date' 'var date = screen.getNamedWidget("DATE").text();' +
  'alert("Date:"+date)'
NAMED_WIDGET DATE DATE
```
![DATE](/img/telemetry_viewer/widgets/date.png)


### RADIOGROUP
**RADIOBUTTONのグループを作成する**

RADIOBUTTONは選択ロジックを有効にするためにグループの一部である必要があります

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 初期選択ボタン | 初期化時にラジオボタンを選択します（0ベース） | False |

### RADIOBUTTON
**ラジオボタンとテキストを表示する**

これは単独では使用が限られており、主にNAMED_WIDGETと組み合わせて使用されます。単一のRADIOBUTTONの一般的な選択を有効にするには、RADIOGROUPに含まれている必要があります。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| テキスト | ラジオボタンの隣に表示するテキスト | True |

使用例:
```ruby
NAMED_WIDGET GROUP RADIOGROUP 1 # 初期状態で'Clear'を選択、0ベースインデックス
  RADIOBUTTON 'Abort'
  RADIOBUTTON 'Clear'
END
BUTTON 'Send' "screen.getNamedWidget('GROUP').selected() === 0 ? " +
  "api.cmd('INST ABORT') : api.cmd('INST CLEAR')"
```
![RADIOBUTTON](/img/telemetry_viewer/widgets/radiobutton.png)


### TEXTFIELD
**ユーザーがテキストを入力できる長方形のボックスを表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 文字数 | テキストフィールドの幅（文字数）（デフォルト = 12） | False |
| テキスト | テキストフィールドに入れるデフォルトテキスト（デフォルトは空白） | False |

使用例:
```ruby
NAMED_WIDGET DURATION TEXTFIELD 12 "10.0"
BUTTON 'Start Collect' 'var dur = screen.getNamedWidget("DURATION").text();' +
      'api.cmd("INST COLLECT with TYPE NORMAL, DURATION "+dur+"")'
```
![TEXTFIELD](/img/telemetry_viewer/widgets/textfield.png)


### TIME
**時間ピッカーを表示する**

これは単独では使用が限られており、主にNAMED_WIDGETと組み合わせて使用されます。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 時間ラベル | 時間選択にラベル付けするテキスト（デフォルトは'Time'） | False |

使用例:
```ruby
BUTTON 'Alert Time' 'var time = screen.getNamedWidget("TIME").text();' +
  'alert("Time:"+time)'
NAMED_WIDGET TIME TIME
```
![TIME](/img/telemetry_viewer/widgets/time.png)


## キャンバスウィジェット
****

キャンバスウィジェットは、テレメトリ画面にカスタム表示を描画するために使用されます。キャンバス座標フレームは(0,0)をキャンバスの左上隅に配置します。


### CANVAS
**他のキャンバスウィジェットのためのレイアウトウィジェット**

すべてのキャンバスウィジェットはCANVASウィジェット内に含まれている必要があります。

:::warning
キャンバス座標フレームは(0,0)をキャンバスの左上隅に配置します。
:::

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 幅 | キャンバスの幅 | True |
| 高さ | キャンバスの高さ | True |

### CANVASLABEL
**キャンバスにテキストを描画する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| X位置 | キャンバス上のテキストの左上隅のX位置 | True |
| Y位置 | キャンバス上のテキストの左上隅のY位置 | True |
| テキスト | キャンバスに描画するテキスト | True |
| フォントサイズ | テキストのフォントサイズ（デフォルト = 12） | False |
| 色 | テキストの色 | False |

使用例:
```ruby
CANVAS 100 100
  CANVASLABEL 5 34 "Label1" 24 red
  CANVASLABEL 5 70 "Label2" 18 blue
END
```
![CANVASLABEL](/img/telemetry_viewer/widgets/canvaslabel.png)


### CANVASLABELVALUE
**テレメトリアイテムのテキスト値をオプションのフレーム内にキャンバス上に描画する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| X位置 | キャンバス上のテキストの左上隅のX位置 | True |
| Y位置 | キャンバス上のテキストの左上隅のY位置 | True |
| フォントサイズ | テキストのフォントサイズ（デフォルト = 12） | False |
| 色 | テキストの色 | False |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED。<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |

使用例:
```ruby
CANVAS 200 100
  CANVASLABELVALUE INST HEALTH_STATUS TEMP1 5 34 12 red
  CANVASLABELVALUE INST HEALTH_STATUS TEMP2 5 70 10 blue WITH_UNITS
END
```
![CANVASLABELVALUE](/img/telemetry_viewer/widgets/canvaslabelvalue.png)


### CANVASIMAGE
**キャンバスに画像を表示する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 画像ファイル名 | 画像ファイルの名前。ファイルはプラグインのtargets/TARGET/publicディレクトリに存在する必要があります。 | True |
| X位置 | キャンバス上の画像の左上隅のX位置 | True |
| Y位置 | キャンバス上の画像の左上隅のY位置 | True |

使用例:
```ruby
CANVAS 250 430
  CANVASIMAGE "satellite.png" 10 10 200 200
    SETTING SCREEN INST HS
  CANVASIMAGE "https://images.pexels.com/photos/256152/pexels-photo-256152.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=640&w=426" 0 250 250 150
END
```
![CANVASIMAGE](/img/telemetry_viewer/widgets/canvasimage.png)

以下の設定はCANVASIMAGEに適用されます。これらはSETTINGキーワードを使用して適用されます。
#### SCREEN
**クリック時に別のスクリーンを開く**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲットの名前 | True |
| スクリーン名 | スクリーンの名前 | True |

### CANVASIMAGEVALUE
**テレメトリ値によって変化する画像をキャンバスに表示する**

さまざまなSETTING値を使用して、テレメトリに基づいて表示する画像を指定します。例えば、SETTING IMAGE CONNECTED "ground_on.png" 400 100。完全な例についてはDEMOを参照してください。

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 値タイプ | 表示する値のタイプ<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | True |
| デフォルト画像ファイル名 | 表示するデフォルト画像。ファイルはtargets/TARGET/publicディレクトリに存在する必要があります。 | True |
| X位置 | キャンバス上の画像の左上隅のX位置 | True |
| Y位置 | キャンバス上の画像の左上隅のY位置 | True |
| 画像の幅 | 画像の幅（デフォルトは100%） | False |
| 画像の高さ | 画像の高さ（デフォルトは100%） | False |

使用例:
```ruby
CANVAS 230 230
  CANVASIMAGEVALUE INST HEALTH_STATUS GROUND1STATUS CONVERTED "ground_error.png" 10 10 180 180
    SETTING IMAGE CONNECTED "ground_on.png" 10 10
    SETTING IMAGE UNAVAILABLE "ground_off.png" 10 10
    SETTING SCREEN INST HS
END
```
![CANVASIMAGEVALUE](/img/telemetry_viewer/widgets/canvasimagevalue.png)

以下の設定はCANVASIMAGEVALUEに適用されます。これらはSETTINGキーワードを使用して適用されます。
#### IMAGE
**状態または値に画像をマッピングする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 値 | 状態または値 | True |
| 画像ファイル名 | 表示する画像。ファイルはtargets/TARGET/publicディレクトリに存在する必要があります。 | True |
| X位置 | キャンバス上の画像の左上隅のX位置 | True |
| Y位置 | キャンバス上の画像の左上隅のY位置 | True |

#### SCREEN
**クリック時に別のスクリーンを開く**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲットの名前 | True |
| スクリーン名 | スクリーンの名前 | True |

### CANVASLINE
**キャンバスに線を描画する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 開始X位置 | キャンバス上の線の開始位置のX座標 | True |
| 開始Y位置 | キャンバス上の線の開始位置のY座標 | True |
| 終了X位置 | キャンバス上の線の終了位置のX座標 | True |
| 終了Y位置 | キャンバス上の線の終了位置のY座標 | True |
| 色 | 線の色 | False |
| 幅 | 線の幅（ピクセル単位）（デフォルト = 1） | False |

使用例:
```ruby
CANVAS 100 50
  CANVASLINE 5 5 95 5
  CANVASLINE 5 5 5 45 green 2
  CANVASLINE 95 5 95 45 blue 3
END
```
![CANVASLINE](/img/telemetry_viewer/widgets/canvasline.png)


### CANVASLINEVALUE
**色が変化する線をキャンバスに描画する**

線は関連するテレメトリアイテムの値に基づいて2つの色のいずれかで表現されます

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| ターゲット名 | ターゲット名 | True |
| パケット名 | パケット名 | True |
| アイテム名 | アイテム名 | True |
| 開始X位置 | キャンバス上の線の開始位置のX座標 | True |
| 開始Y位置 | キャンバス上の線の開始位置のY座標 | True |
| 終了X位置 | キャンバス上の線の終了位置のX座標 | True |
| 終了Y位置 | キャンバス上の線の終了位置のY座標 | True |
| 幅 | 線の幅（ピクセル単位）（デフォルト = 3） | False |
| 値タイプ | 表示する値のタイプ。デフォルトはCONVERTED<br/><br/>有効な値: <span class="values">RAW, CONVERTED, FORMATTED, WITH_UNITS</span> | False |

使用例:
```ruby
CANVAS 120 50
  CANVASLABELVALUE INST HEALTH_STATUS GROUND1STATUS 0 12 12 black
  CANVASLINEVALUE INST HEALTH_STATUS GROUND1STATUS 5 25 115 25 5 RAW
    SETTING VALUE_EQ 1 GREEN
    SETTING VALUE_EQ 0 RED
  CANVASLINEVALUE INST HEALTH_STATUS GROUND1STATUS 5 45 115 45
    SETTING VALUE_EQ CONNECTED GREEN
    SETTING VALUE_EQ UNAVAILABLE RED
END
```
![CANVASLINEVALUE](/img/telemetry_viewer/widgets/canvaslinevalue.png)

以下の設定はCANVASLINEVALUEに適用されます。これらはSETTINGキーワードを使用して適用されます。
#### VALUE_EQ
<div class="right">(Since 5.5.1)</div>**値を色にマッピングする**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| 値 | 状態または値 | True |
| 色 | 線の色 | True |

### CANVASDOT
**キャンバスに点を描画する**

| パラメータ | 説明 | 必須 |
|-----------|-------------|----------|
| X位置 | 点のX位置 | True |
| Y位置 | 点のY位置 | True |
| 色 | 点の色 | True |
| 半径 | 点の半径（ピクセル単位） | True |

使用例:
```ruby
CANVAS 50 50
  CANVASDOT 10 15 BLUE 5
END
```
![CANVASDOT](/img/telemetry_viewer/widgets/canvasdot.png)



## 例ファイル

例ファイル: TARGET/myscreen.txt

<!-- prettier-ignore -->
```ruby
SCREEN AUTO AUTO 0.5
VERTICAL
  TITLE "<%= target_name %> Commanding Examples"
  LABELVALUE INST HEALTH_STATUS COLLECTS
  LABELVALUE INST HEALTH_STATUS COLLECT_TYPE
  LABELVALUE INST HEALTH_STATUS DURATION
  VERTICALBOX "Send Collect Command:"
    HORIZONTAL
      LABEL "Type: "
      NAMED_WIDGET COLLECT_TYPE COMBOBOX NORMAL SPECIAL
    END
    HORIZONTAL
      LABEL "  Duration: "
      NAMED_WIDGET DURATION TEXTFIELD 12 "10.0"
    END
    BUTTON 'Start Collect' "api.cmd('INST COLLECT with TYPE '+screen.getNamedWidget('COLLECT_TYPE').text()+', DURATION '+screen.getNamedWidget('DURATION').text())"
  END
  SETTING BACKCOLOR 163 185 163
  VERTICALBOX "パラメータ-less Commands:"
    NAMED_WIDGET GROUP RADIOGROUP 1 # Select 'Clear' initially, 0-based index
      RADIOBUTTON 'Abort'
      RADIOBUTTON 'Clear'
    END
    NAMED_WIDGET CHECK CHECKBUTTON 'Ignore Hazardous Checks' # No option is by default UNCHECKED
    BUTTON 'Send' "screen.getNamedWidget('GROUP').selected() === 0 ? api.cmd('INST ABORT') : (screen.getNamedWidget('CHECK').checked() ? api.cmd_no_hazardous_check('INST CLEAR') : api.cmd('INST CLEAR'))"
  END
  SETTING BACKCOLOR 163 185 163
END
```
