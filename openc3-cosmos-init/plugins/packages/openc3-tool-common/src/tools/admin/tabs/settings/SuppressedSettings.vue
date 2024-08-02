<!--
# Copyright 2024 OpenC3, Inc.
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
    <v-card-title>Reset suppressed warnings</v-card-title>
    <v-card-subtitle>
      This resets "don't show this again" dialogs on this browser
    </v-card-subtitle>
    <v-card-text>
      <template v-if="suppressedWarnings.length">
        <v-checkbox
          v-model="selectAllSuppressedWarnings"
          label="Select all"
          class="mt-0"
          data-test="select-all-suppressed-warnings"
        />
        <v-checkbox
          v-for="warning in suppressedWarnings"
          :key="warning.key"
          v-model="selectedSuppressedWarnings"
          :label="warning.text"
          :value="warning.key"
          class="mt-0"
          dense
        />
      </template>
      <template v-else> No warnings to reset </template>
    </v-card-text>
    <v-card-actions>
      <v-btn
        :disabled="!selectedSuppressedWarnings.length"
        @click="resetSuppressedWarnings"
        color="warning"
        text
        class="ml-2"
        data-test="reset-suppressed-warnings"
      >
        Reset
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
export default {
  data() {
    return {
      suppressedWarnings: [],
      selectedSuppressedWarnings: [],
      selectAllSuppressedWarnings: false,
    }
  },
  watch: {
    selectAllSuppressedWarnings: function (val) {
      if (val) {
        this.selectedSuppressedWarnings = this.suppressedWarnings.map(
          (warning) => warning.key,
        )
      } else {
        this.selectedSuppressedWarnings = []
      }
    },
  },
  created() {
    this.loadSuppressedWarnings()
  },
  methods: {
    loadSuppressedWarnings: function () {
      this.suppressedWarnings = Object.keys(localStorage)
        .filter((key) => {
          return key.startsWith('suppresswarning__')
        })
        .map(this.localStorageKeyToDisplayObject)
      this.selectedSuppressedWarnings = []
    },
    localStorageKeyToDisplayObject: function (key) {
      const name = key.split('__')[1].replaceAll('_', ' ')
      return {
        key,
        text: name.charAt(0).toUpperCase() + name.slice(1),
        value: localStorage[key],
      }
    },
    resetSuppressedWarnings: function () {
      this.deleteLocalStorageKeys(this.selectedSuppressedWarnings)
      this.loadSuppressedWarnings()
    },
    deleteLocalStorageKeys: function (keys) {
      for (const key of keys) {
        delete localStorage[key]
      }
    },
  },
}
</script>
