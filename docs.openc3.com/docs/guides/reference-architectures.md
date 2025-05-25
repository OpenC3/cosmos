---
title: Reference Architectures
description: Typical COSMOS use-cases
sidebar_custom_props:
  myEmoji: 🏗️
---

COSMOS is the best way to command and control hardware with embedded software. The hardware it can control and the configuration of the software is limitless. However, there are several "Reference Architectures" that are commonly used which describe the vast majority of use-cases for COSMOS.

## Core Single Server Architecture

COSMOS Core (Open Source) deployed on a single server is most suitable for evaluation, test or development. COSMOS can be deployed on a individual computer with Windows or Mac OS via [Docker Desktop](https://docs.docker.com/desktop/). It can deployed on Linux directly using Docker on Ubuntu or Podman on RedHat.

If you deploy COSMOS Core you have to configure COSMOS yourself and build all your hardware plugins from scratch. You must rely on the COSMOS documentation and github issues instead of having direct email support from the OpenC3 team. Core configures a single user with a shared password having admin privileges. The Core license is AGPLv3 which means your users must have access to the COSMOS source code or any extensions you build into COSMOS itself.

Most Suitible for:

- Evaluation of COSMOS
- University teams
- Individual use
- Localized lab development

| Advantages                          | Considerations                         |
| ----------------------------------- | -------------------------------------- |
| ✅&nbsp;&nbsp;Free (AGPLv3 license) | 🤔&nbsp;&nbsp;No OpenC3 support        |
| ✅&nbsp;&nbsp;Easy to deploy        | 🤔&nbsp;&nbsp;No Users, RBAC or SSO    |
| ✅&nbsp;&nbsp;Easy to configure     | 🤔&nbsp;&nbsp;Limited scalability      |
|                                     | 🤔&nbsp;&nbsp;No Calendar or Autonomic |

### Enterprise Single Server Architecture

COSMOS Enterprise deployed on a single server is most suitable for formal test, production or operations.
COSMOS Enterprise can be deployed on a individual computer with Windows or Mac OS via [Docker Desktop](https://docs.docker.com/desktop/). It can deployed on Linux directly using Docker on Ubuntu or Podman on RedHat.

Enterprise comes with a number of plugins that help you jump start your development: CCSDS TC/TM/CFDP, SCPI, SNMP, Gems, Protocol Buffers, gRPC, etc. Enterprise comes with email support from the OpenC3 team. Enterprise includes users, RBAC (role based access control) and SSO (single sign-on) through Keycloak. The Enterprise license is Commercial which means you can build proprietary COSMOS extensions and not be required to give your users access to the source code.

Most Suitible for:

- Quickly connecting to SCPI, SNMP, Gems, gRPC, etc
- Controlling hardware utilizing CCSDS TC, TM, CFDP
- Operating cFS ([Core Flight System](https://etd.gsfc.nasa.gov/capabilities/core-flight-system/))
- Formal test with user attribution
- Operations for 1 or more satellites

| Advantages                                | Considerations                    |
| ----------------------------------------- | --------------------------------- |
| ✅&nbsp;&nbsp;OpenC3 Supported            | 🤔&nbsp;&nbsp;Limited scalability |
| ✅&nbsp;&nbsp;Commercial License          |                                   |
| ✅&nbsp;&nbsp;Library of existing plugins |                                   |
| ✅&nbsp;&nbsp;Users with RBAC and SSO     |                                   |
| ✅&nbsp;&nbsp;Calendar and Autonomic      |                                   |
| ✅&nbsp;&nbsp;Easy to deploy              |                                   |
| ✅&nbsp;&nbsp;Easy to configure           |                                   |

### Enterprise Cloud Architecture

COSMOS Enterprise deployed in the cloud (public or private) is most suitable for operations of satellite constellations or as a satellite operations center. In addition to the benefits listed under the Enterprise Single Server Architecture, Enterprise comes with cloud scripts to help create a reference deployment (EKS, GKE, etc). Enterprise also comes with helm charts to deploy COSMOS in Kubernetes.

Most Suitible for:

- Operating a satellite constellation (10-1000 satellites)
- Running a satellite ops center which supports many different satellite buses / payloads

| Advantages                                | Considerations                                 |
| ----------------------------------------- | ---------------------------------------------- |
| ✅&nbsp;&nbsp;OpenC3 Supported            | 🤔&nbsp;&nbsp;Cloud configuration / complexity |
| ✅&nbsp;&nbsp;Commercial License          | 🤔&nbsp;&nbsp;Kubernetes management            |
| ✅&nbsp;&nbsp;Library of existing plugins | 🤔&nbsp;&nbsp;Public cloud costs               |
| ✅&nbsp;&nbsp;Users with RBAC and SSO     |                                                |
| ✅&nbsp;&nbsp;Calendar and Autonomic      |                                                |
| ✅&nbsp;&nbsp;Cloud configuration scripts |                                                |
| ✅&nbsp;&nbsp;Helm charts                 |                                                |
