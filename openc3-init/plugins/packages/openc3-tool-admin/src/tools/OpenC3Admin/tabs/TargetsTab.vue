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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
-->

<template>
  <div>
    <v-list data-test="targetList">
      <div v-for="(target, index) in targets" :key="target">
        <v-list-item>
          <v-list-item-content>
            <v-list-item-title>{{ target.name }}</v-list-item-title>
            <v-list-item-subtitle
              >Plugin: {{ target.plugin }}</v-list-item-subtitle
            >
          </v-list-item-content>
          <v-list-item-icon>
            <div class="mx-3" v-if="target.modified">
              <v-tooltip bottom>
                <template v-slot:activator="{ on, attrs }">
                  <v-icon
                    @click="downloadTarget(target.name)"
                    v-bind="attrs"
                    v-on="on"
                  >
                    mdi-download
                  </v-icon>
                </template>
                <span>Download Target Modified Files</span>
              </v-tooltip>
            </div>
            <v-tooltip bottom>
              <template v-slot:activator="{ on, attrs }">
                <v-icon @click="showTarget(target)" v-bind="attrs" v-on="on">
                  mdi-eye
                </v-icon>
              </template>
              <span>Show Target Details</span>
            </v-tooltip>
          </v-list-item-icon>
        </v-list-item>
        <v-divider v-if="index < targets.length - 1" :key="index" />
      </div>
    </v-list>
    <edit-dialog
      v-model="showDialog"
      v-if="showDialog"
      :content="jsonContent"
      :title="`Target: ${dialogTitle}`"
      readonly
      @submit="dialogCallback"
    />
  </div>
</template>

<script>
import Api from '@openc3/tool-common/src/services/api'
import EditDialog from '@/tools/OpenC3Admin/EditDialog'
export default {
  components: { EditDialog },
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
    add() {},
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
