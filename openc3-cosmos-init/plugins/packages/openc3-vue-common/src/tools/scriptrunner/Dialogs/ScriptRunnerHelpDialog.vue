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

<!--
# Help dialogs opened from the Script Runner Help menu. Each topic explains
# functionality that is otherwise only discoverable through right click
# menus, keyboard shortcuts, or Enterprise settings.
-->
<template>
  <v-dialog v-model="show" scrollable width="720">
    <v-card :data-test="`help-dialog-${topic}`">
      <v-toolbar height="24">
        <v-spacer />
        <span>{{ content.title }}</span>
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
        </template>

        <!-- Goto / Execute Selection -->
        <template v-else-if="topic === 'selection'">
          <p class="mb-4">
            Right click in the editor to run part of a script instead of the
            whole thing. What the menu offers depends on whether a script is
            running.
          </p>
          <v-card
            v-for="section in selectionSections"
            :key="section.title"
            variant="tonal"
            class="mb-4"
          >
            <v-card-item
              :prepend-icon="section.icon"
              :title="section.title"
              :subtitle="section.subtitle"
            />
            <v-divider />
            <v-list density="compact" bg-color="transparent" class="py-0">
              <template v-for="(entry, index) in section.items" :key="index">
                <v-divider v-if="index > 0" />
                <v-list-item class="py-2">
                  <v-list-item-title class="font-weight-bold">
                    {{ entry.name }}
                  </v-list-item-title>
                  <div class="text-body-2 text-medium-emphasis mt-1">
                    {{ entry.text }}
                  </div>
                </v-list-item>
              </template>
            </v-list>
          </v-card>
        </template>

        <!-- Script Lifecycle -->
        <template v-else-if="topic === 'lifecycle'">
          <v-alert
            v-if="!versionsEnabled || !lifecycleEnabled"
            type="info"
            variant="tonal"
            density="compact"
            class="mb-4"
          >
            {{
              versionsEnabled
                ? 'Script Lifecycle is turned off. An admin can enable it in Admin Console > Settings.'
                : 'Script Lifecycle is available in COSMOS Enterprise.'
            }}
          </v-alert>
          <p class="mb-3">
            Script Lifecycle adds a review and approval step before a script can
            be run by operators. Every saved script is in one of three states,
            shown as a chip next to the filename:
          </p>
          <div class="d-flex flex-wrap ga-2 my-3">
            <v-chip
              v-for="state in states"
              :key="state.value"
              :color="lifecycleStateColor(state.value)"
              variant="flat"
              size="small"
            >
              {{ state.text }}
            </v-chip>
          </div>
          <ul class="ps-5 mb-2">
            <li class="mb-2">
              <strong>In Development</strong>: new and edited scripts. Anyone
              who can edit scripts can change them and move them to review.
            </li>
            <li class="mb-2">
              <strong>In Review</strong>: waiting on an approver. Only script
              approvers can approve a script.
            </li>
            <li class="mb-2">
              <strong>Approved</strong>: locked. The script can't be edited or
              deleted until an approver moves it back to review. Users who can
              only run scripts may only run approved scripts.
            </li>
          </ul>
          <p class="mt-3 mb-3">
            Click the state chip or use Script &gt; Script Lifecycle to change
            the state. Each change can include a comment and is kept in the
            lifecycle history along with who made it and when.
          </p>
        </template>

        <!-- Script Versioning -->
        <template v-else-if="topic === 'versioning'">
          <v-alert
            v-if="!versionsEnabled"
            type="info"
            variant="tonal"
            density="compact"
            class="mb-4"
          >
            Script Versioning is available in COSMOS Enterprise.
          </v-alert>
          <p class="mb-3">
            Every time a script is saved, a new version is recorded along with
            who saved it and when. Nothing is lost when a script is overwritten.
          </p>
          <p class="mt-3 mb-3">
            Open Script &gt; Version History to see the versions of the current
            file, newest first.
          </p>
          <ul class="ps-5 mb-2">
            <li class="mb-2">Click a version to view its contents.</li>
            <li class="mb-2">
              Use the diff button to compare a version with the one before it.
              Either side of the diff can be changed to compare any two
              versions.
            </li>
            <li class="mb-2">
              <strong>Restore</strong> saves the selected version as a new
              version. The history is kept, so a restore can itself be undone.
            </li>
          </ul>
        </template>
      </v-card-text>
      <v-card-actions class="px-2">
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
import { computed } from 'vue'
import { formatShortcut, isMac } from '@/util/formatShortcut'
import {
  LIFECYCLE_STATE_LABELS,
  lifecycleStateColor,
} from '@/tools/scriptrunner/useScriptLifecycle'

