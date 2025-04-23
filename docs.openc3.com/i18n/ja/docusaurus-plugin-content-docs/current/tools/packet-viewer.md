---
title: パケットビューア
description: すべてのパケットとその項目を表示
sidebar_custom_props:
  myEmoji: 🛠️
---

## はじめに

パケットビューアは、定義されたすべてのターゲット、パケット、項目の現在の値を表示するために設定を必要としないライブテレメトリビューアです。制限値を持つ項目は、現在の状態に応じて色付け（青、緑、黄、または赤）されて表示されます。項目を右クリックすると詳細情報を取得できます。

![パケットビューア](pathname:///img/packet_viewer/packet_viewer.png)

## パケットビューアのメニュー

### ファイルメニュー項目

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/packet_viewer/file_menu.png').default}
alt="ファイルメニュー"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 120 + 'px'}} />

- 更新間隔と古い間隔を変更
- 保存された設定を開く
- 現在の設定（表示設定）を保存
- 設定をリセット（デフォルト設定）

### 表示メニュー項目

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/packet_viewer/view_menu.png').default}
alt="表示メニュー"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 180 + 'px'}} />

- [無視された項目](../configuration/target.md#ignore_item)を表示
- [派生](../configuration/telemetry.md#derived-items)項目を最後に表示
- [単位](../configuration/telemetry#units)付きで整形された項目を表示
- [整形された](../configuration/telemetry#format_string)項目を表示
- [変換された](../configuration/telemetry#read_conversion)項目を表示
- 生の項目を表示

## パケットの選択

パケットビューアを最初に開くと、アルファベット順で最初のターゲットとパケットが開きます。ドロップダウンメニューをクリックして、項目テーブルを新しいパケットに更新します。項目のリストをフィルタリングするには、検索ボックスに入力できます。

### 詳細

項目を右クリックして詳細を選択すると、詳細ダイアログが開きます。

![詳細](pathname:///img/packet_viewer/temp1_details.png)

このダイアログは、テレメトリ項目に定義されているすべてのものをリストします。