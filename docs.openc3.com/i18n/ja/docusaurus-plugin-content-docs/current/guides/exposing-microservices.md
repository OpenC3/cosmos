---
title: マイクロサービスの公開
description: マイクロサービスへの外部アクセシビリティを提供する
sidebar_custom_props:
  myEmoji: 🚪
---

COSMOSは、新しいAPIを追加し、カスタムマイクロサービスとインターフェースをネットワークからアクセス可能にするシンプルな方法を提供します。

:::warning 公開するものがセキュアであることを確認してください

公開する新しいAPIがユーザー認証情報をチェックし、アクションを適切に認可することを確認してください。
:::

## PORTとROUTE_PREFIXキーワードを使用してマイクロサービスを公開する

plugin.txtファイルでは、[INTERFACE](../configuration/plugins#interface-1)と[MICROSERVICE](../configuration/plugins#microservice-1)の両方が[PORT](../configuration/plugins#port-1)と[ROUTE_PREFIX](../configuration/plugins#route_prefix-1)キーワードをサポートしています。

[PORT](../configuration/plugins#port-1)は、マイクロサービスが接続をリッスンしているポートを宣言するために使用されます。これは[ROUTE_PREFIX](../configuration/plugins#route_prefix-1)と組み合わせて、マイクロサービスへの動的なtraefikルートを作成するために使用されます。

以下のコードは、traefikがマイクロサービスに内部で接続する場所を知らせるために内部的に使用されます：

```ruby
if ENV['OPENC3_OPERATOR_HOSTNAME']
  url = "http://#{ENV['OPENC3_OPERATOR_HOSTNAME']}:#{port}"
else
  if ENV['KUBERNETES_SERVICE_HOST']
    url = "http://#{microservice_name.downcase.gsub('__', '-').gsub('_', '-')}-service:#{port}"
  else
    url = "http://openc3-operator:#{port}"
  end
end
```

これはマイクロサービスへの内部ルートであることに注意してください。このルートを決定するには、2つの異なる環境変数をチェックします。

OPENC3_OPERATOR_HOSTNAMEは、通常のdocker composeオペレータの「openc3-operator」のデフォルトサービス名を上書きするために使用されます。通常、これは設定されていません。

OpenC3 Enterpriseでは、KUBERNETES_SERVICE_HOSTはKubernetes環境で実行されているかどうかを検出するために使用されます（Kubernetesによって設定されます）。その場合、サービスはscope-user-microservicename-serviceという名前のKubernetesサービスを持つことが期待されます。例えば、DEFAULTスコープを使用していて、MYMICROSERVICEという名前のマイクロサービスがある場合、サービスはdefault-user-mymicroservice-serviceというホスト名で見つかります。二重アンダースコアまたは単一アンダースコアはダッシュに置き換えられ、名前はすべて小文字になります。

[ROUTE_PREFIX](../configuration/plugins#route_prefix-1)は外部ルートを定義するために使用されます。外部ルートはhttp(s)://YOURCOSMOSDOMAIN:PORT/ROUTE_PREFIXという形式になります。例えば、[ROUTE_PREFIX](../configuration/plugins#route_prefix-1)を/mymicroserviceに設定した場合、デフォルトのローカルインストールでは`http://localhost:2900/mymicroservice`でアクセスできます。`http://localhost:2900`の部分は、COSMOSにアクセスしているドメインで置き換える必要があります。

以下は、plugin.txtファイル内で[PORT](../configuration/plugins#port-1)と[ROUTE_PREFIX](../configuration/plugins#route_prefix-1)を使用している例です：

```bash
VARIABLE cfdp_microservice_name CFDP
VARIABLE cfdp_route_prefix /cfdp
VARIABLE cfdp_port 2905

MICROSERVICE CFDP <%= cfdp_microservice_name %>
  WORK_DIR .
  ROUTE_PREFIX <%= cfdp_route_prefix %>
  PORT <%= cfdp_port %>
```

変数をデフォルト値のままにすると、以下のようになります：

- マイクロサービスはDocker（オープンソースまたはエンタープライズ）に内部的に`http://openc3-operator:2905`で公開されます
- マイクロサービスはKubernetes（エンタープライズ）に内部的に`http://default-user-cfdp-service:2905`で公開されます
- マイクロサービスはネットワークに外部的に`http://localhost:2900/cfdp`で公開されます

同様のことが[INTERFACE](../configuration/plugins#interface-1)でも可能ですが、Kubernetesサービス名は`SCOPE__INTERFACE__INTERFACENAME`の形式をとるインターフェースのマイクロサービス名を使用することに注意してください。

以下は、[INTERFACE](../configuration/plugins#interface-1)で[PORT](../configuration/plugins#port)と[ROUTE_PREFIX](../configuration/plugins#route_prefix)を使用する例です：

```bash
VARIABLE my_interface_name MY_INT
VARIABLE my_route_prefix /myint
VARIABLE my_port 2910

INTERFACE <%= my_interface_name %> http_server_interface.rb <%= my_port %>
  ROUTE_PREFIX <%= my_route_prefix %>
  PORT <%= my_port %>
```

- インターフェースはDocker（オープンソースまたはエンタープライズ）に内部的に`http://openc3-operator:2910`で公開されます
- インターフェースはKubernetes（エンタープライズ）に内部的に`http://default-interface-my-int-service:2905`で公開されます
- インターフェースはネットワークに外部的に`http://localhost:2900/myint`で公開されます

:::warning Kubernetesでのシャーディングされたオペレータ（Enterprise）

シャーディングされたオペレータは、Kubernetesオペレータが使用されていない場合にKubernetesで使用されることが期待されています。通常、これはユーザーがKubernetes APIを直接使用してコンテナを起動する権限がないためです（これはKubernetesオペレータを使用するために必要です）。この場合、Kubernetesサービスは自動的に作成されず、Kubernetesでの権限を持つユーザーによって手動で作成されるか、他の承認された方法（カスタムフレームワークダッシュボードや設定ファイルなど）を通じて作成する必要があります。
:::

## plugin.txtの異なるINTERFACEからマイクロサービスに接続する

時には、実行しているマイクロサービスにINTERFACEを接続したい場合があります。この場合、内部的に接続するだけでROUTE_PREFIXは使用されないため、INTERFACEまたはMICROSERVICEにはPORTキーワードのみが必要です。

デモプラグインから取得した以下のコードは、plugin.txtファイル内でオープンソースとエンタープライズの両方のCOSMOSバージョンで正しいホスト名を計算する方法の例を提供しています：

```
  <% example_host = ENV['KUBERNETES_SERVICE_HOST'] ? "#{scope}-user-#{example_microservice_name.downcase.gsub('__', '-').gsub('_', '-')}-service" : "openc3-operator" %>
  INTERFACE <%= example_int_name %> example_interface.rb <%= example_host %> <%= example_port %>
    MAP_TARGET <%= example_target_name %>
```

上記のコードはOPENC3_OPERATOR_HOSTNAME環境変数を処理していないことに注意してください。これはopenc3-operatorのデフォルト名を変更する可能性があります。必要に応じて更新してください。