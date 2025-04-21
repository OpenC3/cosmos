---
title: Raspberry Pi
description: Raspberry PiでCOSMOSを実行する
sidebar_custom_props:
  myEmoji: 🍓
---

### Raspberry Pi 4でCOSMOSを実行する

Raspberry Pi 4は、Linuxを実行する低コストで強力なARMベースのミニコンピュータです。そして、最新のLinuxを実行するため、COSMOSも実行できます！以下の手順で、セットアップと実行方法を説明します。

必要なもの：

- Raspberry Pi 4ボード（8GB RAMでテスト済み）
- Piケース（オプション）
- Raspberry Pi電源アダプタ
- 32GB以上のSDカード - 速いものほど良い
- SDカードに書き込み可能なノートパソコン

それでは始めましょう！

1. SDカードに64-bit Raspbian OS Liteをセットアップする

   https://www.raspberrypi.com/software/ からRaspberry Pi Imagerアプリを入手していることを確認してください

   1. SDカードをコンピュータに挿入します（注意：この処理によりSDカード上のすべてのデータが消去されます！）
   1. Raspberry Pi Imagerアプリを開きます
   1. 「Choose Device」ボタンをクリックします
   1. お使いのRaspberry Piモデルを選択します
   1. 「Choose OS」ボタンをクリックします
   1. 「Raspberry Pi OS (other)」を選択します
   1. 「Raspberry Pi OS Lite (64-bit)」を選択します
   1. 「Choose Storage」ボタンをクリックします
   1. SDカードを選択します
   1. Edit Settings（設定を編集）をクリックします
   1. Wi-Fi情報を事前に入力するかどうか尋ねられたら、OKを選択します
   1. ホスト名を cosmos.local に設定します
   1. ユーザー名とパスワードを設定します。デフォルトのユーザー名はあなたのユーザー名ですが、システムを安全にするためにパスワードも設定する必要があります
   1. Wi-Fi情報を入力し、国を適切に設定します（例：JP）
   1. 正しいタイムゾーンを設定します
   1. サービスタブに移動し、SSHを有効にします
   1. パスワード認証を使用するか、コンピュータがすでにパスワードなしSSH用に設定されている場合は公開鍵のみを使用できます
   1. オプションタブに移動し、「Enable Telemetry」（テレメトリを有効にする）がチェックされていないことを確認します
   1. すべて入力したら「Save」（保存）をクリックします
   1. OS カスタマイズ設定を適用するために「Yes」をクリックし、「Are You Sure」（本当によろしいですか）に「Yes」と答え、完了するまで待ちます

1. Raspberry Piの電源が入っていないことを確認します

1. SDカードをコンピュータから取り出し、Raspberry Piに挿入します

1. Raspberry Piに電源を供給し、起動するまで約1分待ちます

1. Raspberry PiにSSH接続します

   1. ターミナルウィンドウを開き、SSHを使用してPiに接続します

      1. Mac / Linux: ssh yourusername@cosmos.local
      1. Windowsでは、Puttyを使用して接続します。.localアドレスを機能させるには、Windows用のBonjourをインストールする必要がある場合があります。

1. SSHから、以下のコマンドを入力します

```bash
   sudo sysctl -w vm.max_map_count=262144
   sudo sysctl -w vm.overcommit_memory=1
   sudo apt update
   sudo apt upgrade
   sudo apt install git -y
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo usermod -aG docker $USER
   newgrp docker
   git clone https://github.com/OpenC3/cosmos-project.git cosmos
   cd cosmos
   # compose.yamlを編集し、openc3-traefikサービスのportsセクションから127.0.0.1:を削除します
   ./openc3.sh run
```

1. 約2分後、コンピュータでウェブブラウザを開き、http://cosmos.local:2900 にアクセスします

1. おめでとうございます！これでRaspberry PiでCOSMOSが実行されています！