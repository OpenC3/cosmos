---
title: COSMOSの開発
description: COSMOSのビルドとフロントエンド・バックエンドの開発
sidebar_custom_props:
  myEmoji: 💻
---

# COSMOSの開発

COSMOSの開発に貢献したいですか？私たちのオープンソースCOSMOSコードはすべて[Github](https://github.com/)にあります。まず最初に[アカウント](https://github.com/join)を取得してください。次に[COSMOS](https://github.com/openc3/cosmos)リポジトリを[クローン](https://docs.github.com/ja/repositories/creating-and-managing-repositories/cloning-a-repository)します。私たちは他の方からの貢献を[プルリクエスト](https://docs.github.com/ja/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests)として受け付けています。

## 開発ツール

COSMOSのコアチームは[Visual Studio Code](https://code.visualstudio.com/)エディタを使用して開発しており、強くお勧めします。また、docker、kubernetes、gitlens、prettier、eslint、python、vetur、rubyなど多くの拡張機能を利用しています。これらのプラグインの構成を支援するために、VSCode用の`openc3.code-workspace`設定をコミットしています。また、COSMOSを実行するための要件である[Docker Desktop](https://www.docker.com/products/docker-desktop)も必要です。さらに、[NodeJS](https://nodejs.org/ja/download/)と[yarn](https://yarnpkg.com/getting-started/install)もインストールする必要があります。

# COSMOSのビルド

注意：私たちは主にMacOSでCOSMOSを開発しているため、ここで紹介するコマンドはbashスクリプトを参照していますが、Windowsでも同じファイルがバッチスクリプトとして存在します。

`openc3.sh`スクリプトを使用してCOSMOSをビルドします：

```bash
% ./openc3.sh build
```

これにより、すべてのCOSMOSコンテナの依存関係がダウンロードされ、ローカルコンテナがビルドされます。注意：特に初回のビルドでは、これには長時間かかることがあります！

ビルドが完了すると、次のコマンドでビルドされたイメージを確認できます：

```bash
% docker image ls | grep "openc3"
openc3inc/openc3-cosmos-init                latest   4cac7a3ea9d3   29 hours ago   446MB
openc3inc/openc3-cosmos-script-runner-api   latest   4aacbaf49f7a   29 hours ago   431MB
openc3inc/openc3-cosmos-cmd-tlm-api         latest   9a8806bd4be3   3 days ago     432MB
openc3inc/openc3-operator                   latest   223e98129fe9   3 days ago     405MB
openc3inc/openc3-base                       latest   98df5c0378c2   3 days ago     405MB
openc3inc/openc3-redis                      latest   5a3003a49199   8 days ago     111MB
openc3inc/openc3-traefik                    latest   ec13a8d16a2f   8 days ago     104MB
openc3inc/openc3-minio                      latest   787f6e3fc0be   8 days ago     238MB
openc3inc/openc3-node                       latest   b3ee86d3620a   8 days ago     372MB
openc3inc/openc3-ruby                       latest   aa158bbb9539   8 days ago     326MB
```

:::info オフラインでのビルド

オフライン環境でビルドする場合や、プライベートなRubygems、NPM、APKサーバー（例：Nexus）を使用したい場合は、[.env](https://github.com/openc3/cosmos/blob/main/.env)ファイルで次の環境変数を更新できます：RUBYGEMS_URL、NPM_URL、APK_URLなど。例：

    ALPINE_VERSION=3.19<br/>
    ALPINE_BUILD=7<br/>
    RUBYGEMS_URL=https://rubygems.org<br/>
    NPM_URL=https://registry.npmjs.org<br/>
    APK_URL=http://dl-cdn.alpinelinux.org<br/>

:::

# COSMOSの実行

開発モードでCOSMOSを実行すると、内部APIポートへのlocalhostアクセスが可能になり、cmd-tlm-apiとscript-runner-api Railsサーバーで`RAILS_ENV=development`が設定されます。開発モードで実行するには：

```bash
% ./openc3.sh run
```

これで実行中のコンテナを確認できます（スペースを節約するためにCONTAINER ID、CREATED、STATUSは削除しています）：

```bash
% docker ps
IMAGE                                             COMMAND                  PORTS                      NAMES
openc3/openc3-cmd-tlm-api:latest         "/sbin/tini -- rails…"   127.0.0.1:2901->2901/tcp   cosmos-openc3-cmd-tlm-api-1
openc3/openc3-script-runner-api:latest   "/sbin/tini -- rails…"   127.0.0.1:2902->2902/tcp   cosmos-openc3-script-runner-api-1
openc3/openc3-traefik:latest             "/entrypoint.sh trae…"   0.0.0.0:2900->80/tcp       cosmos-openc3-traefik-1
openc3/openc3-operator:latest            "/sbin/tini -- ruby …"                              cosmos-openc3-operator-1
openc3/openc3-minio:latest               "/usr/bin/docker-ent…"   127.0.0.1:9000->9000/tcp   cosmos-openc3-minio-1
openc3/openc3-redis:latest               "docker-entrypoint.s…"   127.0.0.1:6379->6379/tcp   cosmos-openc3-redis-1
```

localhost:2900にアクセスすると、COSMOSが起動して実行されているのを確認できます！

## フロントエンドアプリケーションの実行

COSMOSが起動して実行されている状態で、個々のCOSMOSアプリケーションを開発するにはどうすればよいでしょうか？

1. yarnでフロントエンドをブートストラップします

```bash
openc3-init/plugins % yarn
openc3-init/plugins % yarn build:common
```

2. ローカルのCOSMOSアプリケーション（CmdTlmServer、ScriptRunnerなど）を提供します

```bash
openc3-init % cd plugins/packages/openc3-tool-scriptrunner
openc3-tool-scriptrunner % yarn serve
built in 128722ms
```

3. アプリケーションの[single SPA](https://single-spa.js.org/)オーバーライドを設定します

    localhost:2900にアクセスして右クリックし、「検証」を選択します<br/>
    コンソールに以下を貼り付けます：

```javascript
localStorage.setItem("devtools", true);
```

    更新すると、右下に`{...}`が表示されます<br/>
    アプリケーション(@openc3/tool-scriptrunner)の横にあるDefaultボタンをクリックします<br/>
    開発パスを貼り付けます。これはローカルのyarn serveが返すポートとツール名（scriptrunner）に依存します

        http://localhost:2914/tools/scriptrunner/main.js

4. ページを更新すると、アプリケーション（この例ではScript Runner）のローカルコピーが表示されます。コード（`console.log`など）を動的に追加すると、yarnウィンドウで再コンパイルされ、ブラウザが更新されて新しいコードが表示されます。フロントエンド開発を計画している場合は、ブラウザの[開発ツール](https://developer.chrome.com/docs/devtools/overview/)に慣れることを強くお勧めします。

## バックエンドサーバーの実行

開発したいコードがcmd-tlm-apiまたはscript-runner-apiバックエンドサーバーの場合、開発コピーへのアクセスを可能にするためにいくつかの手順があります。

1. traefikの開発バージョンを実行します。COSMOSはtraefikを使用してAPIリクエストを適切な場所に転送します。

```bash
% cd openc3-traefik
openc3-traefik % docker ps
# traefikを含む名前のコンテナを探します
openc3-traefik % docker stop cosmos-openc3-traefik-1
openc3-traefik % docker build --build-arg TRAEFIK_CONFIG=traefik-dev.yaml -t openc3-traefik-dev .
openc3-traefik % docker run --network=openc3-cosmos-network -p 2900:2900 -it --rm openc3-traefik-dev
```

2. cmd-tlm-apiまたはscript-runner-apiのローカルコピーを実行します

```bash
% cd openc3-cosmos-cmd-tlm-api
openc3-cosmos-cmd-tlm-api % docker ps
# cmd-tlm-apiを含む名前のコンテナを探します
openc3-cosmos-cmd-tlm-api % docker stop cosmos-openc3-cosmos-cmd-tlm-api-1
# Windowsでは以下を実行します：
openc3-cosmos-cmd-tlm-api> dev_server.bat
# Linuxでは、.envファイルのすべての環境変数を設定し、REDISをローカルにオーバーライドします
openc3-cosmos-cmd-tlm-api % set -a; source ../.env; set +a
openc3-cosmos-cmd-tlm-api % export OPENC3_REDIS_HOSTNAME=127.0.0.1
openc3-cosmos-cmd-tlm-api % export OPENC3_REDIS_EPHEMERAL_HOSTNAME=127.0.0.1
openc3-cosmos-cmd-tlm-api % bundle install
openc3-cosmos-cmd-tlm-api % bundle exec rails s
```

3. `bundle exec rails s`コマンドが返ると、フロントエンドコードからの操作によるAPIリクエストが表示されるようになります。cmd-tlm-apiコードにコード（Rubyデバッグステートメントなど）を追加した場合は、サーバーを停止（CTRL-C）して再起動し、その効果を確認する必要があります。
