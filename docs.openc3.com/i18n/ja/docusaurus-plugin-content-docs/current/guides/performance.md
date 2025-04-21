---
title: パフォーマンス
description: メモリやCPUなどのハードウェア要件
sidebar_custom_props:
  myEmoji: 📊
---

COSMOSのアーキテクチャはスケーラビリティを念頭に置いて作成されました。私たちの目標は、無制限の接続数をサポートし、クラウドテクノロジーを使用してスケールすることです。[COSMOS Enterprise Edition](https://openc3.com/enterprise)のみが、このレベルのスケーラビリティを可能にするKubernetesと様々なクラウドプラットフォームをサポートしています。真のスケーラビリティはCOSMOS Enterpriseでのみ達成されますが、オープンソース版とエンタープライズ版の両方には、パフォーマンスに影響を与える様々なレベルの可観測性と設定があります。

# COSMOSのハードウェア要件

## メモリ

COSMOSは、Raspberry Piからクラウド上のKubernetesクラスタまで実行できます。すべてのプラットフォームで、主なパフォーマンス要因はターゲットの数と複雑さ、およびそれらが定義するパケットです。ターゲットは、100MBのRAMを使用する単純なものから、400MBを使用する複雑なものまでさまざまです。ベースとなるCOSMOSコンテナには約800MBのRAMが必要です。経験則として、ターゲットあたり平均約300MBのRAMを見積もるとよいでしょう。例として、COSMOSデモには4つのターゲットがあり、2つが複雑（INSTとINST2）、2つが比較的シンプル（EXAMPLEとTEMPLATED）で、800MBのRAMが必要です（ベースコンテナRAMの800MBに加えて）。

- 基本RAM MB計算式 = 800 + (ターゲット数) \* 300

さらに、Redisストリームには、すべてのターゲットの生データとデコミュテーション（復調）データの過去10分間のデータが含まれています。したがって、実際のメモリ使用量のピークを確認するには約15分待つ必要があります。COSMOSデモでは、INSTとINST2ターゲットは比較的シンプルで、約15項目を持つ4つの1Hzパケットと、20項目を持つ1つの10Hzパケットがあります。`docker stats`によると、これはRedisのRAM使用量を50MiBにしかしません。各パケットに1000項目ある10個のパケットを10Hzで送信するCOSMOS [LoadSim](https://github.com/OpenC3/openc3-cosmos-load-sim)をインストールすると、Redisのメモリ使用量は約350MiBになりました。

## CPU

もう一つの考慮事項はCPUパフォーマンスです。オープンソース版では、デフォルトでCOSMOSはターゲットごとに2つのマイクロサービスを起動します。1つはパケットのロギングとデータのデコミュテーションを組み合わせ、もう1つはデータリダクションを実行します。Kubernetes上のCOSMOS Enterprise Editionでは、各プロセスはクラスタにデプロイされる独立したコンテナになり、水平スケーリングが可能になります。

COSMOSのコマンドとテレメトリAPIおよびスクリプト実行APIサーバーは専用のコアを持つべきですが、ターゲットは一般的にコアを共有できます。アーキテクチャ、クロックスピード、コア数が多様なため、一般的な目安を示すのは難しいです。ベストプラクティスは、予想される負荷でCOSMOSをインストールし、`htop`でモニタリングして様々なコアの負荷を視覚化することです。単一のコアが過負荷（100%）になるとシステムの遅延が発生する可能性があるため、これは懸念事項です。

## パフォーマンス比較

パフォーマンス特性評価は、[Docker](https://docs.docker.com/desktop/vm-vdi/#turn-on-nested-virtualization-on-microsoft-hyper-v)ごとの仮想化を可能にするために選択されたAzureのStandard D4s v5（4 vcpu、16 GiBメモリ）で実行されました。COSMOS [5.9.1](https://github.com/OpenC3/cosmos-enterprise/releases/tag/v5.9.1) Enterprise EditionがWindows 11 Pro [^1]とUbuntu 22の両方にインストールされました。注意：Enterprise Editionはコンテナオーケストレーションにはコンテナエンジンを使用していて、Kubernetesは使っていません。テストでは、COSMOSデモを起動し、すべてのターゲット（EXAMPLE、INST、INST2、TEMPLATED）を接続し、次のTlmViewerスクリーン（ADCS、ARRAY、BLOCK、COMMANDING、HS、LATEST、LIMITS、OTHER、PARAMS、SIMPLE、TABS）を開き、INST HEALTH_STATUS TEMP[1-4]とINST ADCS POS[X,Y,Z]およびINST ADCS VEL[X,Y,Z]で構成される2つのTlmGrapherグラフを作成しました。これは1時間実行され、結果は`htop`を使用して収集されました：

| プラットフォーム     | コアCPU %       | RAM          |
| :----------------- | :-------------- | :----------- |
| Windows 11 Pro     | 12% 12% 10% 10% | 3.9G / 7.7G  |
| Headless Ubuntu 22 | 7% 7% 8% 6%     | 3.2G / 15.6G |

- Windowsは[.wslconfig](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#configuration-setting-for-wslconfig)設定により、割り当てられたRAMが8GBのみでした。
- Ubuntuはヘッドレスで実行されていたため、画面とグラフは別のマシンで表示されました。

`docker stats`も実行され、個々のコンテナのCPUとメモリ使用量が表示されました：

| 名前                                                        | Windows CPU % | Ubuntu CPU % | Windows MEM | Ubuntu MEM |
| :---------------------------------------------------------- | :------------ | ------------ | :---------- | ---------- |
| cosmos-enterprise-project-openc3-traefik-1                  | 4.16%         | 1.32%        | 43.54MiB    | 51.38MiB   |
| cosmos-enterprise-project-openc3-cosmos-cmd-tlm-api-1       | 10.16%        | 6.14%        | 401.6MiB    | 392MiB     |
| cosmos-enterprise-project-openc3-keycloak-1                 | 0.17%         | 0.13%        | 476.8MiB    | 476.8MiB   |
| cosmos-enterprise-project-openc3-operator-1                 | 21.27%        | 13.91%       | 1.214GiB    | 1.207GiB   |
| cosmos-enterprise-project-openc3-cosmos-script-runner-api-1 | 0.01%         | 0.01%        | 127.4MiB    | 117.1MiB   |
| cosmos-enterprise-project-openc3-metrics-1                  | 0.01%         | 0.00%        | 105.2MiB    | 83.87MiB   |
| cosmos-enterprise-project-openc3-redis-ephemeral-1          | 4.05%         | 1.89%        | 46.22MiB    | 69.84MiB   |
| cosmos-enterprise-project-openc3-redis-1                    | 1.56%         | 0.72%        | 12.82MiB    | 9.484MiB   |
| cosmos-enterprise-project-openc3-minio-1                    | 0.01%         | 0.00%        | 152.9MiB    | 169.8MiB   |
| cosmos-enterprise-project-openc3-postgresql-1               | 0.00%         | 0.39%        | 37.33MiB    | 41.02MiB   |

- メモリプロファイルは両プラットフォーム間で類似しています
- redis-ephemeralは小さなパケットを持つ基本デモではあまりメモリを使用していません

この時点で、デフォルト設定のCOSMOS [LoadSim](https://github.com/OpenC3/openc3-cosmos-load-sim)がインストールされ、それぞれに1000項目ある10個のパケットを10Hz（110kB/s）で生成します。1時間の実行後、htopは次のような結果を示しました：

| プラットフォーム     | コアCPU %       | RAM           |
| :----------------- | :-------------- | :------------ |
| Windows 11 Pro     | 40% 35% 39% 42% | 4.64G / 7.7G  |
| Headless Ubuntu 22 | 17% 20% 16% 18% | 3.74G / 15.6G |

LoadSimターゲットの大きなパケットとデータレートにより、両プラットフォームでCPU使用率が劇的に増加しましたが、Linuxマシンはかなり高いパフォーマンスを維持しています。

`docker stats`も実行され、個々のコンテナのCPUとメモリ使用量が表示されました：

| 名前                                                        | Windows CPU % | Ubuntu CPU % | Windows MEM | Ubuntu MEM |
| :---------------------------------------------------------- | :------------ | ------------ | :---------- | ---------- |
| cosmos-enterprise-project-openc3-traefik-1                  | 4.09%         | 0.01%        | 44.3MiB     | 0.34MiB    |
| cosmos-enterprise-project-openc3-cosmos-cmd-tlm-api-1       | 17.78%        | 6.18%        | 407.9MiB    | 405.8MiB   |
| cosmos-enterprise-project-openc3-keycloak-1                 | 0.20%         | 0.12%        | 480.2MiB    | 481.5MiB   |
| cosmos-enterprise-project-openc3-operator-1                 | 221.15%       | 66.72%       | 1.6GiB      | 1.512GiB   |
| cosmos-enterprise-project-openc3-cosmos-script-runner-api-1 | 0.01%         | 0.01%        | 136.6MiB    | 127.5MiB   |
| cosmos-enterprise-project-openc3-metrics-1                  | 0.01%         | 0.01%        | 106.3MiB    | 84.87MiB   |
| cosmos-enterprise-project-openc3-redis-ephemeral-1          | 19.63%        | 3.91%        | 333.8MiB    | 370.8MiB   |
| cosmos-enterprise-project-openc3-redis-1                    | 7.42%         | 1.49%        | 15.87MiB    | 11.81MiB   |
| cosmos-enterprise-project-openc3-minio-1                    | 0.10%         | 0.02%        | 167.8MiB    | 179.2MiB   |
| cosmos-enterprise-project-openc3-postgresql-1               | 0.00%         | 0.00%        | 35.4MiB     | 42.93MiB   |

- メモリプロファイルは両プラットフォーム間で類似しています
- redis-ephemeralは大きなLoadSimパケットを保存しているため、より多くのRAMを使用しています
- Windowsはオペレータ、cmd-tlm、redisの実行に多くのCPUパワーを使用しています

# 結論

どのDockerプラットフォームでもCOSMOSを実行するのは簡単ですが、ターゲットの数と複雑さを増やすには、適切なハードウェアを選択する必要があります。サイジングは概算できますが、最良の解決策は代表的なターゲットをインストールし、`docker stats`と`htop`を使用して特定のハードウェア上のCPUとメモリの負荷を判断することです。

Kubernetes上の[COSMOS Enterprise Edition](https://openc3.com/enterprise)は、システムのニーズを満たすためにクラスタをスケーリングすることで、ハードウェアサイジングの問題を解消するのに役立ちます。RyanがGSAWで行った[最近の講演](https://openc3.com/news/scaling)をチェックして、EKS上の4ノードKubernetesクラスタで160以上の衛星にスケールした方法を確認してください。

<hr/>

[^1]: Windows プラットフォームの詳細仕様：

    ```
    Windows 11 Pro
    Docker Desktop 4.22.0
    WSL version: 1.2.5.0
    Kernel version: 5.15.90.1
    WSLg version: 1.0.51
    MSRDC version: 1.2.3770
    Direct3D version: 1.608.2-61064218
    DXCore version: 10.0.25131.1002-220531-1700.rs-onecore-base2-hyp
    Windows version: 10.0.22621.2134
    ```