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
    <v-alert v-model="showAlert" closable :type="alertType">{{
      alert
    }}</v-alert>
    <div class="text-caption text-medium-emphasis mt-2 mb-2 ml-4">
      <template v-if="hasServiceFilter && filteredServiceCount === 0">
        No microservices match filter (showing 0 / {{ totalServiceCount }})
      </template>
      <template v-else-if="hasServiceFilter">
        Showing {{ filteredServiceCount }} /
        {{ totalServiceCount }} microservices
      </template>
      <template v-else> {{ totalServiceCount }} microservices </template>
    </div>
    <v-row v-if="hasServiceFilter" class="ml-1 mb-1">
      <v-col cols="auto">
        <v-btn
          color="primary"
          prepend-icon="mdi-filter-off"
          aria-label="Filter applied. Click to clear filter and show all services."
          @click="clearServiceFilter"
        >
          Show All
        </v-btn>
      </v-col>
      <v-col cols="auto">
        <v-btn
          color="warning"
          prepend-icon="mdi-refresh"
          :disabled="filteredServiceCount === 0"
          @click="bulkRestartServices"
        >
          Restart All
        </v-btn>
      </v-col>
      <v-col cols="auto">
        <v-btn
          color="error"
          prepend-icon="mdi-stop"
          :disabled="filteredServiceCount === 0"
          @click="bulkStopServices"
        >
          Stop All
        </v-btn>
      </v-col>
    </v-row>
    <v-list class="list" data-test="microserviceList">
      <div
        v-for="microservice in filteredMicroservices"
        :key="microservice.name"
      >
        <v-list-item>
          <v-list-item-title>{{ microservice.name }}</v-list-item-title>
          <v-list-item-subtitle v-if="microservice_status[microservice.name]">
            Updated:
            {{ formatDate(microservice_status[microservice.name].updated_at) }},
            Enabled: {{ isEnabled(microservice.name) ? 'True' : 'False' }},
            Count:
            {{ microservice_status[microservice.name].count }}
          </v-list-item-subtitle>
          <template #append>
            <v-btn
              v-show="microservice_status[microservice.name]?.error"
              icon="mdi-alert"
              variant="text"
              @click="showMicroserviceError(microservice.name)"
            />
            <v-chip
              v-if="microservice_status[microservice.name]"
              :color="getStateColor(microservice.name)"
              size="small"
              label
            >
              {{ getStateText(microservice.name) }}
            </v-chip>
            <v-tooltip
              :text="isEnabled(microservice.name) ? 'Restart' : 'Start'"
              location="top"
            >
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  :aria-label="
                    isEnabled(microservice.name)
                      ? 'Restart Microservice'
                      : 'Start Microservice'
                  "
                  :icon="
                    isRestarting(microservice.name) ||
                    isStarting(microservice.name)
                      ? 'mdi-loading'
                      : isEnabled(microservice.name)
                        ? 'mdi-refresh'
                        : 'mdi-play'
                  "
                  :class="{
                    'rotating-icon':
                      isRestarting(microservice.name) ||
                      isStarting(microservice.name),
                  }"
                  variant="text"
                  :disabled="isOperationInProgress(microservice.name)"
                  @click="restartMicroservice(microservice.name)"
                />
              </template>
            </v-tooltip>
            <v-tooltip text="Stop" location="top">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  aria-label="Stop Microservice"
                  :icon="
                    isStopping(microservice.name) ? 'mdi-loading' : 'mdi-stop'
                  "
                  :class="{ 'rotating-icon': isStopping(microservice.name) }"
                  variant="text"
                  :disabled="isOperationInProgress(microservice.name)"
                  @click="stopMicroservice(microservice.name)"
                />
              </template>
            </v-tooltip>
            <v-tooltip text="Show Details" location="top">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  aria-label="Show Microservice Details"
                  icon="mdi-eye"
                  variant="text"
                  @click="showMicroservice(microservice.name)"
                />
              </template>
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
      type="Microservice"
      :name="dialogTitle"
      @submit="dialogCallback"
    />
    <text-box-dialog
      v-if="showError"
      v-model="showError"
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
      filteredMicroservices: [],
      allMicroservices: [],
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
      // { service_name:
      //   { operation: 'stopping' | 'restarting' | 'starting',
      //     enabled_states: []
      //     initial_updated_at: timestamp
      //     time_started: timestamp
      //   }
      // }
      microserviceOperations: {},
    }
  },
  computed: {
    serviceFilter() {
      const services = this.$route.query.services
      if (!services) return null
      return services
        .split(',')
        .map((s) => s.trim())
        .filter((s) => s)
    },
    hasServiceFilter() {
      return this.serviceFilter && this.serviceFilter.length > 0
    },
    totalServiceCount() {
      return this.allMicroservices.length
    },
    filteredServiceCount() {
      return this.filteredMicroservices.length
    },
  },
  watch: {
    '$route.query.services': function () {
      this.applyServiceFilter()
    },
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
    isOperationInProgress: function (name) {
      return !!this.microserviceOperations[name]
    },
    isEnabled: function (name) {
      const microservice = this.allMicroservices.find((ms) => ms.name === name)
      return microservice?.enabled !== false
    },
    isRestarting: function (name) {
      return this.microserviceOperations[name]?.operation === 'restarting'
    },
    isStarting: function (name) {
      return this.microserviceOperations[name]?.operation === 'starting'
    },
    isStopping: function (name) {
      return this.microserviceOperations[name]?.operation === 'stopping'
    },
    update: function () {
      Api.get('/openc3-api/microservice_status/all').then((response) => {
        this.microservice_status = response.data
        this.checkOperationCompletion()
      })
      Api.get('/openc3-api/microservices/all').then((response) => {
        // Convert hash of microservices to array of microservices
        let microservices = []
        for (const [_microservice_name, microservice] of Object.entries(
          response.data,
        )) {
          microservices.push(microservice)
        }
        microservices.sort((a, b) => a.name.localeCompare(b.name))
        this.allMicroservices = microservices
        this.applyServiceFilter()
      })
    },
    checkOperationCompletion: function () {
      for (const [name, tracking] of Object.entries(
        this.microserviceOperations,
      )) {
        const microservice = this.allMicroservices.find(
          (ms) => ms.name === name,
        )
        if (!microservice) continue

        const currentEnabled = microservice.enabled !== false
        const lastEnabled =
          tracking.enabled_states[tracking.enabled_states.length - 1]

        // Only add state if it changed
        if (currentEnabled !== lastEnabled) {
          tracking.enabled_states.push(currentEnabled)
        }

        const isComplete = this.isOperationComplete(name, tracking)
        if (isComplete) {
          delete this.microserviceOperations[name]
        }
      }
    },
    isOperationComplete: function (serviceName, tracking) {
      // Check for timeout (30 seconds)
      const elapsed = Date.now() - tracking.time_started
      if (elapsed > 30000) {
        this.alert = `${serviceName} timed out when ${tracking.operation}.`
        this.alertType = 'error'
        this.showAlert = true
        setTimeout(() => {
          this.showAlert = false
        }, 5000)
        delete this.microserviceOperations[serviceName]
        return true
      }

      if (tracking.operation === 'stopping') {
        // Track true -> false
        return tracking.enabled_states.includes(false)
      }
      if (tracking.operation === 'starting') {
        // Track false -> true
        return tracking.enabled_states.includes(true)
      }
      if (tracking.operation === 'restarting') {
        // Check if updated_at has changed
        const currentUpdatedAt =
          this.microservice_status[serviceName]?.updated_at
        if (currentUpdatedAt && tracking.initial_updated_at) {
          return currentUpdatedAt !== tracking.initial_updated_at
        }
        return false
      }
      return false
    },
    applyServiceFilter: function () {
      if (this.hasServiceFilter) {
        this.filteredMicroservices = this.allMicroservices.filter((ms) =>
          this.serviceFilter.includes(ms.name),
        )
      } else {
        this.filteredMicroservices = this.allMicroservices
      }
    },
    clearServiceFilter: function () {
      this.$router.push({ query: {} })
    },
    bulkRestartServices: function () {
      const microserviceNames = this.filteredMicroservices.map((m) => m.name)
      const microserviceList = microserviceNames.join(', ')
      const confirmMessage = `Are you sure you want to restart ${microserviceNames.length} microservice(s)? ${microserviceList}`

      this.$dialog
        .confirm(confirmMessage, {
          okText: 'Restart',
          cancelText: 'Cancel',
        })
        .then(() => {
          microserviceNames.forEach((name) => {
            const microservice = this.allMicroservices.find(
              (ms) => ms.name === name,
            )
            const currentEnabled = microservice?.enabled !== false
            const initialUpdatedAt = this.microservice_status[name]?.updated_at
            this.microserviceOperations[name] = {
              operation: 'restarting',
              enabled_states: [currentEnabled],
              initial_updated_at: initialUpdatedAt,
              time_started: Date.now(),
            }
            Api.post(`/openc3-api/microservices/${name}/start`).catch(
              (error) => {
                this.alert = `Start command failed for ${name}: ${error}`
                this.alertType = 'error'
                this.showAlert = true
                setTimeout(() => {
                  this.showAlert = false
                }, 5000)
                delete this.microserviceOperations[name]
              },
            )
          })
        })
        .catch(() => {
          // User cancelled
        })
    },
    bulkStopServices: function () {
      const microserviceNames = this.filteredMicroservices.map((m) => m.name)
      const microserviceList = microserviceNames.join(', ')
      const confirmMessage = `Are you sure you want to stop ${microserviceNames.length} microservice(s)?\n\n${microserviceList}`

      this.$dialog
        .confirm(confirmMessage, {
          okText: 'Stop',
          cancelText: 'Cancel',
        })
        .then(() => {
          microserviceNames.forEach((name) => {
            const microservice = this.allMicroservices.find(
              (ms) => ms.name === name,
            )
            const currentEnabled = microservice?.enabled !== false
            this.microserviceOperations[name] = {
              operation: 'stopping',
              enabled_states: [currentEnabled],
              time_started: Date.now(),
            }
            Api.post(`/openc3-api/microservices/${name}/stop`).catch(
              (error) => {
                this.alert = `Stop command failed for ${name}: ${error}`
                this.alertType = 'error'
                this.showAlert = true
                setTimeout(() => {
                  this.showAlert = false
                }, 5000)
                delete this.microserviceOperations[name]
              },
            )
          })
        })
        .catch(() => {
          // User cancelled
        })
    },
    stopMicroservice: function (name) {
      this.$dialog
        .confirm(`Are you sure you want to stop microservice: ${name}?`, {
          okText: 'Stop',
          cancelText: 'Cancel',
        })
        .then((_dialog) => {
          const microservice = this.allMicroservices.find(
            (ms) => ms.name === name,
          )
          const currentEnabled = microservice?.enabled !== false
          this.microserviceOperations[name] = {
            operation: 'stopping',
            enabled_states: [currentEnabled],
            time_started: Date.now(),
          }
          Api.post(`/openc3-api/microservices/${name}/stop`).catch((error) => {
            this.alert = `Stop command failed for ${name}: ${error}`
            this.alertType = 'error'
            this.showAlert = true
            setTimeout(() => {
              this.showAlert = false
            }, 5000)
            delete this.microserviceOperations[name]
          })
        })
    },
    restartMicroservice: function (name) {
      this.$dialog
        .confirm(`Are you sure you want to restart microservice: ${name}?`, {
          okText: 'Restart',
          cancelText: 'Cancel',
        })
        .then((_dialog) => {
          const microservice = this.allMicroservices.find(
            (ms) => ms.name === name,
          )
          const currentEnabled = microservice?.enabled !== false
          this.microserviceOperations[name] = {
            operation: 'restarting',
            enabled_states: [currentEnabled],
            initial_updated_at: this.microservice_status[name]?.updated_at,
            time_started: Date.now(),
          }
          Api.post(`/openc3-api/microservices/${name}/start`).catch((error) => {
            this.alert = `Restart command failed for ${name}: ${error}`
            this.alertType = 'error'
            this.showAlert = true
            setTimeout(() => {
              this.showAlert = false
            }, 5000)
            delete this.microserviceOperations[name]
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
    // States are determined by the microservice and not from an explicitly defined set
    // However, we can provide useful colors for errors and common states
    getStateColor(microserviceName) {
      const status = this.microservice_status[microserviceName]
      if (!status) return 'grey'
      if (status.error) return 'red'
      // If not enabled, show as stopped even if state is "running"
      if (!this.isEnabled(microserviceName) || status.state === 'STOPPED')
        return 'yellow'
      if (status.state === 'RUNNING') return 'green'
      return 'grey'
    },
    getStateText(microserviceName) {
      if (!this.isEnabled(microserviceName)) {
        return 'STOPPED'
      }
      return this.microservice_status[microserviceName].state
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
.rotating-icon {
  animation: spin 1s linear infinite;
}
@keyframes spin {
  from {
    transform: rotate(0deg);
  }
  to {
    transform: rotate(360deg);
  }
}
</style>
