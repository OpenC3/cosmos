---
sidebar_position: 4
title: アップグレード
description: COSMOSのアップグレードと移行方法
sidebar_custom_props:
  myEmoji: ⬆️
---

## COSMOSのアップグレード

COSMOSはDockerコンテナとしてリリースされています。Dockerコンテナとボリュームを使用しているため、既存のCOSMOSアプリケーションを停止し、新しいリリースをダウンロードして実行するだけでアップグレードが完了します。

:::info リリースノート
常に[リリース](https://github.com/OpenC3/cosmos/releases)ページにあるリリースに関連するリリースノートを確認してください。移行に関する注意事項が含まれている場合があります。
:::

この例では、C:\cosmos-projectに既存のCOSMOSプロジェクトがあることを前提としています。

1. 現在のCOSMOSアプリケーションを停止します

   ```batch
   C:\cosmos-project> openc3.bat stop
   ```

1. .envファイル内のリリースを希望のリリースに変更します

   ```batch
   OPENC3_TAG=5.1.1
   ```

1. 新しいCOSMOSアプリケーションを実行します

   ```batch
   C:\cosmos-project> openc3.bat run
   ```

:::warning ダウングレード
ダウングレードは必ずしもサポートされていません。COSMOSをアップグレードする際には、データベースをアップグレードし、内部データ構造を移行する必要があることがあります。すべてのリリースで完全な回帰テストを実施していますが、特定のプラグインを使用して個別のマシンをアップグレードし、本番システムへのアップグレードを展開する前にローカルでテストすることをお勧めします。

一般的に、パッチリリース(x.y.Z)はダウングレード可能ですが、マイナーリリース(x.Y.z)は_場合によってダウングレード可能かもしれません。メジャーリリース(X.y.z)はダウングレードすることはできません。
:::

## COSMOS 5からCOSMOS 6への移行

:::info 開発者向け
カスタムツールやウィジェットを作成していない場合、COSMOS 5からCOSMOS 6へのアップグレードに特別な変更は必要ありません。上記の通常のアップグレード手順に従い、リリースノートに従ってください。
:::

COSMOS 6は、Vueフレームワークと共通ライブラリコードに関するカスタムツールに互換性のない変更をいくつか導入しています。Vue 2（2023年12月31日にEOL）からVue 3にアップグレードしました。これらのVueバージョンは互いに互換性がないため、Vue 2で書かれたツールはすべて更新する必要があります。さらに、`@openc3/tool-common` NPMパッケージは非推奨となり、その機能は`@openc3/js-common`と`@openc3/vue-common`の2つのパッケージに再編成されました。これにより、Vueフレームワークを使用せずにCOSMOSツールを構築する開発者により良い体験を提供します。

また、COSMOS 6ではほとんど使用されていなかった[APIメソッド](../guides/scripting-api#migration-from-cosmos-v5-to-v6)をいくつか削除しました。

### Vueの更新

_ツールがVueで構築されていない場合（例：フロントエンドフレームワークなしで構築された、またはReact、Angularなどで構築された場合）、このセクションはスキップできます。_

#### 簡易的な方法

比較的シンプルなツールであれば、依存関係を更新して発生するビルドエラーを修正し、ツールのテストと使用から見つかったランタイムエラーを修正するだけで、一度にアップグレードできる可能性があります。このアップグレード方法に自信がある場合は、[このプルリクエスト](https://github.com/OpenC3/cosmos/pull/1747)を参照して、何を変更する必要があるかを確認できます。それ以外の場合は、このガイドの残りの部分で、より詳細で完全な移行プロセスを説明します。

#### ステップ1：Vue互換モード

VueチームはVue 2からVue 3への移行を支援するための互換モードを提供しています。これによりツールを起動して実行でき、必要な変更を見つけやすくなります。

##### (1.a) 依存関係の更新

パッケージマネージャーを使用するか、package.jsonファイルを編集して、次の依存関係を更新します（使用していない「Update」とマークされたパッケージは無視してください）

- **削除:** `vue-template-compiler`
- **追加:** `@vue/compat` >= 3.5 ([npmjs.com](https://www.npmjs.com/package/@vue/compat))
- **追加:** `@vue/compiler-sfc` >= 3.5 ([npmjs.com](https://www.npmjs.com/package/@vue/compiler-sfc))
- **更新:** `@vue/test-utils` >= 2.4 ([npmjs.com](https://www.npmjs.com/package/@vue/compiler-sfc))
- **更新:** `vue` >= 3.5 ([npmjs.com](https://www.npmjs.com/package/vue))
- **更新:** `vuex` >= 4.1 ([npmjs.com](https://www.npmjs.com/package/vuex))
- **更新:** `vue-router` >= 4.4 ([npmjs.com](https://www.npmjs.com/package/vue-router))
- **更新:** `vuetify` >= 3.7 ([npmjs.com](https://www.npmjs.com/package/vuetify))
- **更新:** `single-spa-vue` >= 3.0 ([npmjs.com](https://www.npmjs.com/package/single-spa-vue))

Eslintは移行のためにコードに必要な変更を指摘するのに役立つため、まだプロジェクトに含まれていない場合は、eslintを含めることをお勧めします。その方法を説明するオンラインガイドはたくさんあります。eslintを使用している場合は、ツールの依存関係に次の追加変更を行います：

- **追加:** `eslint-plugin-vuetify` >= 2.5 ([npmjs.com](https://www.npmjs.com/package/eslint-plugin-vuetify))
- **追加:** `vue-eslint-parser` >= 9.4 ([npmjs.com](https://www.npmjs.com/package/vue-eslint-parser))

package.jsonファイルを手動で変更した場合は、プロジェクトのルートで`yarn`または`npm install`を実行して変更を適用することを忘れないでください。

##### (1.b) Vue構成ファイル(`vue.config.js`)の更新

このファイルからエクスポートされるオブジェクトに、次のような`chainWebpack`プロパティがある可能性があります（内容は異なる場合があります）

```js
chainWebpack: (config) => {
  config.module
    .rule('vue')
    .use('vue-loader')
    .tap((options) => {
      return {
        prettify: false,
      }
    })
},
```

このブロックの最上部に`@vue/compat`の解決エイリアスを追加し、コンパイラがVue 2互換モードを使用するように設定します：

```js
chainWebpack: (config) => {
  config.resolve.alias.set('vue', '@vue/compat') // この行を追加
  config.module
    .rule('vue')
    .use('vue-loader')
    .tap((options) => {
      return {
        prettify: false,
        compilerOptions: { // このブロックを
          compatConfig: {  // 追加
            MODE: 2,       //
          },               //
        },                 // ここまで
      }
    })
},
```

##### (1.c) eslint構成ファイル(`.eslintrc`)の更新

`extends`ブロックに`'plugin:vue/essential'`を見つけて、`'plugin:vue/vue3-essential'`に変更します。そのプラグインが`extends`ブロックにない場合、またはブロック全体が欠けている場合は、これを追加します。VueのAPIの使用方法に関する互換性のない変更を見つけるのに役立ちます。

```js
extends: [
  'plugin:vue/vue3-essential', // plugin:vue/essentialから変更
  'plugin:prettier/recommended',
  '@vue/prettier',
],
```

##### (1.d) ビルドおよびランタイムの警告とエラーの修正

リントとビルドスクリプトを実行します（例：`yarn lint`および`yarn build`）。eslintプラグインとVueの互換モードにより、対処する必要があるコード変更の最初のセットが見つかります。プロジェクトが正常にビルドされるまで、これらのlint/ビルドエラーを修正します。

ビルドが完了したら、通常の開発時と同様にプロジェクトを実行します。`yarn serve`でローカル開発サーバーから提供し、ブラウザのインポートマップオーバーライドに追加することをお勧めします。ツールの機能をテストし、ブラウザコンソールに表示されるVueのエラーと警告に対処します。_（注意：`MODE: 2`-このセクションの最初は、ツールが完全に動作しなくても問題ありません。ブラウザコンソールに記録される警告とエラーに対処するだけです。次のステップでツールを完全に動作させます。）_

COSMOSのファーストパーティツールを移行した経験から、最低でも`main.js`と`router.js`ファイルを変更する必要がある可能性が高いです。上記の「簡易的な方法」セクションで言及したPRを参照して変更内容を確認するか、Vue 2 -> Vue 3移行ガイドをインターネットで検索して、警告やエラーに対処するための助けを得ることができます。

#### ステップ2：互換モードを2から3に変える

vue構成ファイル（`vue.config.js`）に追加した`compatConfig`を`MODE: 2`から`MODE: 3`に変更します。これにより、前のステップで変更に対処したことをVueの互換モードに伝え、次の問題セットを見つけます（これは複数ステップのプロセスであるため）。「(1.d) ビルドおよびランタイムの警告とエラーの修正」ステップを繰り返します。

#### ステップ3：Vuetifyの更新

_Vuetifyを使用していない場合は、このステップをスキップできます。_

eslint構成（`.eslintrc`）を再度変更してVuetifyプラグインを追加します：

```js
extends: [
  'plugin:vue/vue3-essential',
  'plugin:vuetify/base', // この行を追加
  'plugin:prettier/recommended',
  '@vue/prettier',
],
```

**注意：** Vuetify eslintプラグインはVuetify 2からVuetify 3へのプロジェクト移行用に設計されており、リントのパフォーマンスに問題を引き起こす可能性があるため、ツールの移行が完了したら削除する必要があります。

`.eslintrc`で再度、`parserOptions`ブロックを見つけて、その上に`parser`プロパティを追加します：

```js
parser: 'vue-eslint-parser', // この行を追加
parserOptions: {
  ...
},
```

これで、eslintを実行すると、コードがVuetify APIをどのように使用しているかに関して対処する必要がある変更について教えてくれます。これらの変更を見つけるには、Vueファイルでeslintを実行します（例：`yarn eslint . --ext .vue`）。これらを手動で対処することもできますし、eslintを信頼しているか、優れたバージョン管理を行っている場合は、プラグインに自動的に修正させることができます（`yarn eslint . --ext .vue --fix`）。

最後に、COSMOSからVuetifyを介してAstro UXDSアイコンを使用している場合—または他のカスタムアイコンパックを使用している場合—パックエイリアス形式を`$packName-`から`packName:`に変更する必要があります。`antenna-transmit` Astroアイコンの例を示します：

```html
<!-- Vue 2 / Vuetify 2 (古い) -->
<v-icon> $astro-antenna-transmit </v-icon>

<!-- Vue 3 / Vuetify 3 (新しい) -->
<v-icon> astro:antenna-transmit </v-icon>
```

#### ステップ4：クリーンアップ

- ステップ1.aで追加した`@vue/compat`と`eslint-plugin-vuetify`の依存関係を削除します
- ステップ1.bで追加した`compatConfig`を削除します
- ステップ3で追加した`'plugin:vuetify/base'`を削除します

### 新しいOpenC3共通パッケージへの移行

このガイドの最初の段落で述べたように、`@openc3/tool-common` NPMパッケージは非推奨になりました。その機能はすべて同じままですが、すべてが異なる方法で整理されているため、依存関係とインポートを更新する必要があります。

#### ステップ1：依存関係の更新

パッケージマネージャーを使用するか、package.jsonファイルを編集して、次の依存関係を更新します

- **削除:** `@openc3/tool-common`
- **追加:** `@openc3/js-common` >= 6.0 ([npmjs.com](https://www.npmjs.com/package/@openc3/js-common))
- **追加:** `@openc3/vue-common` >= 6.0 ([npmjs.com](https://www.npmjs.com/package/@openc3/vue-common))
  - これは、当社のVue関連のもの（コンポーネント、プラグインなど）を使用している場合にのみ必要です

#### ステップ2：コード内のインポートの更新

COSMOS 5では、`@openc3/tool-common`の`src`ディレクトリから直接インポートしてビルドプロセスでツールに組み込んでいました。COSMOS 6では、すべてが新しい共通パッケージでいくつかのトップレベルエクスポートを通じてエクスポートされています。一般的なパターンは次のとおりです：

- COSMOS 5: `import bar from '@openc3/tool-common/src/foo/bar'`
- COSMOS 6: `import { bar } from '@openc3/vue-common/foo'`

このパターンにより、複数のインポートステートメントを1つにまとめることもできます（例：`import { bar, baz } from '@openc3/vue-common/foo'`）。

このパターンには3つの例外があります：

- ウィジェットは`components`ディレクトリ配下ではなく、独自のトップレベルエクスポートを取得します
  - 古い: `import foo from '@openc3/tool-common/src/components/widgets/Foo`
  - 新しい: `import { foo } from '@openc3/vue-common/widgets`
- アイコンも同様の扱いになりました
  - 古い: `import bar from '@openc3/tool-common/src/components/icons/Bar`
  - 新しい: `import { bar } from '@openc3/vue-common/icons`
- `TimeFilters`ミックスインは`tools/base`から`util`に移動されました
  - 古い: `import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters`
  - 新しい: `import { TimeFilters } from '@openc3/vue-common/util`

#### `@openc3/js-common`

このパッケージには、以前は`@openc3/tool-common/src/services`にあったものが含まれています。そのパス以外のものは、以下で説明する`vue-common`パッケージに含まれています。

そのパスからのインポートを適宜更新します。例：

```js
// COSMOS 5 (古い)
import Api from "@openc3/tool-common/src/services/api";
import Cable from "@openc3/tool-common/src/services/cable";
import { OpenC3Api } from "@openc3/tool-common/src/services/openc3Api";

// COSMOS 6 (新しい)
import { Api, Cable, OpenC3Api } from "@openc3/js-common/services";
```

このパッケージは、おそらく必要ないかもしれませんが、役立つかもしれないいくつかのトップレベルインポートも提供しています：

- `import { prependBasePath } from '@openc3/js-common/utils` はVue Routerの`route`オブジェクトとその下にベースパス（例：localhost:2900）を前置する関数を提供します。これは、完全なパスが必要なsingle-spaとvue-router 4のルーティングロジックの特定の問題に遭遇した場合に役立ちます。使用方法は[こちら](https://github.com/OpenC3/cosmos/blob/f0193f4146e28e1cd383732763a9d27d84b5ca71/openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-cmdtlmserver/src/router.js#L76)で確認できます。

- `import { devServerPlugin } from '@openc3/js-common/viteDevServerPlugin`。このViteプラグインは、webpack/vue-cliから移行する際にツール用のローカル開発サーバーを実行するための一時的なハックです。Viteの組み込み`vite dev`開発サーバーに置き換えるべきですが、少なくとも当社のファーストパーティCOSMOSツールでは現在動作していません。使用方法は[こちら](https://github.com/OpenC3/cosmos/blob/f0193f4146e28e1cd383732763a9d27d84b5ca71/openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-cmdtlmserver/vite.config.js#L37)で確認できます。

#### `@openc3/vue-common`

このパッケージには、ファーストパーティツールの構築に使用するすべての共有Vueコンポーネントが提供されています。主なトップレベルエクスポートは`components`、`icons`、`plugins`、`util`、および`widgets`です。COSMOS Enterpriseとのコード共有のために構築したツール固有のエクスポートもあります：`tool/base`、`tool/admin`、および`tool/calendar`。以下は例ですが、上記で言及したパターンを参照してください。

```js
// COSMOS 5 (古い)
import DetailsDialog from "@openc3/tool-common/src/components/DetailsDialog";
import Graph from "@openc3/tool-common/src/components/Graph";
import Notify from "@openc3/tool-common/src/plugins/notify";
import TimeFilters from "@openc3/tool-common/src/tools/base/util/timeFilters";
import VWidget from "@openc3/tool-common/src/components/widgets/VWidget";

// COSMOS 6 (新しい)
import { DetailsDialog, Graph } from "@openc3/vue-common/components";
import { Notify } from "@openc3/vue-common/plugins";
import { TimeFilters } from "@openc3/vue-common/util";
import { VWidget } from "@openc3/vue-common/widgets";
```

## COSMOS 4からCOSMOS 5への移行

:::info すべてのCOSMOSユーザー
すべてのCOSMOS 4ユーザーは構成を5にアップグレードする必要があります。ただし、コマンド、テレメトリ、画面定義（キーワードと構文）は同じままです。
:::

COSMOS 5は新しいアーキテクチャであり、ターゲットを独立した[プラグイン](../configuration/plugins.md)として扱います。したがって、COSMOS 4からCOSMOS 5への移行における主な作業は、ターゲットをプラグインに変換することです。独立したターゲット（独自のインターフェースを持つ）ごとにプラグインを作成することをお勧めしますが、インターフェースを共有するターゲットは同じプラグインの一部である必要があります。独立したプラグインを推奨する理由は、プラグインを個別にバージョン管理でき、特定のプロジェクト外で共有しやすくなるためです。プロジェクト固有のターゲット（カスタムハードウェアなど）がある場合は、デプロイを容易にするために潜在的に組み合わせることができます。

### 構成移行ツール

COSMOS 5（COSMOS 6ではなく）には、既存のCOSMOS 4構成をCOSMOS 5プラグインに変換するための移行ツールが含まれています。この例では、C:\COSMOSに既存のCOSMOS 4構成があり、C:\cosmos-projectに新しいCOSMOS 5インストールがあることを前提としています。Linuxユーザーはパスを調整し、.batを.shに変更して同様に実行できます。

1. 既存のCOSMOS 4構成ディレクトリに移動します。config、lib、procedures、outputsディレクトリが表示されるはずです。次に、COSMOS 5インストールの絶対パスを指定して移行ツールを実行できます。

   ```batch
   C:\COSMOS> C:\cosmos-project\openc3.bat cli migrate -a demo
   ```

   これにより、既存のlibとproceduresファイルと既存のすべてのターゲットを含むDEMOという名前のターゲットを持つopenc3-cosmos-demoという新しいCOSMOS 5プラグインが作成されます。

   ```batch
   C:\COSMOS> C:\cosmos-project\openc3.bat cli migrate demo-part INST
   ```

   これにより、既存のlibとproceduresファイル、およびINSTターゲット（他のターゲットは含まない）を含むDEMO_PARTという名前のターゲットを持つopenc3-cosmos-demo-partという新しいCOSMOS 5プラグインが作成されます。

1. 新しいCOSMOS 5プラグインを開き、[plugin.txt](../configuration/plugins.md#plugintxt-configuration-file)ファイルが正しく構成されていることを確認します。移行ツールはVARIABLEsやMICROSERVICEsを作成せず、ターゲット置換も処理しないため、これらの機能は手動で追加する必要があります。

1. [プラグインの構築](gettingstarted.md#building-your-plugin)の「はじめに」チュートリアルの部分に従って、新しいプラグインを構築し、COSMOS 5にアップロードしてください。

### カスタムツールのアップグレード

COSMOS 4はQtデスクトップベースのアプリケーションでした。COSMOS 5は完全に新しいアーキテクチャで、JavascriptフレームワークとしてVue.jsを、GUIライブラリとしてVuetifyを使用して、ブラウザでネイティブに実行されます。single-spaを利用して、任意の言語でCOSMOSツールプラグインを作成できるようにし、Vue.js（推奨）、Angular、React、Svelteの[テンプレート](https://github.com/OpenC3/cosmos/tree/main/openc3/templates)を提供しています。COSMOS 4のカスタムツールはCOSMOS 5で実行するために完全に書き直す必要があります。ネイティブのCOSMOS [ツール](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages)を使用し、再作成しようとしているツールに最も一致するGUIの概念と機能を見つけることをお勧めします。

カスタム開発が必要な場合は、sales@openc3.comまでお問い合わせください。