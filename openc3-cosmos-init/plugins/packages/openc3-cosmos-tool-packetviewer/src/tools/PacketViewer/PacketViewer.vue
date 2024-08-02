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
      <div style="padding: 10px">
        <target-packet-item-chooser
          :initial-target-name="this.$route.params.target"
          :initial-packet-name="this.$route.params.packet"
          @on-set="packetChanged($event)"
        />
      </div>
      <v-card-title>
        Items
        <v-spacer />
        <v-text-field
          v-model="search"
          label="Search"
          prepend-inner-icon="mdi-magnify"
          clearable
          outlined
          dense
          single-line
          hide-details
          class="search"
        />
      </v-card-title>
      <v-data-table
        :headers="headers"
        :items="rows"
        :search="search"
        :items-per-page="itemsPerPage"
        @update:items-per-page="itemsPerPage = $event"
        :footer-props="{
          itemsPerPageOptions: [10, 20, 50, 100, 500, 1000],
          showFirstLastPage: true,
          firstIcon: 'mdi-page-first',
          lastIcon: 'mdi-page-last',
          prevIcon: 'mdi-chevron-left',
          nextIcon: 'mdi-chevron-right',
        }"
        multi-sort
        dense
      >
        <template v-slot:item.name="{ item }">
          {{ item.name }}<span v-if="item.derived">&nbsp;*</span>
        </template>
        <template v-slot:item.value="{ item }">
          <value-widget
            :value="item.value"
            :limits-state="item.limitsState"
            :counter="item.counter"
            :parameters="[targetName, packetName, item.name]"
            :settings="[['WIDTH', '100%']]"
            :time-zone="timeZone"
          />
        </template>
        <template v-slot:footer.prepend
          >* indicates a&nbsp;
          <a href="/tools/staticdocs/docs/configuration/telemetry#derived-items"
            >DERIVED</a
          >&nbsp;item</template
        >
      </v-data-table>
    </v-card>
    <v-dialog
      v-model="optionsDialog"
      @keydown.esc="optionsDialog = false"
      max-width="300"
    >
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span>Options</span>
          <v-spacer />
        </v-system-bar>
        <v-card-text>
          <div class="pa-3">
            <v-text-field
              min="0"
              max="10000"
              step="100"
              type="number"
              label="Refresh Interval (ms)"
              :value="refreshInterval"
              @change="refreshInterval = $event"
              data-test="refresh-interval"
            />
          </div>
          <div class="pa-3">
            <v-text-field
              min="1"
              max="10000"
              step="1"
              type="number"
              label="Time at which to mark data Stale (seconds)"
              :value="staleLimit"
              @change="staleLimit = parseInt($event)"
              data-test="stale-limit"
            />
          </div>
        </v-card-text>
      </v-card>
    </v-dialog>
    <!-- Note we're using v-if here so it gets re-created each time and refreshes the list -->
    <open-config-dialog
      v-if="showOpenConfig"
      v-model="showOpenConfig"
      :configKey="configKey"
      @success="openConfiguration"
    />
    <!-- Note we're using v-if here so it gets re-created each time and refreshes the list -->
    <save-config-dialog
      v-if="showSaveConfig"
      v-model="showSaveConfig"
      :configKey="configKey"
      @success="saveConfiguration"
    />
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'
import ValueWidget from '@openc3/tool-common/src/components/widgets/ValueWidget'
import TargetPacketItemChooser from '@openc3/tool-common/src/components/TargetPacketItemChooser'
import TopBar from '@openc3/tool-common/src/components/TopBar'
import Config from '@openc3/tool-common/src/components/config/Config'
import OpenConfigDialog from '@openc3/tool-common/src/components/config/OpenConfigDialog'
import SaveConfigDialog from '@openc3/tool-common/src/components/config/SaveConfigDialog'

// Used in the menu and openConfiguration lookup
const valueTypeToRadioGroup = {
  WITH_UNITS: 'Formatted Items with Units',
  FORMATTED: 'Formatted Items',
  CONVERTED: 'Converted Items',
  RAW: 'Raw Items',
}

