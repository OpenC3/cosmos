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
    <v-list class="list" data-test="microserviceList">
      <div v-for="microservice in microservices" :key="microservice">
        <v-list-item>
          <v-list-item-title>{{ microservice }}</v-list-item-title>
          <v-list-item-subtitle v-if="microservice_status[microservice]">
            Updated:
            {{ formatDate(microservice_status[microservice].updated_at) }},
            State: {{ microservice_status[microservice].state }}, Count:
            {{ microservice_status[microservice].count }}
          </v-list-item-subtitle>

          <template v-slot:append>
            <div v-if="microservice_status[microservice]">
              <div v-show="!!microservice_status[microservice].error">
                <v-tooltip location="bottom">
                  <template v-slot:activator="{ props }">
                    <v-icon
                      v-bind="props"
                      @click="showMicroserviceError(microservice)"
                    >
                      mdi-alert
                    </v-icon>
                  </template>
                  <span>View Error</span>
                </v-tooltip>
              </div>
            </div>
            <v-tooltip location="bottom">
              <template v-slot:activator="{ props }">
                <v-icon v-bind="props" @click="showMicroservice(microservice)">
                  mdi-eye
                </v-icon>
              </template>
              <span>View Microservice</span>
            </v-tooltip>
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
import Api from '../../../services/api'
import OutputDialog from '../../../components/OutputDialog'
import TextBoxDialog from '../../../components/TextBoxDialog'

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
    }
  },
  mounted() {
    this.update()
  },
  methods: {
    update: function () {
      Api.get('/openc3-api/microservice_status/all').then((response) => {
        this.microservice_status = response.data
      })
      Api.get('/openc3-api/microservices').then((response) => {
        this.microservices = response.data
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
        toDate(parseInt(nanoSecs) / 1_000_000),
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
