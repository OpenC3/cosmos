---
sidebar_position: 11
title: SSL-TLS
description: How to configure SSL and TLS
sidebar_custom_props:
  myEmoji: 🔐
---

COSMOS 5 is a container based service which does not use SSL/TLS out of the box. This guide will help you configure SSL and TLS. Learn more at the Traefik [docs](https://doc.traefik.io/traefik/routing/entrypoints/#tls).

### Generate the certificate

> Note: Self-signed certificates are considered insecure for the Internet. Firefox will treat the site as having an invalid certificate, while Chrome will act as if the connection was plain HTTP.

To create a new Self-Signed SSL Certificate, use the openssl req command (run on linux from the cosmos-project root):

```bash
openssl req -newkey rsa:4096 \
            -x509 \
            -sha256 \
            -days 3650 \
            -nodes \
            -out ./openc3-traefik/cert.crt \
            -keyout ./openc3-traefik/cert.key

Country Name (2 letter code) [XX]:.
State or Province Name (full name) []:.
Locality Name (eg, city) [Default City]:.
Organization Name (eg, company) [Default Company Ltd]:.
Organizational Unit Name (eg, section) []:.
Common Name (eg, your name or your server hostname) []: <!-- UPDATE WITH YOUR HOSTNAME HERE -->
Email Address []:
```

Let's breakdown the command and understand what each option means:

- `newkey rsa:4096` - Creates a new certificate request and 4096 bit RSA key. The default one is 2048 bits.
- `x509` - Creates a X.509 Certificate.
- `sha256` - Use 265-bit SHA (Secure Hash Algorithm).
- `days 3650` - The number of days to certify the certificate for. 3650 is ten years. You can use any positive integer.
- `nodes` - Creates a key without a passphrase.
- `out ./openc3-traefik/cert.crt` - Specifies the filename to write the newly created certificate to. You can specify any file name.
- `keyout ./openc3-traefik/cert.key` - Specifies the filename to write the newly created private key to. You can specify any file name.

For more information about the `openssl req` command options, visit the [OpenSSL req documentation page](https://www.openssl.org/docs/man1.0.2/man1/openssl-req.html).

### Updating the openc3-traefik Dockerfile

Add the new cert to the traefik Docker container.

```diff
--- a/openc3-traefik/Dockerfile
+++ b/openc3-traefik/Dockerfile
@@ -1,3 +1,4 @@
 FROM traefik:2.4
 COPY ./traefik.yaml /etc/traefik/traefik.yaml
+COPY ./cert.crt ./cert.key /etc/certs/
 EXPOSE 80
```

### Updating the Traefik config

Configure Traefik to use the new cert file.

openc3-traefik/traefik.yaml

```diff
--- a/openc3-traefik/traefik.yaml
+++ b/openc3-traefik/traefik.yaml
@@ -3,6 +3,17 @@
+tls:
+  certificates:
+   - certFile: "/etc/certs/cert.crt"
+     keyFile: "/etc/certs/cert.key"
# Listen for everything coming in on the standard HTTP port
entrypoints:
  web:
    address: ":2900"
+    http:
+      redirections:
+        entryPoint:
+          to: websecure
+          scheme: https
+  websecure:
+    address: ":2943"
+    http:
+      tls:
+        domains:
+          - main: "<!-- UPDATE WITH YOUR HOSTNAME HERE -->"
```

### Update docker-compose.yaml

Update traefik to use secure port 443 instead of port 80.

```diff
--- a/compose.yaml
+++ b/compose.yaml
 services:
   openc3-minio:
@@ -70,7 +70,7 @@ services:
   openc3-traefik:
     image: "ballaerospace/openc3-traefik:${OPENC3_TAG}"
     ports:
-      - "80:2900"
+      - "443:2943"
     restart: "unless-stopped"
     depends_on:
```

Now you can run `./openc3.sh start` to rebuild the Traefik container and it should include your new cert file.

## Let's Encrypt

#### KEY

privkey.pem is the "key" file

Sometimes it is named as cert.key or example.com.key.

#### CRT

fullchain.pem is your "crt" file.

Sometimes it is named as example.com.crt.

#### CRT/KEY Bundle

bundle.pem would be made like so: cat fullchain.pem privkey.pem > bundle.pem

HAProxy is the only server that I know of that uses bundle.pem.

#### cert.pem

cert.pem contains ONLY your certificate, which can only be used by itself if the browser already has the certificate which signed it, which may work in testing (which makes it seem like it may be the right file), but will actually fail for many of your users in production with a security error of untrusted certificate.

However, you don't generally use the cert.pem by itself. It's almost always coupled with chain.pem as fullchain.pem.

#### chain.pem

chain.pem is the intermediary signed authority, signed by the root authority - which is what all browsers are guaranteed to have in their pre-built cache.

### Checking certs

You can inspect the cert like so:

```
openssl x509 -in cert.pem -text -noout
```

## Extracting the certificate and keys from a .pfx file

The .pfx file, which is in a PKCS#12 format, contains the SSL certificate (public keys) and the corresponding private keys. You might have to import the certificate and private keys separately in an unencrypted plain text format to use it on another system. This topic provides instructions on how to convert the .pfx file to .crt and .key files.

### Extract .crt and .key files from .pfx file

> PREREQUISITE: Ensure OpenSSL is installed in the server that contains the SSL certificate.

1. Start OpenSSL from the OpenSSL\bin folder.

1. Open the command prompt and go to the folder that contains your .pfx file.

1. Run the following command to extract the private key:

```
openssl pkcs12 -in [yourfile.pfx] -nocerts -out [drlive.key]
```

You will be prompted to type the import password. Type the password that you used to protect your keypair when you created the .pfx file. You will be prompted again to provide a new password to protect the .key file that you are creating. Store the password to your key file in a secure place to avoid misuse.

1. Run the following command to extract the certificate:

```
openssl pkcs12 -in [yourfile.pfx] -clcerts -nokeys -out [drlive.crt]
```

1. Run the following command to decrypt the private key:

```
openssl rsa -in [drlive.key] -out [drlive-decrypted.key]
```

Type the password that you created to protect the private key file in the previous step.
The .crt file and the decrypted and encrypted .key files are available in the path, where you started OpenSSL.

### Convert .pfx file to .pem format

There might be instances where you might have to convert the .pfx file into .pem format. Run the following command to convert it into PEM format.

```
openssl rsa -in [keyfile-encrypted.key] -outform PEM -out [keyfile-encrypted-pem.key]
```

## TLS1.2 INADEQUATE_SECURITY Errors

- https://doc.traefik.io/traefik/https/tls/#cipher-suites
- https://pkg.go.dev/crypto/tls#pkg-constants

```yaml
tls:
  options:
    default:
      cipherSuites:
        - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
        - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
        - TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256
        - TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256
```
