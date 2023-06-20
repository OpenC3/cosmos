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
    <top-bar :menus="menus" :title="title" />
    <v-row dense>
      <v-col>
        <v-text-field
          v-model="startDate"
          label="Start Date"
          type="date"
          :rules="[rules.required]"
          data-test="start-date"
        />
      </v-col>
      <v-col>
        <v-text-field
          v-model="startTime"
          label="Start Time"
          type="time"
          step="1"
          :rules="[rules.required]"
          data-test="start-time"
        />
      </v-col>
      <v-col>
        <v-text-field
          v-model="endDate"
          label="End Date"
          type="date"
          :rules="endTime ? [rules.required] : []"
          data-test="end-date"
        />
      </v-col>
      <v-col>
        <v-text-field
          v-model="endTime"
          label="End Time"
          type="time"
          step="1"
          :rules="endDate ? [rules.required] : []"
          data-test="end-time"
        />
      </v-col>
      <v-col cols="auto" class="pt-4">
        <v-btn
          v-if="running"
          color="primary"
          width="100"
          data-test="stop-button"
          @click="stop"
        >
          Stop
        </v-btn>
        <v-btn
          v-else
          :disabled="!canStart"
          color="primary"
          width="100"
          class="start-button"
          data-test="start-button"
          @click="start"
        >
          Start
        </v-btn>
      </v-col>
    </v-row>
    <div class="mb-3" v-show="warning || error || connectionFailure">
      <v-alert type="warning" v-model="warning" dismissible>
        {{ warningText }}
      </v-alert>
      <v-alert type="error" v-model="error" dismissible>
        {{ errorText }}
      </v-alert>
      <v-alert type="error" v-model="connectionFailure">
        OpenC3 backend connection failed.
      </v-alert>
    </div>
    <v-card>
      <v-tabs ref="tabs" v-model="curTab">
        <v-tab
          v-for="(tab, index) in config.tabs"
          :key="index"
          @contextmenu="(event) => tabMenu(event, index)"
          data-test="tab"
        >
          {{ tab.tabName }}
        </v-tab>
        <v-btn class="mt-2 ml-2" @click="addTab" icon data-test="new-tab">
          <v-icon>mdi-tab-plus</v-icon>
        </v-btn>
      </v-tabs>
      <v-tabs-items v-model="curTab">
        <v-tab-item v-for="(tab, index) in config.tabs" :key="tab.ref" eager>
          <keep-alive>
            <v-card flat>
              <v-divider />
              <v-card-title class="pa-3">
                <span v-text="tab.name" />
                <v-spacer />
                <v-btn
                  @click="() => deleteComponent(index)"
                  icon
                  data-test="delete-component"
                >
                  <v-icon color="red">mdi-delete</v-icon>
                </v-btn>
              </v-card-title>
              <component
                v-on="$listeners"
                :is="tab.type"
                :name="tab.component"
                :ref="tab.ref"
                :config="tab.config"
                :packets="tab.packets"
                @config="(config) => (tab.config = config)"
              />
              <v-card-text v-if="receivedPackets.length === 0">
                No data! Make sure to hit the START button!
              </v-card-text>
            </v-card></keep-alive
          >
        </v-tab-item>
      </v-tabs-items>
      <v-card v-if="!config.tabs.length">
        <v-card-title>You're not viewing any packets</v-card-title>
        <v-card-text>Click the new tab icon to start.</v-card-text>
      </v-card>
    </v-card>
    <!-- Dialogs for opening and saving configs -->
    <open-config-dialog
      v-if="openConfig"
      v-model="openConfig"
      :tool="toolName"
      @success="openConfiguration($event)"
    />
    <save-config-dialog
      v-if="saveConfig"
      v-model="saveConfig"
      :tool="toolName"
      @success="saveConfiguration($event)"
    />
    <!-- Dialog for renaming a new tab -->
    <v-dialog v-model="tabNameDialog" width="600">
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span> DataViewer: Rename Tab</span>
          <v-spacer />
        </v-system-bar>
        <v-card-text>
          <v-text-field
            v-model="newTabName"
            label="Tab name"
            data-test="rename-tab-input"
          />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn
            outlined
            class="mx-2"
            data-test="cancel-rename"
            @click="cancelTabRename"
          >
            Cancel
          </v-btn>
          <v-btn
            color="primary"
            class="mx-2"
            data-test="rename"
            :disabled="!newTabName"
            @click="renameTab"
          >
            Rename
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
    <!-- Menu for right clicking on a tab -->
    <v-menu
      v-model="showTabMenu"
      :position-x="tabMenuX"
      :position-y="tabMenuY"
      absolute
      offset-y
    >
      <v-list>
        <v-list-item data-test="context-menu-rename">
          <v-list-item-title style="cursor: pointer" @click="openTabNameDialog">
            Rename
          </v-list-item-title>
        </v-list-item>
      </v-list>
    </v-menu>
    <!-- Dialog for adding a new component to a tab -->
    <add-component-dialog
      :components="components"
      v-if="showAddComponentDialog"
      v-model="showAddComponentDialog"
      @add="addComponent"
      @cancel="cancelAddComponent"
    />
  </div>
