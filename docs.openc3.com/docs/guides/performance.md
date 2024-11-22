---
title: Performance
description: Hardware requirements like memory and CPU
sidebar_custom_props:
  myEmoji: 📊
---

The COSMOS architecture was created with scalability in mind. Our goal is to support an unlimited number of connections and use cloud technologies to scale. Only [COSMOS Enterprise Edition](https://openc3.com/enterprise) supports Kubernetes and the various cloud platforms which allow this level of scalability. While true scalability is only achieved in COSMOS Enterprise, both Open Source and Enterprise have various levels of observability and configuration settings which can affect performance.

# COSMOS Hardware Requirements

## Memory

COSMOS can run on a Raspberry Pi up to a Kubernetes cluster in the cloud. On all platforms the key performance factor is the number and complexity of the targets and their defined packets. Targets can vary from simple targets taking 100 MB of RAM to complex targets taking 400 MB. The base COSMOS containers require about 800 MB of RAM. A good rule of thumb is to average about 300 MB of RAM for targets. As an example data point, the COSMOS Demo has 4 targets, two complex (INST & INST2) and two relatively simple (EXAMPLE & TEMPLATED), and requires 800 MB of RAM (on top of the 800 MB of base container RAM).

- Base RAM MB Calculator = 800 + (num targets) \* 300

In addition, the Redis streams contain the last 10 min of both raw and decommutated data from all targets. Thus you must wait ~15min to truly see what the high water memory mark will be. In the COSMOS Demo the INST & INST2 targets are fairly simple with four 1Hz packet of ~15 items and one 10Hz packet with 20 items. This only causes 50 MiB of redis RAM usage according to `docker stats`. Installing the COSMOS [LoadSim](https://github.com/OpenC3/openc3-cosmos-load-sim) with 10 packets with 1000 items each at 10Hz pushed the redis memory usage to about 350 MiB.

## CPU

Another consideration is the CPU performance. In the Open Source Edition, by default COSMOS spawns off 2 microservices per target. One combines packet logging and decommutation of the data and the other performs data reduction. In COSMOS Enterprise Edition on Kubernetes, each process becomes an independent container that is deployed on the cluster allowing horizontal scaling.

The COSMOS command and telemetry API and script running API servers should have a dedicated core while targets can generally share cores. It's hard to provide a general rule of thumb with the wide variety of architectures, clock speeds, and core counts. The best practice is to install COSMOS with the expected load and do some monitoring with `htop` to visualize the load on the various cores. Any time a single core gets overloaded (100%) this is a concern and system slowdown can occur.

## Performance Comparison

Performance characterization was performed in Azure on a Standard D4s v5 (4 vcpus, 16 GiB memory) chosen to allow virtualization per [Docker](https://docs.docker.com/desktop/vm-vdi/#turn-on-nested-virtualization-on-microsoft-hyper-v). COSMOS [5.9.1](https://github.com/OpenC3/cosmos-enterprise/releases/tag/v5.9.1) Enterprise Edition was installed on both Windows 11 Pro [^1] and Ubuntu 22. Note: Enterprise Edition was not utilizing Kubernetes, just Docker. Testing involved starting the COSMOS Demo, connecting all targets (EXAMPLE, INST, INST2, TEMPLATED), opening the following TlmViewer screens (ADCS, ARRAY, BLOCK, COMMANDING, HS, LATEST, LIMITS, OTHER, PARAMS, SIMPLE, TABS) and creating two TlmGrapher graphs consisting of INST HEALTH_STATUS TEMP[1-4] and INST ADCS POS[X,Y,Z] and INST ADCS VEL[X,Y,Z]. This was allowed to run for 1hr and results were collected using `htop`:

| Platform           | Core CPU %      | RAM          |
| :----------------- | :-------------- | :----------- |
| Windows 11 Pro     | 12% 12% 10% 10% | 3.9G / 7.7G  |
| Headless Ubuntu 22 | 7% 7% 8% 6%     | 3.2G / 15.6G |

- Windows was only allocated 8 GB of RAM due to the [.wslconfig](https://learn.microsoft.com/en-us/windows/wsl/wsl-config#configuration-setting-for-wslconfig) settings.
- Since Ubuntu was running headless, the screens and graphs were brought up on another machine.

`docker stats` was also run to show individual container cpu and memory usage:

| NAME                                                        | Windows CPU % | Ubuntu CPU % | Windows MEM | Ubuntu MEM |
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

- memory profiles are similar between the two platforms
- redis-ephemeral isn't using much memory on the base Demo with its small packets

At this point the COSMOS [LoadSim](https://github.com/OpenC3/openc3-cosmos-load-sim) was installed with default settings which creates 10 packets with 1000 items each at 10Hz (110kB/s). After a 1 hr soak, htop now indicated:

| Platform           | Core CPU %      | RAM           |
| :----------------- | :-------------- | :------------ |
| Windows 11 Pro     | 40% 35% 39% 42% | 4.64G / 7.7G  |
| Headless Ubuntu 22 | 17% 20% 16% 18% | 3.74G / 15.6G |

The larger packets and data rate of the LoadSim target caused both platforms to dramatically increase CPU utilization but the Linux machine stays quite performant.

`docker stats` was also run to show individual container cpu and memory usage:

| NAME                                                        | Windows CPU % | Ubuntu CPU % | Windows MEM | Ubuntu MEM |
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

- memory profiles are similar between the two platforms
- redis-ephemeral is now using much more RAM as it is storing the large LoadSim packets
- Windows is using much more CPU power running the operator, cmd-tlm, and redis

# Conclusions

While it is easy to run COSMOS on any Docker platform, increasing the number and complexity of the targets requires choosing the correct hardware. Sizing can be approximated but the best solution is to install representative targets and use `docker stats` and `htop` to judge the CPU and memory pressure on the given hardware.

[COSMOS Enterprise Edition](https://openc3.com/enterprise) on Kubernetes helps to eliminate the hardware sizing issue by scaling the cluster to meet the needs of the system. Check out [this recent talk](https://openc3.com/news/scaling) Ryan gave at GSAW showing how we scaled to over 160 satellites on a 4 node kubernetes cluster on EKS.

<hr/>

[^1]: Full specs of the Windows Platform:

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
