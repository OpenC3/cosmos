---
sidebar_position: 2
title: インストール
description: OpenC3 COSMOSのインストール
sidebar_custom_props:
  myEmoji: 💾
---

## OpenC3 COSMOSのインストール

以下のセクションでは、様々なオペレーティングシステムにOpenC3 COSMOSをインストールする方法について説明します。このドキュメントは、ホストマシンのセットアップを行い、すぐにCOSMOSの実行バージョンを使用できるようにするのに役立ちます。

## ホストマシンへのOpenC3 COSMOSのインストール

### 前提条件

Linux（本番環境に推奨）をお使いの場合は、[Docker Engineのインストール](https://docs.docker.com/engine/install/)の手順に従ってDockerをインストールすることをお勧めします（LinuxではDocker Desktopを使用しないでください）。注意：Red Hatユーザーは[Podman](podman)ドキュメントをお読みください。WindowsまたはMacを使用している場合は、[Docker Desktop](https://docs.docker.com/get-docker/)をインストールしてください。すべてのプラットフォームで[Docker Compose](https://docs.docker.com/compose/install/)もインストールする必要があります。

- Dockerに割り当てる最小リソース: 8GB RAM, 1 CPU, 80GB ディスク
- Dockerに割り当てる推奨リソース: 16GB RAM, 2+ CPUs, 100GB ディスク
- WSL2を使用したWindows上のDocker:

  - WSL2はWindows上の合計メモリの50%または8GB（いずれか小さい方）を消費します。ただし、Windows ビルド20175より前のバージョン（確認するには`winver`を使用）では、合計メモリの80%を消費します。これはWindowsのパフォーマンスに悪影響を与える可能性があります！
  - Windowsビルド < 20175の場合、またはより細かい制御のために、C:\\Users\\\<username\>\\[.wslconfig](https://docs.microsoft.com/en-us/windows/wsl/wsl-config)を作成してください。32GBマシンでの推奨内容:

        [wsl2]
        memory=16GB
        swap=0

:::warning 重要: Dockerの接続タイムアウトを変更する
Dockerはデフォルトで、5分間のアイドル（データなし）接続を切断します。この「機能」は、Docker設定を調整しないと、最終的に問題を引き起こす可能性があります。これは、アイドル接続が切断されたり、データが再び流れ始めた後に再開できないことなどの形で現れることがあります。WindowsではC:\\Users\\username\\AppData\\Roaming\\Docker\\settings.jsonにあるファイルを、MacOSでは~/Library/Group Containers/group.com.docker/settings.jsonを見つけてください。タイムアウトを変更するには`vpnKitMaxPortIdleTime`の値を変更します（0に設定することをお勧めします）。**注意:** 0はタイムアウトなし（アイドル接続が切断されない）を意味します
:::

**注意:** 2021年12月現在、COSMOS Dockerコンテナは Alpine Dockerイメージをベースにしています。

### プロジェクトのクローン

始めるには、COSMOS [プロジェクトテンプレート](key-concepts#プロジェクト)を使用することをお勧めします。

```bash
git clone https://github.com/OpenC3/cosmos-project.git
git clone https://github.com/OpenC3/cosmos-enterprise-project.git
```

:::info オフラインインストール

  <p style={{"margin-bottom": 20 + 'px'}}>オフライン環境にインストールする必要がある場合は、まずCOSMOSコンテナを直接使用できるかどうかを確認してください。もし可能であれば、まずコンテナを保存できます：</p>

  <p style={{"margin-bottom": 20 + 'px'}}><code>./openc3.sh util save docker.io openc3inc 6.3.0</code></p>

  <p style={{"margin-bottom": 20 + 'px'}}>これにより、openc3incネームスペースとバージョン5.16.2を使用して、docker.ioリポジトリからCOSMOSコンテナがダウンロードされます。リポジトリ、ネームスペース、バージョンはすべて設定可能です。tarファイルは「tmp」ディレクトリに作成され、オフライン環境に転送できます。tarファイルをオフライン環境のプロジェクトの「tmp」ディレクトリに転送し、以下のコマンドでインポートします：</p>

  <p style={{"margin-bottom": 20 + 'px'}}><code>./openc3.sh util load 6.3.0</code></p>

  <p style={{"margin-bottom": 20 + 'px'}}>saveで指定したバージョンは、loadで指定するバージョンと一致する必要があることに注意してください。</p>
:::

### 証明書

COSMOSコンテナは、SSL復号化デバイスの存在下で動作し、構築されるように設計されています。これをサポートするため、組織が必要とする証明書を含むcacert.pemファイルをCOSMOS 6プロジェクトのベースに配置できます。**注意**：`SSL_CERT_FILE`環境変数にSSLファイルへのパスを設定すると、openc3セットアップスクリプトがそれをコピーして、Dockerコンテナがロードするために配置します。

:::warning SSL問題

組織ではますますSSL復号化デバイスのようなものを使用するようになっており、これによりcurlやgitなどの他のコマンドラインツールでSSL証明書の問題が発生する可能性があります。インストールが「certificate」「SSL」「self-signed」または「secure」に関するメッセージで失敗した場合、これが問題です。ITは通常、ブラウザが正しく動作するように設定しますが、コマンドラインアプリケーションは設定しません。ファイル拡張子は.pemではない可能性があり、.pem、.crt、.ca-bundle、.cer、.p7b、.p7sなど、他の拡張子の可能性もあります。

回避策は、curlなどのツールで使用できるIT部門から適切なローカル証明書ファイルを取得することです（例：C:\Shared\Ball.pem）。スペースがない場所であればどこでも構いません。

その後、次の環境変数をそのパスに設定します（例：C:\Shared\Ball.pem）

SSL_CERT_FILE<br/>
CURL_CA_BUNDLE<br/>
REQUESTS_CA_BUNDLE<br/>

Windowsの環境変数に関するいくつかの指示はこちらです：[Windows環境変数](https://www.computerhope.com/issues/ch000549.htm)

上記の名前で新しい環境変数を作成し、その値を証明書ファイルへのフルパスに設定する必要があります。
:::

### 実行

ローカルにクローンしたプロジェクトディレクトリをパスに追加して、バッチファイルまたはシェルスクリプトを直接使用できるようにします。Windowsでは、"C:\openc3-project"をPATHに追加します。Linuxでは、シェルのrcファイルを編集してPATHをエクスポートします。例えば、Macでは次の行を~/.zshrcに追加します：`export PATH=~/cosmos-project:$PATH`。

`openc3.bat run`（Windows）または`./openc3.sh run`（Linux/Mac）を実行します。

注意、.envファイルを編集して、OPENC3_TAGを「latest」ではなく特定のリリース（例：6.3.0）に変更できます。

Dockerデーモンが実行されていないというエラーが表示された場合は、DockerとDocker Composeがインストールされ、実行されていることを確認してください。エラーが発生した場合は、`docker --version`または`docker-compose --version`を実行してみて、再度開始コマンドを実行してみてください。エラーが続く場合は、問題を作成する場合は、バージョンを問題に含めてください。

`docker ps`を実行すると、実行中のコンテナを表示できます。

`openc3.*`は複数の引数を取ります。引数なしで実行するとヘルプが表示されます。openc3.shを引数なしで実行すると、以下のような使用ガイドが表示されます。

```bash
./openc3.sh
Usage: ./openc3.sh [cli, cliroot, start, stop, cleanup, run, util]
*  cli: デフォルトユーザーとしてcliコマンドを実行（詳細は'cli help'）
*  cliroot: ルートユーザーとしてcliコマンドを実行（詳細は'cli help'）
*  start: docker-compose openc3を開始
*  stop: 実行中のopenc3用Dockerを停止
*  cleanup: openc3のネットワークとボリュームをクリーンアップ
*  run: openc3用のプリビルドコンテナを実行
*  util: さまざまなヘルパーコマンド
```

### 接続

Webブラウザで http://localhost:2900 に接続します。パスワードは好きなものに設定してください。

### 次のステップ

[はじめに](gettingstarted)に進みます。

---

### フィードバック

:::note ドキュメントに問題がありましたか？

GitHubで[課題を作成](https://github.com/OpenC3/cosmos/issues/new/choose)して、
改善方法を教えてください。

:::
