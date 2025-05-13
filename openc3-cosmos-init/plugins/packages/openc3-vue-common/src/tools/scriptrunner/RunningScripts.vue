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
    <v-card flat class="tab-card">
      <v-tabs
        v-model="activeTab"
        bg-color="var(--color-background-base-default)"
      >
        <v-tab value="running">Running Scripts</v-tab>
        <v-tab value="completed">Completed Scripts</v-tab>
      </v-tabs>
      <v-window v-model="activeTab">
        <!-- Running Scripts Tab -->
        <v-window-item value="running">
          <v-card-title>
            <v-row dense>
              <v-spacer />
              <v-btn class="mr-3" color="primary" @click="getRunningScripts"
                >Refresh</v-btn
              >
              <v-text-field
                v-model="runningSearch"
                class="pt-0 search"
                label="Search"
                prepend-inner-icon="mdi-magnify"
                clearable
                variant="outlined"
                density="compact"
                single-line
                hide-details
                data-test="running-search"
                style="max-width: 300px"
              />
            </v-row>
          </v-card-title>

          <v-data-table-server
            :headers="runningHeaders"
            :items="runningScripts"
            :items-length="runningTotal"
            :loading="runningLoading"
            :search="runningSearch"
            density="compact"
            data-test="running-scripts"
            :items-per-page="runningItemsPerPage"
            :page="runningPage"
            :items-per-page-options="[10, 25, 50]"
            class="script-table"
            @update:page="updateRunningPage"
            @update:items-per-page="updateRunningItemsPerPage"
          >
            <template #item.name="{ item }">
              <v-btn
                color="primary"
                density="comfortable"
                @click="showScript(item)"
                >{{ item.name }}</v-btn
              >
            </template>
            <template #item.connect="{ item }">
              <v-btn color="primary" @click="connectScript(item)">
                <span>Connect</span>
                <v-icon v-show="connectInNewTab" end> mdi-open-in-new </v-icon>
              </v-btn>
            </template>
            <template #item.stop="{ item }">
              <v-btn color="primary" @click="deleteScript(item)">
                <span>Stop</span>
                <v-icon end> mdi-close-circle-outline </v-icon>
              </v-btn>
            </template>
          </v-data-table-server>
        </v-window-item>

        <!-- Completed Scripts Tab -->
        <v-window-item value="completed">
          <v-card-title>
            <v-row dense>
              <v-spacer />
              <v-btn class="mr-3" color="primary" @click="getCompletedScripts"
                >Refresh</v-btn
              >
              <v-text-field
                v-model="completedSearch"
                class="pt-0 search"
                label="Search"
                prepend-inner-icon="mdi-magnify"
                clearable
                variant="outlined"
                density="compact"
                single-line
                hide-details
                style="max-width: 300px"
              />
            </v-row>
          </v-card-title>

          <v-data-table-server
            :headers="completedHeaders"
            :items="completedScripts"
            :items-length="completedTotal"
            :loading="completedLoading"
            :search="completedSearch"
            density="compact"
            data-test="completed-scripts"
            :items-per-page="completedItemsPerPage"
            :page="completedPage"
            :items-per-page-options="[10, 25, 50]"
            class="script-table"
            @update:page="updateCompletedPage"
            @update:items-per-page="updateCompletedItemsPerPage"
          >
            <template #item.name="{ item }">
              <v-btn
                color="primary"
                density="comfortable"
                @click="showScript(item)"
                >{{ item.name }}</v-btn
              >
            </template>
            <template #item.log="{ item }">
              <v-btn
                color="primary"
                density="comfortable"
                icon="mdi-eye"
                @click="viewScriptLog(item, 'log')"
              />
              <v-btn
                color="primary"
                density="comfortable"
                icon="mdi-file-download-outline"
                :disabled="downloadScript"
                :loading="downloadScript && downloadScript.name === item.name"
                @click="downloadScriptLog(item, 'log')"
              />
            </template>
            <template #item.report="{ item }">
              <div v-if="!item.report">
                <span>N/A</span>
              </div>
              <div v-else>
                <v-btn
                  color="primary"
                  density="comfortable"
                  icon="mdi-eye"
                  @click="viewScriptLog(item, 'report')"
                />
                <v-btn
                  color="primary"
                  density="comfortable"
                  icon="mdi-file-download-outline"
                  :disabled="downloadScript"
                  :loading="downloadScript && downloadScript.name === item.name"
                  @click="downloadScriptLog(item, 'report')"
                />
              </div>
            </template>
          </v-data-table-server>
        </v-window-item>
      </v-window>
    </v-card>

    <output-dialog
      v-if="showDialog"
      v-model="showDialog"
      :content="dialogContent"
      type="Script"
      :name="dialogName"
      :filename="dialogFilename"
      @submit="showDialog = false"
    />
  </div>
</template>

<script>
import { Api, OpenC3Api } from '@openc3/js-common/services'
import { OutputDialog } from '@/components'
import { TimeFilters } from '@/util'

