---
title: モニタリング
description: COSMOSの内部を監視する様々な方法
sidebar_custom_props:
  myEmoji: 🖥️
---

### モニタリングと可観測性

:::warning 例示のみ
FluentdによるモニタリングはOpenC3によって公式にサポートされておらず、ここに記載されているドキュメントはその実行方法の例に過ぎません。
:::

COSMOSをコンテナベースのサービスに移行するにあたり、COSMOSの内部をより良く監視する方法が必要でした。そこで、COSMOSを監視するために使用できる外部サービスに関する情報をいくつか紹介します。[分散システムのモニタリング](https://sre.google/sre-book/monitoring-distributed-systems/)についてさらに詳しく知りたい場合はこちらをご覧ください。

### [Fluent/Fluentd](https://www.fluentd.org/guides/recipes/docker-logging)

> Fluentdはオープンソースのデータコレクターであり、データ収集と消費を統一して、データのより良い使用と理解を可能にします。

in_docker.conf

```
<source>
  @type forward
  port 24224
  bind 0.0.0.0
</source>
<match *.metric>
  @type copy
  <store>
    @type elasticsearch
    host openc3-elasticsearch
    port 9200
    logstash_format true
    logstash_prefix metric
    logstash_dateformat %Y%m%d
    include_tag_key true
    type_name access_log
    tag_key @log_name
    flush_interval 1s
  </store>
  <store>
    @type stdout
  </store>
</match>
<match *__openc3.log>
  @type copy
  <store>
    @type elasticsearch
    host openc3-elasticsearch
    port 9200
    logstash_format true
    logstash_prefix openc3
    logstash_dateformat %Y%m%d
    include_tag_key true
    type_name access_log
    tag_key @log_name
    flush_interval 1s
  </store>
  <store>
    @type stdout
  </store>
</match>
<match *.**>
  @type copy
  <store>
    @type elasticsearch
    host openc3-elasticsearch
    port 9200
    logstash_format true
    logstash_prefix fluentd
    logstash_dateformat %Y%m%d
    include_tag_key true
    type_name access_log
    tag_key @log_name
    flush_interval 1s
  </store>
  <store>
    @type stdout
  </store>
</match>
```

Dockerfile

注意：FROM行でアーキテクチャ固有のビルドを使用する必要があります。例、MacBookである場合：`FROM arm64v8/fluentd:v1.18-1`

```
FROM fluent/fluentd:v1.18-1

COPY ./in_docker.conf /fluentd/etc/fluent.conf
USER root
RUN gem install fluent-plugin-elasticsearch --no-document --version 5.4.3 \
  && gem install fluent-plugin-prometheus --no-document --version 2.2.0
USER fluent
```

### [OpenDistro](https://opendistro.github.io/for-elasticsearch-docs/)

> Open Distro for Elasticsearchは、強力で使いやすいイベントモニタリングおよびアラートシステムを提供し、データを監視して自動的に関係者に通知を送信できるようにします。直感的なKibanaインターフェースと強力なAPIにより、アラートの設定と管理が容易です。

- [Docker](https://opendistro.github.io/for-elasticsearch-docs/docs/install/docker/)

これをテストした際、opendistroにログを取り込む方法によっては、セキュリティを無効にする必要があることがわかりました。以下はDockerfileの例です。

Dockerfile

```
FROM amazon/opendistro-for-elasticsearch:1.12.0

RUN /usr/share/elasticsearch/bin/elasticsearch-plugin remove opendistro_security
```

### [Prometheus](https://prometheus.io/)

> Prometheusは、計測されたジョブからメトリクスを直接、または短命なジョブのための中間プッシュゲートウェイを介して収集します。収集したすべてのサンプルをローカルに保存し、このデータに対してルールを実行して、既存のデータから新しい時系列データを集計して記録したり、アラートを生成したりします。収集されたデータの視覚化には、Grafanaやその他のAPIコンシューマーを使用できます。

prometheus.yaml

```
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  # - "first.rules"
  # - "second.rules"

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: openc3-internal-metrics
    metrics_path: "/openc3-api/internal/metrics"
    static_configs:
      - targets: ["openc3-cmd-tlm-api:2901"]

  - job_name: openc3-cmd-tlm-api
    metrics_path: "/openc3-api/metrics"
    static_configs:
      - targets: ["openc3-cmd-tlm-api:2901"]

  - job_name: openc3-script-runner-api
    metrics_path: "/script-api/metrics"
    static_configs:
      - targets: ["openc3-script-runner-api:2902"]

  - job_name: minio-job
    metrics_path: /minio/v2/metrics/cluster
    scheme: http
    static_configs:
    - targets: ['openc3-minio:9000']
```

Dockerfile

```
FROM prom/prometheus:v3.2.1
ADD prometheus.yaml /etc/prometheus/
```

### [Grafana](https://grafana.com/)

> Grafanaは、マルチプラットフォームのオープンソース分析および対話型可視化Webアプリケーションです。サポートされているデータソースに接続すると、Web用のチャート、グラフ、アラートを提供します。

datasource.yaml

```
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    # アクセスモード - proxy (UIのサーバー) または direct (UIのブラウザ)
    access: proxy
    url: http://openc3-prometheus:9090
```

Dockerfile

```
FROM grafana/grafana

COPY datasource.yaml /etc/grafana/provisioning/datasources/
```