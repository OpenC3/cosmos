---
title: COSMOSのテスト
description: Playwrightインテグレーションテストとユニットテストの実行
sidebar_custom_props:
  myEmoji: 📋
---

## Playwright

### 前提条件

1. Yarnのインストール

   ```bash
   npm install --global yarn
   ```

1. COSMOS Playwrightリポジトリのクローン

   ```bash
   git clone https://github.com/OpenC3/cosmos-playwright
   ```

1. Playwrightと依存関係のインストール

   ```bash
   cosmos-playwright % yarn install
   ```

### Playwrightテスト

1. COSMOSの起動

   ```bash
   cosmos % openc3.sh start
   ```

1. ブラウザでCOSMOSを開きます。ログイン画面でパスワードを「password」に設定します。

1. テストの実行（注：--headedオプションはテストを視覚的に表示します。バックグラウンドで実行する場合は省略してください）

   テストは並行実行されるグループと直列実行されるグループに分けられています。これは全体の実行時間を短縮するためです。

   ```bash
   cosmos-playwright % yarn test:parallel --headed
   cosmos-playwright % yarn test:serial --headed
   ```

   両方のグループを一緒に実行することもできますが、--headedオプションは両方のグループに適用されません：

   ```bash
   cosmos-playwright % yarn test
   ```

1. _[任意]_ istanbul/nycカバレッジソースルックアップの修正（Linuxでない場合は `fixwindows` を使用）。

   このステップなしでもテストは正常に実行され、カバレッジ統計は取得できますが、行ごとのカバレッジは機能しません。

   ```bash
   cosmos-playwright % yarn fixlinux
   ```

1. コードカバレッジの生成

   ```bash
   cosmos-playwright % yarn coverage
   ```

コードカバレッジレポートは `openc3-playwright/coverage/index.html` で閲覧できます

## Rubyユニットテスト

1. **cosmos/openc3** フォルダに移動し、次のコマンドを実行します：

   ```bash
   cosmos/openc3 % rake build
   cosmos/openc3 % bundle exec rspec
   ```

コードカバレッジレポートは `cosmos/openc3/coverage/index.html` にあります

## Pythonユニットテスト

1. **cosmos/openc3/python** フォルダに移動し、次のコマンドを実行します：

   ```bash
   cosmos/openc3/python % python -m pip install poetry
   cosmos/openc3/python % poetry install
   cosmos/openc3/python % poetry run coverage run -m pytest
   cosmos/openc3/python % poetry run coverage html
   ```

コードカバレッジレポートは `cosmos/openc3/python/coverage/index.html` にあります