export default {
  components: {
    TargetPacketItemChooser,
    ValueWidget,
    TopBar,
    OpenConfigDialog,
    SaveConfigDialog,
  },
  mixins: [Config],
  data() {
    return {
      title: 'Packet Viewer',
      configKey: 'packet_viewer',
      showOpenConfig: false,
      showSaveConfig: false,
      timeZone: 'local',
      search: '',
      data: [],
      headers: [
        { text: 'Name', value: 'name', align: 'end' },
        { text: 'Value', value: 'value' },
      ],
      optionsDialog: false,
      showIgnored: false,
      derivedLast: false,
      ignoredItems: [],
      derivedItems: [],
      menus: [
        {
          label: 'File',
          items: [
            {
              label: 'Options',
              icon: 'mdi-cog',
              command: () => {
                this.optionsDialog = true
              },
            },
            {
              divider: true,
            },
            {
              label: 'Open Configuration',
              icon: 'mdi-folder-open',
              command: () => {
                this.showOpenConfig = true
              },
            },
            {
              label: 'Save Configuration',
              icon: 'mdi-content-save',
              command: () => {
                this.showSaveConfig = true
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
        {
          label: 'View',
          radioGroup: 'Formatted Items with Units', // Default radio selected
          items: [
            {
              label: 'Show Ignored Items',
              checkbox: true,
              checked: false,
              command: (item) => {
                this.showIgnored = item.checked
              },
            },
            {
              label: 'Display DERIVED Last',
              checkbox: true,
              checked: false,
              command: (item) => {
                this.derivedLast = item.checked
              },
            },
            {
              divider: true,
            },
            {
              label: valueTypeToRadioGroup['WITH_UNITS'],
              radio: true,
              command: () => {
                this.valueType = 'WITH_UNITS'
              },
            },
            {
              label: valueTypeToRadioGroup['FORMATTED'],
              radio: true,
              command: () => {
                this.valueType = 'FORMATTED'
              },
            },
            {
              label: valueTypeToRadioGroup['CONVERTED'],
              radio: true,
              command: () => {
                this.valueType = 'CONVERTED'
              },
            },
            {
              label: valueTypeToRadioGroup['RAW'],
              radio: true,
              command: () => {
                this.valueType = 'RAW'
              },
            },
          ],
        },
      ],
      updater: null,
      counter: 0,
      targetName: '',
      packetName: '',
      valueType: 'WITH_UNITS',
      refreshInterval: 1000,
      staleLimit: 30,
      rows: [],
      menuItems: [],
      itemsPerPage: 20,
      api: null,
    }
  },
  watch: {
    showIgnored: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
    derivedLast: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
    valueType: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
    // Create a watcher on refreshInterval so we can change the updater
    refreshInterval: function () {
      this.changeUpdater(false)
      this.saveDefaultConfig(this.currentConfig)
    },
    staleLimit: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
    itemsPerPage: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
  },
  computed: {
    currentConfig: function () {
      return {
        target: this.targetName,
        packet: this.packetName,
        refreshInterval: this.refreshInterval,
        staleLimit: this.staleLimit,
        showIgnored: this.showIgnored,
        derivedLast: this.derivedLast,
        valueType: this.valueType,
        itemsPerPage: this.itemsPerPage,
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

    // Called like /tools/packetviewer?config=temps
    if (this.$route.query && this.$route.query.config) {
      this.openConfiguration(this.$route.query.config, true) // routed
      this.changeUpdater(true)
    } else {
      // Merge default config into the currentConfig in case default isn't yet defined
      let config = { ...this.currentConfig, ...this.loadDefaultConfig() }
      this.applyConfig(config)
      // If we're passed in the route then manually call packetChanged to update
      if (this.$route.params.target && this.$route.params.packet) {
        // Initial position of chooser should be correct so call packetChanged for it
        this.packetChanged({
          targetName: this.$route.params.target.toUpperCase(),
          packetName: this.$route.params.packet.toUpperCase(),
        })
      } else {
        if (config.target && config.packet) {
          // Chooser probably won't be at the right packet so need to refresh
          this.$router.push({
            name: 'PackerViewer',
            params: {
              target: config.target,
              packet: config.packet,
            },
          })
          this.$router.go()
        }
      }
      this.changeUpdater(true)
    }
  },
  beforeDestroy() {
    if (this.updater != null) {
      clearInterval(this.updater)
      this.updater = null
    }
  },
  methods: {
    packetChanged(event) {
      this.api.get_target(event.targetName).then((target) => {
        this.ignoredItems = target.ignored_items
      })
      this.api
        .get_packet_derived_items(event.targetName, event.packetName)
        .then((derived) => {
          this.derivedItems = derived
        })

      this.targetName = event.targetName
      this.packetName = event.packetName
      if (
        this.$route.params.target !== event.targetName ||
        this.$route.params.packet !== event.packetName
      ) {
        this.saveDefaultConfig(this.currentConfig)
        this.$router.push({
          name: 'PackerViewer',
          params: {
            target: this.targetName,
            packet: this.packetName,
          },
        })
      }
      this.changeUpdater(true)
    },
    changeUpdater(clearExisting) {
      if (this.updater != null) {
        clearInterval(this.updater)
        this.updater = null
      }
      if (clearExisting) {
        this.rows = []
      }
      this.updater = setInterval(() => {
        this.api
          .get_tlm_packet(
            this.targetName,
            this.packetName,
            this.valueType,
            this.staleLimit,
          )
          .then((data) => {
            // Make sure data isn't null or undefined. Note this is the only valid use of == or !=
            if (data != null) {
              this.counter += 1
              let derived = []
              let other = []
              data.forEach((value) => {
                if (!this.showIgnored && this.ignoredItems.includes(value[0])) {
                  return
                }
                if (this.derivedItems.includes(value[0])) {
                  derived.push({
                    name: value[0],
                    value: value[1],
                    limitsState: value[2],
                    derived: true,
                    counter: this.counter,
                  })
                } else {
                  other.push({
                    name: value[0],
                    value: value[1],
                    limitsState: value[2],
                    derived: false,
                    counter: this.counter,
                  })
                }
              })
              if (this.derivedLast) {
                this.rows = other.concat(derived)
              } else {
                this.rows = derived.concat(other)
              }
            }
          })
          // Catch errors but just log to the console
          // We don't clear the updater because errors can happen on upgrade
          // and we want to continue updating once the new plugin comes online
          .catch((error) => {
            // eslint-disable-next-line
            console.log(error)
          })
      }, this.refreshInterval)
    },
    resetConfig: function () {
      this.targetName = ''
      this.packetName = ''
      this.refreshInterval = 1000
      this.staleLimit = 30
      this.showIgnored = false
      this.derivedLast = false
      this.valueType = 'WITH_UNITS'
      this.itemsPerPage = 20
    },
    applyConfig: function (config) {
      this.targetName = config.target
      this.packetName = config.packet
      this.refreshInterval = config.refreshInterval || 1000
      this.staleLimit = config.staleLimit || 30
      this.showIgnored = config.showIgnored || false
      this.menus[1].items[0].checked = this.showIgnored
      this.derivedLast = config.derivedLast || false
      this.menus[1].items[1].checked = this.derivedLast
      this.valueType = config.valueType || 'WITH_UNITS'
      this.menus[1].radioGroup = valueTypeToRadioGroup[this.valueType]
      this.itemsPerPage = config.itemsPerPage || 20
    },
    openConfiguration: function (name, routed = false) {
      this.openConfigBase(name, routed, async (config) => {
        this.applyConfig(config)
        this.saveDefaultConfig(config)
        if (
          this.$route.params.target !== config.target ||
          this.$route.params.packet !== config.packet ||
          this.$route.query.config !== name
        ) {
          // Need full refresh since chooser won't be on the right packet
          this.$router.push({
            name: 'PackerViewer',
            params: {
              target: config.target,
              packet: config.packet,
            },
            query: {
              config: name,
            },
          })
          this.$router.go()
        }
      })
    },
    saveConfiguration: function (name) {
      this.saveConfigBase(name, this.currentConfig)
    },
  },
}
</script>
