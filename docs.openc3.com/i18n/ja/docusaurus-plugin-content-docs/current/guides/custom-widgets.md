---
title: カスタムウィジェット
description: Telemetry Viewerで使用するカスタムウィジェットの構築方法
sidebar_custom_props:
  myEmoji: 🔨
---

COSMOSでは、[プラグイン](../configuration/plugins.md)と共にデプロイして[テレメトリビューア](../tools/tlm-viewer.md)で使用できるカスタムウィジェットを構築することができます。カスタムウィジェットの構築には任意のJavaScriptフレームワークを使用できますが、COSMOSはVue.jsで書かれているため、このチュートリアルではそのフレームワークを使用します。カスタムウィジェットの基本構造を生成する方法については、[ウィジェットジェネレーター](../getting-started/generators#ウィジェットジェネレーター)ガイドを参照してください。

## カスタムウィジェット

基本的にCOSMOSの[デモ](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo)に従って、そのカスタムウィジェットがどのように作成されたかを説明します。

デモの[plugin.txt](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/plugin.txt)ファイルの下部を見ると、ウィジェットを宣言しているのが分かります：

```ruby
WIDGET BIG
WIDGET HELLOWORLD
```

プラグインがデプロイされると、COSMOSはビルド済みのウィジェットを探します。BIGウィジェットの場合、`tools/widgets/BigWidget/BigWidget.umd.min.js`でウィジェットを探します。同様に、HELLOWORLDは`tools/widgets/HelloworldWidget/HelloworldWidget.umd.min.js`で探します。これらのディレクトリとファイル名は不思議に思えるかもしれませんが、それはウィジェットがどのようにビルドされるかに関係しています。

### Helloworldウィジェット

Helloworldウィジェットのソースコードはプラグインのsrcディレクトリにあり、[HelloworldWidget.vue](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/src/HelloworldWidget.vue)と呼ばれています。基本構造は次の通りです：

```vue
<template>
  <!-- ここにウィジェットを実装 -->
</template>

<script>
import { Widget } from "@openc3/vue-common/widgets";
export default {
  mixins: [Widget],
  data() {
    return {
      // リアクティブデータ項目
    };
  },
};
</script>
<style scoped>
/* ウィジェット固有のスタイル */
</style>
```

:::info Vue & Vuetify
COSMOSフロントエンド（すべてのウィジェットを含む）がどのように構築されているかについての詳細は、[Vue.js](https://vuejs.org)と[Vuetify](https://vuetifyjs.com)をご確認ください。
:::

このカスタムウィジェットをビルドするために、デモの[Rakefile](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/Rakefile)を変更して、プラグインがビルドされるときに`yarn run build`を呼び出すようにしました。`yarn run XXX`は[package.json](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/package.json)ファイル内で実行する「スクリプト」を探します。package.jsonを開くと、次のようになっています：

```json
  "scripts": {
    "build": "vue-cli-service build --target lib --dest tools/widgets/HelloworldWidget --formats umd-min src/HelloworldWidget.vue --name HelloworldWidget && vue-cli-service build --target lib --dest tools/widgets/BigWidget --formats umd-min src/BigWidget.vue --name BigWidget"
  },
```

これは`vue-cli-service`を使用して、`src/HelloworldWidget.vue`にあるコードをビルドし、`umd-min`形式でフォーマットして、`tools/widgets/HelloworldWidget`ディレクトリに配置します。そのため、プラグインは`tools/widgets/HelloworldWidget/HelloworldWidget.umd.min.js`でプラグインを探します。`vue-cli-service build`のドキュメントについては[こちら](https://cli.vuejs.org/guide/cli-service.html#vue-cli-service-build)をクリックしてください。

デモプラグインの[simple.txt](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST/screens/simple.txt)画面を見ると、ウィジェットを使用していることがわかります：

```ruby
SCREEN AUTO AUTO 0.5
LABELVALUE <%= target_name %> HEALTH_STATUS CCSDSSEQCNT
HELLOWORLD
BIG <%= target_name %> HEALTH_STATUS TEMP1
```

テレメトリビューアでこの画面を開くと、次のようになります：

![シンプル画面](/img/guides/simple_screen.png)

これは単純な例ですが、カスタムウィジェットの可能性は無限大です！