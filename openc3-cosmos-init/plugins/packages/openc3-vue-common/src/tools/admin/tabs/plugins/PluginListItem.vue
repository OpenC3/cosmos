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
  <v-list-item data-test="plugin-list-item">
    <v-list-item-title>
      <template v-if="isModified"> * </template>
      {{ plugin.name }}
    </v-list-item-title>
    <v-list-item-subtitle v-if="pluginTargets(plugin.name).length !== 0">
      <span
        v-for="(target, index) in pluginTargets(plugin.name)"
        :key="index"
        class="mr-2"
      >
        <a
          v-if="target.modified"
          @click.prevent="downloadTarget(target.name)"
        >
          {{ target.name }}
        </a>
        <span v-else> {{ target.name }} </span>
      </span>
    </v-list-item-subtitle>

    <template v-slot:append>
      <div class="mx-3">
        <v-tooltip location="top">
          <template v-slot:activator="{ props }">
            <v-icon
              v-bind="props"
              @click="downloadPlugin"
              icon="mdi-download"
              data-test="download-plugin"
            />
          </template>
          <span> Download Plugin </span>
        </v-tooltip>
      </div>
      <div class="mx-3">
        <v-tooltip location="top">
          <template v-slot:activator="{ props }">
            <v-icon
              v-bind="props"
              @click="editPlugin"
              icon="mdi-pencil"
              data-test="edit-plugin"
            />
          </template>
          <span> Edit Plugin Details </span>
        </v-tooltip>
      </div>
      <div class="mx-3">
        <v-tooltip location="top">
          <template v-slot:activator="{ props }">
            <v-icon
              v-bind="props"
              @click="upgradePlugin"
              icon="mdi-update"
              data-test="upgrade-plugin"
            />
          </template>
          <span> Upgrade Plugin </span>
        </v-tooltip>
      </div>
      <div class="mx-3">
        <v-tooltip location="top">
          <template v-slot:activator="{ props }">
            <v-icon
              v-bind="props"
              @click="deletePrompt"
              icon="mdi-delete"
              data-test="delete-plugin"
            />
          </template>
          <span> Delete Plugin </span>
        </v-tooltip>
      </div>
    </template>
  </v-list-item>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import PluginTargets from './PluginTargets'

export default {
  mixins: [PluginTargets],
  emits: ['edit', 'upgrade'],
  props: {
    plugin: Object,
    isModified: Boolean,
  },
  methods: {
    downloadPlugin: function () {
      Api.post(`/openc3-api/packages/${this.plugin.name}/download`).then((response) => {
        // Decode Base64 string
        const decodedData = window.atob(response.data.contents)
        // Create UNIT8ARRAY of size same as row data length
        const uInt8Array = new Uint8Array(decodedData.length)
        // Insert all character code into uInt8Array
        for (let i = 0; i < decodedData.length; ++i) {
          uInt8Array[i] = decodedData.charCodeAt(i)
        }
        const blob = new Blob([uInt8Array], { type: 'application/zip' })
        const link = document.createElement('a')
        link.href = URL.createObjectURL(blob)
        link.setAttribute('download', response.data.filename)
        link.click()
      })
    },
    downloadTarget: function (name) {
      Api.post(`/openc3-api/targets/${name}/download`).then((response) => {
        // Decode Base64 string
        const decodedData = window.atob(response.data.contents)
        // Create UNIT8ARRAY of size same as row data length
        const uInt8Array = new Uint8Array(decodedData.length)
        // Insert all character code into uInt8Array
        for (let i = 0; i < decodedData.length; ++i) {
          uInt8Array[i] = decodedData.charCodeAt(i)
        }
        const blob = new Blob([uInt8Array], { type: 'application/zip' })
        const link = document.createElement('a')
        link.href = URL.createObjectURL(blob)
        link.setAttribute('download', response.data.filename)
        link.click()
      })
    },
    editPlugin: function () {
      this.$emit('edit')
    },
    upgradePlugin: function () {
      this.$emit('upgrade')
    },
  },
}
</script>
