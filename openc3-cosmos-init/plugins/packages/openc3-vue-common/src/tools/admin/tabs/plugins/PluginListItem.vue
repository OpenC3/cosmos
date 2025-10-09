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
  <tr
    :class="{ 'cursor-pointer': hasDetails }"
    data-test="plugin-list-item"
    @click="openDetails"
  >
    <td>
      <v-img
        v-if="imageContentsWithMimeType"
        :src="imageContentsWithMimeType"
        max-height="56"
        min-width="56"
      />
    </td>
    <td>
      <div class="text-h6" v-text="displayTitle" />
      <div class="text-subtitle-2 v-list-item-subtitle pl-0">
        <!-- subtitle -->
        <template v-if="isModified"> * </template>
        {{ name }}
      </div>
      <div v-if="targets?.length">
        <!-- sub-subtitle -->
        <span v-for="(target, index) in targets" :key="index" class="mr-2">
          <a
            v-if="target.modified"
            style="cursor: pointer"
            @click.prevent="downloadTarget(target.name)"
            v-text="target.name"
          />
          <span v-else v-text="target.name" />
        </span>
      </div>
    </td>

    <td>
      <v-menu>
        <template #activator="{ props }">
          <v-icon
            v-bind="props"
            icon="mdi-dots-horizontal"
            data-test="plugin-actions"
          />
        </template>
        <v-list>
          <v-list-item
            title="Download"
            prepend-icon="mdi-download"
            data-test="download-plugin"
            @click="downloadPlugin"
          />
          <v-list-item
            title="Edit Details"
            prepend-icon="mdi-pencil"
            data-test="edit-plugin"
            @click="edit"
          />
          <v-list-item
            title="Upgrade"
            prepend-icon="mdi-update"
            data-test="upgrade-plugin"
            @click="upgrade"
          />
          <v-list-item
            title="Delete"
            prepend-icon="mdi-delete"
            data-test="delete-plugin"
            @click="deletePrompt"
          />
        </v-list>
      </v-menu>
    </td>
  </tr>
  <plugin-details-dialog
    v-model="showCard"
    v-bind="plugin"
    @trigger-uninstall="deletePrompt"
  />
</template>

<script>
import { Api } from '@openc3/js-common/services'
import { PluginDetailsDialog, PluginProps } from '@/plugins/plugin-store'

export default {
  components: {
    PluginDetailsDialog,
  },
  mixins: [PluginProps],
  props: {
    targets: {
      type: Array,
      default: () => {
        return []
      },
    },
    isModified: Boolean,
  },
  emits: ['edit', 'delete', 'upgrade'],
  data() {
    return {
      showCard: false,
    }
  },
  computed: {
    displayTitle: function () {
      if (this.title) {
        return this.title
      }
      return this.name
        .replace(/^openc3-cosmos-/, '')
        .replace(/-?\d+\.\d+\.\d+(?:\.pre\.beta\d+\.\d+)?\.gem(?:__\d+)?$/, '') // '-6.6.1.pre.beta0.20250801182255.gem__20250801182444' or '6.6.1.gem'
    },
  },
  methods: {
    openDetails: function () {
      if (this.hasDetails) {
        this.showCard = true
      }
    },
    downloadPlugin: function () {
      Api.post(`/openc3-api/packages/${this.name}/download`).then(
        (response) => {
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
        },
      )
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
    edit: function () {
      this.$emit('edit')
    },
    upgrade: function () {
      this.$emit('upgrade')
    },
    deletePrompt: function () {
      this.showCard = false
      this.$emit('delete')
    },
  },
}
</script>
