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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-row no-gutters align="center" class="px-2">
      <v-col class="pa-2 mt-2">
        <v-btn @click="selectFile">Install Package</v-btn>
        <input
          ref="fileInput"
          style="display: none"
          type="file"
          @change="fileChange"
        />
      </v-col>
      <v-col class="ml-4 mr-2" cols="4">
        <rux-progress :value="progress"></rux-progress>
      </v-col>
    </v-row>
    <v-list
      v-if="Object.keys(processes).length > 0"
      class="list"
      data-test="process-list"
    >
      <v-row no-gutters class="px-4">
        <v-col class="text-h6">Process List</v-col>
        <v-col align="right">
          <!-- See openc3/lib/openc3/utilities/process_manager.rb CLEANUP_CYCLE_SECONDS -->
          <div>Showing last 10 min of activity</div>
        </v-col>
      </v-row>
      <div v-for="process in processes" :key="process.name">
        <v-list-item>
          <v-list-item-title>
            <span
              :class="process.state.toLowerCase()"
              v-text="
                `Processing ${process.process_type}: ${process.detail} - ${process.state}`
              "
            />
          </v-list-item-title>
          <v-list-item-subtitle>
            <span v-text="' Updated At: ' + formatDate(process.updated_at)" />
          </v-list-item-subtitle>

          <template v-if="process.state !== 'Running'" #append>
            <v-tooltip :open-delay="600" location="top">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  icon="mdi-eye"
                  variant="text"
                  @click="showOutput(process)"
                />
              </template>
              <span>Show Output</span>
            </v-tooltip>
          </template>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <v-list class="list" data-test="packageList">
      <v-row class="px-4"><v-col class="text-h6">Ruby Gems</v-col></v-row>
      <div v-for="(gem, index) in gems" :key="index">
        <v-list-item>
          <v-list-item-title>{{ gem }}</v-list-item-title>

          <template #append>
            <v-btn
              icon="mdi-delete"
              variant="text"
              @click="deletePackage(gem)"
            />
          </template>
        </v-list-item>
        <v-divider />
      </div>
      <v-row class="px-4"><v-col class="text-h6">Python Packages</v-col></v-row>
      <div v-for="(pkg, index) in python" :key="index">
        <v-list-item>
          <v-list-item-title>{{ pkg }}</v-list-item-title>

          <template #append>
            <v-btn
              icon="mdi-delete"
              variant="text"
              @click="deletePackage(pkg)"
            />
          </template>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <download-dialog v-model="showDownloadDialog" />
    <simple-text-dialog
      v-model="showProcessOutput"
      title="Process Output"
      :text="processOutput"
    />
  </div>
</template>

<script>
import { toDate, format } from 'date-fns'
import { Api } from '@openc3/js-common/services'
import { SimpleTextDialog } from '@/components'
import { DownloadDialog } from '@/tools/admin'

export default {
  components: {
    DownloadDialog,
    SimpleTextDialog,
  },
  data() {
    return {
      showDownloadDialog: false,
      showProcessOutput: false,
      processOutput: '',
      files: [],
      loadingPackage: false,
      progress: 0,
      gems: [],
      python: [],
      processes: {},
    }
  },
  mounted() {
    this.update()
    this.updateProcesses()
  },
  methods: {
    showOutput: function (process) {
      this.processOutput = process.output
      this.showProcessOutput = true
    },
    update() {
      Api.get('/openc3-api/packages').then((response) => {
        this.gems = response.data.ruby
        this.python = response.data.python
      })
    },
    updateProcesses: function () {
      Api.get('/openc3-api/process_status/package_?substr=true').then(
        (response) => {
          this.processes = response.data
          if (Object.keys(this.processes).length > 0) {
            // process_manager.rb script operates on a 5 second cycle
            setTimeout(() => {
              this.updateProcesses()
              this.update()
            }, 2500)
          }
        },
      )
    },
    formatDate(nanoSecs) {
      return format(
        toDate(parseInt(nanoSecs) / 1000000),
        'yyyy-MM-dd HH:mm:ss.SSS',
      )
    },
    selectFile() {
      this.progress = 0
      this.$refs.fileInput.click()
    },
    fileChange(event) {
      const files = event.target.files
      if (files.length > 0) {
        this.loadingPackage = true
        let self = this
        const promises = [...files].map((file) => {
          const formData = new FormData()
          formData.append('package', file, file.name)
          return Api.post('/openc3-api/packages', {
            data: formData,
            headers: { 'Content-Type': 'multipart/form-data' },
            onUploadProgress: function (progressEvent) {
              let percentCompleted = Math.round(
                (progressEvent.loaded * 100) / progressEvent.total,
              )
              self.progress = percentCompleted
            },
          })
        })
        Promise.all(promises)
          .then((responses) => {
            this.$notify.normal({
              body: `Uploaded ${responses.length} package${
                responses.length > 1 ? 's' : ''
              }`,
            })
            this.loadingPackage = false
            this.files = []
            setTimeout(() => {
              this.updateProcesses()
            }, 2500)
          })
          .catch((error) => {
            this.loadingPackage = false
          })
      }
    },
    deletePackage(pkg) {
      this.$dialog
        .confirm(`Are you sure you want to remove: ${pkg}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          return Api.delete(`/openc3-api/packages/${pkg}`)
        })
        .then((response) => {
          this.$notify.normal({
            body: `Removed package ${pkg}`,
          })
          setTimeout(() => {
            this.updateProcesses()
          }, 2500)
        })
        // Error will probably never happen because we spawn the package removal
        // and then wait for the response which happens in the background
        .catch((error) => {
          this.$notify.serious({
            body: `Failed to remove package ${pkg}`,
          })
        })
    },
  },
}
</script>

<style scoped>
.v-subheader {
  font-size: 1rem;
}
.list {
  background-color: var(--color-background-surface-default) !important;
  overflow-x: hidden;
}
.v-theme--cosmosDark.v-list div:nth-child(odd) .v-list-item {
  background-color: var(--color-background-base-selected) !important;
}
</style>
