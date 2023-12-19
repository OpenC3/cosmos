---
title: Custom Widgets
---

COSMOS allows you to build custom widgets which can be deployed with your [plugin](../configuration/plugins.md) and used in [Telemetry Viewer](../tools/tlm-viewer.md). Building custom widgets can utilitize any javascript frameworks but since COSMOS is written with Vue.js, we will use that framework in this tutorial.

## Custom Widgets

We're basically going to follow the COSMOS [Demo](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo) and explain how that custom widget was created.

If you look at the bottom of the Demo's [plugin.txt](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/plugin.txt) file you'll see we declare the widgets:

```ruby
WIDGET BIG
WIDGET HELLOWORLD
```

When the plugin is deployed this causes COSMOS to look for the as-built widgets. For the BIG widget it will look for the widget at `tools/widgets/BigWidget/BigWidget.umd.min.js`. Similarly it looks for HELLOWORLD at `tools/widgets/HelloworldWidget/HelloworldWidget.umd.min.js`. These directories and file names may seem mysterious but it's all about how the widgets get built.

### Helloworld Widget

The Helloworld Widget source code is found in the plugin's src directory and is called [HelloworldWidget.vue](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/src/HelloworldWidget.vue). The basic structure is as follows:

```vue
<template>
  <!-- Implement widget here -->
</template>

<script>
import Widget from "@openc3/tool-common/src/components/widgets/Widget";
export default {
  mixins: [Widget],
  data() {
    return {
      // Reactive data items
    };
  },
};
</script>
<style scoped>
/* widget specific style */
</style>
```

:::info Vue & Vuetify
For more information about how the COSMOS frontend is built (including all the Widgets) please check out [Vue.js](https://vuejs.org) and [Vuetify](https://vuetifyjs.com).
:::

To build this custom widget we changed the Demo [Rakefile](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/Rakefile) to call `yarn run build` when the plugin is built. `yarn run XXX` looks for 'scripts' to run in the [package.json](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/package.json) file. If we open package.json we find the following:

```json
  "scripts": {
    "build": "vue-cli-service build --target lib --dest tools/widgets/HelloworldWidget --formats umd-min src/HelloworldWidget.vue --name HelloworldWidget && vue-cli-service build --target lib --dest tools/widgets/BigWidget --formats umd-min src/BigWidget.vue --name BigWidget"
  },
```

This uses the `vue-cli-service` to build the code found at `src/HelloworldWidget.vue` and formats as `umd-min` and puts it in the `tools/widgets/HelloworldWidget` directory. So this is why the plugin looks for the plugin at `tools/widgets/HelloworldWidget/HelloworldWidget.umd.min.js`. Click [here](https://cli.vuejs.org/guide/cli-service.html#vue-cli-service-build) for the `vue-cli-service build` documentation.

If you look at the Demo plugin's [simple.txt](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo/targets/INST/screens/simple.txt) screen you'll see we're using the widgets:

```ruby
SCREEN AUTO AUTO 0.5
LABELVALUE <%= target_name %> HEALTH_STATUS CCSDSSEQCNT
HELLOWORLD
BIG <%= target_name %> HEALTH_STATUS TEMP1
```

Opening this screen in Telemetry Viewer results in the following:

![Simple Screen](/img/guides/simple_screen.png)

While this is a simple example the possibilities with custom widgets are limitless!
