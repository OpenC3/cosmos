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
      <v-card-title class="d-flex align-center justify-content-space-between">
        Items
        <v-spacer />
        <v-text-field
          v-model="search"
          label="Search"
          prepend-inner-icon="mdi-magnify"
          clearable
          variant="outlined"
          density="compact"
          single-line
          hide-details
          class="search"
          data-test="search"
        />
      </v-card-title>
      <v-data-table
        :search="search"
        :headers="headers"
        :header-props="{
          style: 'width: 50%',
        }"
        :items="rows"
        :custom-filter="filter"
        :sort-by="sortBy"
        multi-sort
        v-model:items-per-page="itemsPerPage"
        :items-per-page-options="[10, 20, 50, 100, -1]"
        density="compact"
      >
        <template v-slot:item.name="{ item }">
          <div @contextmenu="(event) => showContextMenu(event, item)">
            <v-tooltip bottom :key="`${item.name}-${isPinned(item.name)}`">
              <template v-slot:activator="{ props }">
                <v-icon
                  v-if="isPinned(item.name)"
                  v-bind="props"
                  class="pin-item"
                >
                  mdi-pin
                </v-icon>
              </template>
              <span
                >Pinned items remain at the top.<br />Right click to
                unpin.</span
              >
            </v-tooltip>
            {{ item.name }}<span v-if="item.derived">&nbsp;*</span>
          </div>
        </template>
        <template v-slot:item.value="{ item }">
          <value-widget
            :key="item.name"
            :value="item.value"
            :limits-state="item.limitsState"
            :counter="item.counter"
            :parameters="[targetName, packetName, item.name]"
            :settings="[['WIDTH', '100%']]"
            :screen-time-zone="timeZone"
          />
        </template>
        <template v-slot:footer.prepend>
          <v-tooltip right close-delay="2000">
            <template v-slot:activator="{ props }">
              <v-icon v-bind="props" class="info-tooltip">
                mdi-information-variant-circle
              </v-icon>
            </template>
            <span>
              Name with * indicates
              <a
                href="/tools/staticdocs/docs/configuration/telemetry#derived-items"
                target="_blank"
                >DERIVED</a
              >&nbsp;item<br />
              Right click name to pin item<br />
              Right click value for details / graph
            </span>
          </v-tooltip>
          <v-spacer />
        </template>
      </v-data-table>
    </v-card>
    <v-dialog
      v-model="optionsDialog"
      @keydown.esc="optionsDialog = false"
      max-width="360px"
    >
      <v-card>
        <v-toolbar :height="24">
          <v-spacer />
          <span>Options</span>
          <v-spacer />
        </v-toolbar>
        <v-card-text>
          <div class="pa-3">
            <v-text-field
              min="0"
              max="10000"
              step="100"
              type="number"
              label="Refresh Interval (ms)"
              v-model="refreshInterval"
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
              :model-value="staleLimit"
              @update:model-value="staleLimit = parseInt($event)"
              min-width="280px"
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
    <v-menu v-model="contextMenuShown" :target="[x, y]" absolute offset-y>
      <v-list>
        <v-list-item
          v-for="(item, index) in contextMenuOptions"
          :key="index"
          @click.stop="item.action"
        >
          <v-list-item-title>{{ item.title }}</v-list-item-title>
        </v-list-item>
      </v-list>
    </v-menu>
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'
import {
  Config,
  OpenConfigDialog,
  SaveConfigDialog,
  TargetPacketItemChooser,
  TopBar,
} from '@openc3/vue-common/components'
import { ValueWidget } from '@openc3/vue-common/widgets'

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
        {
          title: 'Name',
          key: 'name',
          align: 'end',
        },
        { title: 'Value', key: 'value' },
      ],
      sortBy: [{ key: 'pinned', order: 'desc' }],
      optionsDialog: false,
      showIgnored: false,
      derivedLast: false,
      ignoredItems: [],
      derivedItems: [],
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
      pinnedItems: [],
      contextMenuShown: false,
      itemName: '',
      x: 0,
      y: 0,
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
    pinnedItems: {
      handler(_newVal, _oldVal) {
        this.saveDefaultConfig(this.currentConfig)
      },
      deep: true, // Because pinnedItems is an array
    },
  },
  computed: {
    menus: function () {
      return [
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
          items: [
            {
              label: 'Show Ignored Items',
              checkbox: true,
              checked: this.showIgnored,
              command: (item) => {
                this.showIgnored = !this.showIgnored
              },
            },
            {
              label: 'Display DERIVED Last',
              checkbox: true,
              checked: this.derivedLast,
              command: (item) => {
                this.derivedLast = !this.derivedLast
              },
            },
            {
              divider: true,
            },
            {
              radioGroup: true,
              value: this.valueType,
              command: (value) => {
                this.valueType = value
              },
              choices: [
                {
                  label: valueTypeToRadioGroup['WITH_UNITS'],
                  value: 'WITH_UNITS',
                },
                {
                  label: valueTypeToRadioGroup['FORMATTED'],
                  value: 'FORMATTED',
                },
                {
                  label: valueTypeToRadioGroup['CONVERTED'],
                  value: 'CONVERTED',
                },
                {
                  label: valueTypeToRadioGroup['RAW'],
                  value: 'RAW',
                },
              ],
            },
          ],
        },
      ]
    },
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
        pinnedItems: this.pinnedItems,
      }
    },
    contextMenuOptions: function () {
      let options = []
      if (this.isPinned(this.itemName)) {
        options.push({
          title: 'Unpin Item',
          action: () => {
            this.contextMenuShown = false
            this.pinnedItems = this.pinnedItems.filter(
              (item) =>
                !(
                  item.target === this.targetName &&
                  item.packet === this.packetName &&
                  item.item === this.itemName
                ),
            )
          },
        })
      } else {
        options.push({
          title: 'Pin Item',
          action: () => {
            this.contextMenuShown = false
            this.pinnedItems.push({
              target: this.targetName,
              packet: this.packetName,
              item: this.itemName,
            })
          },
        })
      }
      return options
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
        }
      }
      this.changeUpdater(true)
    }
  },
  beforeUnmount() {
    if (this.updater != null) {
      clearInterval(this.updater)
      this.updater = null
    }
  },
  methods: {
    showContextMenu(e, item) {
      e.preventDefault()
      this.itemName = item.name
      this.contextMenuShown = false
      this.x = e.clientX
      this.y = e.clientY
      this.$nextTick(() => {
        this.contextMenuShown = true
      })
    },
    isPinned(name) {
      return this.pinnedItems.find(
        (item) =>
          item.target === this.targetName &&
          item.packet === this.packetName &&
          item.item === name,
      )
    },
    filter(value, search, _item) {
      if (this.isPinned(value)) {
        return true
      } else {
        return value.toString().indexOf(search.toUpperCase()) >= 0
      }
    },
    packetChanged(event) {
      this.api
        .get_target(event.targetName)
        .then((target) => {
          if (target) {
            this.ignoredItems = target.ignored_items

            return this.api.get_packet_derived_items(
              event.targetName,
              event.packetName,
            )
          } else {
            // Probably got here from an old config or URL params that point to something that no longer exists
            // (e.g. the plugin that defined this target was deleted). Unset these to avoid API errors.
            this.targetName = null
            this.packetName = null
            this.$router.push({
              name: 'PackerViewer',
              params: {},
            })
          }
        })
        .then((derived) => {
          if (derived) {
            this.derivedItems = derived

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
          }
        })
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
        if (!this.targetName || !this.packetName) {
          return // noop if target/packet aren't set
        }
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
                    pinned: this.isPinned(value[0]),
                  })
                } else {
                  other.push({
                    name: value[0],
                    value: value[1],
                    limitsState: value[2],
                    derived: false,
                    counter: this.counter,
                    pinned: this.isPinned(value[0]),
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
      this.refreshInterval = 1000
      this.staleLimit = 30
      this.showIgnored = false
      this.derivedLast = false
      this.valueType = 'WITH_UNITS'
      this.itemsPerPage = 20
      this.pinnedItems = []
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
      this.pinnedItems = config.pinnedItems || []
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
        }
      })
    },
    saveConfiguration: function (name) {
      this.saveConfigBase(name, this.currentConfig)
    },
  },
}
</script>

<style scoped>
a {
  color: blue;
}
.pin-item {
  float: left;
}
.info-tooltip {
  margin-left: 10px;
}
</style>
