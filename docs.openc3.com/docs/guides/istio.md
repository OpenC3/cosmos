---
title: Istio Support
description: Running COSMOS alongside an Istio service mesh
sidebar_custom_props:
  myEmoji: 🕸️
---

## What is Istio?

[Istio](https://istio.io) is an open-source service mesh for Kubernetes. It injects an Envoy proxy sidecar next to each application container and transparently handles cross-service networking concerns — mutual TLS between Pods, fine-grained traffic policy and routing, retries and circuit breaking, and consistent observability (metrics, traces, access logs) — without requiring changes to the application itself.

For COSMOS, running inside an Istio mesh is useful when you want encrypted service-to-service traffic between the pods without managing certificates manually.

:::info[Kubernetes only]
Istio is a Kubernetes-native service mesh, so `OPENC3_ISTIO_ENABLED` is only relevant when COSMOS is deployed on Kubernetes with Istio sidecar injection enabled. **Do not set this variable on Docker Compose or Podman deployments** — there is no sidecar to coordinate with, and the init container will hang waiting for one.
:::

## Enabling Istio support

Set `OPENC3_ISTIO_ENABLED` to any non-empty value (for example `"1"`) on the `openc3-cosmos-init` container's environment:

```yaml
env:
  - name: OPENC3_ISTIO_ENABLED
    value: "1"
```

Set this whenever Istio sidecar injection is enabled for the namespace COSMOS runs in. Leave it unset (or empty) for non-Istio deployments. No other COSMOS container needs this variable.

When enabled, the init container coordinates with the Envoy sidecar on the standard Istio ports:

| Port  | Endpoint         | Used for                                         |
| ----- | ---------------- | ------------------------------------------------ |
| 15021 | `/healthz/ready` | Wait for the sidecar to be ready before init work |
| 15020 | `/quitquitquit`  | Ask the sidecar to exit after init work finishes  |

If deploying with the COSMOS Enterprise Helm chart, `OPENC3_ISTIO_ENABLED` is not set automatically — add it to the init Pod's environment in your values override or chart customization.

## GKE Workload Identity

If you are using GKE Workload Identity inside an Istio mesh, exclude the GKE metadata server from sidecar interception, or Workload Identity calls will fail. Apply either:

- A per-workload annotation:
  ```yaml
  annotations:
    traffic.sidecar.istio.io/excludeOutboundIPRanges: "169.254.169.254/32"
  ```
- Or the mesh-wide `global.proxy.excludeIPRanges` setting in the Istio ConfigMap.
