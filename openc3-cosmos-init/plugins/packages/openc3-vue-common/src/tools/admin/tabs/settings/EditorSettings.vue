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
      <template v-if="isEnterprise">
        <v-alert
          v-if="!gitHistoryEnabled"
          type="info"
          density="compact"
          class="mb-2"
        >
          The Script Lifecycle requires the Version History git store, which is
          not configured on this server (set OPENC3_VERSION_HISTORY_DIR).
          Enabling this setting has no effect until it is available.
        </v-alert>
        <v-switch
          v-model="lifecycleEnabled"
          :disabled="!gitHistoryEnabled"
          label="Script Lifecycle - When enabled, scripts are tracked through
          In Development, In Review, and Approved states. Users with the script_edit permission
          can move scripts to In Review, and users with the script_approver permission may approve scripts.
          Approved scripts cannot be modified or deleted, and users with only the runner
          permission can only run approved scripts."
          color="primary"
          data-test="script-lifecycle-enabled"
        />
      </template>
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
import { Api } from '@openc3/js-common/services'
import { AceEditorUtils } from '@/components/ace'
import Settings from './settings.js'

const SCRIPT_LOCKING_SETTING = 'script_runner_locking'
const SCRIPT_LIFECYCLE_SETTING = 'script_runner_lifecycle'

export default {
  mixins: [Settings],
  data() {
    return {
      vimMode: AceEditorUtils.isVimModeEnabled(),
      scriptLockingEnabled: true,
      // Script Lifecycle is Enterprise-only and inert without the git-backed
      // version store, so gate the control on both (info.enterprise and
      // info.script_versions, the latter reflecting OPENC3_VERSION_HISTORY_DIR).
      lifecycleEnabled: false,
      isEnterprise: false,
      gitHistoryEnabled: false,
      defaultLanguage: AceEditorUtils.getDefaultScriptingLanguage(),
      languageOptions: [
        { text: 'Ruby', value: 'ruby' },
        { text: 'Python', value: 'python' },
      ],
    }
  },
  created() {
    this.loadSetting(SCRIPT_LOCKING_SETTING)
    this.loadSetting(SCRIPT_LIFECYCLE_SETTING)
    Api.get('/openc3-api/info').then(({ data }) => {
      this.isEnterprise = data.enterprise === true
      this.gitHistoryEnabled = data.script_versions === true
    })
  },
  methods: {
    save: function () {
      AceEditorUtils.setVimMode(this.vimMode)
      AceEditorUtils.setDefaultScriptingLanguage(this.defaultLanguage)
      this.saveSetting(SCRIPT_LOCKING_SETTING, this.scriptLockingEnabled)
      if (this.isEnterprise) {
        this.saveSetting(SCRIPT_LIFECYCLE_SETTING, this.lifecycleEnabled)
      }
    },
    parseSetting: function (response, kwparams) {
      if (response === null || response === undefined) {
        return
      }
      if (kwparams?.setting === SCRIPT_LIFECYCLE_SETTING) {
        this.lifecycleEnabled = response
      } else {
        this.scriptLockingEnabled = response
      }
    },
  },
}
</script>
