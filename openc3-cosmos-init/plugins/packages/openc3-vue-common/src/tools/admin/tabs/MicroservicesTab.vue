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
    <v-alert
      v-model="showAlert"
      dismissible
      transition="scale-transition"
      :type="alertType"
      >{{ alert }}</v-alert
    >
    <v-list class="list" data-test="microserviceList">
      <div v-for="microservice in microservices" :key="microservice">
        <v-list-item>
          <v-list-item-title>{{ microservice.name }}</v-list-item-title>
          <v-list-item-subtitle v-if="microservice_status[microservice.name]">
            Updated:
            {{ formatDate(microservice_status[microservice.name].updated_at) }},
            State: {{ microservice_status[microservice.name].state }}, Enabled:
            {{ microservice.enabled === false ? 'False' : 'True' }}, Count:
            {{ microservice_status[microservice.name].count }}
          </v-list-item-subtitle>

          <template v-slot:append>
            <div v-if="microservice_status[microservice.name]">
              <div v-show="!!microservice_status[microservice.name].error">
                <v-tooltip location="top">
                  <template v-slot:activator="{ props }">
                    <v-icon
                      v-bind="props"
                      @click="showMicroserviceError(microservice.name)"
                    >
                      mdi-alert
                    </v-icon>
                  </template>
                  <span>View Error</span>
                </v-tooltip>
              </div>
            </div>
            <v-list-item-icon class="mr-3">
              <v-tooltip bottom>
                <template v-slot:activator="{ on, attrs }">
                  <v-icon
                    @click="startMicroservice(microservice.name)"
                    v-bind="attrs"
                    v-on="on"
                  >
                    mdi-play
                  </v-icon>
                </template>
                <span>Start Microservice</span>
              </v-tooltip>
            </v-list-item-icon>
            <v-list-item-icon class="mr-3">
              <v-tooltip bottom>
                <template v-slot:activator="{ on, attrs }">
                  <v-icon
                    @click="stopMicroservice(microservice.name)"
                    v-bind="attrs"
                    v-on="on"
                  >
                    mdi-stop
                  </v-icon>
                </template>
                <span>Stop Microservice</span>
              </v-tooltip>
            </v-list-item-icon>
            <v-list-item-icon>
              <v-tooltip bottom>
                <template v-slot:activator="{ on, attrs }">
                  <v-icon
                    @click="showMicroservice(microservice.name)"
                    v-bind="attrs"
                    v-on="on"
                  >
                    mdi-eye
                  </v-icon>
                </template>
                <span>View Microservice</span>
              </v-tooltip>
            </v-list-item-icon>
          </template>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <output-dialog
      v-model="showDialog"
      v-if="showDialog"
      :content="jsonContent"
      type="Microservice"
      :name="dialogTitle"
      @submit="dialogCallback"
    />
    <text-box-dialog
      v-model="showError"
      v-if="showError"
      :text="jsonContent"
      :title="dialogTitle"
    />
  </div>
</template>

<script>
import { toDate, format } from 'date-fns'
import { Api } from '@openc3/js-common/services'
import { OutputDialog, TextBoxDialog } from '@/components'

export default {
  components: {
    OutputDialog,
    TextBoxDialog,
  },
  data() {
    return {
      microservices: [],
      microservice_status: {},
      microservice_id: null,
      jsonContent: '',
      dialogTitle: '',
      showDialog: false,
      showError: false,
      alert: '',
      alertType: 'success',
      showAlert: false,
      updater: null,
    }
  },
  mounted() {
    this.update()
    this.updater = setInterval(() => {
      this.update()
    }, 2000)
  },
  beforeUnmount() {
    clearInterval(this.updater)
    this.updater = null
  },
  methods: {
    update: function () {
      Api.get('/openc3-api/microservice_status/all').then((response) => {
        this.microservice_status = response.data
      })
      Api.get('/openc3-api/microservices/all').then((response) => {
        // Convert hash of microservices to array of microservices
        let microservices = []
        for (const [microservice_name, microservice] of Object.entries(response.data)) {
          microservices.push(microservice)
        }
        microservices.sort((a, b) => a.name.localeCompare(b.name))
        this.microservices = microservices
      })
    },
    startMicroservice: function (name) {
      this.$dialog
        .confirm(
          `Are you sure you want to restart microservice: ${name}?`,
          {
            okText: 'Start',
            cancelText: 'Cancel',
          },
        ).then((dialog) => {
          Api.post(`/openc3-api/microservices/${name}/start`).then((response) => {
            this.alert = `Started ${name}`
            this.alertType = 'success'
            this.showAlert = true
            setTimeout(() => {
              this.showAlert = false
            }, 5000)
          }).then(() => {
            this.update()
          })
        })
    },
    stopMicroservice: function (name) {
      this.$dialog
        .confirm(
          `Are you sure you want to stop microservice: ${name}?`,
          {
            okText: 'Stop',
            cancelText: 'Cancel',
          },
        ).then((dialog) => {
          Api.post(`/openc3-api/microservices/${name}/stop`).then((response) => {
            this.alert = `Stopped ${name}`
            this.alertType = 'success'
            this.showAlert = true
            setTimeout(() => {
              this.showAlert = false
            }, 5000)
          }).then(() => {
            this.update()
          })
        })
    },
    showMicroservice: function (name) {
      Api.get(`/openc3-api/microservices/${name}`).then((response) => {
        this.microservice_id = name
        this.dialogTitle = name
        this.jsonContent = JSON.stringify(response.data, null, '\t')
        this.showDialog = true
      })
    },
    showMicroserviceError: function (name) {
      this.dialogTitle = name
      const e = this.microservice_status[name].error
      this.jsonContent = JSON.stringify(e, null, '\t')
      this.showError = true
    },
    formatDate(nanoSecs) {
      return format(
        toDate(parseInt(nanoSecs) / 1000000),
        'yyyy-MM-dd HH:mm:ss.SSS',
      )
    },
    dialogCallback: function (content) {
      this.showDialog = false
      if (content !== null) {
        let parsed = JSON.parse(content)
        let method = 'put'
        let url = `/openc3-api/microservices/${this.microservice_id}`
        if (parsed['name'] !== this.microservice_id) {
          method = 'post'
          url = '/openc3-api/microservices'
        }

        Api[method](url, {
          data: {
            json: content,
          },
        }).then((response) => {
          this.alert = 'Modified Microservice'
          this.alertType = 'success'
          this.showAlert = true
          setTimeout(() => {
            this.showAlert = false
          }, 5000)
          this.update()
        })
      }
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
