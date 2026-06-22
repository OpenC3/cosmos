---
title: Custom Tools
description: How to build custom tools as standalone UI plugins
sidebar_custom_props:
  myEmoji: 🛠️
---

# Custom Tools

<div style={{ textAlign: 'center' }}>
  <iframe
    width="560"
    height="315"
    src="https://www.youtube.com/embed/8xilz5cSxyA"
    title="How to Make a Tool in COSMOS"
    frameBorder="0"
    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
    allowFullScreen
  ></iframe>
</div>


This guide will walk you through the process of building custom tools for use in COSMOS. While you can use any JavaScript framework, we'll use Vue.js since COSMOS is built with it. Before starting, you may want to check out the [Tool Generator](/docs/getting-started/generators#tool-generator) guide to create the initial scaffolding.

## Step 1: Generate a Tool with the Tool Generator

Follow the guide in [Tool Generator](/docs/getting-started/generators#tool-generator) to generate the scaffolding for your Tool.

Ensure your plugin has the correct directory structure:

```
your-plugin/
├── LICENSE.md
├── your-plugin.gemspec
├── package.json
├── plugin.txt
├── Rakefile
├── README.md
├── src/
│   └── App.vue
│   └── main.js
│   └── router.js
│   └── tools/your-plugin/your-plugin.vue
└── vite.config.js
```

## Step 2: Declare Your Tool in plugin.txt

In your plugin's `plugin.txt` file, declare the custom tool:

```cosmos
TOOL YOURCUSTOM "Your Custom Tool Title"
  INLINE_URL main.js
  ICON mdi-YOURCUSTOM
```

The ICON can use MDI icons defined by the [Material Design Icon Library](https://pictogrammers.com/library/mdi/).

## Step 3: Configure Your Build Process

### Set Up package.json

Ensure your `package.json` includes the necessary build script:

```json
{
  "scripts": {
    "build": "vite build"
  },
  "dependencies": {
    "@openc3/vue-common": "latest"
  },
  "devDependencies": {
    "vite": "latest"
  }
}
```

### Update Your Rakefile

Ensure your `Rakefile` is configured to run the build script in its `:build` task:

_(This should happen automatically if you use our code generators mentioned above.)_

```ruby
task :build do
  # ...

  # Build the tool and gem using sh built into Rake:
  # https://rubydoc.info/gems/rake/FileUtils#sh-instance_method
  sh('pnpm run build') do |ok, status|

  # ...
end
```

## Step 4: Create Your Tool

If it doesn't exist already, create a Vue component file in the `src` directory, following the naming convention: `src/tools/your-plugin/your-plugin.vue`.

```html
<template>
  <!-- Your tool's HTML structure goes here -->
</template>

<script>
  export default {
    data() {
      return {
        // Reactive data items
      };
    },
  };
</script>
<style scoped>
  /* Tool-specific styles */
</style>
```

## Step 5: Develop Your Tool

This is where you'll design the actual layout and functionality of your tool. Follow [Vue.js documentation](https://vuejs.org/guide/introduction) for best practices on Front-End development for Vue.js development.

## Step 6: Configure Your Build Output

Ensure your `vite.config.js` file is configured to properly build your widgets:

```javascript
import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";
import { devServerPlugin } from '@openc3/js-common/viteDevServerPlugin'

const DEFAULT_EXTENSIONS = [".mjs", ".js", ".ts", ".jsx", ".tsx", ".json"];

export default defineConfig((options) => {
  return {
    build: {
      outDir: 'tools/your-tool',
      emptyOutDir: true,
      rollupOptions: {
        input: 'src/main.js',
        output: {
         ...
        },
        external: ['single-spa', 'vue', 'pinia', 'vue-router', 'vuetify'],
        preserveEntrySignatures: 'strict',
      },
    },
    server: {
      port: 2999,
    },
    plugins: [
      ...
      devServerPlugin(options),
    ],
    resolve: {
     ...
    },
    define: {
      __BASE_URL__: JSON.stringify('/tools/severeweather'),
    }
  }
})
```

## Step 7: Build and Deploy Your Plugin

In order to build a tool, a container containing `node` and `pnpm` is necessary.

<Tabs groupId="platform">
<TabItem value="linux" label="Linux / macOS">

```bash
% docker run -it -v `pwd`:/openc3/local:z -w /openc3/local openc3inc/openc3-node sh
/openc3/local $ pnpm install
/openc3/local $ rake build
```

</TabItem>

<TabItem value="windows" label="Windows">

```bash
docker run -it -v %cd%:/openc3/local -w /openc3/local openc3inc/openc3-node sh
/openc3/local $ pnpm install
/openc3/local $ rake build
```

</TabItem>
</Tabs>

Notes:

- The `openc3-node` container is currently missing the `openc3` gem, so the gem validation will fail. This does not impact tool development.
- The `openc3-node` container may need to be run as `root` so that `pnpm` has the permissions to create `node_modules` in the host tool directory.
- If you are behind a firewall/proxy, the `NODE_EXTRA_CA_CERTS` in the container may need to be set for `pnpm` to work. The `Error: self-signed certificate in certificate chain error` signifies the need for this env variable.

## Step 8: Install your Tool to COSMOS

From the Admin Console, browse for the newly creating `.gem` file containing your Tool plugin, and install it. After installation and refresh, you should see your tool appear on the left side navigation bar as a new Tool within COSMOS.

## Step 9: Enable Hot-Reloads for Fast Development

1.  Bootstrap the tool with pnpm

```bash
openc3-init/plugins % pnpm install --frozen-lockfile --ignore-scripts
openc3-init/plugins % pnpm build:common
```

1.  Serve a your tool locally

```bash
openc3-init % pnpm serve
```

1.  Set the [single SPA](https://single-spa.js.org/) override for the application

    Visit localhost:2900 and Right-click 'Inspect'<br/>
    In the console paste:

```javascript
localStorage.setItem("devtools", true);
```

    Refresh and you should see `{...}` in the bottom right<br/>
    Click the Default button next to the application (@openc3/tool-your-plugin)<br/>
    Paste in the development path which is dependent on the port that is defined in the `vite.config.js` under `server.port`:

        http://localhost:2999/tools/your-plugin/main.js

1.  Refresh the page and you should see your local copy of the application. If you dynamically add code (like `console.log`) the pnpm window should re-compile and the browser should refresh displaying your new code. It is highly recommended to get familiar with your browser's [development tools](https://developer.chrome.com/docs/devtools/overview/) if you plan to do frontend development.

The possibilities with custom tools are limitless!