<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-list class="list" data-test="targetList">
      <div v-for="target in targets" :key="target">
        <v-list-item>
          <v-list-item-title>{{ target.name }}</v-list-item-title>
          <v-list-item-subtitle
            >Plugin: {{ target.plugin }}</v-list-item-subtitle
          >

          <template #append>
            <div v-if="target.modified" class="mx-3">
              <v-tooltip location="top">
                <template #activator="{ props }">
                  <v-icon v-bind="props" @click="downloadTarget(target.name)">
                    mdi-download
                  </v-icon>
                </template>
                <span>Download Target Modified Files</span>
              </v-tooltip>
            </div>
            <v-tooltip location="top">
              <template #activator="{ props }">
                <v-icon v-bind="props" @click="showTarget(target.name)">
                  mdi-eye
                </v-icon>
              </template>
              <span>Show Target Details</span>
            </v-tooltip>
          </template>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <output-dialog
      v-if="showDialog"
      v-model="showDialog"
      :content="jsonContent"
      type="Target"
      :name="dialogTitle"
      @submit="dialogCallback"
    />
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import { OutputDialog } from '@/components'

export default {
  components: { OutputDialog },
  data() {
    return {
      targets: [],
      jsonContent: '',
      dialogTitle: '',
      showDialog: false,
    }
  },
  mounted() {
    this.update()
  },
  methods: {
    update() {
      Api.get('/openc3-api/targets_modified').then((response) => {
        this.targets = response.data
      })
    },
    showTarget(name) {
      Api.get(`/openc3-api/targets/${name}`).then((response) => {
        this.jsonContent = JSON.stringify(response.data, null, '\t')
        this.dialogTitle = name
        this.showDialog = true
      })
    },
    dialogCallback(content) {
      this.showDialog = false
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
  },
}
</script>

<style scoped>
.list {
  background-color: var(--color-background-surface-default) !important;
  overflow-x: hidden;
}
.v-theme--cosmosDark.v-list div:nth-child(odd) .v-list-item {
  background-color: var(--color-background-base-selected) !important;
}
</style>
