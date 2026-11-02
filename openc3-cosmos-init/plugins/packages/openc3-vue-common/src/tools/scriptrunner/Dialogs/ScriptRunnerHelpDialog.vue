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
          <p class="mb-3">
            Right click in the editor to run part of a script instead of the
            whole thing. What the menu offers depends on whether a script is
            running.
          </p>
          <div class="text-overline mt-3">When no script is running</div>
          <ul class="ps-5 mb-2">
            <li class="mb-2">
              <strong>Execute Selection</strong> starts the script but runs only
              the selected lines. Select the lines first, then right click.
            </li>
            <li class="mb-2">
              <strong>Run From Line</strong> starts the script at the line the
              cursor is on and skips everything above it.
            </li>
          </ul>
          <div class="text-overline mt-3">
            While a script is paused, at a breakpoint, or stopped on an error
          </div>
          <ul class="ps-5 mb-2">
            <li class="mb-2">
              <strong>Execute Selection</strong> runs the selected lines inside
              the paused script, so they can use its variables. When they finish
              the script stays paused where it was. This is a handy way to retry
              a failed step.
            </li>
            <li class="mb-2">
              <strong>Goto Line</strong> skips ahead (or back) and continues the
              script from the line the cursor is on.
            </li>
          </ul>
          <div class="text-overline mt-3">Related</div>
          <ul class="ps-5 mb-2">
            <li class="mb-2">
              Click the line number gutter to add or remove a breakpoint. The
              script pauses before running that line.
            </li>
            <li class="mb-2">
              <strong>Insert Command</strong> (or
              <strong>Edit Command</strong> when the cursor is on a
              <code>cmd()</code> line) opens a command builder and writes the
              line for you.
            </li>
            <li class="mb-2">
              The Debug prompt (Script &gt; Toggle Debug) runs single statements
              in the running script. Use Up and Down to recall earlier ones.
            </li>
          </ul>
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

const shortcutGroups = [
  {
    title: 'Files',
    rows: [
      { action: 'Open File', keys: keys('Mod+O') },
      { action: 'Quick Open', keys: keys('Mod+P') },
      { action: 'Save File', keys: keys('Mod+S') },
      { action: 'Save As', keys: keys('Mod+Shift+S') },
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
