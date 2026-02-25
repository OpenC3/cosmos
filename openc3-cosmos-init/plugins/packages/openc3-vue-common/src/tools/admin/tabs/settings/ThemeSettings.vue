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
    <v-card-title>Theme</v-card-title>
    <v-alert v-model="errorLoading" type="error" closable density="compact">
      Error loading previous configuration due to {{ errorText }}
    </v-alert>
    <v-alert v-model="errorSaving" type="error" closable density="compact">
      Error saving due to {{ errorText }}
    </v-alert>
    <v-alert v-model="successSaving" type="success" closable density="compact">
      Saved! (Refresh the page to see changes)
    </v-alert>
    <v-card-text class="pt-4 pb-0">
      <v-select
        v-model="selectedTheme"
        label="Theme"
        :items="themeOptions"
        item-title="label"
        item-value="value"
        data-test="theme-select"
      />
    </v-card-text>
    <v-card-actions>
      <v-btn
        color="success"
        variant="text"
        data-test="save-theme-settings"
        @click="save"
      >
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import Settings from './settings.js'
const settingName = 'theme'
export default {
  mixins: [Settings],
  data() {
    return {
      selectedTheme: 'cosmosDark',
      themeOptions: [
        { label: 'Astro (Default)', value: 'cosmosDark' },
        { label: 'Dark Cobalt', value: 'cosmosDarkCobalt' },
        { label: 'Dark Indigo', value: 'cosmosDarkIndigo' },
        { label: 'Dark Slate', value: 'cosmosDarkSlate' },
        { label: 'Dark Emerald', value: 'cosmosDarkEmerald' },
      ],
    }
  },
  created() {
    this.loadSetting(settingName)
  },
  methods: {
    save() {
      this.saveSetting(settingName, this.selectedTheme)
    },
    parseSetting(response) {
      if (response) {
        this.selectedTheme = response
      }
    },
  },
}
</script>
