---
sidebar_position: 7
title: Podman
description: PodmanでのCOSMOSのインストールと実行
sidebar_custom_props:
  myEmoji: 🫛
---

### ルートレスPodmanとDocker-Composeを使用したOpenC3 COSMOS

:::info Podmanのインストール方法
これらの手順は、DockerではなくPodmanを使用してCOSMOSをインストールおよび実行するためのものです。Dockerが利用可能な場合は、そちらの方がより簡単な方法です。
:::

PodmanはDockerの代替となるコンテナ技術で、RedHatによって積極的に推進されています。主な利点は、Podmanがルートレベルのデーモンサービスなしで実行できることであり、標準的なDockerと比較して設計上、大幅にセキュリティが向上します。ただし、使用するのは少し複雑です。以下の手順でPodmanを使って環境を構築できます。これらの手順はRHEL 8.8およびRHEL 9.2でテストされていますが、他のオペレーティングシステムでも同様の手順になるはずです。

:::warning ルートレスPodmanはNFSホームディレクトリでは直接動作しません
NFSは、ユーザーIDとグループIDの問題により、コンテナストレージの保持に使用できません。回避策はありますが、いずれもコンテナストレージを別の場所に移動する必要があります（ホストのローカルディスク上の異なるパーティション、または特別にマウントされたディスクイメージのいずれかです）。

参照：[https://www.redhat.com/sysadmin/rootless-podman-nfs](https://www.redhat.com/sysadmin/rootless-podman-nfs)。

また、/etc/containers/storage.confにあるrootless_storage_pathという設定を使って、ストレージの場所をより簡単に変更できるPodmanの新しい設定もあります。参照：[https://www.redhat.com/sysadmin/nfs-rootless-podman](https://www.redhat.com/sysadmin/nfs-rootless-podman)
:::

# Redhat 8.8と9.2の手順

1. 前提条件パッケージのインストール

   注：これはGithubの最新の2.x リリースからdocker-composeをダウンロードしてインストールします。オペレーティングシステムにdocker-composeパッケージがある場合は、それを使用してインストールする方が簡単です。RHEL8にはdocker-composeパッケージがありません。

   ```bash
   sudo yum update
   sudo yum install git podman-docker netavark
   curl -SL https://github.com/docker/compose/releases/download/v2.16.0/docker-compose-linux-x86_64 -o docker-compose
   sudo mv docker-compose /usr/local/bin/docker-compose
   sudo chmod +x /usr/local/bin/docker-compose
   sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
   ```

1. RedisのためのホストOSの設定

   ```bash
   sudo su
   echo never > /sys/kernel/mm/transparent_hugepage/enabled
   echo never > /sys/kernel/mm/transparent_hugepage/defrag
   sysctl -w vm.max_map_count=262144
   exit
   ```

1. DNS用のNetavarkを使用するようにPodmanを設定

   ```bash
   sudo cp /usr/share/containers/containers.conf /etc/containers/.
   sudo vi /etc/containers/containers.conf
   ```

   次に、network_backendの行を「cni」から「netavark」に編集します

1. ルートレスpodmanソケットサービスの開始

   ```bash
   systemctl enable --now --user podman.socket
   ```

1. 以下を.bashrcファイル（または.bash_profileなど）に追加

   ```bash
   export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
   ```

1. 現在のターミナルでプロファイルファイルを読み込む

   ```bash
   source .bashrc
   ```

1. COSMOSの取得 - リリースまたは現在のmainブランチ（mainブランチを表示）

   ```bash
   git clone https://github.com/OpenC3/cosmos.git
   ```

1. オプション - デフォルトコンテナレジストリの設定

   どのレジストリを使用するかをpodmanに問い合わせないようにするには、$HOME/.config/containers/registries.confを作成し、メインのdockerレジストリのみを持つように変更します（または/etc/containers/registries.confファイルを直接変更します）

   ```bash
   mkdir -p $HOME/.config/containers
   cp /etc/containers/registries.conf $HOME/.config/containers/.
   vi $HOME/.config/containers/registries.conf
   ```

   次に、unqualified-search-registries =の行を編集して、必要なレジストリ（おそらくdocker.io）のみを含めるようにします

1. cosmos/compose.yamlの編集

   ```bash
   cd cosmos
   vi compose.yaml
   ```

   compose.yamlを編集し、user: 0:0の行のコメントを解除し、user: `"${OPENC3_USER_ID}:${OPENC3_GROUP_ID}"`の行をコメントアウトします。
   また、traefik設定を更新してインターネットからのアクセスを許可するために、127.0.0.1を削除し、おそらくSSL設定ファイルまたはhttp許可設定に切り替えることもできます。また、選択したポートへのアクセスをファイアウォールが許可していることを確認してください。ルートレスpodmanでは、より高い番号のポート（1-1023以外）を使用する必要があります。

1. COSMOSの実行

   ```bash
   ./openc3.sh run
   ```

1. すべてが構築され、実行されるまで待ってから、ブラウザで http://localhost:2900 にアクセスします

:::info MacOSでのPodman
PodmanはMacOSでも使用できますが、一般的にはDocker Desktopをお勧めします
:::

## MacOSの手順

1. Podmanのインストール

   ```bash
   brew install podman
   ```

1. Podman仮想マシンの開始

   ```bash
   podman machine init
   podman machine start
   # 注意：次の行でユーザー名を更新するか、'podman machine start'の出力からコピーペーストしてください
   export DOCKER_HOST='unix:///Users/ryanmelt/.local/share/containers/podman/machine/qemu/podman.sock'
   ```

1. docker-composeのインストール

   ```bash
   brew install docker-compose # Docker Desktopがすでにある場合は必要無し
   ```

1. cosmos/compose.yamlの編集

   compose.yamlを編集し、user: 0:0の行のコメントを解除し、user: `"${OPENC3_USER_ID}:${OPENC3_GROUP_ID}"`の行をコメントアウトします。

   重要：MacOSでは、ボリュームマウント行からすべての:zを削除する必要もあります

   また、インターネットからのアクセスを許可するためにtraefik設定を更新することもできます。

1. COSMOSの実行

   ```bash
   cd cosmos
   ./openc3.sh run
   ```