</template>

<script>
import { format } from 'date-fns'
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'
import Api from '@openc3/tool-common/src/services/api'
import OpenConfigDialog from '@openc3/tool-common/src/components/OpenConfigDialog'
import SaveConfigDialog from '@openc3/tool-common/src/components/SaveConfigDialog'
import Cable from '@openc3/tool-common/src/services/cable.js'
import TopBar from '@openc3/tool-common/src/components/TopBar'

import AddComponentDialog from '@/tools/DataViewer/AddComponentDialog'
// DynamicComponent is how we load custom user components
import DynamicComponent from '@/tools/DataViewer/DynamicComponent'
// Import the built-in DataViewer components
import DumpComponent from '@/tools/DataViewer/DumpComponent'

export default {
  components: {
    AddComponentDialog,
    OpenConfigDialog,
    SaveConfigDialog,
    DynamicComponent,
    DumpComponent,
    TopBar,
  },
  data() {
    return {
      title: 'COSMOS Data Viewer',
      toolName: 'data-viewer',
      // Initialize with all built-in components
      components: [{ label: 'COSMOS Raw/Decom', value: 'DumpComponent' }],
      counter: 0,
      componentType: null,
      componentName: null,
      openConfig: false,
      saveConfig: false,
      api: null,
      cable: new Cable(),
      subscription: null,
      startDate: format(new Date(), 'yyyy-MM-dd'),
      startTime: format(new Date(), 'HH:mm:ss'),
      endDate: '',
      endTime: '',
      rules: {
        required: (value) => !!value || 'Required',
      },
      autoStart: false,
      canStart: false,
      running: false,
      curTab: null,
      receivedPackets: {},
      menus: [
        {
          label: 'File',
          items: [
            {
              label: 'Open Configuration',
              icon: 'mdi-folder-open',
              command: () => {
                this.openConfig = true
              },
            },
            {
              label: 'Save Configuration',
              icon: 'mdi-content-save',
              command: () => {
                this.saveConfig = true
              },
            },
          ],
        },
      ],
      warning: false,
      warningText: '',
      error: false,
      errorText: '',
      connectionFailure: false,
      config: {
        tabs: [],
      },
      tabNameDialog: false,
      newTabName: '',
      showTabMenu: false,
      tabMenuX: 0,
      tabMenuY: 0,
      showAddComponentDialog: false,
    }
  },
  computed: {
    startEndTime: function () {
      return {
        start_time:
          new Date(this.startDate + ' ' + this.startTime).getTime() * 1_000_000,
        end_time: this.endDate
          ? new Date(this.endDate + ' ' + this.endTime).getTime() * 1_000_000
          : null,
      }
    },
    allPackets: function () {
      return this.config.tabs.flatMap((tab) => {
        return tab.packets
      })
    },
  },
  watch: {
    'config.tabs.length': function () {
      this.resizeTabs()
    },
    // canStart is set by the subscription when it connects.
    // We set autoStart to true during mounted() when loading from
    // a route or a previous saved configuration.
    canStart: function (newVal, _) {
      if (newVal === true && this.autoStart) {
        this.start()
      }
    },
  },
  created() {
    // Determine if there are any user added widgets
    Api.get('/openc3-api/widgets').then((response) => {
      response.data.forEach((widget) => {
        // Only list the ones following the naming convention DataviewerxxxxxWidget
        const found = widget.match(/DATAVIEWER([A-Z]+)/)
        if (found) {
          Api.get(`/openc3-api/widgets/${widget}`).then((response) => {
            let label = response.data.label
            if (label === null) {
              label = response.data.name.slice(10)
              label = label.charAt(0) + label.slice(1).toLowerCase()
            }
            this.components.push({
              label: label,
              value: found[0],
            })
          })
        }
      })
    })
    this.api = new OpenC3Api()
    this.subscribe()
  },
  mounted: function () {
    const previousConfig = localStorage['lastconfig__data_viewer']
    // Called like /tools/dataviewer?config=config
    if (this.$route.query && this.$route.query.config) {
      this.autoStart = true
      this.openConfiguration(this.$route.query.config, true) // routed
    } else if (previousConfig) {
      this.autoStart = true
      this.openConfiguration(previousConfig)
    }
  },
  destroyed: function () {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    this.cable.disconnect()
  },
  methods: {
    packetTitle: function (packet) {
      return `${packet.targetName} ${packet.packetName} [ ${packet.mode} ]`
    },
    resizeTabs: function () {
      if (this.$refs.tabs) this.$refs.tabs.onResize()
    },
    start: function () {
      this.autoStart = false
      // Check for a future start time
      if (new Date(this.startDate + ' ' + this.startTime) > Date.now()) {
        this.warningText = 'Start date/time is in the future!'
        this.warning = true
        return
      }
      // Check for an empty time period
      if (this.startEndTime.start_time === this.startEndTime.end_time) {
        this.warningText = 'Start date/time is equal to end date/time!'
        this.warning = true
        return
      }
      // Check for a future End Time
      if (new Date(this.endDate + ' ' + this.endTime) > Date.now()) {
        this.warningText =
          'Note: End date/time is greater than current date/time. Data will continue to stream in real-time until ' +
          this.endDate +
          ' ' +
          this.endTime +
          ' is reached.'
        this.warning = true
      }
      this.running = true
      this.addPacketsToSubscription()
    },
    stop: function () {
      this.running = false
      this.removePacketsFromSubscription()
    },
    subscribe: function () {
      this.cable
        .createSubscription('StreamingChannel', window.openc3Scope, {
          received: (data) => this.received(data),
          connected: () => {
            this.canStart = true
            this.connectionFailure = false
          },
          disconnected: () => {
            this.stop()
            this.canStart = false
            this.warningText = 'OpenC3 backend connection disconnected.'
            this.warning = true
            this.connectionFailure = true
          },
          rejected: () => {
            this.warningText = 'OpenC3 backend connection rejected.'
            this.warning = true
          },
        })
        .then((subscription) => {
          this.subscription = subscription
          if (this.running) this.addPacketsToSubscription()
        })
    },
    addPacketsToSubscription: function (packets) {
      packets = packets || this.allPackets
      // Group by mode
      const modeGroups = packets.reduce((groups, packet) => {
        if (groups[packet.mode]) {
          groups[packet.mode].push(packet)
        } else {
          groups[packet.mode] = [packet]
        }
        return groups
      }, {})
      Object.keys(modeGroups).forEach((mode) => {
        // This eliminates duplicates by converted to Set and back to Array
        modeGroups[mode] = [...new Set(modeGroups[mode])]
      })
      OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(
        (refreshed) => {
          if (refreshed) {
            OpenC3Auth.setTokens()
          }
          Object.keys(modeGroups).forEach((mode) => {
            this.subscription.perform('add', {
              scope: window.openc3Scope,
              token: localStorage.openc3Token,
              packets: modeGroups[mode].map(this.subscriptionKey),
              ...this.startEndTime,
            })
          })
        }
      )
    },
    removePacketsFromSubscription: function (packets) {
      packets = packets || this.allPackets
      if (packets.length > 0) {
        this.subscription.perform('remove', {
          scope: window.openc3Scope,
          token: localStorage.openc3Token,
          packets: packets.map(this.subscriptionKey),
        })
      }
    },
    received: function (parsed) {
      this.cable.recordPing()
      if (parsed['error']) {
        this.errorText = parsed['error']
        this.error = true
        return
      }
      if (!parsed.length) {
        this.stop()
        return
      }
      const groupedPackets = parsed.reduce((groups, packet) => {
        if (groups[packet.__packet]) {
          groups[packet.__packet].push(packet)
        } else {
          groups[packet.__packet] = [packet]
        }
        return groups
      }, {})
      this.config.tabs.forEach((tab, i) => {
        tab.packets.forEach((packetConfig) => {
          let packetName = this.packetKey(packetConfig)
          this.receivedPackets[packetName] = true
          if (groupedPackets[packetName]) {
            this.$refs[tab.ref][0].receive(groupedPackets[packetName])
          }
        })
      })
      this.receivedPackets = { ...this.receivedPackets }
    },
    packetKey: function (packet) {
      let key = packet.mode + '__'
      if (packet.cmdOrTlm === 'TLM') {
        key += 'TLM'
      } else {
        key += 'CMD'
      }
      key += `__${packet.targetName}__${packet.packetName}`
      if (packet.mode === 'DECOM') key += `__${packet.valueType}`
      return key
    },
    subscriptionKey: function (packet) {
      const cmdOrTlm = packet.cmdOrTlm.toUpperCase()
      let key = `${packet.mode}__${cmdOrTlm}__${packet.targetName}__${packet.packetName}`
      if (packet.mode === 'DECOM') key += `__${packet.valueType}`
      return key
    },
    openConfiguration: function (name, routed = false) {
      this.api
        .load_config(this.toolName, name)
        .then((response) => {
          if (response) {
            this.stop()
            this.receivedPackets = {}
            this.config = JSON.parse(response)
            // Only call start() if autoStart is false like during a reload.
            // Otherwise we might call start before the subscription is valid.
            // See watch on canStart for more info.
            if (this.autoStart === false) {
              this.start()
            }
            this.$notify.normal({
              title: 'Loading configuration',
              body: name,
            })
            if (!routed) {
              this.$router.push({
                name: 'DataViewer',
                query: {
                  config: name,
                },
              })
            }
            localStorage['lastconfig__data_viewer'] = name
          } else {
            this.$notify.caution({
              title: 'Unknown configuration',
              body: name,
            })
            localStorage.removeItem('lastconfig__data_viewer')
          }
        })
        .catch((error) => {
          if (error) {
            this.$notify.serious({
              title: `Error opening configuration: ${name}`,
              body: error,
            })
          }
          localStorage.removeItem('lastconfig__data_viewer')
        })
    },
    saveConfiguration: function (name) {
      this.api
        .save_config(this.toolName, name, JSON.stringify(this.items))
        .then(() => {
          this.$notify.normal({
            title: 'Saved configuration',
            body: name,
          })
          localStorage['lastconfig__data_viewer'] = name
        })
        .catch((error) => {
          if (error) {
            this.$notify.serious({
              title: `Error saving configuration: ${name}`,
              body: error,
            })
          }
          localStorage.removeItem('lastconfig__data_viewer')
        })
    },
    addTab: function () {
      this.cancelTabRename()
      this.showAddComponentDialog = true
    },
    cancelTabRename: function () {
      this.tabNameDialog = false
      this.newTabName = ''
    },
    tabMenu: function (event, index) {
      this.curTab = index
      event.preventDefault()
      this.showTabMenu = false
      this.tabMenuX = event.clientX
      this.tabMenuY = event.clientY
      this.$nextTick(() => {
        this.showTabMenu = true
      })
    },
    openTabNameDialog: function () {
      this.newTabName = this.config.tabs[this.curTab].tabName
      this.tabNameDialog = true
    },
    renameTab: function () {
      this.config.tabs[this.curTab].tabName = this.newTabName
      this.tabNameDialog = false
    },
    packetSelected: function (event) {
      this.newPacket = {
        target: event.targetName,
        packet: event.packetName,
        cmdOrTlm: this.newPacketCmdOrTlm,
      }
    },
    addComponent: function (event) {
      // Built-in components are just themselves
      let type = event.component.value
      let component = event.component.value
      if (event.component.value.includes('DATAVIEWER')) {
        // Dynamic widgets use the DynamicComponent
        type = 'DynamicComponent'
        let name =
          event.component.value.charAt(0).toUpperCase() +
          event.component.value.slice(1).toLowerCase()
        component = `${name}Widget`
      }
      this.config.tabs.push({
        name: event.component.label,
        // Most tabs only have 1 packet so it's a good way to name them
        tabName: this.packetTitle(event.packets[0]),
        packets: [...event.packets], // Make a copy
        type: type,
        component: component,
        config: {}, // Set an empty config object
        ref: `component${this.counter}`,
      })
      this.counter++
      this.curTab = this.config.tabs.length - 1

      if (this.running) {
        this.addPacketsToSubscription(event.packets)
      }
      this.cancelAddComponent()
    },
    cancelAddComponent: function () {
      this.showAddComponentDialog = false
    },
    deleteComponent: function (tabIndex) {
      // Get the list of packets the other tabs are using
      let packetsInUse = []
      this.config.tabs.forEach((tab, i) => {
        if (i !== tabIndex) {
          packetsInUse = packetsInUse.concat(tab.packets.map(this.packetKey))
        }
      })
      // Filter out any packets that are in use
      let filtered = this.config.tabs[tabIndex].packets.filter(
        (packet) => packetsInUse.indexOf(this.packetKey(packet)) === -1
      )
      if (filtered.length > 0) {
        this.removePacketsFromSubscription(filtered)
      }
      this.config.tabs.splice(tabIndex, 1)
    },
  },
}
</script>

<style scoped>
/* Add some juice to the START button to indicate it needs to be pressed */
.start-button {
  animation: pulse 2s infinite;
}
@keyframes pulse {
  0% {
    -webkit-box-shadow: 0 0 0 0 rgba(255, 255, 255, 0.4);
  }
  70% {
    -webkit-box-shadow: 0 0 0 10px rgba(255, 255, 255, 0);
  }
  100% {
    -webkit-box-shadow: 0 0 0 0 rgba(255, 255, 255, 0);
  }
}

.text-component-missing-name {
  font-family: 'Courier New', Courier, monospace;
}

.v-tabs-items {
  overflow: visible;
}
</style>
