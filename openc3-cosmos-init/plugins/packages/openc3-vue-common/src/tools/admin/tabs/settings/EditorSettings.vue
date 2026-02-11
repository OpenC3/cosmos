<!--
# Copyright 2025 OpenC3, Inc.
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
      Settings for the code editors built into COSMOS (e.g. in Script Runner)
    </v-card-subtitle>
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

export default {
  data() {
    return {
      vimMode: AceEditorUtils.isVimModeEnabled(),
      defaultLanguage: AceEditorUtils.getDefaultScriptingLanguage(),
      languageOptions: [
        { text: 'Ruby', value: 'ruby' },
        { text: 'Python', value: 'python' },
      ],
    }
  },
  methods: {
    save: function () {
      AceEditorUtils.setVimMode(this.vimMode)
      AceEditorUtils.setDefaultScriptingLanguage(this.defaultLanguage)
    },
  },
}
</script>