const TITLES = {
  shortcuts: 'Keyboard Shortcuts',
  selection: 'Goto / Execute Selection',
  lifecycle: 'Script Lifecycle',
  versioning: 'Script Versioning',
}

const props = defineProps({
  // shortcuts, selection, lifecycle, or versioning
  topic: {
    type: String,
    required: true,
  },
  lifecycleEnabled: Boolean,
  versionsEnabled: Boolean,
})

const show = defineModel({ type: Boolean, required: true })

const content = computed(() => ({ title: TITLES[props.topic] }))

const states = Object.entries(LIFECYCLE_STATE_LABELS).map(([value, text]) => ({
  value,
  text,
}))

const keys = (...shortcuts) => shortcuts.map(formatShortcut)

const selectionSections = [
  {
    title: 'No script running',
    subtitle: 'Starts a new run',
    icon: 'mdi-play-outline',
    items: [
      {
        name: 'Execute Selection',
        text: 'Runs only the selected lines. Select the lines first, then right click.',
      },
      {
        name: 'Run From Line',
        text: 'Starts at the line the cursor is on and skips everything above it.',
      },
    ],
  },
  {
    title: 'Script paused',
    subtitle: 'Also at a breakpoint or stopped on an error',
    icon: 'mdi-pause',
    items: [
      {
        name: 'Execute Selection',
        text: 'Runs the selected lines inside the paused script so they can use its variables, then stays paused where it was. Handy for retrying a failed step.',
      },
      {
        name: 'Goto Line',
        text: 'Skips ahead (or back) and continues the script from the line the cursor is on.',
      },
    ],
  },
  {
    title: 'Related',
    icon: 'mdi-link-variant',
    items: [
      {
        name: 'Breakpoints',
        text: 'Click the line number gutter to add or remove one. The script pauses before running that line.',
      },
      {
        name: 'Insert / Edit Command',
        text: 'Opens a command builder and writes the line for you. Shows Edit Command when the cursor is on a cmd() line.',
      },
      {
        name: 'Debug Prompt',
        text: 'Script > Toggle Debug runs single statements in the running script. Use Up and Down to recall earlier ones.',
      },
    ],
  },
]

const shortcutGroups = [
  {
    title: 'Files',
    rows: [
      { action: 'Open File', keys: keys('Mod+O') },
      { action: 'Save File', keys: keys('Mod+S') },
      { action: 'Save As', keys: keys('Mod+Shift+S') },
    ],
  },
  {
    title: 'Open File Dialog',
    rows: [
      { action: 'Select the previous / next file', keys: ['↑', '↓'] },
      { action: 'Open the selected file', keys: ['Enter'] },
    ],
  },
  {
    title: 'Editor',
    rows: [
      { action: 'Find', keys: keys('Mod+F') },
      { action: 'Replace', keys: keys(isMac ? 'Mod+Alt+F' : 'Mod+H') },
      { action: 'Toggle Comment', keys: keys('Mod+/') },
      { action: 'Undo', keys: keys('Mod+Z') },
      { action: 'Redo', keys: keys(isMac ? 'Mod+Shift+Z' : 'Mod+Y') },
    ],
  },
  {
    title: 'File Explorer',
    rows: [
      { action: 'Move between files', keys: ['↑', '↓'] },
      { action: 'Open or close a folder', keys: ['←', '→'] },
      { action: 'Open the selected file', keys: ['Enter'] },
      { action: 'Save As', keys: ['Right Click'] },
    ],
  },
  {
    title: 'Debug Prompt',
    rows: [
      { action: 'Run the statement', keys: ['Enter'] },
      { action: 'Previous / next statement', keys: ['↑', '↓'] },
      { action: 'Clear', keys: ['Esc'] },
    ],
  },
]
</script>
