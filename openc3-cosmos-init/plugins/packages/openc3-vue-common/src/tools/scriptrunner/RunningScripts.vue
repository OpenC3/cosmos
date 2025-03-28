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
    <v-card flat>
      <v-card-title>
        <v-row dense>
          <span class="mr-2">Running Scripts</span>
          <v-spacer />
          <v-btn class="mr-2" color="primary" @click="getRunningScripts"
            >Refresh</v-btn
          >
          <v-spacer />
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
            data-test="running-search" /></v-row
      ></v-card-title>
      <v-data-table
        :headers="runningHeaders"
        :items="runningScripts"
        :search="runningSearch"
        density="compact"
        data-test="running-scripts"
        :items-per-page-options="[3]"
        max-height="400"
      >
        <template v-slot:item.connect="{ item }">
          <v-btn color="primary" @click="connectScript(item)">
            <span>Connect</span>
            <v-icon end v-show="connectInNewTab"> mdi-open-in-new </v-icon>
          </v-btn>
        </template>
        <template v-slot:item.stop="{ item }">
          <v-btn color="primary" @click="stopScript(item)">
            <span>Stop</span>
            <v-icon end> mdi-close-circle-outline </v-icon>
          </v-btn>
        </template>
        <template v-slot:item.delete="{ item }">
          <v-btn color="primary" @click="deleteScript(item)">
            <span>Delete</span>
            <v-icon end> mdi-alert-octagon-outline </v-icon>
          </v-btn>
        </template>
      </v-data-table>
    </v-card>
    <v-card flat>
      <v-card-title>
        <v-row dense>
          <span class="mr-2">Completed Scripts</span>
          <v-spacer />
          <v-btn color="primary" @click="getCompletedScripts">Refresh</v-btn>
          <v-spacer />
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
          />
        </v-row>
      </v-card-title>
      <!-- TODO: This probably needs to be paginated -->
      <v-data-table
        :headers="completedHeaders"
        :items="completedScripts"
        :search="completedSearch"
        density="compact"
        data-test="completed-scripts"
        :items-per-page-options="[5]"
      >
        <template v-slot:item.view="{ item }">
          <v-btn color="primary" @click="viewScriptLog(item)">
            <span v-if="item.name.includes('(') && item.name.includes(')')">
              Script Report
            </span>
            <span v-else> Script Log </span>
            <v-icon right> mdi-eye </v-icon>
          </v-btn>
        </template>
        <template v-slot:item.download="{ item }">
          <v-btn
            :disabled="downloadScript"
            :loading="downloadScript && downloadScript.name === item.name"
            @click="downloadScriptLog(item)"
          >
            <span v-if="item.name.includes('(') && item.name.includes(')')">
              Script Report
            </span>
            <span v-else> Script Log </span>
            <v-icon end> mdi-file-download-outline </v-icon>
            <template v-slot:loader>
              <span> Loading... </span>
            </template>
          </v-btn>
        </template>
      </v-data-table>
    </v-card>
    <output-dialog
      :content="dialogContent"
      type="Script"
      :name="dialogName"
      :filename="dialogFilename"
      v-model="showDialog"
      v-if="showDialog"
      @submit="showDialog = false"
    />
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import { OutputDialog } from '@/components'

export default {
  props: {
    tabId: Number,
    curTab: Number,
    connectInNewTab: Boolean,
  },
  components: { OutputDialog },
  data() {
    return {
      downloadScript: null,
      runningSearch: '',
      runningScripts: [],
      runningHeaders: [
        {
          title: 'Connect',
          key: 'connect',
          sortable: false,
          filterable: false,
        },
        { title: 'Id', key: 'id' },
        { title: 'User', key: 'user' },
        { title: 'Name', key: 'name' },
        { title: 'Start Time', key: 'start_time' },
        {
          title: 'Stop',
          key: 'stop',
          sortable: false,
          filterable: false,
        },
        {
          title: 'Force Quit',
          key: 'delete',
          sortable: false,
          filterable: false,
        },
      ],
      completedSearch: '',
      completedScripts: [],
      completedHeaders: [
        { title: 'Id', value: 'id' },
        { title: 'User', value: 'user' },
        { title: 'Name', value: 'name' },
        { title: 'Start Time', value: 'start' },
        {
          title: 'View',
          value: 'view',
          sortable: false,
          filterable: false,
        },
        {
          title: 'Download',
          key: 'download',
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
  created() {
    this.getRunningScripts()
    this.getCompletedScripts()
  },
  methods: {
    getRunningScripts: function () {
      Api.get('/script-api/running-script').then((response) => {
        this.runningScripts = response.data
      })
    },
    getCompletedScripts: function () {
      // TODO: Support pagination because you could have a lot of completed scripts
      Api.get('/script-api/completed-scripts').then((response) => {
        this.completedScripts = response.data
      })
    },
    connectScript: function (script) {
      // Must disconnect before connecting
      this.$emit('disconnect')
      const destination = {
        name: 'ScriptRunner',
        params: { id: script.id },
      }
      if (this.connectInNewTab) {
        let { href } = this.$router.resolve(destination)
        window.open(href, '_blank')
      } else {
        this.$router.push(destination)
        this.$emit('close')
      }
    },
    stopScript: function (script) {
      this.$dialog
        .confirm(
          `Are you sure you want to stop script: ${script.id} ${script.name}?`,
          {
            okText: 'Stop',
            cancelText: 'Cancel',
          },
        )
        .then((dialog) => {
          return Api.post(`/script-api/running-script/${script.id}/stop`)
        })
        .then((response) => {
          this.$notify.normal({
            body: `Stopped script: ${script.id} ${script.name}`,
          })
          this.getRunningScripts()
        })
        .catch((error) => {
          if (error !== true) {
            this.$notify.caution({
              body: `Failed to stop script: ${script.id} ${script.name}`,
            })
          }
        })
    },
    deleteScript: function (script) {
      this.$dialog
        .confirm(
          `Are you sure you want to force quit script: ${script.id} ${script.name}?\n` +
            'Did you try to stop the script first to allow the script to stop gracefully?',
          {
            okText: 'Force Quit',
            cancelText: 'Cancel',
          },
        )
        .then((dialog) => {
          return Api.post(`/script-api/running-script/${script.id}/delete`)
        })
        .then((response) => {
          this.$notify.normal({
            body: `Stopped script: ${script.id} ${script.name}`,
          })
          this.getRunningScripts()
        })
        .catch((error) => {
          if (error !== true) {
            this.$notify.caution({
              body: `Failed to stop script: ${script.id} ${script.name}`,
            })
          }
        })
    },
    viewScriptLog: function (script) {
      if (script.name.includes('(') && script.name.includes(')')) {
        this.dialogName = 'Report'
      } else {
        this.dialogName = 'Log'
      }
      Api.get(
        `/openc3-api/storage/download_file/${encodeURIComponent(
          script.log,
        )}?bucket=OPENC3_LOGS_BUCKET`,
      ).then((response) => {
        const filenameParts = script.log.split('/')
        this.dialogFilename = filenameParts[filenameParts.length - 1]
        // Decode Base64 string
        this.dialogContent = window.atob(response.data.contents)
        this.showDialog = true
      })
    },
    downloadScriptLog: function (script) {
      this.downloadScript = script
      Api.get(
        `/openc3-api/storage/download/${encodeURIComponent(
          script.log,
        )}?bucket=OPENC3_LOGS_BUCKET`,
      )
        .then((response) => {
          const filenameParts = script.log.split('/')
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
            title: `Unable to download log for ${script.name}`,
            body: `You may be able to download this log manually from the 'logs' bucket at ${script.log}`,
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
