<!--
# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

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
    }
  },
  methods: {
    save: function () {
      AceEditorUtils.setVimMode(this.vimMode)
    },
  },
}
</script>
