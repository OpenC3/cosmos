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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-row no-gutters>
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
    </v-row>
    <v-row no-gutters class="px-2 pb-2">
      <!-- <v-btn
        @click="showDownloadDialog = true"
        class="mx-2"
        data-test="packageDownload"
        :disabled="files.length > 0"
      >
        <v-icon left dark>mdi-cloud-download</v-icon>
        <span> Download </span>
      </v-btn> -->
      <v-spacer />
      <v-btn
        @click="upload()"
        class="mx-2"
        color="primary"
        data-test="packageUpload"
        :disabled="files.length < 1"
        :loading="loadingPackage"
      >
        <v-icon left dark>mdi-cloud-upload</v-icon>
        <span> Upload </span>
        <template v-slot:loader>
          <span>Loading...</span>
        </template>
      </v-btn>
    </v-row>
    <v-alert
      v-model="showAlert"
      dismissible
      transition="scale-transition"
      :type="alertType"
      >{{ alert }}</v-alert
    >
    <v-list v-if="Object.keys(processes).length > 0" data-test="processList">
      <div v-for="process in processes" :key="process.name">
        <v-list-item>
          <v-list-item-content>
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
          </v-list-item-content>
          <v-list-item-icon v-if="process.state !== 'Running'">
            <v-tooltip bottom>
              <template v-slot:activator="{ on, attrs }">
                <v-icon @click="showOutput(process)" v-bind="attrs" v-on="on">
                  mdi-eye
                </v-icon>
              </template>
              <span>Show Output</span>
            </v-tooltip>
          </v-list-item-icon>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <v-list data-test="packageList">
      <v-subheader>Ruby Gems</v-subheader>
      <div v-for="(gem, index) in gems" :key="index">
        <v-list-item>
          <v-list-item-content>
            <v-list-item-title>{{ gem }}</v-list-item-title>
          </v-list-item-content>
          <v-list-item-icon>
            <v-tooltip bottom>
              <template v-slot:activator="{ on, attrs }">
                <v-icon @click="deletePackage(gem)" v-bind="attrs" v-on="on">
                  mdi-delete
                </v-icon>
              </template>
              <span>Delete Package</span>
            </v-tooltip>
          </v-list-item-icon>
        </v-list-item>
        <v-divider v-if="index < gems.length - 1" :key="index" />
      </div>
      <v-subheader>Python Packages</v-subheader>
      <div v-for="(pkg, index) in python" :key="index">
        <v-list-item>
          <v-list-item-content>
            <v-list-item-title>{{ pkg }}</v-list-item-title>
          </v-list-item-content>
          <v-list-item-icon>
            <v-tooltip bottom>
              <template v-slot:activator="{ on, attrs }">
                <v-icon @click="deletePackage(pkg)" v-bind="attrs" v-on="on">
                  mdi-delete
                </v-icon>
              </template>
              <span>Delete Package</span>
            </v-tooltip>
          </v-list-item-icon>
        </v-list-item>
        <v-divider v-if="index < python.length - 1" :key="index" />
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
      const promises = this.files.map((file) => {
        const formData = new FormData()
        formData.append('package', file, file.name)
        return Api.post('/openc3-api/packages', { data: formData })
      })
      Promise.all(promises)
        .then((responses) => {
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
