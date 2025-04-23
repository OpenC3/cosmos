---
sidebar_position: 11
title: SSL-TLS
description: SSLとTLSの設定方法
sidebar_custom_props:
  myEmoji: 🔐
---

COSMOS 6はコンテナベースのサービスであり、標準ではSSL/TLSを使用していません。このガイドはSSLとTLSの設定方法を説明します。詳細はTraefikの[ドキュメント](https://doc.traefik.io/traefik/routing/entrypoints/#tls)で確認できます。

### 証明書の生成

> 注意: 自己署名証明書はインターネット上では安全でないと見なされます。Firefoxはサイトを無効な証明書として扱い、Chromeは接続がプレーンHTTPであるかのように動作します。

新しい自己署名SSL証明書を作成するには、openssl reqコマンドを使用します（cosmos-projectのルートからLinux上で実行）:

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
Common Name (eg, your name or your server hostname) []: <!-- ここであなたのホスト名を更新してください -->
Email Address []:
```

コマンドの内容と各オプションの意味を見てみましょう:

- `newkey rsa:4096` - 新しい証明書リクエストと4096ビットのRSA鍵を作成します。デフォルトは2048ビットです。
- `x509` - X.509証明書を作成します。
- `sha256` - 256ビットのSHA（セキュアハッシュアルゴリズム）を使用します。
- `days 3650` - 証明書の有効期間を日数で指定します。3650は10年です。任意の正の整数を使用できます。
- `nodes` - パスフレーズなしで鍵を作成します。
- `out ./openc3-traefik/cert.crt` - 新しく作成された証明書を書き込むファイル名を指定します。任意のファイル名を指定できます。
- `keyout ./openc3-traefik/cert.key` - 新しく作成された秘密鍵を書き込むファイル名を指定します。任意のファイル名を指定できます。

`openssl req`コマンドオプションの詳細については、[OpenSSL reqドキュメントページ](https://www.openssl.org/docs/man1.0.2/man1/openssl-req.html)を参照してください。

### openc3-traefik Dockerfileの更新

新しい証明書をtraefik Dockerコンテナに追加します。

```diff
--- a/openc3-traefik/Dockerfile
+++ b/openc3-traefik/Dockerfile
@@ -1,3 +1,4 @@
 FROM traefik:2.4
 COPY ./traefik.yaml /etc/traefik/traefik.yaml
+COPY ./cert.crt ./cert.key /etc/certs/
 EXPOSE 80
```

### Traefik設定の更新

新しい証明書ファイルを使用するようにTraefikを設定します。

openc3-traefik/traefik.yaml

```diff
--- a/openc3-traefik/traefik.yaml
+++ b/openc3-traefik/traefik.yaml
@@ -3,6 +3,17 @@
+tls:
+  certificates:
+   - certFile: "/etc/certs/cert.crt"
+     keyFile: "/etc/certs/cert.key"
# 標準HTTPポートで入ってくるすべてをリッスンする
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
+          - main: "<!-- ここであなたのホスト名を更新してください -->"
```

### docker-compose.yamlの更新

traefikがポート80の代わりにセキュアポート443を使用するように更新します。

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

これで`./openc3.sh start`を実行してTraefikコンテナを再ビルドすると、新しい証明書ファイルが含まれるはずです。

## 暗号化

#### KEY

privkey.pemは「キー」ファイルです。

時にはcert.keyやexample.com.keyとして名前が付けられることもあります。

#### CRT

fullchain.pemが「crt」ファイルです。

時にはexample.com.crtとして名前が付けられることもあります。

#### CRT/KEYバンドル

bundle.pemは次のように作成されます: cat fullchain.pem privkey.pem > bundle.pem

HAProxyはbundle.pemを使用する唯一のサーバーです。

#### cert.pem

cert.pemには証明書のみが含まれており、ブラウザがすでに署名した証明書を持っている場合にのみ単独で使用できます。これはテストでは機能するかもしれませんが（正しいファイルであるように見える）、実際には本番環境では多くのユーザーに対して信頼されていない証明書のセキュリティエラーで失敗します。

ただし、一般的にcert.pemを単独で使用することはありません。ほとんどの場合、chain.pemとfullchain.pemとして組み合わせて使用されます。

#### chain.pem

chain.pemは、ルート認証局によって署名された中間署名認証局です。これはすべてのブラウザが事前に構築されたキャッシュに持っていることが保証されているものです。

### 証明書の確認

次のように証明書を確認できます:

```
openssl x509 -in cert.pem -text -noout
```

## .pfxファイルから証明書と鍵を抽出する

PKCS#12形式の.pfxファイルには、SSL証明書（公開鍵）と対応する秘密鍵が含まれています。別のシステムで使用するために、証明書と秘密鍵を暗号化されていないプレーンテキスト形式で別々にインポートする必要がある場合があります。このトピックでは、.pfxファイルを.crtファイルと.keyファイルに変換する方法について説明します。

### .pfxファイルから.crtと.keyファイルを抽出する

> 前提条件: SSL証明書を含むサーバーにOpenSSLがインストールされていることを確認してください。

1. OpenSSL\binフォルダからOpenSSLを起動します。

1. コマンドプロンプトを開き、.pfxファイルが含まれているフォルダに移動します。

1. 次のコマンドを実行して秘密鍵を抽出します:

```
openssl pkcs12 -in [yourfile.pfx] -nocerts -out [drlive.key]
```

インポートパスワードの入力を求められます。.pfxファイルを作成した時にキーペアを保護するために使用したパスワードを入力してください。作成中の.keyファイルを保護するための新しいパスワードを提供するよう再度求められます。不正使用を避けるため、安全な場所にキーファイルのパスワードを保存してください。

1. 次のコマンドを実行して証明書を抽出します:

```
openssl pkcs12 -in [yourfile.pfx] -clcerts -nokeys -out [drlive.crt]
```

1. 次のコマンドを実行して秘密鍵を復号化します:

```
openssl rsa -in [drlive.key] -out [drlive-decrypted.key]
```

前のステップで秘密鍵ファイルを保護するために作成したパスワードを入力します。
.crtファイルと復号化および暗号化された.keyファイルは、OpenSSLを起動したパスで利用できます。

### .pfxファイルを.pem形式に変換する

.pfxファイルを.pem形式に変換する必要がある場合があります。次のコマンドを実行してPEM形式に変換します。

```
openssl rsa -in [keyfile-encrypted.key] -outform PEM -out [keyfile-encrypted-pem.key]
```

## TLS1.2 INADEQUATE_SECURITYエラー

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
