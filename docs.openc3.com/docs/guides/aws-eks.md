---
title: AWS EKS
description: Installing COSMOS Enterprise on AWS EKS (Kubernetes) with Helm
sidebar_custom_props:
  myEmoji: ☸️
---

Running OpenC3 COSMOS Enterprise on Amazon Web Services (AWS) uses EKS (Elastic Kubernetes Service), S3 storage, and other AWS services. OpenC3 provides a CloudFormation template that deploys the basic set of services COSMOS Enterprise requires. You can either integrate this template into your own deployment strategy or make sure you already have similar services configured before deploying the Helm charts. For a simpler single server deployment, see the [AWS EC2](/docs/guides/aws-ec2) guide.

## Installation

Install to AWS by following the [AWS README](https://repos.openc3.com/OpenC3/cosmos-enterprise/src/branch/main/cloud/aws/README.md).

This describes installing the AWS CLI, creating the CloudFormation stack, creating the AWS Certificate Manager (ACM) certificate, configuring kubectl, ensuring a default storage class, and installing the AWS Load Balancer Controller.

The tsdb (QuestDB) requires `vm.max_map_count` to be raised on every worker node. The CloudFormation template does this through its `MaxMapCount` parameter, so leave it at the default (1048576) unless you have a reason to change it.

## Enterprise Helm Charts

There are 3 Helm charts that install the full COSMOS Enterprise:

- **openc3-nfs** - Network file storage chart that creates an NFS volume
- **openc3-db** - Installs the COSMOS databases: Redis, the tsdb (QuestDB), and PostgreSQL (for Keycloak). On AWS the buckets subchart is disabled because COSMOS uses S3.
- **openc3** - Installs the remaining COSMOS Enterprise software

### openc3-nfs

First examine the [openc3-nfs cloud values](https://repos.openc3.com/OpenC3/cosmos-enterprise/src/branch/main/openc3-helm/openc3-nfs/ci/cloud-values.yaml):

```yaml
global:
  # Modify to your own DNS record
  cosmosDomain: aws.openc3.com
  image:
    registry: repos.openc3.com
    namespace: openc3
    pullSecrets:
      - name: registry
```

Change `cosmosDomain` to your own domain. Update the registry if you've deployed the containers to a local registry (for example if you're air-gapped).

### openc3-db

Next examine the [openc3-db AWS values](https://repos.openc3.com/OpenC3/cosmos-enterprise/src/branch/main/openc3-helm/openc3-db/ci/aws-values.yaml).

Change `cosmosDomain` and potentially the registry. Leave `buckets.enabled: false` since S3 provides the buckets. Disable `postgresql` only if you are using an external Keycloak. The `tsdb.maxMapCount` setting adds a privileged init container that raises `vm.max_map_count` on nodes that were not tuned by the CloudFormation template. It is harmless on tuned nodes, but a namespace with PodSecurity `baseline` or `restricted` will reject it, in which case remove it and tune the nodes instead.

### openc3

Next examine the [openc3 AWS values](https://repos.openc3.com/OpenC3/cosmos-enterprise/src/branch/main/openc3-helm/openc3/ci/aws-values.yaml).

Change `cosmosDomain`, `cosmosExternalUrl`, and potentially the registry. You also need to update:

- `logsBucket`, `toolsBucket`, and `configBucket` to the bucket names created by the CloudFormation stack
- `cloud.aws.region` (and `cloud.aws.arnPrefix` to `arn:aws-us-gov` for US GovCloud)
- `serviceAccount.annotations` with your account ID and stack name
- `aws.certArn` to your ACM certificate ARN
- `grafana.rootUrl`, `grafana.authUrl`, and `keycloak.externalUrl` to match your domain

The AWS ALB terminates TLS with the ACM certificate, so keep `ssl: true` and `traefik.tlsCerts: false`. See [SSL-TLS](/docs/configuration/ssl-tls#pattern-1-platform-load-balancer-terminates-tls-aws-eks-gcp-gke) for details on this pattern and the `openc3-cacert` secret.

## Deploy Helm Charts

Follow the instructions in the [Helm README](https://repos.openc3.com/OpenC3/cosmos-enterprise/src/branch/main/openc3-helm/README.md) using the "Initial steps" and "Development in the cloud" sections. These describe authenticating with the registry, creating a namespace, installing the registry pull secret, creating the secrets, and deploying the Helm charts.

Once everything has been deployed and the pods are running, go to AWS EC2 Load Balancers. The Helm deployment creates a Load Balancer called `openc3-lb`. Copy its DNS name and go to your DNS settings to create a CNAME record that points from your domain (aws.openc3.com in this example) to the Load Balancer DNS name.

You can now load your domain (https://\<DOMAIN\>/auth/admin/master/console) and start [configuring Keycloak](https://repos.openc3.com/OpenC3/cosmos-enterprise-project/src/branch/main/KeycloakConfiguration.md).

## Troubleshooting

See [Troubleshooting](/docs/guides/troubleshooting).
