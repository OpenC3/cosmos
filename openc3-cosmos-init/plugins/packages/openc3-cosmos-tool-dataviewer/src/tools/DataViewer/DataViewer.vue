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
    <top-bar :menus="menus" :title="title" />
    <v-card>
      <v-expansion-panels v-model="panel" style="margin-bottom: 5px">
        <v-expansion-panel>
          <v-expansion-panel-title style="z-index: 1"></v-expansion-panel-title>
          <v-expansion-panel-text>
            <v-container>
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
                    class="pulse-button"
                    data-test="start-button"
                    @click="start"
                  >
                    Start
                  </v-btn>
                </v-col>
              </v-row>
            </v-container>
          </v-expansion-panel-text>
        </v-expansion-panel>
      </v-expansion-panels>
      <div class="mb-3" v-show="warning || error || connectionFailure">
        <v-alert type="warning" v-model="warning" closable>
          {{ warningText }}
        </v-alert>
        <v-alert type="error" v-model="error" closable>
          {{ errorText }}
        </v-alert>
        <v-alert type="error" v-model="connectionFailure">
          OpenC3 backend connection failed.
        </v-alert>
      </div>
      <v-tabs ref="tabs" v-model="curTab" :key="`v-tabs_${config.tabs.length}`">
        <v-tab
          v-for="(tab, index) in config.tabs"
          :key="index"
          @contextmenu="(event) => tabMenu(event, index)"
          data-test="tab"
        >
          {{ tab.tabName }}
        </v-tab>
        <v-tooltip location="bottom">
          <template v-slot:activator="{ props }">
            <v-btn
              icon="mdi-tab-plus"
              class="ml-2"
              variant="text"
              @click="addTab"
              v-bind="props"
              :class="config.tabs.length === 0 ? 'pulse-button' : ''"
              data-test="new-tab"
            />
          </template>
          <span>Add Component</span>
        </v-tooltip>
      </v-tabs>
      <v-tabs-window
        :model-value="curTab"
        :key="`v-tabs-window_${config.tabs.length}`"
      >
        <v-tabs-window-item
          v-for="(tab, index) in config.tabs"
          :key="tab.ref"
          eager
        >
          <keep-alive>
            <v-card flat>
              <v-divider />
              <v-card-title class="pa-3 d-flex align-center">
                <span v-text="tab.name" />
                <v-spacer />
                <v-tooltip location="bottom">
                  <template v-slot:activator="{ props }">
                    <v-btn
                      variant="text"
                      icon="mdi-delete"
                      @click="() => deleteComponent(index)"
                      v-bind="props"
                      data-test="delete-component"
                    />
                  </template>
                  <span> Remove Component </span>
                </v-tooltip>
              </v-card-title>
              <component
                v-bind="$attrs"
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
            </v-card>
          </keep-alive>
        </v-tabs-window-item>
      </v-tabs-window>
      <v-card v-if="!config.tabs.length">
        <v-card-title>You're not viewing any packets</v-card-title>
        <v-card-text>Click the new tab icon to start.</v-card-text>
      </v-card>
    </v-card>
    <!-- Dialogs for opening and saving configs -->
    <open-config-dialog
      v-if="openConfig"
      v-model="openConfig"
      :configKey="configKey"
      @success="openConfiguration"
    />
    <save-config-dialog
      v-if="saveConfig"
      v-model="saveConfig"
      :configKey="configKey"
      @success="saveConfiguration"
    />
    <!-- Dialog for renaming a new tab -->
    <v-dialog v-model="tabNameDialog" width="600">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span> DataViewer: Rename Tab</span>
          <v-spacer />
        </v-toolbar>
        <v-card-text>
          <v-text-field
            v-model="newTabName"
            label="Tab name"
            data-test="rename-tab-input"
          />
        </v-card-text>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn
            variant="outlined"
            data-test="cancel-rename"
            @click="cancelTabRename"
          >
            Cancel
          </v-btn>
          <v-btn
            variant="flat"
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
    <v-menu v-model="showTabMenu" :target="[tabMenuX, tabMenuY]">
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
import { Api, Cable, OpenC3Api } from '@openc3/js-common/services'
import {
  Config,
  OpenConfigDialog,
  SaveConfigDialog,
  TopBar,
} from '@openc3/vue-common/components'
import { TimeFilters } from '@openc3/vue-common/util'

