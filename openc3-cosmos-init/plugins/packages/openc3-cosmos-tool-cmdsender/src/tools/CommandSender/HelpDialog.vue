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

<!-- Help dialogs opened from the Command Sender Help menu -->
<template>
  <v-dialog v-model="show" scrollable width="760">
    <v-card class="cs-help" :data-test="`help-dialog-${topic}`">
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
            Page shortcuts are ignored while typing in a field or while a dialog
            is open. None of them send a command: only the Send button does.
          </p>
        </template>

        <!-- Using Command Sender -->
        <template v-else-if="topic === 'guide'">
          <div class="text-overline">Sending a command</div>
          <p class="mb-2">
            Select a target and packet, fill in the parameters and press
            <strong>Send</strong>. Send is the only way to send: loading a
            command from the history or a paste only fills in the form.
          </p>
          <ul class="ps-5 mb-4">
            <li class="mb-1">
              Required parameters must be set before the command is sent.
            </li>
            <li class="mb-1">
              The <strong>Mode</strong> menu decides how every command is sent,
              e.g. without range checks or parameter conversions.
            </li>
            <li class="mb-1">
              Select a <strong>Queue</strong> to send the command to a command
              queue instead of directly to the target.
            </li>
            <li class="mb-1">
              The status next to Send shows the result, with a count when the
              same command is sent again.
            </li>
          </ul>

          <div class="text-overline">Hazardous commands</div>
          <p class="mb-2">
            Command Sender checks the command as the parameters change. A
            hazardous command, or a hazardous state outlines the form in yellow
            and turns Send yellow before it is pressed. The hazardous
            description is shown next to Send.
          </p>
          <ul class="ps-5 mb-4">
            <li class="mb-1">
              Pressing Send asks to confirm. <strong>Cancel</strong> (or Esc)
              doesn't send anything.
            </li>
            <li class="mb-1">
              <strong>Ignore Range Checks</strong> and
              <strong>Disable Parameter Conversions</strong> make every command
              hazardous, since either can bypass what makes a command safe.
            </li>
            <li class="mb-1">
              (Enterprise) Critical commands are queued until enough users
              approve them. Approved commands are added to the history.
            </li>
          </ul>

          <div class="text-overline">History</div>
          <ul class="ps-5 mb-4">
            <li class="mb-1">
              Every command sent is listed, newest first, with the time it was
              sent. Sending a command again adds another entry.
            </li>
            <li class="mb-1">
              <strong>Click</strong> a command to load it into the form with all
              its parameters. Review or change them, then press Send.
            </li>
            <li class="mb-1">
              The copy button copies the command, ready to paste into a script.
            </li>
            <li class="mb-1">
              Obfuscated parameters show as ***** and must be entered again
              after loading.
            </li>
            <li class="mb-1">
              The history is kept in this browser until it is cleared.
            </li>
          </ul>

          <div class="text-overline">Pasting a command</div>
          <p class="mb-2">
            Click the clipboard button next to Send, choose
            <strong>File &gt; Paste Command</strong>, or press
            <v-kbd>{{ pasteKey }}</v-kbd> with no field selected. Paste a
            command as written in a script and press Load to fill in the form.
          </p>
          <ul class="ps-5 mb-2">
            <li class="mb-1">
              <code>cmd("INST COLLECT with TYPE 'NORMAL'")</code> and the bare
              <code>INST COLLECT with TYPE 'NORMAL'</code> both work.
            </li>
            <li class="mb-1">
              A <code>queue</code> keyword selects that queue.
            </li>
            <li class="mb-1">
              The method (e.g. <code>cmd_no_range_check</code>) and
              <code>validate</code> are not applied: the Mode menu decides
              those, and the status says what was skipped.
            </li>
          </ul>
        </template>
      </v-card-text>
      <v-card-actions class="px-2">
        <v-btn
          v-if="topic === 'guide'"
          variant="text"
          append-icon="mdi-open-in-new"
          href="/tools/staticdocs/docs/tools/cmd-sender"
          target="_blank"
          text="Command Sender documentation"
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
import { formatShortcut } from '@openc3/vue-common/util'

const TITLES = {
  shortcuts: 'Keyboard Shortcuts',
  guide: 'Using Command Sender',
}

defineProps({
  // shortcuts or guide
  topic: { type: String, required: true },
})
const show = defineModel({ type: Boolean, required: true })

const pasteKey = formatShortcut('Mod+V')

const shortcutGroups = [
  {
    title: 'Command Sender',
    rows: [
      {
        action: 'Paste a command into the paste box',
        keys: [pasteKey],
      },
      {
        action: 'Load the next older command in the history',
        keys: [formatShortcut('Alt+↓')],
      },
      {
        action: 'Load the next newer command in the history',
        keys: [formatShortcut('Alt+↑')],
      },
    ],
  },
  {
    title: 'Paste Box',
    rows: [
      { action: 'Load the command into the form', keys: ['Enter'] },
      { action: 'Close without loading', keys: ['Esc'] },
    ],
  },
  {
    title: 'Parameters',
    rows: [
      { action: 'Move to the next field', keys: ['Tab'] },
      { action: 'Pick the best matching state', keys: ['Enter'] },
    ],
  },
  {
    title: 'Hazardous Warning',
    rows: [{ action: "Cancel, the command isn't sent", keys: ['Esc'] }],
  },
]
</script>

<style scoped>
/* The dialog is teleported out of Command Sender, so it sets its type. The
   typography classes set Roboto, so they inherit it instead. */
.cs-help {
  font-family: 'IBM Plex Sans', system-ui, sans-serif;
  font-size: 14px;
  line-height: 1.5;
}
.cs-help .text-overline,
.cs-help .text-caption,
.cs-help :deep(.v-table) {
  font-family: inherit;
}
.cs-help code {
  padding: 0.1em 0.35em;
  border-radius: 4px;
  background: rgba(var(--v-theme-on-surface), 0.08);
  font-family: 'IBM Plex Mono', ui-monospace, monospace;
  font-size: 0.9em;
}
</style>
