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
    <v-card-title> Script Lifecycle Settings </v-card-title>
    <v-card-subtitle>
      Track scripts through In Development, In Review, and Approved lifecycle
      states in Script Runner.
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
      <v-switch
        v-model="lifecycleEnabled"
        label="Script Lifecycle - When enabled, scripts are tracked through
        In Development, In Review, and Approved states. Operators can move
        scripts between development and review, but only admins can approve
        scripts or move approved scripts back to review. Approved scripts
        cannot be modified or deleted, and users with only the runner
        permission can only run approved scripts."
        color="primary"
        data-test="script-lifecycle-enabled"
      />
    </v-card-text>
    <v-card-actions>
      <v-btn
        color="success"
        variant="text"
        data-test="save-script-lifecycle-settings"
        @click="save"
      >
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import Settings from './settings.js'

const SCRIPT_LIFECYCLE_SETTING = 'script_runner_lifecycle'

export default {
  mixins: [Settings],
  data() {
    return {
      lifecycleEnabled: false,
    }
  },
  created() {
    this.loadSetting(SCRIPT_LIFECYCLE_SETTING)
  },
  methods: {
    save: function () {
      this.saveSetting(SCRIPT_LIFECYCLE_SETTING, this.lifecycleEnabled)
    },
    parseSetting: function (response) {
      if (response !== null && response !== undefined) {
        this.lifecycleEnabled = response
      }
    },
  },
}
</script>
