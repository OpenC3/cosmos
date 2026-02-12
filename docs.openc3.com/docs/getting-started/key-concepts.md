---
sidebar_position: 1
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

The following diagram shows all the COSMOS Core and Enterprise container images. Images are built from the bottom up in the Dockerfile using [FROM](https://docs.docker.com/reference/dockerfile/#from). Images referenced with "Uses" are used during the build stage.

![COSMOS Images](/img/cosmos-images.png)

### Containers

Per [Docker](https://www.docker.com/resources/what-container/), "a container is a standard unit of software that packages up code and all its dependencies so the application runs quickly and reliably from one computing environment to another." Also per [Docker](https://docs.docker.com/guides/walkthroughs/what-is-a-container/), "A container is an isolated environment for your code. This means that a container has no knowledge of your operating system, or your files. It runs on the environment provided to you by Docker Desktop. Containers have everything that your code needs in order to run, down to a base operating system." COSMOS utilizes containers to provide a consistent runtime environment. Containers make it easy to deploy to local on-prem servers, cloud environments, or air-gapped networks.

The COSMOS Core containers consist of the following:

| Name                                     | Description                                                                                           |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| cosmos-openc3-cosmos-init-1              | Run migrations, installs the COSMOS tools, and then exits                                             |
| cosmos-openc3-operator-1                 | Main COSMOS container that runs the interfaces and target microservices                               |
| cosmos-openc3-traefik-1                  | Provides a reverse proxy and load balancer with routes to the COSMOS endpoints                        |
| cosmos-openc3-cosmos-cmd-tlm-api-1       | Rails server that provides all the COSMOS API endpoints                                               |
| cosmos-openc3-cosmos-script-runner-api-1 | Rails server that provides the Script API endpoints                                                   |
| cosmos-openc3-buckets-1                  | Provides a S3 like bucket storage interface and also serves as a static webserver for the tool files  |
| cosmos-openc3-redis-1                    | Serves the static target configuration and Current Value Table                                        |
| cosmos-openc3-redis-ephemeral-1          | Serves the [streams](https://valkey.io/topics/streams-intro/) containing the raw and decomutated data |

The container list for [COSMOS Enterprise](https://openc3.com/enterprise) consists of the following:

| Name                                  | Description                                                                                   |
| ------------------------------------- | --------------------------------------------------------------------------------------------- |
| cosmos-enterprise-openc3-grafana-1    | [Grafana](https://grafana.com/) container preconfigured with the COSMOS Data Source           |
| cosmos-enterprise-openc3-metrics-1    | Rails server that provides metrics on COSMOS performance                                      |
| cosmos-enterprise-openc3-keycloak-1   | Single-Sign On service for authentication                                                     |
| cosmos-enterprise-openc3-postgresql-1 | SQL Database for use by Keycloak                                                              |
| openc3-nfs \*                         | Network File System pod only for use in Kubernetes to share code libraries between containers |

A diagram of the running containers is shown below:

![COSMOS Images](/img/cosmos-containers.png)

### Docker Compose

Per [Docker](https://docs.docker.com/compose/), "Compose is a tool for defining and running multi-container Docker applications. With Compose, you use a YAML file to configure your application's services. Then, with a single command, you create and start all the services from your configuration." OpenC3 uses compose files to both build and run COSMOS. The [compose.yaml](https://github.com/OpenC3/cosmos-project/blob/main/compose.yaml) is where ports are exposed and environment variables are used.

### Environment File

COSMOS uses an [environment file](https://docs.docker.com/compose/environment-variables/env-file/) along with Docker Compose to pass environment variables into the COSMOS runtime. This [.env](https://github.com/OpenC3/cosmos-project/blob/main/.env) file consists of simple key value pairs that contain the version of COSMOS deployed, usernames and passwords, and much more.

### Kubernetes

Per [Kubernetes.io](https://kubernetes.io/), "Kubernetes, also known as K8s, is an open-source system for automating deployment, scaling, and management of containerized applications. It groups containers that make up an application into logical units for easy management and discovery." [COSMOS Enterprise](https://openc3.com/enterprise) provides [Helm charts](https://helm.sh/docs/topics/charts/) for easy deployment to Kubernetes in various cloud environments.

COSMOS Enterprise also provides configuration to deploy COSMOS infrastructure on various cloud environments (e.g. CloudFormation template on AWS).

## Frontend

### Vue.js

The COSMOS frontend is fully browser native and is implemented in the Vue.js framework. Per [Vue.js](https://vuejs.org/guide/introduction.html), "Vue is a JavaScript framework for building user interfaces. It builds on top of standard HTML, CSS, and JavaScript and provides a declarative and component-based programming model that helps you efficiently develop user interfaces, be they simple or complex." COSMOS utilizes Vue.js and the [Vuetify](https://vuetifyjs.com/en/) Component Framework UI library to build all the COSMOS tools which run in the browser of your choice. COSMOS 5 utilized Vue.js 2.x and Vuetify 2.x while COSMOS 6 utilizes Vue.js 3.x and Vuetify 3.x.

### Single-Spa

While COSMOS itself is written in Vue.js, we utilize a technology called [single-spa](https://single-spa.js.org/) to allow COSMOS developers to create applications in any javascript framework they choose. Single-spa is a micro frontend framework and acts as a top level router to render the application being requested. COSMOS provides sample applications ready to plug into single-spa in Angular, React, Svelte, and Vue.

### Astro UX

Per [AstroUXDS](https://www.astrouxds.com/), "The Astro Space UX Design System enables developers and designers to build rich space app experiences with established interaction patterns and best practices." COSMOS utilizes the Astro design guidelines for color, typograpy, and iconograpy. In some cases, e.g. [Astro Clock](https://www.astrouxds.com/components/clock/), COSMOS directly incorporates Astro components.

## Backend

### Valkey

[Valkey](https://valkey.io/) is an in-memory data store with support for strings, hashes, lists, sets, sorted sets, streams, and more. COSMOS uses Valkey to store both our configuration and data. If you look back at our [container list](/docs/getting-started/key-concepts#containers) you'll notice two valkey containers: cosmos-openc3-redis-1 and cosmos-openc3-redis-ephemeral-1 (still named Redis after the original). The ephemeral container contains all the real-time data pushed into [streams](https://valkey.io/topics/streams-intro/). The other container contains COSMOS configuration that is meant to persist. [COSMOS Enterprise](https://openc3.com/enterprise) provides helm charts that setup [Valkey Cluster](https://valkey.io/topics/cluster-tutorial/) to perform horizontal scaling where data is shared across multiple nodes.

### Versitygw

[Versitygw](https://github.com/versity/versitygw/) is a high-performance, S3 compatible object store. COSMOS uses this storage technology to host both the COSMOS tools themselves and the long term log files. [COSMOS Enterprise](https://openc3.com/enterprise) deployed in a cloud environment uses the available cloud native bucket storage technology, e.g. AWS S3, GCP Buckets, and Azure Blob Storage. Using bucket storage allows COSMOS to directly serve the tools as a static website and thus we don't need to deploy Tomcat or Nginx for example.

### Ruby on Rails

The COSMOS API and Script Runner backends are powered by [Ruby on Rails](https://rubyonrails.org/). Rails is a web application development framework written in the Ruby programming language. Rails (and our familiarity with Ruby) allows us to write less code while accomplishing more than many other languages and frameworks.

### QuestDB

COSMOS uses [QuestDB](https://questdb.io/) as its time-series database (TSDB) for long-term telemetry storage. QuestDB is a high-performance database optimized for time-series data, offering fast ingestion rates and efficient querying of large datasets.

While Redis stores real-time streaming data and the current value table, QuestDB provides persistent storage for historical telemetry. This enables users to query telemetry data over extended time periods using standard SQL syntax.

### Keycloak (Enterprise)

[COSMOS Enterprise](https://openc3.com/enterprise) uses [Keycloak](https://www.keycloak.org/) as its Single Sign-On (SSO) solution. Keycloak is an open-source Identity and Access Management system that provides authentication, authorization, and user federation capabilities. Keycloak implements the OAuth 2.0 and OpenID Connect protocols and issues several types of tokens to manage user sessions.

#### Access Token

The access token is a short-lived JSON Web Token (JWT) used to authenticate API requests. It is included in the `Authorization: Bearer <token>` header of HTTP requests and contains user identity and permissions (claims). When an access token expires, the client must obtain a new one using a refresh token. COSMOS Enterprise default: **5 minutes**.

#### Refresh Token

The refresh token is a longer-lived token used solely to obtain new access tokens. It is never sent to resource servers—only to Keycloak's token endpoint. Each refresh request typically returns a new refresh token (token rotation). The refresh token expires after a period of inactivity (SSO Session Idle) or after a maximum lifespan (SSO Session Max), at which point the user must re-authenticate. COSMOS Enterprise defaults: **30 minutes** idle timeout, **10 hours** max lifespan.

#### Offline Access Token

The offline access token is a special type of refresh token designed for long-lived sessions lasting days, weeks, or indefinitely. It is obtained by requesting the `offline_access` scope during authentication. Unlike regular refresh tokens, offline access tokens survive Keycloak server restarts and user session logouts. They are useful for automated scripts or services that need persistent access without user interaction. Offline tokens have separate configuration settings: "Offline Session Idle" and "Offline Session Max". COSMOS Enterprise defaults: **30 days** idle timeout, max lifespan not enforced (tokens can last indefinitely if used regularly).

#### Token Lifecycle

The typical token lifecycle works as follows:

1. User authenticates with Keycloak and receives an access token and refresh token
2. Client uses the access token for API calls
3. Access token expires and client sends the refresh token to Keycloak
4. Keycloak issues a new access token and new refresh token
5. Steps 2-4 repeat until the refresh token expires or the user logs out

For examples of using these tokens with curl see [Testing with Curl](/docs/guides/curl).

#### Automatic Token Refresh

COSMOS Enterprise automatically refreshes tokens to maintain user sessions. Every 60 seconds, the application checks if the access token will expire within the next 2 minutes. If so, it sends the current refresh token to Keycloak's token endpoint and receives both a new access token and a new refresh token.

With the default 5-minute access token lifespan, this results in token refreshes approximately every 3-4 minutes. Each refresh resets the refresh token's idle timeout, keeping the session alive as long as the user has the application open.

Important notes on idle timeout behavior:

- The refresh token idle timeout is only reset when the application communicates with Keycloak (i.e., during token refresh)
- Making API calls using the access token does **not** reset the refresh token idle timeout, because those requests never reach Keycloak
- If a user closes the browser for longer than the idle timeout (default 30 minutes), they must re-authenticate

#### Default Token Lifespans

| Token Type    | Setting      | Default Value |
| ------------- | ------------ | ------------- |
| Access Token  | Lifespan     | 5 minutes     |
| Refresh Token | Idle Timeout | 30 minutes    |
| Refresh Token | Max Lifespan | 10 hours      |
| Offline Token | Idle Timeout | 30 days       |
| Offline Token | Max Lifespan | Not enforced  |
