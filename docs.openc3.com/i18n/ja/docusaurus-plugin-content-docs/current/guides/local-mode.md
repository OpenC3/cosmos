---
title: ローカルモード
description: ホストファイルシステム上で直接スクリプトと画面を編集する
sidebar_custom_props:
  myEmoji: 🧭
---

ローカルモードは、COSMOS 5.0.9リリースの新機能です。これは、編集されたプラグインの設定を取得して、設定管理できるようにすることを目的としています。プラグインの一部（スクリプトや画面）を選択したエディタでローカルに編集し、その変更がCOSMOSプラグインにすぐに反映されるようにします。これにより、コマンドやテレメトリ、インターフェース定義を編集する際に必要なプラグインのビルド/インストールサイクルを回避できます。

## ローカルモードの使用

このチュートリアルでは、[インストールガイド](../getting-started/installation.md)で設定されたCOSMOSデモを使用します。[cosmos-project](https://github.com/OpenC3/cosmos-project)をクローンし、`openc3.sh run`を使用して起動しているはずです。

プロジェクトディレクトリを確認すると、`plugins/DEFAULT/openc3-cosmos-demo`ディレクトリが表示されるはずです。これには、インストールされたgemと`plugin_instance.json`ファイルの両方が含まれています。`plugin_instance.json`ファイルは、プラグインがインストールされたときのplugin.txtの値を取得します。注意点として、pluginsディレクトリ内のすべてのファイルはプロジェクトと共に設定管理されることを意図しています。これにより、ローカルで編集してチェックインすると、別のユーザーがプロジェクトをクローンして全く同じ設定を取得できます。これについては後で説明します。

### スクリプトの編集

:::info Visual Studio Code
このチュートリアルでは、COSMOSの開発者が使用しているエディタである[VS Code](https://code.visualstudio.com)を使用します。
:::

ローカルモードの最も一般的なユースケースはスクリプト開発です。Script Runnerを起動し、`INST/procedures/checks.rb`ファイルを開きます。このスクリプトを実行すると、完了まで実行できないいくつかのエラー（設計上）があることに気付くでしょう。修正しましょう！7行目と9行目をコメントアウトして、スクリプトを保存します。これでローカルモードがスクリプトのコピーを`plugins/targets_modified/INST/procedures/checks.rb`に保存したことに気付くはずです。

![プロジェクトレイアウト](pathname:///img/guides/local_mode/project.png)

この時点で、ローカルモードはこれらのスクリプトを同期させているため、どちらの場所でも編集できます。ローカルスクリプトを編集して、先頭に簡単なコメントを追加してみましょう：`# This is a script`。Script Runnerに戻ると、変更は_自動的に_表示されていません。ただし、ファイル名の横にあるReloadボタンがあり、これをクリックするとバックエンドからファイルを更新できます。

![プロジェクトレイアウト](pathname:///img/guides/local_mode/reload_file.png)

これをクリックすると、COSMOSに同期されたファイルがリロードされ、コメントが表示されます。

![プロジェクトレイアウト](pathname:///img/guides/local_mode/reloaded.png)

### ローカルモードの無効化

ローカルモードを無効にしたい場合は、.envファイルを編集して設定`OPENC3_LOCAL_MODE=1`を削除できます。

## 構成管理

pluginsディレクトリを含むプロジェクト全体を構成管理することをお勧めします。これにより、COSMOSを起動するすべてのユーザーが同一の構成を起動できます。プラグインはtargets_modifiedディレクトリで見つかった変更で作成および更新されます。

いずれかの時点で、おそらくローカルの変更を元のプラグインに戻したいと思うでしょう。targets_modified/TARGETディレクトリ全体を元のプラグインにコピーするだけです。その時点で、CLIを使用してプラグインを再ビルドできます。

```
openc3-cosmos-demo % ./openc3.sh cli rake build VERSION=1.0.1
  Successfully built RubyGem
  Name: openc3-cosmos-demo
  Version: 1.0.1
  File: openc3-cosmos-demo-1.0.1.gem
```

管理者プラグインタブとアップグレードリンクを使用してプラグインをアップグレードします。新しくビルドしたプラグインを選択すると、COSMOSは既存の変更を検出し、それらを削除するかどうか尋ねます。これは永久に変更を削除するため、警告が付いています。変更を移動してプラグインを再ビルドしたので、チェックボックスをオンにしてINSTALLします。

![プロジェクトレイアウト](pathname:///img/guides/local_mode/delete_modified.png)

新しいプラグインがインストールされると、プロジェクトの`plugins`ディレクトリが新しいプラグインで更新され、targets_modifiedディレクトリの下にあるすべてのものは新しいインストールでは変更がないため削除されます。

ローカルモードは、ローカルファイルシステム上でスクリプトや画面を開発し、自動的にそれらをCOSMOSと同期させる強力な方法です。