---
sidebar_position: 1
title: 主要概念
description: プロジェクト、コンテナ化、フロントエンド、バックエンド
sidebar_custom_props:
  myEmoji: 💡
---

# OpenC3 COSMOS 主要概念

## プロジェクト

メインのCOSMOS [リポジトリ](https://github.com/OpenC3/cosmos)には、COSMOSをビルドして実行するために使用されるすべてのソースコードが含まれています。ただし、COSMOS のユーザー（ソフトウェア開発者ではない）は、COSMOS を起動するために COSMOS [プロジェクト](https://github.com/OpenC3/cosmos-project)を使用するのを勧めます。プロジェクトは、COSMOS の起動と停止のための[openc3.sh](https://github.com/OpenC3/cosmos-project/blob/main/openc3.sh)と[openc3.bat](https://github.com/OpenC3/cosmos-project/blob/main/openc3.bat)ファイル、COSMOS コンテナの設定のための[compose.yaml](https://github.com/OpenC3/cosmos-project/blob/main/compose.yaml)、そしてランタイム変数を設定するための[.env](https://github.com/OpenC3/cosmos-project/blob/main/.env)ファイルで構成されています。さらに、COSMOSプロジェクトには、RedisとTraefikの両方のためのユーザー修正可能な設定ファイルが含まれています。

## コンテナ化

### イメージ

[Docker](https://docs.docker.com/get-started/overview/#images)によれば、「イメージは、Dockerコンテナを作成するための指示を含む読み取り専用のテンプレート」です。COSMOSが使用する基本オペレーティングシステムは[Alpine Linux](https://www.alpinelinux.org/)と呼ばれています。これは依存関係をインストールできる完全なパッケージシステムを備えたシンプルでコンパクトなイメージです。Alpineをベースに、RubyとPythonといくつかの他のパッケージを追加するための[Dockerfile](https://docs.docker.com/engine/reference/builder/)を作成して、独自のDockerイメージを作成します。さらに、そのイメージを元にして、フロントエンドをサポートするNodeJSイメージと、バックエンドをサポートする追加イメージを構築しています。

### コンテナ

[Docker](https://www.docker.com/resources/what-container/)によれば、「コンテナは、コードとそのすべての依存関係をパッケージ化するソフトウェアの標準単位であり、アプリケーションがあるコンピューティング環境から別の環境へ迅速かつ確実に実行されるようにするもの」です。また、[Docker](https://docs.docker.com/guides/walkthroughs/what-is-a-container/)は、「コンテナはコードのための独立した環境です。これは、コンテナがあなたのオペレーティングシステムやファイルについての知識を持たないことを意味します。Docker Desktopによって提供される環境で実行されます。コンテナには、ベースとなるオペレーティングシステムまで、コードを実行するために必要なすべてのものが含まれています」とも述べています。COSMOSはコンテナを利用して一貫したランタイム環境を提供しています。コンテナにより、ローカルのオンプレミスサーバー、クラウド環境、またはエアギャップネットワークへの展開が容易になります。

COSMOS オープンソースのコンテナは以下で構成されています：

| 名前                                     | 説明                                                                                            |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| cosmos-openc3-cosmos-init-1              | ファイルをMinioにコピーしてCOSMOSを設定し、その後終了します                                                 |
| cosmos-openc3-operator-1                 | インターフェイスとターゲットマイクロサービスを実行するメインのCOSMOSコンテナ                                |
| cosmos-openc3-cosmos-cmd-tlm-api-1       | すべてのCOSMOS APIエンドポイントを提供するRailsサーバー                                                |
| cosmos-openc3-cosmos-script-runner-api-1 | スクリプトAPIエンドポイントを提供するRailsサーバー                                                    |
| cosmos-openc3-redis-1                    | 静的ターゲット設定を提供します                                                                 |
| cosmos-openc3-redis-ephemeral-1          | 生データと復調されたデータを含む[ストリーム](https://redis.io/docs/data-types/streams)を提供します |
| cosmos-openc3-minio-1                    | S3のようなバケットストレージインターフェイスを提供し、ツールファイル用の静的ウェブサーバーとしても機能します   |
| cosmos-openc3-traefik-1                  | COSMOSエンドポイントへのルートを持つリバースプロキシとロードバランサーを提供します                         |

[Enterprise COSMOS](https://openc3.com/enterprise)のコンテナリストは以下で構成されています：

| 名前                                  | 説明                                                                                   |
| ------------------------------------- | --------------------------------------------------------------------------------------------- |
| cosmos-enterprise-openc3-metrics-1    | COSMOSのパフォーマンスに関するメトリクスを提供するRailsサーバー                                      |
| cosmos-enterprise-openc3-keycloak-1   | 認証のためのシングルサインオンサービス                                                     |
| cosmos-enterprise-openc3-postgresql-1 | Keycloakが使用するSQLデータベース                                                              |
| openc3-nfs \*                         | コンテナ間でコードライブラリを共有するためにKubernetesでのみ使用するネットワークファイルシステムポッド |

### Docker Compose

[Docker](https://docs.docker.com/compose/)によれば、「Composeは、マルチコンテナDockerアプリケーションを定義して実行するためのツールです。Composeでは、YAMLファイルを使用してアプリケーションのサービスを設定します。その後、1つのコマンドで設定からすべてのサービスを作成して起動します」。OpenC3は、COSMOSの構築と実行の両方にComposeファイルを使用しています。[compose.yaml](https://github.com/OpenC3/cosmos-project/blob/main/compose.yaml)は、ポートが公開され、環境変数が使用される場所です。

### 環境ファイル

COSMOSは、Docker Composeとともに[環境ファイル](https://docs.docker.com/compose/environment-variables/env-file/)を使用して、環境変数をCOSMOSランタイムに渡します。この[.env](https://github.com/OpenC3/cosmos-project/blob/main/.env)ファイルは、デプロイされたCOSMOSのバージョン、ユーザー名とパスワード、その他多くの情報を含む単純なキーと値のペアで構成されています。

### Kubernetes

[Kubernetes.io](https://kubernetes.io/)によれば、「Kubernetes（K8sとも呼ばれる）は、コンテナ化されたアプリケーションのデプロイメント、スケーリング、管理を自動化するためのオープンソースシステムです。アプリケーションを構成するコンテナを論理的なユニットにグループ化して、管理と発見を容易にします」。[COSMOS Enterprise](https://openc3.com/enterprise)は、様々なクラウド環境へのKubernetesへの簡単なデプロイメントのための[Helmチャート](https://helm.sh/docs/topics/charts/)を提供しています。

COSMOS Enterpriseはまた、様々なクラウド環境（例：AWSのCloudFormationテンプレート）にCOSMOSインフラストラクチャをデプロイするための設定も提供しています。

## フロントエンド

### Vue.js

COSMOSフロントエンドは完全にブラウザネイティブであり、Vue.jsフレームワークで実装されています。[Vue.js](https://vuejs.org/guide/introduction.html)によれば、「Vueはユーザーインターフェイスを構築するためのJavaScriptフレームワークです。標準的なHTML、CSS、JavaScriptの上に構築され、シンプルであれ複雑であれ、ユーザーインターフェイスを効率的に開発するのに役立つ宣言的でコンポーネントベースのプログラミングモデルを提供します」。COSMOSはVue.jsと[Vuetify](https://vuetifyjs.com/en/)コンポーネントフレームワークUIライブラリを利用して、お好みのブラウザで実行されるすべてのCOSMOSツールを構築しています。COSMOS 5はVue.js 2.xとVuetify 2.xを使用していましたが、COSMOS 6はVue.js 3.xとVuetify 3.xを使用しています。

### Single-Spa

COSMOS自体はVue.jsで書かれていますが、COSMOS開発者が選択した任意のJavaScriptフレームワークでアプリケーションを作成できるように、[single-spa](https://single-spa.js.org/)と呼ばれる技術を利用しています。Single-spaはマイクロフロントエンドフレームワークであり、要求されたアプリケーションをレンダリングするトップレベルのルーターとして機能します。COSMOSは、Angular、React、Svelte、Vueですぐにsingle-spaに接続できるサンプルアプリケーションを提供しています。

### Astro UX

[AstroUXDS](https://www.astrouxds.com/)によれば、「Astro Space UX Design Systemは、開発者やデザイナーが確立されたインタラクションパターンとベストプラクティスを使用して、豊かな宇宙アプリケーション体験を構築できるようにします」。COSMOSは、色、タイポグラフィ、アイコングラフィのためにAstroデザインガイドラインを利用しています。場合によっては、例えば[Astro Clock](https://www.astrouxds.com/components/clock/)のように、COSMOSは直接Astroコンポーネントを組み込んでいます。

## バックエンド

### Redis

[Redis](https://redis.io/)は、文字列、ハッシュ、リスト、セット、ソート済みセット、ストリームなどをサポートするインメモリデータストアです。COSMOSはRedisを使用して設定とデータの両方を保存します。[コンテナリスト](/docs/getting-started/key-concepts#コンテナ)を振り返ると、2つのRedisコンテナがあることに気づくでしょう：cosmos-openc3-redis-1とcosmos-openc3-redis-ephemeral-1です。一時的なコンテナには、[Redisストリーム](https://redis.io/docs/data-types/streams/)にプッシュされるすべてのリアルタイムデータが含まれています。もう一つのRedisコンテナには、永続化されることを意図したCOSMOS設定が含まれています。[COSMOS Enterprise](https://openc3.com/enterprise)は、データが複数のRedisノード間で共有される水平スケーリングを実行するための[Redisクラスター](https://redis.io/docs/management/scaling/)をセットアップするHelmチャートを提供しています。

### MinIO

[MinIO](https://min.io/)は、高性能でS3互換のオブジェクトストアです。COSMOSはこのストレージ技術を使用して、COSMOSツール自体と長期的なログファイルの両方をホストしています。クラウド環境にデプロイされた[COSMOS Enterprise](https://openc3.com/enterprise)は、利用可能なクラウドネイティブのバケットストレージ技術（AWS S3、GCPバケット、Azure Blobストレージなど）を使用します。バケットストレージを使用することで、COSMOSは静的ウェブサイトとしてツールを直接提供できるため、例えばTomcatやNginxをデプロイする必要がありません。

### Ruby on Rails

COSMOS APIとScript Runnerのバックエンドは、[Ruby on Rails](https://rubyonrails.org/)によって動作しています。Railsは、Rubyプログラミング言語で書かれたWebアプリケーション開発フレームワークです。Railsにより、他の多くの言語やフレームワークよりも少ないコードで多くのことを達成できます。
