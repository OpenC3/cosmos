---
sidebar_position: 5
title: Key Concepts
description: Projects, Containerization, Frontend, Backend
sidebar_custom_props:
  myEmoji: 💡
---

# OpenC3 COSMOS Key Concepts

## Projects

The main COSMOS [repo](https://github.com/OpenC3/cosmos) contains all the source code used to build and run COSMOS. However, users (not developers) of COSMOS should use the COSMOS [project](https://github.com/OpenC3/cosmos-project) to launch COSMOS. The project consists of the [openc3.sh](https://github.com/OpenC3/cosmos-project/blob/main/openc3.sh) and [openc3.bat](https://github.com/OpenC3/cosmos-project/blob/main/openc3.bat) files for starting and stopping COSMOS, the [compose.yaml](https://github.com/OpenC3/cosmos-project/blob/main/compose.yaml) for configuring the COSMOS containers, and the [.env](https://github.com/OpenC3/cosmos-project/blob/main/.env) file for setting runtime variables. Additionally, the COSMOS project contains user modifiable config files for both Redis and Traefik.

## Containerization

### Images

Per [Docker](https://docs.docker.com/get-started/overview/#images), "An image is a read-only template with instructions for creating a Docker container." The base operating system COSMOS uses is called [Alpine Linux](https://www.alpinelinux.org/). It is a simple and compact image with a full package system that allows us to install our dependencies. Starting with Alpine, we create a [Dockerfile](https://docs.docker.com/engine/reference/builder/) to add Ruby and Python and a few other packages to create our own docker image. We further build upon that image to create a NodeJS image to support our frontend and additional images to support our backend.

### Containers

Per [Docker](https://www.docker.com/resources/what-container/), "a container is a standard unit of software that packages up code and all its dependencies so the application runs quickly and reliably from one computing environment to another." Also per [Docker](https://docs.docker.com/guides/walkthroughs/what-is-a-container/), "A container is an isolated environment for your code. This means that a container has no knowledge of your operating system, or your files. It runs on the environment provided to you by Docker Desktop. Containers have everything that your code needs in order to run, down to a base operating system." COSMOS utilizes containers to provide a consistent runtime environment. Containers make it easy to deploy to local on-prem servers, cloud environments, or air-gapped networks.

The COSMOS Open Source containers consist of the following:

| Name                                     | Description                                                                                            |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| cosmos-openc3-cosmos-init-1              | Copies files to Minio and configures COSMOS then exits                                                 |
| cosmos-openc3-operator-1                 | Main COSMOS container that runs the interfaces and target microservices                                |
| cosmos-openc3-cosmos-cmd-tlm-api-1       | Rails server that provides all the COSMOS API endpoints                                                |
| cosmos-openc3-cosmos-script-runner-api-1 | Rails server that provides the Script API endpoints                                                    |
| cosmos-openc3-redis-1                    | Serves the static target configuration                                                                 |
| cosmos-openc3-redis-ephemeral-1          | Serves the [streams](https://redis.io/docs/data-types/streams) containing the raw and decomutated data |
| cosmos-openc3-minio-1                    | Provides a S3 like bucket storage interface and also serves as a static webserver for the tool files   |
| cosmos-openc3-traefik-1                  | Provides a reverse proxy and load balancer with routes to the COSMOS endpoints                         |

The container list for [Enterprise COSMOS](https://openc3.com/enterprise) consists of the following:

| Name                                  | Description                                                                                   |
| ------------------------------------- | --------------------------------------------------------------------------------------------- |
| cosmos-enterprise-openc3-metrics-1    | Rails server that provides metrics on COSMOS performance                                      |
| cosmos-enterprise-openc3-keycloak-1   | Single-Sign On service for authentication                                                     |
| cosmos-enterprise-openc3-postgresql-1 | SQL Database for use by Keycloak                                                              |
| openc3-nfs \*                         | Network File System pod only for use in Kubernetes to share code libraries between containers |

### Docker Compose

Per [Docker](https://docs.docker.com/compose/), "Compose is a tool for defining and running multi-container Docker applications. With Compose, you use a YAML file to configure your application's services. Then, with a single command, you create and start all the services from your configuration." OpenC3 uses compose files to both build and run COSMOS. The [compose.yaml](https://github.com/OpenC3/cosmos-project/blob/main/compose.yaml) is where ports are exposed and environment variables are used.

### Environment File

COSMOS uses an [environment file](https://docs.docker.com/compose/environment-variables/env-file/) along with Docker Compose to pass environment variables into the COSMOS runtime. This [.env](https://github.com/OpenC3/cosmos-project/blob/main/.env) file consists of simple key value pairs that contain the version of COSMOS deployed, usernames and passwords, and much more.

### Kubernetes

Per [Kubernetes.io](https://kubernetes.io/), "Kubernetes, also known as K8s, is an open-source system for automating deployment, scaling, and management of containerized applications. It groups containers that make up an application into logical units for easy management and discovery." [COSMOS Enterprise](https://openc3.com/enterprise) provides [Helm charts](https://helm.sh/docs/topics/charts/) for easy deployment to Kubernetes in various cloud environments.

COSMOS Enterprise also provides [Terraform](https://www.terraform.io/) scripts to deploy COSMOS infrastructure on various cloud environments.

## Frontend

### Vue.js

The COSMOS frontend is fully browser native and is implemented in the Vue.js framework. Per [Vue.js](https://vuejs.org/guide/introduction.html), "Vue is a JavaScript framework for building user interfaces. It builds on top of standard HTML, CSS, and JavaScript and provides a declarative and component-based programming model that helps you efficiently develop user interfaces, be they simple or complex." COSMOS utilizes Vue.js and the [Vuetify](https://vuetifyjs.com/en/) Component Framework UI library to build all the COSMOS tools which run in the browser of your choice. COSMOS 5 utilized Vue.js 2.x and Vuetify 2.x while COSMOS 6 utilizes Vue.js 3.x and Vuetify 3.x.

### Single-Spa

While COSMOS itself is written in Vue.js, we utilize a technology called [single-spa](https://single-spa.js.org/) to allow COSMOS developers to create applications in any javascript framework they choose. Single-spa is a micro frontend framework and acts as a top level router to render the application being requested. COSMOS provides sample applications ready to plug into single-spa in Angular, React, Svelte, and Vue.

### Astro UX

Per [AstroUXDS](https://www.astrouxds.com/), "The Astro Space UX Design System enables developers and designers to build rich space app experiences with established interaction patterns and best practices." COSMOS utilizes the Astro design guidelines for color, typograpy, and iconograpy. In some cases, e.g. [Astro Clock](https://www.astrouxds.com/components/clock/), COSMOS directly incorporates Astro components.

## Backend

### Redis

[Redis](https://redis.io/) is an in-memory data store with support for strings, hashes, lists, sets, sorted sets, streams, and more. COSMOS uses Redis to store both our configuration and data. If you look back at our [container list](/docs/getting-started/key_concepts#containers) you'll notice two redis containers: cosmos-openc3-redis-1 and cosmos-openc3-redis-ephemeral-1. The ephemeral container contains all the real-time data pushed into [Redis streams](https://redis.io/docs/data-types/streams/). The other redis container contains COSMOS configuration that is meant to persist. [COSMOS Enterprise](https://openc3.com/enterprise) provides helm charts that setup [Redis Cluster](https://redis.io/docs/management/scaling/) to perform horizontal scaling where data is shared across multiple Redis nodes.

### MinIO

[MinIO](https://min.io/) is a high-performance, S3 compatible object store. COSMOS uses this storage technology to host both the COSMOS tools themselves and the long term log files. [COSMOS Enterprise](https://openc3.com/enterprise) deployed in a cloud environment uses the available cloud native bucket storage technology, e.g. AWS S3, GCP Buckets, and Azure Blob Storage. Using bucket storage allows COSMOS to directly serve the tools as a static website and thus we don't need to deploy Tomcat or Nginx for example.

### Ruby on Rails

The COSMOS API and Script Runner backends are powered by [Ruby on Rails](https://rubyonrails.org/). Rails is a web application development framework written in the Ruby programming language. Rails (and our familiarity with Ruby) allows us to write less code while accomplishing more than many other languages and frameworks.
