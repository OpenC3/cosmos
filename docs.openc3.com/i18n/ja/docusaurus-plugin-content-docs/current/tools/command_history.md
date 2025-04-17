---
title: コマンド履歴 (Enterprise)
description: 送信されたすべてのコマンド、送信者、成功したかどうかを確認
sidebar_custom_props:
  myEmoji: 🛠️
---

## はじめに

コマンド履歴は、COSMOSで送信されたすべてのコマンドを確認する機能を提供します。コマンドは実行時間順にリストされ、誰がコマンドを送信したか、そして（検証された場合）それらが成功したかどうかが含まれます。

![コマンド履歴](/img/command_history/command_history.png)

### 時間の選択

デフォルトでは、コマンド履歴は過去1時間のコマンドを表示し、送信されたコマンドを継続的にストリーミングします。開始日時と終了日時の選択ツールを使用して、異なる時間範囲を選択できます。

## コマンドテーブル

コマンドテーブルは時間でソートされ、ユーザー（またはプロセス）、コマンド、結果、およびオプションの説明がリストされています。

上記のように、ユーザーはシステム内の実際のユーザー（admin、operator）またはバックグラウンドプロセス（DEFAULT\_\_MULTI\_\_INST、DEFAULT\_\_DECOM\_\_INST2）になります。

結果フィールドは、[VALIDATOR](../configuration/command#validator)キーワードによって確立されたコマンドバリデータを実行した結果です。コマンドバリデータは、pre_checkとpost_checkの両方のメソッドでコマンドの成功または失敗を検証するために使用されるRubyまたはPythonクラスです。通常、コマンドが失敗すると、上記の例のように説明が与えられます。

詳細については、[VALIDATOR](../configuration/command#validator)のドキュメントを読み、また[COSMOS Demo](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo)の[Rubyの例](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST/lib/inst_cmd_validator.rb)と[Pythonの例](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST2/lib/inst2_cmd_validator.py)を参照してください。