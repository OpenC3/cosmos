---
title: AWS EC2
description: Installing COSMOS Enterprise on a standalone AWS EC2 instance with S3 storage
sidebar_custom_props:
  myEmoji: ☁️
---

This guide walks through installing OpenC3 COSMOS Enterprise on a standalone Amazon EC2 instance using Docker Compose, with native AWS S3 buckets replacing the local bucket storage container. If you need high availability or horizontal scaling, see the [AWS EKS](/docs/guides/aws-eks) guide instead.

Start by following the [cosmos-enterprise-project README](https://repos.openc3.com/OpenC3/cosmos-enterprise-project) to authenticate with the Enterprise container registry and clone the project onto the instance. The steps below modify that project before you start COSMOS.

## Prerequisites

- An AWS EC2 instance (Ubuntu recommended) with Docker and Docker Compose installed. See the [Installation](/docs/getting-started/installation#prerequisites) prerequisites.
- **At least 100 GB EBS volume** for Docker images and database storage. Note that the Docker images take ~15 GB.
- Three S3 buckets created for config, logs, and tools
- An IAM role with S3 access (see [IAM Setup](#iam-setup-for-s3-access) below)

### Expanding the EBS Volume

If you need to resize your EBS volume later, follow the [AWS guide for recognizing expanded volumes on Linux](https://docs.aws.amazon.com/ebs/latest/userguide/recognize-expanded-volume-linux.html).

For example, from the EC2 Volumes page select Actions -> Modify Volume and increase the volume size (100 GB to 200 GB in this example). Then log into the EC2 instance and expand the file system:

```sh
ubuntu@ip-XXX:~$ lsblk
NAME     MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
xvda     202:0    0  200G  0 disk
├─xvda1  202:1    0   99G  0 part /
├─xvda14 202:14   0    4M  0 part
├─xvda15 202:15   0  106M  0 part /boot/efi
└─xvda16 259:0    0  913M  0 part /boot
ubuntu@ip-XXX:~$ sudo growpart /dev/xvda 1
CHANGED: partition=1 start=2099200 old: size=207615967 end=209715166 new: size=417331167 end=419430366
ubuntu@ip-XXX:~$ sudo resize2fs /dev/xvda1
resize2fs 1.47.0 (5-Feb-2023)
Filesystem at /dev/xvda1 is mounted on /; on-line resizing required
old_desc_blocks = 13, new_desc_blocks = 25
The filesystem on /dev/xvda1 is now 52166395 (4k) blocks long.
```

## Optional: Tailscale for Secure Remote Access

[Tailscale](https://tailscale.com/) provides a private mesh VPN, letting you securely access your EC2 instance without exposing ports to the public internet.

Install Tailscale on the EC2 instance and enable [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh):

```sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
sudo tailscale set --ssh
```

Connect from your local machine using the instance's Tailscale machine name:

```sh
tailscale ssh ubuntu@<MACHINE NAME>
```

## Network Configuration

Follow the [Network Configuration](/docs/guides/network-configuration) guide to open COSMOS to the network. HTTPS with your own certificates is recommended; see [SSL-TLS](/docs/configuration/ssl-tls#configure-cosmos-for-tls-when-running-in-docker-compose).

:::note
Tailscale already encrypts all traffic, so the [HTTP](/docs/guides/network-configuration#http) configuration works over Tailscale, but we still recommend HTTPS. Even over Tailscale, HTTPS is required to use the AI [MCP Server](/docs/guides/mcp-server).
:::

## Configure Environment Variables

Don't edit `.env` directly; it ships the upstream defaults and editing it causes conflicts when you pull COSMOS updates. Instead create a `.env.local` file next to it. `openc3.sh` loads `.env.local` after `.env`, so its values win, and it is gitignored.

In `.env.local`, set the S3 bucket URL, AWS region, and bucket names. Clear the bucket credentials so COSMOS authenticates with the IAM role attached to the instance:

```sh
OPENC3_BUCKET_URL=https://s3.us-east-1.amazonaws.com  # Replace with your AWS region
OPENC3_LOGS_BUCKET=<actual bucket name in S3>
OPENC3_TOOLS_BUCKET=<actual bucket name in S3>
OPENC3_CONFIG_BUCKET=<actual bucket name in S3>

OPENC3_BUCKET_USERNAME=
OPENC3_BUCKET_PASSWORD=
OPENC3_SR_BUCKET_USERNAME=
OPENC3_SR_BUCKET_PASSWORD=

AWS_REGION=us-east-1  # Replace with your AWS region
```

Leave `OPENC3_CLOUD=local`. COSMOS still uses its S3 client, and Traefik serves the tools from `OPENC3_BUCKET_URL`, so the only change is where that URL points.

The Network Configuration guide also adds `.env.local` entries (such as `OPENC3_EXTERNAL_URL`). Keep them all in the same `.env.local` file.

## Remove the Local Buckets Service

Since you're using AWS S3, the local `openc3-buckets` container is not needed.

Leave `compose.yaml` unchanged so future COSMOS updates merge cleanly. Instead, disable the service in `compose.override.yaml`, which `openc3.sh` merges on top of `compose.yaml` automatically. Putting `openc3-buckets` in a profile that is never activated keeps it from starting, and `!override` replaces each `depends_on` list with one that no longer includes `openc3-buckets`. Without the `depends_on` changes, Docker Compose fails with `depends on undefined service "openc3-buckets"`.

Add these entries under the top-level `services:` key (uncomment `services:` if it is still commented out):

```yaml
services:
  openc3-buckets:
    profiles: ["disabled"]
  openc3-cosmos-cmd-tlm-api:
    depends_on: !override
      - "openc3-redis"
      - "openc3-redis-ephemeral"
  openc3-cosmos-script-runner-api:
    depends_on: !override
      - "openc3-redis"
      - "openc3-redis-ephemeral"
  openc3-operator:
    depends_on: !override
      - "openc3-redis"
      - "openc3-redis-ephemeral"
  openc3-traefik:
    depends_on: !override
      - "openc3-redis"
      - "openc3-redis-ephemeral"
  openc3-cosmos-init:
    depends_on: !override
      - "openc3-traefik"
      - "openc3-redis"
      - "openc3-redis-ephemeral"
```

The [Network Configuration](/docs/guides/network-configuration) and [SSL-TLS](/docs/configuration/ssl-tls) guides also add `openc3-traefik` entries (`environment:`, `volumes:`, `ports:`). Merge them into the same service block rather than repeating the service name. These lists match the `depends_on` entries in `compose.yaml` minus `openc3-buckets`; if a future `compose.yaml` adds a dependency, add it here too.

## IAM Setup for S3 Access

### Create an IAM Policy (Optional but Recommended)

While you can use an existing AWS managed policy like `AmazonS3FullAccess`, creating a custom policy with minimum required permissions is a security best practice.

1. Go to the **IAM console** and select **Policies > Create policy**.
2. Use the **Visual editor** or the **JSON tab** to define your permissions.

   Replace `<OPENC3_CONFIG_BUCKET>`, `<OPENC3_LOGS_BUCKET>`, and `<OPENC3_TOOLS_BUCKET>` with the actual bucket names from your `.env.local` file:

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
         "Resource": [
           "arn:aws:s3:::<OPENC3_CONFIG_BUCKET>",
           "arn:aws:s3:::<OPENC3_LOGS_BUCKET>",
           "arn:aws:s3:::<OPENC3_TOOLS_BUCKET>"
         ]
       },
       {
         "Effect": "Allow",
         "Action": ["s3:PutBucketPolicy"],
         "Resource": ["arn:aws:s3:::<OPENC3_TOOLS_BUCKET>"]
       },
       {
         "Effect": "Allow",
         "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
         "Resource": [
           "arn:aws:s3:::<OPENC3_CONFIG_BUCKET>/*",
           "arn:aws:s3:::<OPENC3_LOGS_BUCKET>/*",
           "arn:aws:s3:::<OPENC3_TOOLS_BUCKET>/*"
         ]
       }
     ]
   }
   ```

3. Choose **Next**, enter a name for the policy, and choose **Create policy**.

### Create an IAM Role

1. In the **IAM console**, choose **Roles > Create role**.
2. For **Trusted entity type**, select **AWS service**.
3. For **Use case**, select **EC2** and then choose **Next**.
4. On the **Add permissions** page, search for and select the policy you created (or choose `AmazonS3FullAccess`). Choose **Next**.
5. Enter a **Role name** and an optional description, then choose **Create role**.

### Attach the IAM Role to Your EC2 Instance

1. Open the **Amazon EC2 console** and select **Instances** from the navigation pane.
2. Select the specific instance you want to grant access to.
3. Choose **Actions > Security > Modify IAM role**.
4. In the **Modify IAM role** page, select the new IAM role you created from the dropdown list.
5. Choose **Save**.

## Configure the Tools Bucket Policy

The tools bucket requires public read access so the COSMOS frontend can load tool assets. When COSMOS starts, the init container applies this policy itself using the `s3:PutBucketPolicy` permission above (unless `OPENC3_NO_BUCKET_POLICY` is set). If it can't, it logs a `put_bucket_policy` warning and continues, so apply the policy manually.

:::warning[S3 Block Public Access]
AWS enables Block Public Access on new buckets by default, which rejects public bucket policies. Turn off the **Block public access to buckets and objects granted through new public bucket or access point policies** settings on the tools bucket (only the tools bucket) or the policy cannot be applied. S3 enforces the most restrictive Block Public Access setting across the bucket, the AWS account, and (if used) AWS Organizations, so check **Block Public Access settings for this account** in the S3 console and any organization policies first. If those block public bucket policies, changing the bucket setting has no effect.
:::

To apply it manually, edit the **Bucket policy** for your tools bucket and paste the following, replacing `cosmos-tools` with your actual tools bucket name:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
      "Resource": "arn:aws:s3:::cosmos-tools"
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "AWS": "*"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::cosmos-tools/*"
    }
  ]
}
```

## Start COSMOS

Start COSMOS and configure Keycloak as described in [Start COSMOS](/docs/guides/network-configuration#start-cosmos) in the Network Configuration guide.

## Troubleshooting

See [Troubleshooting](/docs/guides/troubleshooting) and the [troubleshooting](/docs/getting-started/upgrading#troubleshooting) section of the upgrading guide.
