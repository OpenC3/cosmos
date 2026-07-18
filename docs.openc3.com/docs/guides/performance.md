---
title: Performance
description: Hardware requirements like memory and CPU
sidebar_custom_props:
  myEmoji: 📊
---

The COSMOS architecture was created with scalability in mind. Our goal is to support an unlimited number of connections and use cloud technologies to scale. Only [COSMOS Enterprise](https://openc3.com/cosmos-enterprise) supports Kubernetes and the various cloud platforms which allow this level of scalability. While true scalability is only achieved in COSMOS Enterprise, both Core and Enterprise have various levels of observability and configuration settings which can affect performance.

# COSMOS Hardware Requirements

## Memory

COSMOS can run on a Raspberry Pi up to a Kubernetes cluster in the cloud. On all platforms the key performance factor is the number and complexity of the targets and their defined packets. Each target's microservices typically consume 250–400 MB of RAM, with simple targets at the low end and complex targets at the high end. A good rule of thumb is to average about **300 MB of RAM per target**.

The base infrastructure containers also need RAM, and the floor differs significantly between editions:

- **COSMOS Core base**: ~1.8 GiB across all containers (operator scope-level services, cmd-tlm-api, script-runner-api, redis, redis-ephemeral, tsdb, traefik, buckets)
- **COSMOS Enterprise base**: ~3.7 GiB across all containers (Core base plus keycloak, postgresql, grafana, metrics)

Rough sizing formulas:

- **Core RAM (GiB)** ≈ 1.8 + (num targets) × 0.3
- **Enterprise RAM (GiB)** ≈ 3.7 + (num targets) × 0.3

As a concrete data point, the COSMOS Demo (4 targets: EXAMPLE, TEMPLATED, INST, INST2) adds about 1.3 GiB of target microservices on top of the base — individual target RSS measures roughly 265, 270, 374, and 414 MB respectively. See [Performance Comparison](#performance-comparison) below for the full breakdown.

In addition, the Redis streams hold the last 10 min (by default) of both raw and decommutated data from all targets, so you must wait ~15 min after startup to see the high-water memory mark. With just the COSMOS Demo, redis-ephemeral uses ~86 MiB. Adding the COSMOS [LoadSim](https://github.com/OpenC3/openc3-cosmos-load-sim) plugin (10 packets × 1000 items at 1 Hz) pushes redis-ephemeral to ~137 MiB; running LoadSim at its default 10 Hz pushes it considerably higher (~350 MiB).

## CPU

CPU performance is another consideration. In COSMOS Core, by default COSMOS spawns 2 microservices per target inside the operator container — one combines packet logging and decommutation of the data, the other performs data reduction. In COSMOS Enterprise on Kubernetes, each process becomes an independent container deployed on the cluster, allowing horizontal scaling.

The COSMOS command and telemetry API and script running API servers should have a dedicated core while target microservices can generally share cores. It's hard to provide a general rule of thumb across the wide variety of architectures, clock speeds, and core counts. The best practice is to install COSMOS with the expected load and monitor the load on the various cores using `docker stats` or `htop`. Any time a single core gets overloaded (100%) this is a concern and system slowdown can occur.

The dominant CPU consumers are typically the operator container (target microservices) and the tsdb container (telemetry ingest). See [Performance Comparison](#performance-comparison) for measured CPU usage at different load levels.

## Performance Comparison

Performance characterization was performed using COSMOS Enterprise on Docker (host with 16 GiB RAM, Enterprise running in Docker Compose mode without Kubernetes). To understand how COSMOS scales as targets and load are added, four scenarios were measured with `docker stats` and a per-target RSS breakdown of the operator container:

1. **Baseline** — only the scope-level microservices running, no user targets installed
2. **Demo** — the COSMOS Demo plugin installed with its 4 targets (EXAMPLE, TEMPLATED, INST, INST2)
3. **Demo + LoadSim** — Demo plus the [LoadSim](https://github.com/OpenC3/openc3-cosmos-load-sim) plugin configured with 10 telemetry packets (1000 items + 5 derived, 1000 bytes, 1 Hz) and 10 command packets (200 items + 5 derived, 200 bytes)
4. **Soak** — Demo + LoadSim left running for many hours

### Container Memory / CPU %

| Container         | Baseline          | Demo               | Demo + LoadSim     | Soak (many hrs)    |
| :---------------- | :---------------- | :----------------- | :----------------- | :----------------- |
| operator          | 229.2 MiB / 0.75% | 1.444 GiB / 15.57% | 1.665 GiB / 20.40% | 1.721 GiB / 18.58% |
| tsdb              | 1.638 GiB / 3.88% | 1.301 GiB / 34.44% | 1.475 GiB / 46.21% | 1.673 GiB / 43.81% |
| cmd-tlm-api       | 716.9 MiB / 0.57% | 652.6 MiB / 0.42%  | 692.8 MiB / 0.39%  | 702.9 MiB / 0.21%  |
| keycloak          | 698.1 MiB / 0.22% | 687.0 MiB / 0.17%  | 692.2 MiB / 0.20%  | 697.9 MiB / 0.16%  |
| script-runner-api | 409.9 MiB / 0.39% | 405.8 MiB / 0.18%  | 407.5 MiB / 0.16%  | 409.5 MiB / 0.15%  |
| redis-ephemeral   | 30.90 MiB / 0.45% | 85.67 MiB / 3.28%  | 137.2 MiB / 3.66%  | 107.6 MiB / 3.29%  |
| metrics           | 123.1 MiB / 0.27% | 122.5 MiB / 0.01%  | 122.7 MiB / 0.14%  | 122.9 MiB / 0.01%  |
| grafana           | 99.16 MiB / 0.19% | 87.44 MiB / 0.15%  | 87.75 MiB / 0.18%  | 99.16 MiB / 0.12%  |
| buckets           | 77.72 MiB / 0.06% | 87.09 MiB / 0.03%  | 77.30 MiB / 0.03%  | 72.79 MiB / 0.04%  |
| traefik           | 43.89 MiB / 0.07% | 42.93 MiB / 0.02%  | 35.34 MiB / 0.02%  | 40.15 MiB / 0.04%  |
| postgresql        | 41.51 MiB / 0.00% | 42.49 MiB / 0.00%  | 42.50 MiB / 0.00%  | 41.50 MiB / 0.00%  |
| redis             | 15.14 MiB / 0.40% | 16.04 MiB / 0.68%  | 20.39 MiB / 0.76%  | 20.34 MiB / 0.70%  |

### Per-Target RSS (operator container breakdown)

The operator container hosts a microservice for each installed target plus scope-level routing and streaming microservices. Breaking the operator's RSS down by target:

| Target        |  Demo (MB) | Demo + LoadSim (MB) |
| :------------ | ---------: | ------------------: |
| (scope-level) |      171.7 |               268.9 |
| EXAMPLE       |      264.7 |               269.3 |
| TEMPLATED     |      269.9 |               273.2 |
| INST2         |      373.7 |               363.5 |
| INST          |      413.9 |               394.1 |
| LOADSIM       |          – |               214.1 |
| **Total**     | **1493.8** |          **1783.2** |

### Observations

**Baseline footprint.** With no user targets installed, the COSMOS Enterprise infrastructure consumes roughly 3.7 GiB total across all containers, with the operator container alone using only ~230 MiB. This is the floor regardless of how few targets you run — most of the baseline cost lives in the long-running services (tsdb, cmd-tlm-api, keycloak, script-runner-api).

**Per-target overhead.** Adding the Demo's 4 targets grew the operator from 229 MiB to 1.44 GiB — roughly 300 MiB per target on average, consistent with the rule of thumb in the [Memory](#memory) section above. Simple targets (EXAMPLE, TEMPLATED) consume ~265–270 MB each while more complex targets (INST, INST2) consume ~370–415 MB each. Adding targets had little effect on the other infrastructure containers.

**LoadSim impact.** Adding LoadSim added the LOADSIM target microservices (~214 MB) plus an extra ~100 MB of scope-level RSS as the routing/streaming microservices handle the higher-volume traffic. redis-ephemeral grew from 86 MiB to 137 MiB to hold the larger packet streams, and tsdb CPU jumped from 34% to 46% as it ingested the additional telemetry. Operator CPU rose only modestly (15.6% → 20.4%) because LoadSim runs at 1 Hz; higher-rate scenarios will scale CPU proportionally.

**Long-running stability.** Over a multi-hour soak with the full Demo + LoadSim load, container memory remained stable. The operator drifted up by ~60 MiB and tsdb by ~200 MiB (expected as TSDB accumulates indexed data); other containers held steady. CPU profiles also held steady, indicating no runaway behavior.

**What doesn't scale with targets.** cmd-tlm-api, script-runner-api, keycloak, postgresql, traefik, and grafana stay essentially flat across all four scenarios — their footprint is driven by configuration and user activity, not by the number of targets installed.

# Conclusions

While it is easy to run COSMOS on any Docker platform, increasing the number and complexity of the targets requires choosing the correct hardware. Sizing can be approximated but the best solution is to install representative targets and use `docker stats` and `htop` to judge the CPU and memory pressure on the given hardware.

[COSMOS Enterprise](https://openc3.com/cosmos-enterprise) on Kubernetes helps to eliminate the hardware sizing issue by scaling the cluster to meet the needs of the system.
