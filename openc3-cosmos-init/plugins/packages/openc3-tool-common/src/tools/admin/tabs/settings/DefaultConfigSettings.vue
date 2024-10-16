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
    <v-card-title> Clear default configs </v-card-title>
    <v-card-subtitle>
      This clears the default tool configs on this browser
    </v-card-subtitle>
    <v-card-text>
      <template v-if="lastConfigs.length">
        <v-checkbox
          v-model="selectAllLastConfigs"
          label="Select All Configs"
          density="compact"
        />
        <v-checkbox
          v-for="config in lastConfigs"
          :key="config.key"
          v-model="selectedLastConfigs"
          :label="config.text"
          :value="config.key"
          hide-details
          density="compact"
        />
      </template>
      <template v-else> No configs to clear </template>
    </v-card-text>
    <v-card-actions>
      <v-btn
        :disabled="!selectedLastConfigs.length"
        @click="clearLastConfigs"
        color="warning"
        variant="text"
        class="ml-2"
        data-test="clear-default-configs"
      >
        Clear
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
export default {
  data() {
    return {
      lastConfigs: [],
      selectedLastConfigs: [],
      selectAllLastConfigs: false,
    }
  },
  watch: {
    selectAllLastConfigs: function (val) {
      if (val) {
        this.selectedLastConfigs = this.lastConfigs.map((config) => config.key)
      } else {
        this.selectedLastConfigs = []
      }
    },
  },
  created() {
    this.loadLastConfigs()
  },
  methods: {
    loadLastConfigs: function () {
      this.lastConfigs = Object.keys(localStorage)
        .filter((key) => {
          return key.endsWith('__default')
        })
        .map((key) => {
          const name = key.split('__')[0].replaceAll('_', ' ')
          return {
            key,
            text: name.charAt(0).toUpperCase() + name.slice(1),
          }
        })
      this.selectedLastConfigs = []
    },
    clearLastConfigs: function () {
      this.deleteLocalStorageKeys(this.selectedLastConfigs)
      this.loadLastConfigs()
    },
    deleteLocalStorageKeys: function (keys) {
      for (const key of keys) {
        delete localStorage[key]
      }
    },
  },
}
</script>
