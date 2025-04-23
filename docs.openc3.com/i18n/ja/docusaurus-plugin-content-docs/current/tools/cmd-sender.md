---
title: コマンドセンダー
description: 個別のコマンドを送信する
sidebar_custom_props:
  myEmoji: 🛠️
---

## はじめに

コマンドセンダーは、COSMOSからあらゆるコマンドを送信する機能です。コマンドは、ターゲットとパケットのドロップダウンフィールドを使用して選択され、コマンドパラメータ（ある場合）が入力されます。コマンド履歴が保存され、編集も可能です。コマンド履歴内のコマンドはEnterキーを押すことで再実行できます。関連するテレメトリまたは画面は、コマンド履歴の隣の右下に表示されます。

![コマンドセンダー](/img/command_sender/command_sender.png)

## コマンドセンダーのメニュー

### モードメニュー項目

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/command_sender/mode_menu.png').default}
alt="モードメニュー"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 120 + 'px'}} />

- パラメータ範囲チェックを無視
- パラメータ状態値を16進数で表示
- 無視されたパラメータを表示
- すべてのパラメータ変換を無効化

## コマンドの送信

まず「ターゲットを選択 (Select Target)」ドロップダウンからターゲットを選択してコマンドを選択します。ターゲットを変更すると、「パケットを選択 (Select Packet)」オプションが自動的に更新され、そのターゲットからのコマンドのみが表示されます。コマンドにパラメータがある場合、すべてのパラメータを含むテーブルが生成されます。

![INST COLLECT](/img/command_sender/inst_collect.png)

状態を持つパラメータ（上記の例ではTYPE）をクリックすると、状態を選択するためのドロップダウンが表示されます。状態を選択すると、その隣の値フィールドに値が入力されます。コマンドを送信すると、ステータステキストとコマンド履歴が更新されます。

![状態](/img/command_sender/collect_states.png)

コマンド履歴を直接編集してパラメータ値を変更できます。その行でEnterキーを押すと、コマンドが実行されます。コマンドが変更された場合、コマンド履歴に新しい行が入力されます。同じ行でEnterキーを数回押すと、ステータステキストが送信されたコマンドの数（次の例では3）で更新されます。

![履歴](/img/command_sender/history.png)

### 危険なコマンド

[危険な](../configuration/command.md#hazardous)コマンドを送信すると、コマンドを送信するかどうかをユーザーに確認するプロンプトが表示されます。

![INST CLEAR](/img/command_sender/inst_clear.png)

コマンドには危険な[状態](../configuration/command.md#state)（INST COLLECT with TYPE SPECIAL）もあり、ユーザーにプロンプトが表示されます。この例では、無視されたパラメータを表示する、状態値を16進数で表示する（SPECIAL、0x1を参照）、範囲チェックを無効にする（DURATION 1000）、パラメータ変換を無効にするなど、すべてのメニューオプションをチェックしています。

![INST COLLECT 危険](/img/command_sender/inst_collect_hazardous.png)

「はい (Yes)」を選択すると、コマンドが送信され、表示されているすべてのパラメータで履歴が更新されます。スクリプトを作成する際には、明示的に[必須](../configuration/command.md#required)とマークされていない限り、すべてのパラメータはオプションであることに注意してください。