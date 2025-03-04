---
title: Monitoring
description: Various ways to monitor COSMOS internals
sidebar_custom_props:
  myEmoji: 🖥️
---

### Monitoring and observability

:::warning Example Only
Monitoring with Fluentd is not offically supported by OpenC3 and the documentation here is simply an example of how this could be performed.
:::

With moving COSMOS to container based service, we needed a better way to monitor the internals of COSMOS. So here is some information on external services that you can use to monitor COSMOS. If you want to read more about [Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)

### [Fluent/Fluentd](https://www.fluentd.org/guides/recipes/docker-logging)

> Fluentd is an open source data collector, which lets you unify the data collection and consumption for a better use and understanding of data.

#### Notes

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

NOTE: If building on a Macbook (for example) you should use the architecture specific build in the FROM line, e.g. `FROM arm64v8/fluentd:v1.18-1`

```
FROM fluent/fluentd:v1.18-1

COPY ./in_docker.conf /fluentd/etc/fluent.conf
USER root
RUN gem install fluent-plugin-elasticsearch --no-document --version 5.4.3 \
  && gem install fluent-plugin-prometheus --no-document --version 2.2.0
USER fluent
```

### [OpenDistro](https://opendistro.github.io/for-elasticsearch-docs/)

> Open Distro for Elasticsearch provides a powerful, easy-to-use event monitoring and alerting system, enabling you to monitor your data and send notifications automatically to your stakeholders. With an intuitive Kibana interface and powerful API, it is easy to set up and manage alerts.

- [Docker](https://opendistro.github.io/for-elasticsearch-docs/docs/install/docker/)

#### Notes

When testing this I found that depending on how you ingest your logs into the opendistro I found I had to disable security. Here is an example of the docker file.

Dockerfile

```
FROM amazon/opendistro-for-elasticsearch:1.12.0

RUN /usr/share/elasticsearch/bin/elasticsearch-plugin remove opendistro_security
```

### [Prometheus](https://prometheus.io/)

> Prometheus scrapes metrics from instrumented jobs, either directly or via an intermediary push gateway for short-lived jobs. It stores all scraped samples locally and runs rules over this data to either aggregate and record new time series from existing data or generate alerts. Grafana or other API consumers can be used to visualize the collected data.

#### Notes

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

> Grafana is a multi-platform open source analytics and interactive visualization web application. It provides charts, graphs, and alerts for the web when connected to supported data sources.

#### Notes

datasource.yaml

```
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    # Access mode - proxy (server in the UI) or direct (browser in the UI).
    access: proxy
    url: http://openc3-prometheus:9090
```

Dockerfile

```
FROM grafana/grafana

COPY datasource.yaml /etc/grafana/provisioning/datasources/
```