import AddComponentDialog from '@/tools/DataViewer/AddComponentDialog'
// DynamicComponent is how we load custom user components
import DynamicComponent from '@/tools/DataViewer/DynamicComponent'
// Import the built-in DataViewer components
import DumpComponent from '@/tools/DataViewer/DumpComponent'
import ValueComponent from '@/tools/DataViewer/ValueComponent'

export default {
  components: {
    AddComponentDialog,
    OpenConfigDialog,
    SaveConfigDialog,
    DynamicComponent,
    DumpComponent,
    ValueComponent,
    TopBar,
  },
  mixins: [Config, TimeFilters],
  data() {
    return {
      title: 'Data Viewer',
      configKey: 'data_viewer',
      api: null,
      timeZone: 'local',
      // Initialize with all built-in components
      components: [
        {
          label: 'COSMOS Packet Raw/Decom',
          value: 'DumpComponent',
          items: false,
        },
        {
          label: 'COSMOS Item Value',
          value: 'ValueComponent',
          items: true,
        },
      ],
      counter: 0,
      panel: 0,
      componentType: null,
      componentName: null,
      openConfig: false,
      saveConfig: false,
      cable: new Cable(),
      subscription: null,
      startDate: null,
      startTime: null,
      endDate: null,
      endTime: null,
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
            {
              label: 'Reset Configuration',
              icon: 'mdi-monitor-shimmer',
              command: () => {
                this.resetConfig()
                this.resetConfigBase()
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
      let startTemp = null
      let endTemp = null
      try {
        if (this.timeZone === 'local') {
          startTemp = new Date(this.startDate + ' ' + this.startTime)
          if (this.endDate !== null && this.endTime !== null) {
            endTemp = new Date(this.endDate + ' ' + this.endTime)
          }
        } else {
          startTemp = new Date(this.startDate + ' ' + this.startTime + 'Z')
          if (this.endDate !== null && this.endTime !== null) {
            endTemp = new Date(this.endDate + ' ' + this.endTime + 'Z')
          }
        }
      } catch (e) {
        return
      }
      return {
        start_time: startTemp.getTime() * 1000000,
        end_time: endTemp ? endTemp.getTime() * 1000000 : null,
      }
    },
    allPackets: function () {
      return this.config.tabs.flatMap((tab) => {
        return tab.packets
      })
    },
  },
  watch: {
    // canStart is set by the subscription when it connects.
    // We set autoStart to true during mounted() when loading from
    // a route or a previous saved configuration.
    canStart: function (newVal, _) {
      if (newVal === true && this.autoStart) {
        this.start()
      }
    },
    config: {
      handler: function () {
        this.saveDefaultConfig(this.config)
      },
      deep: true,
    },
  },
  async created() {
    this.api = new OpenC3Api()
    await this.api
      .get_setting('time_zone')
      .then((response) => {
        if (response) {
          this.timeZone = response
        }
      })
      .catch((error) => {
        // Do nothing
      })
    let now = new Date()
    this.startDate = this.formatDate(now, this.timeZone)
    this.startTime = this.formatTimeHMS(now, this.timeZone)

    // Determine if there are any user added widgets
    Api.get('/openc3-api/widgets').then((response) => {
      response.data.forEach((widget) => {
        // Only list the ones following the naming convention DataviewerxxxxxWidget
        const found = widget.match(/DATAVIEWER([A-Z]+)/)
        if (found) {
          Api.get(`/openc3-api/widgets/${widget}`).then((response) => {
            let label = response.data.label
            let items = response.data.items
            if (label === null) {
              label = response.data.name.slice(10)
              label = label.charAt(0) + label.slice(1).toLowerCase()
            }
            this.components.push({
              label: label,
              value: found[0],
              items: items,
            })
          })
        }
      })
    })
    this.subscribe()
  },
  mounted: function () {
    // Called like /tools/dataviewer?config=config
    if (this.$route.query && this.$route.query.config) {
      this.autoStart = true
      this.openConfiguration(this.$route.query.config, true) // routed
    } else {
      let config = this.loadDefaultConfig()
      // Only apply the config if it's not an empty object (config does not exist)
      if (JSON.stringify(config) !== '{}') {
        this.autoStart = true
        this.config = config
      }
    }
  },
  unmounted: function () {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    this.cable.disconnect()
  },
  methods: {
    packetTitle: function (packet) {
      if (packet.itemName !== undefined) {
        return `${packet.targetName} ${packet.packetName} ${packet.itemName}`
      } else {
        return `${packet.targetName} ${packet.packetName} [ ${packet.mode} ]`
      }
    },
    start: function () {
      this.autoStart = false
      // Check for a future start time
      if (this.startEndTime.start_time > new Date().getTime() * 1000000) {
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
      if (this.startEndTime.end_time) {
        this.warningText =
          'Note: End date/time is greater than current date/time. Data will continue to stream in real-time until ' +
          this.endDate +
          ' ' +
          this.endTime +
          ' is reached.'
        this.warning = true
      }
      this.running = true
      this.addToSubscription()
    },
    stop: function () {
      this.running = false
      this.removeFromSubscription()
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
          if (this.running) this.addToSubscription()
        })
    },
    addToSubscription: function (packets) {
      packets = packets || this.allPackets

      let itemBased = []
      let packetBased = []
      packets.forEach((packet) => {
        if (packet.itemName !== undefined) {
          itemBased.push(packet)
        } else {
          packetBased.push(packet)
        }
      })

      if (itemBased.length > 0) {
        // Add the items to the subscription
        OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(
          (refreshed) => {
            if (refreshed) {
              OpenC3Auth.setTokens()
            }
            this.subscription.perform('add', {
              scope: window.openc3Scope,
              token: localStorage.openc3Token,
              items: itemBased.map(this.itemSubscriptionKey),
              ...this.startEndTime,
            })
          },
        )
      }

      if (packetBased.length > 0) {
        // Group by mode
        const modeGroups = packetBased.reduce((groups, packet) => {
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
          },
        )
      }
    },
    removeFromSubscription: function (packets) {
      packets = packets || this.allPackets

      let itemBased = []
      let packetBased = []
      packets.forEach((packet) => {
        if (packet.itemName !== undefined) {
          itemBased.push(packet)
        } else {
          packetBased.push(packet)
        }
      })

      if (itemBased.length > 0) {
        this.subscription.perform('remove', {
          scope: window.openc3Scope,
          token: localStorage.openc3Token,
          items: itemBased.map(this.itemSubscriptionKey),
        })
      }
      if (packetBased.length > 0) {
        this.subscription.perform('remove', {
          scope: window.openc3Scope,
          token: localStorage.openc3Token,
          packets: packetBased.map(this.subscriptionKey),
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
        return
      }

      // Iterate over the parsed data and send it to the appropriate component

      // If the parsed data has a __type of ITEMS, we're dealing with an array
      // of items with attributes named after the item. We need to filter
      // the items per tab and send them to the appropriate component.
      if (parsed[0].__type === 'ITEMS') {
        this.config.tabs.forEach((tab, i) => {
          // Skip tabs without items
          if (!tab.items) return

          let keys = tab.packets.map((itemConfig) => this.itemKey(itemConfig))
          let filtered = parsed
            .map((item) => {
              let newItem = {}
              // These fields are always in the item subscription
              newItem['__type'] = item['__type']
              newItem['__time'] = item['__time']
              let found = false
              keys.forEach((key) => {
                if (item[key]) {
                  found = true
                  newItem[key] = item[key]
                }
              })
              if (found) {
                return newItem
              } else {
                return
              }
            })
            .filter(Boolean) // Remove undefined items
          if (
            filtered &&
            typeof this.$refs[tab.ref][0].receive === 'function'
          ) {
            this.$refs[tab.ref][0].receive(filtered)
          }
        })
      } else {
        const groupedPackets = parsed.reduce((groups, packet) => {
          if (groups[packet.__packet]) {
            groups[packet.__packet].push(packet)
          } else {
            groups[packet.__packet] = [packet]
          }
          return groups
        }, {})
        this.config.tabs.forEach((tab, i) => {
          // Skip tabs with items
          if (tab.items) return
          tab.packets.forEach((packetConfig) => {
            let packetName = this.packetKey(packetConfig)
            this.receivedPackets[packetName] = true
            if (
              groupedPackets[packetName] &&
              typeof this.$refs[tab.ref][0].receive === 'function'
            ) {
              this.$refs[tab.ref][0].receive(groupedPackets[packetName])
            }
          })
        })
        this.receivedPackets = { ...this.receivedPackets }
      }
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
    itemKey: function (item) {
      let key = item.mode + '__'
      if (item.cmdOrTlm === 'TLM') {
        key += 'TLM'
      } else {
        key += 'CMD'
      }
      key += `__${item.targetName}__${item.packetName}__${item.itemName}`
      if (item.mode === 'DECOM') key += `__${item.valueType}`
      return key
    },
    // Maybe combine subscriptionKey with itemSubscriptionKey
    subscriptionKey: function (packet) {
      const cmdOrTlm = packet.cmdOrTlm.toUpperCase()
      let key = `${packet.mode}__${cmdOrTlm}__${packet.targetName}__${packet.packetName}`
      if (packet.mode === 'DECOM') key += `__${packet.valueType}`
      return key
    },
    itemSubscriptionKey: function (item) {
      let key = `DECOM__TLM__${item.targetName}__${item.packetName}__${item.itemName}__${item.valueType}`
      return key
    },
    resetConfig: function () {
      this.stop()
      this.receivedPackets = {}
      this.config.tabs = []
    },
    openConfiguration: function (name, routed = false) {
      this.openConfigBase(name, routed, (config) => {
        this.stop()
        this.receivedPackets = {}
        this.config = config
        // Only call start() if autoStart is false like during a reload.
        // Otherwise we might call start before the subscription is valid.
        // See watch on canStart for more info.
        if (this.autoStart === false) {
          this.start()
        }
      })
    },
    saveConfiguration: function (name) {
      this.saveConfigBase(name, this.config)
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
        items: event.component.items,
        config: { timeZone: this.timeZone },
        ref: Date.now(),
      })
      this.curTab = this.config.tabs.length - 1

      if (this.running) {
        this.addToSubscription(event.packets)
      }
      this.cancelAddComponent()
    },
    cancelAddComponent: function () {
      this.showAddComponentDialog = false
    },
    deleteComponent: function (tabIndex) {
      // Check for item based components first
      if (this.config.tabs[tabIndex].packets[0].itemName !== undefined) {
        // Get the list of items the other tabs are using
        let itemsInUse = []
        this.config.tabs.forEach((tab, i) => {
          // Skip tabs without items
          if (!tab.items) return

          if (i !== tabIndex) {
            itemsInUse = itemsInUse.concat(tab.packets.map(this.itemKey))
          }
        })
        // Filter out any items that are in use
        let filtered = this.config.tabs[tabIndex].packets.filter(
          (packet) => itemsInUse.indexOf(this.itemKey(packet)) === -1,
        )
        if (filtered.length > 0) {
          this.removeFromSubscription(filtered)
        }
      } else {
        // Get the list of packets the other tabs are using
        let packetsInUse = []
        this.config.tabs.forEach((tab, i) => {
          // Skip tabs with items
          if (tab.items) return

          if (i !== tabIndex) {
            packetsInUse = packetsInUse.concat(tab.packets.map(this.packetKey))
          }
        })
        // Filter out any packets that are in use
        let filtered = this.config.tabs[tabIndex].packets.filter(
          (packet) => packetsInUse.indexOf(this.packetKey(packet)) === -1,
        )
        if (filtered.length > 0) {
          this.removeFromSubscription(filtered)
        }
      }
      this.config.tabs.splice(tabIndex, 1)
    },
  },
}
</script>

<style scoped>
.v-expansion-panel-text {
  .container {
    margin: 0px;
  }
}
.v-expansion-panel-title {
  min-height: 10px;
  padding: 5px;
}
/* Add some juice to the START button to indicate it needs to be pressed */
.pulse-button {
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
