---
title: Custom Panels
description: How to build custom panel types for Dashboards
sidebar_custom_props:
  myEmoji: 🧩
---

# Custom Panels

Dashboards are built from panels: Stat, Gauge, Graph, Values, Limits, Command, Screen and so on. A plugin can add its own panel types. They show up in the panel type picker under **Plugins**, get the same panel dialog, polling, limits status, playback and edit mode as the built-in panels, and are saved in dashboard files like any other panel:

```
PANEL BATTERY 0 0 3 3 "Main Bus"
  ITEM INST HEALTH_STATUS TEMP1
  SETTING DECIMALS 2
END
```

Panels are written in Vue.js 3 using the Composition API. Use the [Panel Generator](/docs/getting-started/generators#panel-generator) to create the scaffolding.

## Step 1: Generate the Panel

In the root directory of an existing plugin (or one made with the [Plugin Generator](/docs/getting-started/generators#plugin-generator)), run the panel generator with a CapitalCase name ending in `Panel`:

```bash
openc3-cosmos-gse % openc3.sh cli generate panel BatteryPanel
Panel BatteryPanel successfully generated!
Use it in a dashboard as PANEL BATTERY. Be sure BATTERY does not overlap a built-in panel type: https://docs.openc3.com/docs/guides/custom-panels
```

The panel type is the name without `Panel`, uppercased: `BatteryPanel` is `PANEL BATTERY`. This creates:

```
openc3-cosmos-gse/
├── package.json                  # pnpm build script and dependencies
├── pnpm-workspace.yaml
├── Rakefile                      # rake build runs pnpm build, then gem build
├── plugin.txt                    # PANEL BATTERY was appended
├── vite-BatteryPanel.config.js   # builds tools/panels/BATTERY/BATTERY.js
└── src/
    ├── panelSdk.js               # holds the panel SDK, shared by all panels
    ├── BatteryPanel.js           # the panel type definition (entry point)
    └── BatteryPanel.vue          # the panel component
```

Run the generator again for more panels in the same plugin. Each one gets its own `.js`, `.vue` and vite config, and its build is appended to the `build` script in `package.json`.

:::warning[Built-in panel types]
A panel type can't reuse a built-in name (`STAT`, `GAUGE`, `STATE`, `VALUES`, `GRAPH`, `LIMITS`, `COMMAND`, `SCREEN`) or another plugin's. Dashboards reports the clash and skips the panel.
:::

## Step 2: How a Panel Is Loaded

The `PANEL BATTERY` line in `plugin.txt` installs `tools/panels/BATTERY/BATTERY.js` from the plugin gem. When Dashboards opens, it loads every installed panel before parsing any dashboard. Each panel's file is a SystemJS module whose default export is a function. Dashboards calls it with the **panel SDK** and registers the panel type it returns. That's the generated `src/BatteryPanel.js`:

```js
import { setSdk } from "./panelSdk";
import BatteryPanel from "./BatteryPanel.vue";

export default (sdk) => {
  setSdk(sdk);
  return {
    label: "Battery",
    description: "One telemetry value with its limits status",
    icon: "mdi-puzzle-outline",
    component: BatteryPanel,
    content: "items",
    maxItems: 1,
    defaults: { w: 3, h: 3 },
    options: [
      {
        name: "DECIMALS",
        type: "number",
        label: "Decimal places",
        default: null,
        min: 0,
        max: 10,
      },
    ],
  };
};
```

`setSdk` stores the SDK in `src/panelSdk.js` so components can import it. Dashboards calls the entry function before it creates any panel, so the SDK is always there when a component's `setup` runs.

If a dashboard uses a panel type whose plugin isn't installed, the panel shows as "plugin not installed" and keeps its text, so saving the dashboard doesn't lose it.

## Step 3: Describe the Panel Type

Everything about a panel type except its body is in the definition the entry function returns. These are the same fields the built-in panels use:

| Field                          | Description                                                                                                                                                                          |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `component`                    | **Required.** The Vue component that draws the panel body. It gets the panel as its `panel` prop.                                                                                    |
| `label`, `description`, `icon` | Shown in the panel type picker. `icon` is any [Material Design Icon](https://pictogrammers.com/library/mdi/) name, e.g. `mdi-battery`. Defaults to the type name and a puzzle piece. |
| `content`                      | What the top of the panel dialog edits: `'items'` (telemetry items, the default), `'targets'` (like Limits), `'command'` (like Command) or `'screen'` (like Screen).                 |
| `maxItems`                     | Most `ITEM` lines allowed. `null` for no limit (the default), `0` for none.                                                                                                          |
| `options`                      | The panel's `SETTING`s. See [Step 4](#step-4-add-settings).                                                                                                                          |
| `itemOptions`                  | `ITEM_SETTING`s each item understands, same format as `options` (e.g. a line `COLOR`).                                                                                               |
| `keywords`                     | Keywords allowed inside `PANEL ... END`. Defaults to `['ITEM', 'ITEM_SETTING', 'SETTING']`.                                                                                          |
| `defaults`                     | `{ w, h }` size for a new panel, in grid cells. Defaults to 4 x 4.                                                                                                                   |
| `minSize`                      | `{ w, h }` smallest size, when the panel needs more than 2 x 2.                                                                                                                      |
| `validate`                     | `(panel) => message` when the panel is incomplete, else `null`. Panels with `ITEM` already need one item.                                                                            |
| `title`, `subtitle`            | `(panel) => string` for the panel header. The title defaults to the panel's title, then its single item's name.                                                                      |
| `beforeSave`                   | `async (panel) => void`, run when the panel dialog saves. Throw to keep the dialog open with the error shown.                                                                        |

## Step 4: Add Settings

Declare a setting in `options` and it parses, validates, saves (only when it differs from its default) and gets a control in the panel dialog. There is nothing else to write. Read the value in the component with `sdk.option(panel, NAME)`, which returns the typed value or the default.

```js
options: [
  { name: 'SHOW_UNITS', type: 'boolean', label: 'Show units', default: true },
  {
    name: 'STYLE',
    type: 'select',
    label: 'Style',
    default: 'BAR',
    items: [
      { title: 'Bar', value: 'BAR' },
      { title: 'Ring', value: 'RING' },
    ],
  },
  {
    name: 'CAPACITY',
    type: 'number',
    label: 'Capacity',
    default: 100,
    min: 1,
    unit: 'Ah',
    // Only shown for the bar style
    when: (get) => get('STYLE') === 'BAR',
  },
],
```

| Type      | Value                                  | In the dashboard file                     |
| --------- | -------------------------------------- | ----------------------------------------- |
| `boolean` | `true` / `false`                       | `SETTING SHOW_UNITS FALSE`                |
| `number`  | number, or `null`                      | `SETTING CAPACITY 40`                     |
| `select`  | one of `items`' values                 | `SETTING STYLE RING`                      |
| `text`    | string                                 | `SETTING NOTE "Main bus"`                 |
| `color`   | `'#rrggbb'`                            | `SETTING COLOR "#938bdb"`                 |
| `item`    | `{ targetName, packetName, itemName }` | `SETTING SOURCE INST HEALTH_STATUS TEMP1` |

Optional fields: `help` (caption under the control), `when` (`(get, panel) => boolean`, hides the control when it doesn't apply), `min` / `max` / `unit` (numbers), `multiline` (text), `span` (width in the dialog, of 12 columns, default 4) and `newRow`.

## Step 5: Write the Component

The generated `src/BatteryPanel.vue` shows one value with its limits status:

```html
<template>
  <div
    class="d-flex flex-column flex-grow-1 align-center justify-center ga-1 pa-2"
    :class="{ 'cursor-pointer': !!openDetails }"
    @click="showDetails()"
  >
    <div class="d-flex align-center ga-2">
      <StatusSymbol :level="first.level" :size="16" />
      <span class="text-medium-emphasis text-caption">{{ first.label }}</span>
    </div>
    <div :class="['value', { 'text-disabled': first.stale }]">
      {{ text }}
      <span class="text-body-2 text-medium-emphasis">{{ first.units }}</span>
    </div>
  </div>
</template>

<script setup>
  import { computed } from "vue";
  import { sdk } from "./panelSdk";

  const props = defineProps({
    panel: { type: Object, required: true },
  });

  const { first, showDetails, openDetails } = sdk.useTlmPanel(props);
  const { StatusSymbol } = sdk.components;

  const text = computed(() => {
    const decimals = sdk.option(props.panel, "DECIMALS");
    if (decimals === null || first.value.number === null)
      return first.value.text;
    return first.value.number.toFixed(decimals);
  });
</script>
```

:::info[Composition API]
Panels use `<script setup>` and the SDK's composables. Write the `panel` prop out in `defineProps` as above: `defineProps` runs when the module loads, before Dashboards hands over the SDK, so it can't use `sdk.panelProps`. Call SDK functions inside `<script setup>` instead.
:::

### The panel prop

`panel` is the parsed `PANEL ... END` block: `uid`, `type`, `title`, `x` / `y` / `w` / `h`, `items` (each `{ targetName, packetName, itemName, valueType }`) and its settings. Read settings with `sdk.option` and `sdk.itemOption` rather than from the object. A new panel config comes in as a new `panel` prop, so derive everything from it with `computed`.

### Composables

Call one of these at the top of `<script setup>`. They poll the right items, report the panel's status to the dashboard (the colored frame and the health chip) and clean up when the panel goes away.

**`sdk.useTlmPanel(props, options?)`** is for panels that show their `ITEM`s. It returns everything `usePanel` does, plus:

| Name                 | Description                                                                                                                                                                              |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `itemStates`         | One entry per item: `item`, `label`, `path`, `text` (formatted), `number` (or `null`), `units`, `level` (`'normal'`, `'caution'`, `'critical'`, ...), `stale`, `changedAt` and `limits`. |
| `first`              | `itemStates[0]`, for single value panels.                                                                                                                                                |
| `packetTime`         | Received time of the first item's packet, when the type declares a boolean `PACKET_TIME` option and it's on.                                                                             |
| `showDetails(item?)` | Opens the item details sheet (default: the first item), where the dashboard offers it.                                                                                                   |

Options: `extraPollKeys: () => keys` to poll more than the items, and `panelLevel: () => level` to report a status other than the worst item's.

**`sdk.usePanel(props, options?)`** is the base for every panel. Options: `pollKeys: () => keys` (build keys with `sdk.itemKey(item, sdk.pollType(item))`) and `panelLevel: () => level` (e.g. `worstOf(keys)`). These getters are first read when the panel mounts, so they can use computeds declared after the call. It returns:

| Name                         | Description                                                                                                                         |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `poller`                     | `poller.values[key]` is `{ value, state, changedAt }` for each polled key.                                                          |
| `itemInfo`                   | `itemInfo.get(item)` is `{ units, formatString, description, limits }`; `itemInfo.limits(item)` is the current limits set's values. |
| `isEditing`                  | The dashboard is being edited. Telemetry keeps flowing, but don't send commands or run anything.                                    |
| `isPlayback`, `playbackTime` | Playback is on, and the `Date` being shown.                                                                                         |
| `rect`                       | The panel's size and place as drawn, following a resize while it's dragged. Use instead of `panel.w` / `panel.h`.                   |
| `isNarrow`                   | The panel is drawn 2 columns wide or less (of 12). Small panels shorten what they show, e.g. numbers with `sdk.compactNumber`.      |
| `timeZone`                   | `'local'` or `'UTC'`, from Admin Settings. Pass it to the formatters.                                                               |
| `worstOf(keys)`              | Worst status across polled keys.                                                                                                    |
| `openDetails`                | The details sheet opener, or `null` where details aren't offered.                                                                   |

**`sdk.useTlmSeries(props, base, options?)`** adds history over the dashboard's time range (the header's time picker), backfilled when the dashboard opens and streamed live, like the Graph and Stat panels. Pass what `usePanel` or `useTlmPanel` returned as `base`. It returns `series` (`[times in seconds, then one array of values per item]`, oldest first, updated in place), `latest`, `now`, `duration`, `hover` and `setHover(time)` for the hover shared across the dashboard's graphs. Options: `seriesItems: () => items` (default: the panel's items), `seriesUpdated()` (about once a second) and `seriesReset()` (when the series start over).

### Other SDK helpers

| Name                                                                                                                                                              | Description                                                                                        |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `option(panel, NAME)`, `withOption(panel, NAME, value)`                                                                                                           | Read a setting, or copy the panel with one changed.                                                |
| `itemOption(panel, item, NAME)`                                                                                                                                   | Read an item's `ITEM_SETTING`.                                                                     |
| `itemKey(item, type)`, `baseKey(item)`, `packetTimeKey(item)`, `pollType(item)`, `itemLabel(items, item)`                                                         | Poll keys and labels.                                                                              |
| `formatTelemetry(value, formatString)`, `formatItem(name, value, formatString, timeZone)`, `formatTime(time, timeZone)`, `toSeconds(time)`, `clock(ms, timeZone)` | Formatting, matching the built-in panels.                                                          |
| `compactNumber(value)`                                                                                                                                            | Short text for small panels: 2 decimal places, and k / M / B for thousands, millions and billions. |
| `stateToLevel(state)`, `worstLevel(levels)`                                                                                                                       | Limits states to status levels.                                                                    |
| `SERIES_COLORS`, `seriesColor(index)`                                                                                                                             | The graph line palette.                                                                            |
| `components.LimitsBar`, `components.Sparkline`, `components.StatusSymbol`                                                                                         | Building blocks from the built-in panels.                                                          |
| `version`                                                                                                                                                         | The SDK version, bumped on breaking changes.                                                       |

Vuetify components (`v-btn`, `v-icon`, ...) work in templates as they do in COSMOS tools. `vue` and `vuetify` are provided by COSMOS, so they aren't bundled into the panel.

## Step 6: Build and Install

Build the plugin gem. `rake build` runs `pnpm run build`, which bundles each panel into `tools/panels/<TYPE>/<TYPE>.js` with its styles inlined, then builds and validates the gem:

```bash
pnpm install
rake build VERSION=1.0.0
```

Install the gem from the Admin Plugins tab (or upgrade an installed one), then reload Dashboards. The panel type appears under **Plugins** in the panel type picker. If it fails to load, Dashboards shows the error when it opens.