export default {
  components: { OutputDialog },
  mixins: [TimeFilters],
  props: {
    tabId: Number,
    curTab: Number,
    connectInNewTab: Boolean,
  },
  data() {
    return {
      api: null,
      timeZone: 'local',
      activeTab: 'running',
      downloadScript: null,
      refreshTimer: null,
      // Running scripts pagination data
      runningSearch: '',
      runningScripts: [],
      runningTotal: 0,
      runningLoading: false,
      runningPage: 1,
      runningItemsPerPage: 10,
      runningHeaders: [
        {
          title: 'Connect',
          key: 'connect',
          sortable: false,
          filterable: false,
        },
        { title: 'Id', key: 'name' },
        { title: 'User', key: 'user_display' },
        { title: 'Filename', key: 'filename' },
        { title: 'Start Time', key: 'start_time_formatted' },
        { title: 'Duration', key: 'duration' },
        { title: 'State', key: 'state' },
        {
          title: 'Stop',
          key: 'stop',
          sortable: false,
          filterable: false,
        },
      ],
      // Completed scripts pagination data
      completedSearch: '',
      completedScripts: [],
      completedTotal: 0,
      completedLoading: false,
      completedPage: 1,
      completedItemsPerPage: 10,
      completedHeaders: [
        { title: 'Id', key: 'name' },
        { title: 'User', key: 'user_display' },
        { title: 'Filename', key: 'filename' },
        { title: 'Start Time', key: 'start_time_formatted' },
        { title: 'Duration', key: 'duration' },
        { title: 'State', key: 'state' },
        {
          title: 'Log',
          key: 'log',
          sortable: false,
          filterable: false,
        },
        {
          title: 'Report',
          key: 'report',
          sortable: false,
          filterable: false,
        },
      ],
      showDialog: false,
      dialogName: '',
      dialogContent: '',
      dialogFilename: '',
    }
  },
  watch: {
    activeTab(newTab) {
      if (newTab === 'running') {
        this.getRunningScripts()
      } else if (newTab === 'completed') {
        this.getCompletedScripts()
      }
    },
  },
  created() {
    this.api = new OpenC3Api()
    this.api
      .get_setting('time_zone')
      .then((response) => {
        if (response) {
          this.timeZone = response
        }
      })
      .catch((error) => {
        // Do nothing
      })

    this.getRunningScripts()
    this.getCompletedScripts()

    // Start a timer to refresh the running scripts list every 5 seconds
    this.refreshTimer = setInterval(() => {
      if (this.activeTab === 'running') {
        this.getRunningScripts()
      }
    }, 5000)
  },
  beforeUnmount() {
    // Clear the timer when component is unmounted
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  },
  methods: {
    getRunningScripts: function () {
      this.runningLoading = true
      const offset = (this.runningPage - 1) * this.runningItemsPerPage
      Api.get(
        `/script-api/running-script?scope=DEFAULT&offset=${offset}&limit=${this.runningItemsPerPage}`,
      )
        .then((response) => {
          const scripts = response.data.items || []
          const currentTime = new Date()

          // Calculate duration for each running script and format user info
          scripts.forEach((script) => {
            // Format user display as "full_name (username)"
            script.user_display = `${script.user_full_name} (${script.username})`

            // Calculate duration
            if (script.start_time) {
              const startTime = new Date(script.start_time)
              const durationMs = currentTime - startTime
              script.start_time_formatted = this.formatDateTimeHMS(
                startTime,
                this.timeZone,
              )
              // Format duration
              if (durationMs < 0) {
                script.duration = 'N/A'
              } else if (durationMs < 1000) {
                script.duration = '< 1s'
              } else if (durationMs < 60000) {
                script.duration = `${Math.round(durationMs / 1000)}s`
              } else if (durationMs < 3600000) {
                const minutes = Math.floor(durationMs / 60000)
                const seconds = Math.round((durationMs % 60000) / 1000)
                script.duration = `${minutes}m ${seconds}s`
              } else {
                const hours = Math.floor(durationMs / 3600000)
                const minutes = Math.floor((durationMs % 3600000) / 60000)
                const seconds = Math.round((durationMs % 60000) / 1000)
                script.duration = `${hours}h ${minutes}m ${seconds}s`
              }
            } else {
              script.duration = 'N/A'
            }
          })

          this.runningScripts = scripts
          this.runningTotal = response.data.total || scripts.length
          this.runningLoading = false
        })
        .catch((error) => {
          this.runningLoading = false
          this.$notify.caution({
            title: 'Error Loading Running Scripts',
            body: error.message,
          })
        })
    },
    updateRunningPage: function (page) {
      this.runningPage = page
      this.getRunningScripts()
    },
    updateRunningItemsPerPage: function (itemsPerPage) {
      this.runningItemsPerPage = itemsPerPage
      this.runningPage = 1
      this.getRunningScripts()
    },
    getCompletedScripts: function () {
      this.completedLoading = true
      const offset = (this.completedPage - 1) * this.completedItemsPerPage
      Api.get(
        `/script-api/completed-scripts?scope=DEFAULT&offset=${offset}&limit=${this.completedItemsPerPage}`,
      )
        .then((response) => {
          const scripts = response.data.items || []

          // Calculate duration and format user info for each completed script
          scripts.forEach((script) => {
            // Format user display as "full_name (username)"
            script.user_display = `${script.user_full_name} (${script.username})`

            // Calculate duration
            if (script.start_time && script.end_time) {
              const startTime = new Date(script.start_time)
              const endTime = new Date(script.end_time)
              const durationMs = endTime - startTime
              script.start_time_formatted = this.formatDateTimeHMS(
                startTime,
                this.timeZone,
              )

              // Format duration
              if (durationMs < 0) {
                script.duration = 'N/A'
              } else if (durationMs < 1000) {
                script.duration = '< 1s'
              } else if (durationMs < 60000) {
                script.duration = `${Math.round(durationMs / 1000)}s`
              } else if (durationMs < 3600000) {
                const minutes = Math.floor(durationMs / 60000)
                const seconds = Math.round((durationMs % 60000) / 1000)
                script.duration = `${minutes}m ${seconds}s`
              } else {
                const hours = Math.floor(durationMs / 3600000)
                const minutes = Math.floor((durationMs % 3600000) / 60000)
                const seconds = Math.round((durationMs % 60000) / 1000)
                script.duration = `${hours}h ${minutes}m ${seconds}s`
              }
            } else {
              script.duration = 'N/A'
            }
          })

          this.completedScripts = scripts
          this.completedTotal = response.data.total || scripts.length
          this.completedLoading = false
        })
        .catch((error) => {
          this.completedLoading = false
          this.$notify.caution({
            title: 'Error Loading Completed Scripts',
            body: error.message,
          })
        })
    },
    updateCompletedPage: function (page) {
      this.completedPage = page
      this.getCompletedScripts()
    },
    updateCompletedItemsPerPage: function (itemsPerPage) {
      this.completedItemsPerPage = itemsPerPage
      this.completedPage = 1
      this.getCompletedScripts()
    },
    showScript: function (script) {
      this.dialogContent = JSON.stringify(script, null, 2)
      this.dialogName = 'Script: ' + script.name
      this.dialogFilename = ''
      this.showDialog = true
    },
    connectScript: function (script) {
      // Must disconnect before connecting
      this.$emit('disconnect')
      const destination = {
        name: 'ScriptRunner',
        params: { id: script.name },
      }
      if (this.connectInNewTab) {
        let { href } = this.$router.resolve(destination)
        window.open(href, '_blank')
      } else {
        this.$router.push(destination)
        this.$emit('close')
      }
    },
    deleteScript: function (script) {
      this.$dialog
        .confirm(
          `Are you sure you want to stop script: ${script.name} ${script.filename}?\n`,
          {
            okText: 'Stop',
            cancelText: 'Cancel',
          },
        )
        .then((dialog) => {
          return Api.post(`/script-api/running-script/${script.name}/delete`)
        })
        .then((response) => {
          this.$notify.normal({
            body: `Stopped script: ${script.name} ${script.filename}`,
          })
          this.getRunningScripts()
        })
        .catch((error) => {
          if (error !== true) {
            this.$notify.caution({
              body: `Failed to stop script: ${script.name} ${script.filename}`,
            })
          }
        })
    },
    viewScriptLog: function (script, type) {
      let logUrl = null
      if (type === 'report') {
        this.dialogName = 'Report'
        logUrl = script.report
      } else {
        this.dialogName = 'Log'
        logUrl = script.log
      }
      Api.get(
        `/openc3-api/storage/download_file/${encodeURIComponent(
          logUrl,
        )}?bucket=OPENC3_LOGS_BUCKET`,
      ).then((response) => {
        const filenameParts = logUrl.split('/')
        this.dialogFilename = filenameParts[filenameParts.length - 1]
        // Decode Base64 string
        this.dialogContent = window.atob(response.data.contents)
        this.showDialog = true
      })
    },
    downloadScriptLog: function (script, type) {
      let logUrl = null
      if (type === 'report') {
        this.dialogName = 'Report'
        logUrl = script.report
      } else {
        this.dialogName = 'Log'
        logUrl = script.log
      }
      this.downloadScript = script
      Api.get(
        `/openc3-api/storage/download/${encodeURIComponent(
          logUrl,
        )}?bucket=OPENC3_LOGS_BUCKET`,
      )
        .then((response) => {
          const filenameParts = logUrl.split('/')
          const basename = filenameParts[filenameParts.length - 1]
          // Make a link and then 'click' on it to start the download
          const link = document.createElement('a')
          link.href = response.data.url
          link.setAttribute('download', basename)
          link.click()
          this.downloadScript = null
        })
        .catch(() => {
          this.$notify.caution({
            title: `Unable to download log ${logUrl}`,
            body: `You may be able to download this log manually from the 'logs' bucket at ${logUrl}`,
          })
        })
    },
  },
}
</script>
<style>
.v-sheet {
  background-color: var(--color-background-base-default);
}
</style>
