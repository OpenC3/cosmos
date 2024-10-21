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
    <v-row no-gutters align="center" class="px-2">
      <v-col>
        <v-file-input
          v-model="files"
          multiple
          show-size
          accept=".gem,.gz,.zip,.whl"
          class="mx-2"
          label="Click to select file(s) to add to COSMOS"
          ref="fileInput"
        />
      </v-col>
      <v-col class="ml-4 mr-2" cols="4">
        <rux-progress :value="progress"></rux-progress>
      </v-col>
      <v-btn
        @click="upload()"
        class="mx-2"
        color="primary"
        data-test="packageUpload"
        :disabled="files.length < 1"
        :loading="loadingPackage"
      >
        <v-icon start theme="dark">mdi-cloud-upload</v-icon>
        <span> Upload </span>
        <template v-slot:loader>
          <span>Loading...</span>
        </template>
      </v-btn>
    </v-row>
    <v-alert v-model="showAlert" closable :type="alertType">{{
      alert
    }}</v-alert>
    <v-list
      v-if="Object.keys(processes).length > 0"
      class="list"
      data-test="process-list"
    >
      <v-row no-gutters class="px-4"
        ><v-col class="text-h6">Process List</v-col>
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

          <template v-slot:append v-if="process.state !== 'Running'">
            <v-tooltip location="bottom">
              <template v-slot:activator="{ props }">
                <v-icon v-bind="props" @click="showOutput(process)">
                  mdi-eye
                </v-icon>
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

          <template v-slot:append>
            <v-tooltip location="bottom">
              <template v-slot:activator="{ props }">
                <v-icon v-bind="props" @click="deletePackage(gem)">
                  mdi-delete
                </v-icon>
              </template>
              <span>Delete Package</span>
            </v-tooltip>
          </template>
        </v-list-item>
        <v-divider />
      </div>
      <v-row class="px-4"><v-col class="text-h6">Python Packages</v-col></v-row>
      <div v-for="(pkg, index) in python" :key="index">
        <v-list-item>
          <v-list-item-title>{{ pkg }}</v-list-item-title>

          <template v-slot:append>
            <v-tooltip location="bottom">
              <template v-slot:activator="{ props }">
                <v-icon v-bind="props" @click="deletePackage(pkg)">
                  mdi-delete
                </v-icon>
              </template>
              <span>Delete Package</span>
            </v-tooltip>
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
import Api from '../../../services/api'
import DownloadDialog from '../DownloadDialog'
import SimpleTextDialog from '../../../components/SimpleTextDialog'

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
      alert: '',
      alertType: 'success',
      showAlert: false,
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
            setTimeout(() => {
              this.updateProcesses()
              this.update()
            }, 10000)
          }
        },
      )
    },
    formatDate(nanoSecs) {
      return format(
        toDate(parseInt(nanoSecs) / 1_000_000),
        'yyyy-MM-dd HH:mm:ss.SSS',
      )
    },
    upload: function () {
      this.loadingPackage = true
      this.progress = 0
      let self = this
      const promises = this.files.map((file) => {
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
          this.progress = 100
          this.alert = `Uploaded ${responses.length} package${
            responses.length > 1 ? 's' : ''
          }`
          this.alertType = 'success'
          this.showAlert = true
          this.loadingPackage = false
          this.files = []
          setTimeout(() => {
            this.showAlert = false
            this.updateProcesses()
          }, 5000)
          this.update()
        })
        .catch((error) => {
          this.loadingPackage = false
        })
    },
    deletePackage: function (pkg) {
      this.$dialog
        .confirm(`Are you sure you want to remove: ${pkg}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then(function (dialog) {
          return Api.delete(`/openc3-api/packages/${pkg}`)
        })
        .then((response) => {
          this.alert = `Removed package ${pkg}`
          this.alertType = 'success'
          this.showAlert = true
          setTimeout(() => {
            this.showAlert = false
          }, 5000)
          this.update()
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
}
.v-theme--cosmosDark.v-list div:nth-child(odd) .v-list-item {
  background-color: var(--color-background-base-selected) !important;
}
</style>
