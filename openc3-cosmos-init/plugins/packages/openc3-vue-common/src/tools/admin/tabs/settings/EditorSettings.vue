<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card>
    <v-card-title> Code Editor Settings </v-card-title>
    <v-card-subtitle>
      Settings for the code editors built into COSMOS (e.g. in Script Runner).
      These settings are saved to your browser's local storage.
    </v-card-subtitle>
    <v-alert v-model="errorLoading" type="error" closable density="compact">
      Error loading previous configuration due to {{ errorText }}
    </v-alert>
    <v-alert v-model="errorSaving" type="error" closable density="compact">
      Error saving due to {{ errorText }}
    </v-alert>
    <v-alert v-model="successSaving" type="success" closable density="compact">
      Saved! (Refresh the page to see changes)
    </v-alert>
    <v-card-text class="pb-0">
      <v-select
        v-model="defaultLanguage"
        label="Default scripting language"
        :items="languageOptions"
        item-title="text"
        item-value="value"
        color="primary"
        class="mt-4"
        data-test="default-language"
      />
      <v-switch v-model="vimMode" label="Vim mode" color="primary" />
      <v-switch
        v-model="scriptLockingEnabled"
        label="Script File Locking - When enabled, a script being edited
        by one user is read-only for other users until they explicitly force
        unlock. Disable to allow multiple users to edit the same script
        concurrently (last save wins)."
        color="primary"
        data-test="script-locking-enabled"
      />
    </v-card-text>
    <v-card-actions>
      <v-btn
        color="success"
        variant="text"
        data-test="save-editor-settings"
        @click="save"
      >
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import { AceEditorUtils } from '@/components/ace'
import Settings from './settings.js'

const SCRIPT_LOCKING_SETTING = 'script_runner_locking'

export default {
  mixins: [Settings],
  data() {
    return {
      vimMode: AceEditorUtils.isVimModeEnabled(),
      scriptLockingEnabled: true,
      defaultLanguage: AceEditorUtils.getDefaultScriptingLanguage(),
      languageOptions: [
        { text: 'Ruby', value: 'ruby' },
        { text: 'Python', value: 'python' },
      ],
    }
  },
  created() {
    this.loadSetting(SCRIPT_LOCKING_SETTING)
  },
  methods: {
    save: function () {
      AceEditorUtils.setVimMode(this.vimMode)
      AceEditorUtils.setDefaultScriptingLanguage(this.defaultLanguage)
      this.saveSetting(SCRIPT_LOCKING_SETTING, this.scriptLockingEnabled)
    },
    parseSetting: function (response) {
      if (response !== null && response !== undefined) {
        this.scriptLockingEnabled = response
      }
    },
  },
}
</script>
