---
sidebar_position: 4
title: Upgrading
description: How to upgrade and migrate COSMOS
sidebar_custom_props:
  myEmoji: ⬆️
---

## COSMOS Upgrades

OpenC3 releases new versions of COSMOS on a monthy or better cadence. This is done for several reasons: to incorporate new features, fix existing bugs, update dependencies, and close CVEs. We extensively test each release at both the unit level, API level, and system level using Playwright against a deployed COSMOS. Thus we recommend upgrading COSMOS as quickly as possible when new releases become available. While COSMOS itself is tested extensively, we obviously can not test against customer plugins and custom deployments. We recommend having another installation of COSMOS which you can upgrade with your own plugins and verify functionality before upgrading your production environment.

COSMOS is released as Docker containers. Since we're using Docker containers and volumes we can simply stop the existing COSMOS application, then download and run the new release.

:::info Release Notes
Always check the release notes associated with the release on the [releases](https://github.com/OpenC3/cosmos/releases) page. Sometimes there are migration notes.
:::

This example assumes an existing COSMOS project at C:\cosmos-project.

1. Stop the current COSMOS application

   ```batch
   C:\cosmos-project> openc3.bat stop
   ```

1. Change the release in the .env file to the desired release

   ```batch
   OPENC3_TAG=6.4.1
   ```

1. Run the new COSMOS application

   ```batch
   C:\cosmos-project> openc3.bat run
   ```

### Upgrade Migration Process

COSMOS doesn't use strict [semantic versioning](https://semver.org/) for our releases. Our major releases (5.0.0, 6.0.0, etc) are for major architectural changes and backward incompatibilities. Minor releases (6.1.0, 6.2.0, etc) add functionality but can also modify our configuration files. Thus certain minor releases are more important than others when skiping releases.

The following table identifies key release milestones which should be incrementally upgraded to by following the linked release notes. Versions not listed can be safely skipped while upgrading. For example, upgrading COSMOS 5.9.0 can go straight to 5.13.0 at which point the release notes should be carefully followed to avoid breaking changes.

| Version                                                         | Summary                                                                                                                                                                                                     |
| :-------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [5.13.0](https://github.com/OpenC3/cosmos/releases/tag/v5.13.0) | Breaking change to non-root containers and renamed minio volume. Requires running the migration script and updating compose.yaml and traefik configuration.                                                 |
| [5.15.0](https://github.com/OpenC3/cosmos/releases/tag/v5.15.0) | The internal Traefik port was changed to 2900 to match our standard external port and to better support unprivileged runtime environments. Requires updating .env, compose.yaml, and traefik configuration. |
| [6.0.0](https://github.com/OpenC3/cosmos/releases/tag/v6.0.0)   | May require no changes but follow the [COSMOS 6 migration guide](upgrading#migrating-from-cosmos-5-to-cosmos-6) for custom GUI tools.                                                                       |
| [6.1.0](https://github.com/OpenC3/cosmos/releases/tag/v6.1.0)   | Changed from ActionCable to AnyCable which requires updates to compose.yaml, redis.acl, and traefik configuration. We also broke apart the COSMOS helm charts from a single chart to 3 charts.              |

:::warning Downgrades
Downgrades are not necessarily supported. When upgrading COSMOS we need to upgrade databases and sometimes migrate internal data structures. While we perform a full regression test on every release, we recommend upgrading an individual machine with your specific plugins and do local testing before rolling out the upgrade to your production system.

In general, patch releases (x.y.Z) can be downgraded, minor releases (x.Y.z) _might_ be able to be downgraded and major releases (X.y.z) are NOT able to be downgraded.
:::

## Migrating From COSMOS 5 to COSMOS 6

:::info Developers Only
If you haven't written any custom tools or widgets, there are no special changes required to upgrade from COSMOS 5 to COSMOS 6. Simply follow the normal upgrade instructions above including following the release notes.
:::

COSMOS 6 introduces some breaking changes for custom tools regarding the Vue framework and our common library code. We've upgraded from Vue 2 (EOL December 31, 2023) to Vue 3. These versions of Vue are not compatible with each other, so any tools written with Vue 2 will need to be updated. Additionally, our `@openc3/tool-common` NPM package has been deprecated with its functionality reorganized into two packages: `@openc3/js-common` and `@openc3/vue-common`. This is to provide a better experience for developers who are building COSMOS tools without the Vue framework.

We also removed a few rarely used [API methods](../guides/scripting-api#migration-from-cosmos-v5-to-v6) in COSMOS 6.

### Updating Vue

_If your tool was not built with Vue (e.g. it was built without a frontend framework, or it was built with React, Angular, etc.), then you can skip this section._

#### The quick and dirty way

Tools that are relatively simple can probably be upgraded in one shot by just updating the dependencies and fixing any build errors that arise, and then fixing any runtime errors you find from testing and using your tool. If you're confident in this upgrade path, you can reference [this pull request](https://github.com/OpenC3/cosmos/pull/1747) to see what will need to change. Otherwise, the rest of this guide will walk you through a more in-depth and complete migration process.

#### Step 1: Vue compat mode

The Vue team provided a compatibility mode to help with migrating from Vue 2 to Vue 3. This will let you get your tool up and running to make it easier to find the necessary changes.

##### (1.a) Update dependencies

Use your package manager or edit the package.json file to update the following dependencies (ignore any packages marked "Update" that you aren't using)

- **Remove:** `vue-template-compiler`
- **Add:** `@vue/compat` >= 3.5 ([npmjs.com](https://www.npmjs.com/package/@vue/compat))
- **Add:** `@vue/compiler-sfc` >= 3.5 ([npmjs.com](https://www.npmjs.com/package/@vue/compiler-sfc))
- **Update:** `@vue/test-utils` >= 2.4 ([npmjs.com](https://www.npmjs.com/package/@vue/compiler-sfc))
- **Update:** `vue` >= 3.5 ([npmjs.com](https://www.npmjs.com/package/vue))
- **Update:** `vuex` >= 4.1 ([npmjs.com](https://www.npmjs.com/package/vuex))
- **Update:** `vue-router` >= 4.4 ([npmjs.com](https://www.npmjs.com/package/vue-router))
- **Update:** `vuetify` >= 3.7 ([npmjs.com](https://www.npmjs.com/package/vuetify))
- **Update:** `single-spa-vue` >= 3.0 ([npmjs.com](https://www.npmjs.com/package/single-spa-vue))

Eslint will help call out changes you'll need to make to your code for the migration, so it's recommended to include eslint in your project if you haven't already. There are plenty of guides online that will explain how to do that. If you're using eslint, then make the additional changes to your tool's dependencies:

- **Add:** `eslint-plugin-vuetify` >= 2.5 ([npmjs.com](https://www.npmjs.com/package/eslint-plugin-vuetify))
- **Add:** `vue-eslint-parser` >= 9.4 ([npmjs.com](https://www.npmjs.com/package/vue-eslint-parser))

If you modified your package.json file manually, don't forget to `yarn` or `npm install` at your project's root to apply the changes.

##### (1.b) Update the Vue config file (`vue.config.js`)

You likely have a `chainWebpack` property in the object that's exported by this file which looks something like this (though your contents might vary)

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

Add a resolution alias for `@vue/compat` to the top of this block and set the compiler to use the Vue 2 compat mode:

```js
chainWebpack: (config) => {
  config.resolve.alias.set('vue', '@vue/compat') // Add this line
  config.module
    .rule('vue')
    .use('vue-loader')
    .tap((options) => {
      return {
        prettify: false,
        compilerOptions: { // Add this block
          compatConfig: {  //
            MODE: 2,       //
          },               //
        },                 // to here
      }
    })
},
```

##### (1.c) Update the eslint config file (`.eslintrc`)

Find the string `'plugin:vue/essential'` in your `extends` block and change it to `'plugin:vue/vue3-essential'`. If you don't have that plugin in your `extends` block, or you're missing that block entirely, then add this. It will help find breaking changes in how your code is using the Vue API.

```js
extends: [
  'plugin:vue/vue3-essential', // change this from plugin:vue/essential
  'plugin:prettier/recommended',
  '@vue/prettier',
],
```

##### (1.d) Fix build and runtime warnings and errors

Run your linting and build scripts (e.g. `yarn lint` and `yarn build`). The eslint plugin and Vue's compat mode will find the first set of code changes you need to address. Fix these lint/build errors until your project builds successfully.

Once it builds, run your project like you would for development. It's recommended to serve it from a local dev server with `yarn serve` and add it to the import map overrides in the browser. Test the functionality of your tool and address any Vue errors and warnings that get printed to the browser console in the dev tools. _(NOTE: On `MODE: 2` - your first pass through this section - it's ok if your tool doesn't completely work yet. Just address the warnings and errors that are logged to the browser console. You'll get your tool completely working in the next step.)_

From our experience migrating the COSMOS first-party tools, you'll most likely have to make changes to your `main.js` and `router.js` files at a minimum. You can reference the PR mentioned above in the "The quick and dirty way" section above to see what we changed, or search the internet for Vue 2 -> Vue 3 migration guides if you need help addressing any warnings or errors.

#### Step 2: Bump compat mode from 2 to 3

Change the `compatConfig` you added to your vue config file (`vue.config.js`) from `MODE: 2` to `MODE: 3`. This will tell Vue's compat mode that you've addressed the changes in the previous step, and it will find the next set of issues (since this is a multi-step process). Repeat the "(1.d) Fix build and runtime warnings and errors" step.

#### Step 3: Update Vuetify

_If you're not using Vuetify, you can skip this step._

Modify your eslint config (`.eslintrc`) again to add the Vuetify plugin:

```js
extends: [
  'plugin:vue/vue3-essential',
  'plugin:vuetify/base', // Add this line
  'plugin:prettier/recommended',
  '@vue/prettier',
],
```

**Note:** The Vuetify eslint plugin is only designed for migrating projects from Vuetify 2 to Vuetify 3 and can cause linting performance issues, so it should be removed once your tool migration is complete.

Again in `.eslintrc`, find your `parserOptions` block and add the `parser` property above it:

```js
parser: 'vue-eslint-parser', // Add this line
parserOptions: {
  ...
},
```

Now when you run eslint, it can tell you about any changes you'll need to address regarding how your code is using the Vuetify API. To find these changes, run eslint on your Vue files (e.g. `yarn eslint . --ext .vue`). You can address these manually, or if you trust eslint or have good version control, you can have the plugin fix most of them automatically with `yarn eslint . --ext .vue --fix`

Lastly, if you are using the Astro UXDS icons via Vuetify from COSMOS - or any custom icon packs for that matter - then you'll need to change their pack alias format from `$packName-` to `packName:`. Here's an example for the `antenna-transmit` Astro icon:

```html
<!-- Vue 2 / Vuetify 2 (old) -->
<v-icon> $astro-antenna-transmit </v-icon>

<!-- Vue 3 / Vuetify 3 (new) -->
<v-icon> astro:antenna-transmit </v-icon>
```

#### Step 4: Clean up

- Remove the `@vue/compat` and `eslint-plugin-vuetify` dependencies you added in step 1.a
- Remove the `compatConfig` you added in step 1.b
- Remove the `'plugin:vuetify/base'` you added in step 3

### Migrating to the new OpenC3 common packages

As mentioned in the first paragraph of this guide, we've deprecated the `@openc3/tool-common` NPM package. All of its functionality has remained the same, but everything is organized differently, so you'll have to update your dependencies and imports.

#### Step 1: Update dependencies

Use your package manager or edit the package.json file to update the following dependencies

- **Remove:** `@openc3/tool-common`
- **Add:** `@openc3/js-common` >= 6.0 ([npmjs.com](https://www.npmjs.com/package/@openc3/js-common))
- **Add:** `@openc3/vue-common` >= 6.0 ([npmjs.com](https://www.npmjs.com/package/@openc3/vue-common))
  - This is only needed if you are using our Vue stuff (components, plugins, etc.)

#### Step 2: Update imports in your code

In COSMOS 5, things were imported directly from `@openc3/tool-common`'s `src` directory and subsequently built into your tool by your build process. Everything in COSMOS 6 is now exported through several top-level exports in our new common packages. In general, the pattern is as follows:

- COSMOS 5: `import bar from '@openc3/tool-common/src/foo/bar'`
- COSMOS 6: `import { bar } from '@openc3/vue-common/foo'`

This pattern also lets you combine multiple import statements into one (e.g. `import { bar, baz } from '@openc3/vue-common/foo'`).

There are three exceptions to this pattern:

- Widgets are no longer under the `components` directory but instead get their own top-level export
  - Old: `import foo from '@openc3/tool-common/src/components/widgets/Foo`
  - New: `import { foo } from '@openc3/vue-common/widgets`
- Icons got the same treatment
  - Old: `import bar from '@openc3/tool-common/src/components/icons/Bar`
  - New: `import { bar } from '@openc3/vue-common/icons`
- The `TimeFilters` mixin was moved from `tools/base` to `util`
  - Old: `import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters`
  - New: `import { TimeFilters } from '@openc3/vue-common/util`

#### `@openc3/js-common`

This package contains things previously under `@openc3/tool-common/src/services`. Anything not from that path will be in the `vue-common` package discussed below.

Update any of your imports from that path accordingly. Here's an example:

```js
// COSMOS 5 (old)
import Api from "@openc3/tool-common/src/services/api";
import Cable from "@openc3/tool-common/src/services/cable";
import { OpenC3Api } from "@openc3/tool-common/src/services/openc3Api";

// COSMOS 6 (new)
import { Api, Cable, OpenC3Api } from "@openc3/js-common/services";
```

This package also provides a couple more top-level imports which you likely will not need, but they might be useful, so I'll call them out here:

- `import { prependBasePath } from '@openc3/js-common/utils` provides a function that will prepend the base path (e.g. localhost:2900) to Vue Router `route` objects and their children. This can be useful if you run into certain quirks with single-spa and vue-router 4's routing logic where you need the full path. You can see how we use it [here](https://github.com/OpenC3/cosmos/blob/f0193f4146e28e1cd383732763a9d27d84b5ca71/openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-cmdtlmserver/src/router.js#L76).

- `import { devServerPlugin } from '@openc3/js-common/viteDevServerPlugin`. This Vite plugin is a temporary hack to run a local dev server for tools when migrating from webpack/vue-cli. It should be replaced with Vite's built-in `vite dev` dev server, but that's currently not working - at least in our first-party COSMOS tools. You can see how we use it [here](https://github.com/OpenC3/cosmos/blob/f0193f4146e28e1cd383732763a9d27d84b5ca71/openc3-cosmos-init/plugins/packages/openc3-cosmos-tool-cmdtlmserver/vite.config.js#L37).

#### `@openc3/vue-common`

This package provides all the shared Vue components we use to build our first-party tools. The main top-level exports are `components`, `icons`, `plugins`, `util`, and `widgets`. There are also some tool-specific exports that we built for code sharing with COSMOS Enterprise, which you might find useful: `tool/base`, `tool/admin`, and `tool/calendar`. Here's an example, but again, reference the pattern mentioned above.

```js
// COSMOS 5 (old)
import DetailsDialog from "@openc3/tool-common/src/components/DetailsDialog";
import Graph from "@openc3/tool-common/src/components/Graph";
import Notify from "@openc3/tool-common/src/plugins/notify";
import TimeFilters from "@openc3/tool-common/src/tools/base/util/timeFilters";
import VWidget from "@openc3/tool-common/src/components/widgets/VWidget";

// COSMOS 6 (new)
import { DetailsDialog, Graph } from "@openc3/vue-common/components";
import { Notify } from "@openc3/vue-common/plugins";
import { TimeFilters } from "@openc3/vue-common/util";
import { VWidget } from "@openc3/vue-common/widgets";
```

## Migrating From COSMOS 4 to COSMOS 5

:::info All COSMOS Users
All COSMOS 4 users must upgrade their configuration to 5. However, the command, telemetry and screen definitions (keywords and syntax) have remained the same.
:::

COSMOS 5 is a new architecture and treats targets as independent [plugins](../configuration/plugins.md). Thus the primary effort in porting from COSMOS 4 to COSMOS 5 is converting targets to plugins. We recommend creating plugins for each independent target (with its own interface) but targets which share an interface will need to be part of the same plugin. The reason for independent plugins is it allows the plugin to be versioned separately and more easily shared outside your specific project. If you have very project specific targets (e.g. custom hardware) those can potentially be combined for ease of deployment.

### Configuration Migration Tool

COSMOS 5 (but not COSMOS 6) includes a migration tool for converting an existing COSMOS 4 configuration into a COSMOS 5 plugin. This example assumes an existing COSMOS 4 configuration at C:\COSMOS and a new COSMOS 5 installation at C:\cosmos-project. Linux users can adjust paths and change from .bat to .sh to follow along.

1. Change to the existing COSMOS 4 configuration directory. You should see the config, lib, procedures, outputs directory. You can then run the migration tool by specifying the absolute path to the COSMOS 5 installation.

   ```batch
   C:\COSMOS> C:\cosmos-project\openc3.bat cli migrate -a demo
   ```

   This creates a new COSMOS 5 plugin called openc3-cosmos-demo with a target named DEMO containing the existing lib and procedures files as well as all the existing targets.

   ```batch
   C:\COSMOS> C:\cosmos-project\openc3.bat cli migrate demo-part INST
   ```

   This would create a new COSMOS 5 plugin called openc3-cosmos-demo-part with a target named DEMO_PART containing the existing lib and procedures files as well as the INST target (but no others).

1. Open the new COSMOS 5 plugin and ensure the [plugin.txt](../configuration/plugins.md#plugintxt-configuration-file) file is correctly configured. The migration tool doesn't create VARIABLEs or MICROSERVICEs or handle target substitution so those features will have to added manually.

1. Follow the [building your plugin](gettingstarted.md#building-your-plugin) part of the Getting Started tutorial to build your new plugin and upload it to COSMOS 5.

### Upgrading Custom Tools

COSMOS 4 was a Qt Desktop based application. COSMOS 5 is a completely new architecture which runs natively in the browser using [Vue.js](https://vuejs.org/) as the Javascript framework and [Vuetify](https://vuetifyjs.com/en/) as the GUI library. We utilize [single-spa](https://single-spa.js.org/) to allow you to write COSMOS tool plugins in any language and provide [templates](https://github.com/OpenC3/cosmos/tree/main/openc3/templates) for Vue.js (recommended), Angular, React and Svelte. Any COSMOS 4 custom tools will have to be completely re-written to run in COSMOS 5. We recommend using the native COSMOS [tools](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages) and finding GUI concepts and functionality that best match the tool you're trying to re-create.

If you need custom development get in touch at sales@openc3.com.
