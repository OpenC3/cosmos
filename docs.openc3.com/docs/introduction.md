---
title: Introduction
sidebar_position: 0
slug: /
---

This site aims to be a comprehensive guide to OpenC3 COSMOS. We'll cover topics such as getting your configuration up and running, developing test and operations scripts, building custom telemetry screens, and give you some advice on participating in the future development of COSMOS itself.

## So what is COSMOS, exactly?

COSMOS is a suite of applications that can be used to control a set of embedded systems. These systems can be anything from test equipment (power supplies, oscilloscopes, switched power strips, UPS devices, etc), to development boards (Arduinos, Raspberry Pi, Beaglebone, etc), to satellites.

### COSMOS Architecture

![COSMOS Architecture](/img/architecture.png)

COSMOS 5 is a cloud native, containerized, microservice oriented command and control system. All the COSMOS microservices are docker containers which is why Docker is shown containing the entire COSMOS system. The green boxes on the left represent external embedded systems (Targets) which COSMOS connects to. The Redis data store contains the configuration for all the microservices, the current value table, as well as data streams containing decommutated data. The Minio data store contains plugins, targets, configuration data, text logs as well as binary logs of all the raw, decommutated, and reduced data. Users interact with COSMOS from a web browser which routes through the internal Traefik load balancer.

Keep reading for an in-depth discussion of each of the COSMOS Tools.

## Helpful Hints

Throughout this guide there are a number of small-but-handy pieces of
information that can make using COSMOS easier, more interesting, and less
hazardous. Here's what to look out for.

:::note ProTips™ help you get more from COSMOS
These are tips and tricks that will help you be a COSMOS wizard!
:::

:::info Notes are handy pieces of information
These are for the extra tidbits sometimes necessary to understand COSMOS.
:::

:::warning Warnings help you not blow things up
Be aware of these messages if you wish to avoid certain death.
:::

:::note Find a problem in the documentation or in COSMOS itself?
Both using and hacking on COSMOS should be fun, simple, and easy, so if for
some reason you find it's a pain, please [create an issue](https://github.com/OpenC3/cosmos/issues/new/choose) on
GitHub describing your experience so we can make it better.
:::
