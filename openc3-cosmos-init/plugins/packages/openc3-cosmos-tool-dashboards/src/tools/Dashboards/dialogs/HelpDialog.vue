<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<!-- Help dialogs opened from the Dashboards Help menu -->
<template>
  <v-dialog v-model="show" scrollable width="760">
    <v-card :data-test="`help-dialog-${topic}`">
      <v-toolbar height="24">
        <v-spacer />
        <span>{{ TITLES[topic] }}</span>
        <v-spacer />
      </v-toolbar>
      <v-card-text style="max-height: 70vh">
        <!-- Shortcuts -->
        <template v-if="topic === 'shortcuts'">
          <template v-for="group in shortcutGroups" :key="group.title">
            <div class="text-overline">{{ group.title }}</div>
            <v-table density="compact" class="mb-4">
              <tbody>
                <tr v-for="row in group.rows" :key="row.action">
                  <td>{{ row.action }}</td>
                  <td class="text-right text-no-wrap">
                    <v-kbd v-for="key in row.keys" :key="key" class="ms-1">
                      {{ key }}
                    </v-kbd>
                  </td>
                </tr>
              </tbody>
            </v-table>
          </template>
          <p class="text-caption text-medium-emphasis">
            Single key shortcuts act on the panel with keyboard focus, or else
            the one under the mouse. They're ignored while typing in a field.
          </p>
        </template>

        <!-- Migrating from Telemetry Viewer -->
        <template v-else-if="topic === 'migrate'">
          <p class="mb-3">
            Dashboards and Telemetry Viewer screens live side by side.
            Dashboards bring the convenience of simple layouts, ease of use, and
            standardized panels and can incorporate custom Telemetry Viewer
            screens for a custom dashboard.
          </p>

          <div class="text-overline">1. Bring your screens over</div>
          <ol class="ps-5 mb-4">
            <li class="mb-2">In Telemetry Viewer, open the screens you use.</li>
            <li class="mb-2">
              Choose <strong>File &gt; Convert to Dashboard</strong>, pick the
              target to save it in and a name.
            </li>
            <li class="mb-2">
              Each open screen becomes a <strong>Screen</strong> panel and the
              new dashboard opens here. Resize and arrange the panels with
              <strong>Edit</strong>.
            </li>
          </ol>
          <p class="mb-4">
            Or start from any dashboard: <strong>Add panel</strong>, choose
            <strong>Screen</strong> and pick the screen. Edits to the screen's
            definition in the panel dialog are saved to the screen file, so
            Telemetry Viewer shows them too.
          </p>

          <div class="text-overline">2. Replace widgets with panels</div>
          <p class="mb-2">
            Panels bring convenient and simple layouts that are screen-size
            aware for a simpler UX. Telemetry Viewer widgets can be migrated to
            Dashboard panels as follows:
          </p>
          <!-- Fixed layout: the long widget names wrap in their column
               instead of taking width from the panels -->
          <v-table density="compact" class="widget-map mb-4">
            <thead>
              <tr>
                <th scope="col" style="width: 50%">Telemetry Viewer widgets</th>
                <th scope="col">Dashboard panel</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in widgetMap" :key="row.panel">
                <td class="mono text-body-2 text-break">{{ row.widgets }}</td>
                <td class="text-break">
                  <strong>{{ row.panel }}</strong>
                  <div class="text-caption text-medium-emphasis">
                    {{ row.note }}
                  </div>
                </td>
              </tr>
            </tbody>
          </v-table>

          <div class="text-overline">3. Things that work differently</div>
          <ul class="ps-5 mb-2">
            <li class="mb-2">
              <strong>Layout</strong>: panels sit on a 12 (or 24) column grid.
            </li>
            <li class="mb-2">
              <strong>Files</strong>: a dashboard is saved as
              <code>TARGET/dashboards/NAME.txt</code>, next to the target's
              screens, and can be shipped in a plugin the same way. Click
              <strong>Code</strong> to see or edit it as text.
            </li>
            <li class="mb-2">
              <strong>Commands</strong>: Command panels send with a hold (or a
              confirmed click) and are disabled while editing and during
              playback.
            </li>
            <li class="mb-2">
              <strong>Custom widgets</strong>: keep them in a Screen panel, or
              write a custom panel type in a plugin (see the Custom Panels
              guide).
            </li>
          </ul>
        </template>
      </v-card-text>
      <v-card-actions class="px-2">
        <v-btn
          v-if="topic === 'migrate'"
          variant="text"
          append-icon="mdi-open-in-new"
          href="/tools/staticdocs/docs/tools/dashboards"
          target="_blank"
          text="Dashboards documentation"
        />
        <v-spacer />
        <v-btn
          variant="flat"
          text="Ok"
          data-test="help-dialog-ok"
          @click="show = false"
        />
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { formatShortcut, isMac } from '@openc3/vue-common/util'

const TITLES = {
  shortcuts: 'Keyboard Shortcuts',
  migrate: 'Migrating from Telemetry Viewer',
}

defineProps({
  // shortcuts or migrate
  topic: { type: String, required: true },
})
const show = defineModel({ type: Boolean, required: true })

const keys = (...shortcuts) =>
  shortcuts.map((shortcut) => formatShortcut(shortcut))

const shortcutGroups = [
  {
    title: 'Dashboards',
    rows: [{ action: 'Open the dashboard navigator', keys: keys('Mod+O') }],
  },
  {
    title: 'Dashboard Navigator',
    rows: [
      { action: 'Move through folders or dashboards', keys: ['↑', '↓'] },
      { action: 'Open a folder', keys: ['→', 'Enter'] },
      { action: 'Back to the folders', keys: ['←'] },
      { action: 'Open the selected dashboard', keys: ['Enter'] },
    ],
  },
  {
    title: 'Viewing',
    rows: [
      { action: 'Show a panel full screen, or go back', keys: ['V'] },
      { action: 'Leave full screen', keys: ['Esc'] },
      { action: 'Open item details from a focused value', keys: ['Enter'] },
    ],
  },
  {
    title: 'Editing',
    rows: [
      { action: 'Configure a panel', keys: ['E'] },
      { action: 'Move the focused panel', keys: ['←', '↑', '→', '↓'] },
      { action: 'Resize the focused panel', keys: keys('Shift+Arrows') },
      { action: 'Cancel a drag', keys: ['Esc'] },
      { action: 'Undo', keys: keys('Mod+Z') },
      { action: 'Redo', keys: keys(isMac ? 'Mod+Shift+Z' : 'Mod+Y') },
    ],
  },
]

const widgetMap = [
  {
    widgets: 'VALUE, LABELVALUE, FORMATVALUE',
    panel: 'Stat',
    note: 'One value with a sparkline and limits bar',
  },
  {
    widgets: 'LABELVALUEDESC, LABELVALUELIMITSBAR, VALUELIMITSBAR, LIMITSBAR',
    panel: 'Values',
    note: 'A table of items with status, limits bars and units',
  },
  {
    widgets: 'LINEGRAPH, SPARKLINE, LABELSPARKLINE',
    panel: 'Graph',
    note: 'Up to 6 items over the time range with limits bands',
  },
  {
    widgets: 'LED, LABELLED, LIMITSCOLOR',
    panel: 'State',
    note: 'The current state with its status color',
  },
  {
    widgets: 'PROGRESSBAR, LABELPROGRESSBAR, RANGEBAR',
    panel: 'Gauge',
    note: 'A dial with limits zones and its own scale',
  },
  {
    widgets: 'BUTTON with cmd() or a script',
    panel: 'Command',
    note: 'A command with preset parameters, or a script to run',
  },
  {
    widgets: 'LABEL, TITLE',
    panel: 'Text',
    note: 'Markdown notes, headings and links',
  },
  {
    widgets: 'Screens built to watch limits',
    panel: 'Limits',
    note: 'Items out of limits for chosen targets, worst first',
  },
  {
    widgets: '(none)',
    panel: 'Aggregate',
    note: 'Min, max, average and more over the time range',
  },
]
</script>

<style scoped>
.widget-map :deep(table) {
  table-layout: fixed;
}
.widget-map td {
  vertical-align: top;
  padding-block: 6px;
}
</style>
