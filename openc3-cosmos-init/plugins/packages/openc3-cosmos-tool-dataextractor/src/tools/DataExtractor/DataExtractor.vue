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
      <v-container>
        <v-row>
          <v-col>
            <v-text-field
              v-model="startDate"
              label="Start Date"
              type="date"
              :max="todaysDate"
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
            >
            </v-text-field>
          </v-col>
          <v-col>
            <v-text-field
              v-model="endDate"
              label="End Date"
              type="date"
              :max="todaysDate"
              :rules="[rules.required]"
              data-test="end-date"
            />
          </v-col>
          <v-col>
            <v-text-field
              v-model="endTime"
              label="End Time"
              type="time"
              step="1"
              :rules="[rules.required]"
              data-test="end-time"
            >
            </v-text-field>
          </v-col>
        </v-row>
        <v-row no-gutters>
          <v-col>
            <v-radio-group v-model="cmdOrTlm" inline hide-details class="mt-0">
              <v-radio label="Command" value="cmd" data-test="cmd-radio" />
              <v-radio label="Telemetry" value="tlm" data-test="tlm-radio" />
            </v-radio-group>
          </v-col>
        </v-row>
        <v-row>
          <v-col>
            <target-packet-item-chooser
              @add-item="addItem($event)"
              button-text="Add Item"
              :mode="cmdOrTlm"
              :hidden="true"
              choose-item
              allow-all
            />
          </v-col>
        </v-row>
      </v-container>
      <v-toolbar class="pl-3">
        <v-progress-circular :model-value="progress" />
        &nbsp; Processed: {{ totalPacketsReceived }} packets,
        {{ totalItemsReceived }} items
        <v-spacer />
        <v-btn
          class="bg-primary"
          @click="processItems"
          :disabled="items.length < 1"
        >
          {{ processButtonText }}
        </v-btn>
        <v-spacer />
        <v-tooltip location="top">
          <template v-slot:activator="{ props }">
            <v-btn
              icon="mdi-pencil"
              variant="text"
              @click="editAll = true"
              v-bind="props"
              :disabled="items.length < 1"
              data-test="editAll"
            />
          </template>
          <span> Edit All Items </span>
        </v-tooltip>
        <v-tooltip location="top">
          <template v-slot:activator="{ props }">
            <v-btn
              icon="mdi-delete"
              variant="text"
              @click="deleteAll"
              v-bind="props"
              :disabled="items.length < 1"
              data-test="delete-all"
            />
          </template>
          <span>Delete All Items</span>
        </v-tooltip>
      </v-toolbar>
      <!-- <v-row no-gutters> -->
      <v-card width="100%">
        <v-card-title>
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
          />
        </v-card-title>
        <v-data-table
          :headers="headers"
          :items="items"
          :search="search"
          v-model:items-per-page="itemsPerPage"
          :items-per-page-options="[10, 20, 50, 100, -1]"
          multi-sort
          density="compact"
        >
          <template v-slot:item.edit="{ item }">
            <v-tooltip location="top">
              <template v-slot:activator="{ props }">
                <v-icon
                  @click.stop="item.edit = true"
                  v-bind="props"
                  data-test="edit-row"
                >
                  mdi-pencil
                </v-icon>
              </template>
              <span>Edit Item</span>
            </v-tooltip>
            <v-dialog
              v-model="item.edit"
              @keydown.esc="item.edit = false"
              max-width="600"
            >
              <v-card>
                <v-toolbar height="24">
                  <v-spacer />
                  <span> DataExtractor: Edit Item Mode </span>
                  <v-spacer />
                </v-toolbar>
                <v-card-text>
                  <v-row class="mt-3 title-font">
                    <v-col>
                      {{ getItemLabel(item) }}
                    </v-col>
                  </v-row>
                  <v-row>
                    <v-col>
                      <v-select
                        hide-details
                        :items="modes"
                        label="Mode"
                        variant="outlined"
                        v-model="item.mode"
                      />
                    </v-col>
                  </v-row>
                  <v-row>
                    <v-col>
                      <v-select
                        hide-details
                        :items="valueTypes"
                        label="Value Type"
                        variant="outlined"
                        v-model="item.valueType"
                      />
                    </v-col>
                  </v-row>
                  <v-row>
                    <v-col>
                      <v-select
                        hide-details
                        :items="reducedTypes"
                        label="Reduced Type"
                        variant="outlined"
                        v-model="item.reducedType"
                      />
                    </v-col>
                  </v-row>
                </v-card-text>
                <v-card-actions class="px-2">
                  <v-spacer />
                  <v-btn variant="flat" @click="item.edit = false">
                    Close
                  </v-btn>
                </v-card-actions>
              </v-card>
            </v-dialog>
          </template>
          <template v-slot:item.delete="{ item }">
            <v-tooltip location="top">
              <template v-slot:activator="{ props }">
                <v-icon
                  @click="deleteItem(item)"
                  v-bind="props"
                  data-test="delete-row"
                >
                  mdi-delete
                </v-icon>
              </template>
              <span> Delete Item </span>
            </v-tooltip>
          </template>
        </v-data-table>
      </v-card>
    </v-card>
    <v-dialog
      v-model="editAll"
      @keydown.esc="editAll = !editAll"
      max-width="600"
    >
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span> DataExtractor: Edit All Items</span>
          <v-spacer />
        </v-toolbar>
        <v-card-text>
          <v-row class="mt-3">
            <v-col>
              This will change all items to the following data type!
            </v-col>
          </v-row>
          <v-row>
            <v-col>
              <v-select
                hide-details
                :items="modes"
                label="Mode"
                variant="outlined"
                v-model="allItemMode"
              />
            </v-col>
          </v-row>
          <v-row>
            <v-col>
              <v-select
                hide-details
                :items="valueTypes"
                label="Value Type"
                variant="outlined"
                v-model="allItemValueType"
              />
            </v-col>
          </v-row>
          <v-row>
            <v-col>
              <v-select
                hide-details
                :items="reducedTypes"
                label="Reduced Type"
                variant="outlined"
                v-model="allItemReducedType"
              />
            </v-col>
          </v-row>
        </v-card-text>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn variant="outlined" @click="editAll = !editAll"> Cancel </v-btn>
          <v-btn
            variant="flat"
            :disabled="!allItemValueType"
            @click="editAllItems()"
          >
            Ok
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
    <!-- Note we're using v-if here so it gets re-created each time and refreshes the list -->
    <open-config-dialog
      v-if="openConfig"
      v-model="openConfig"
      :configKey="configKey"
      @success="openConfiguration"
    />
    <!-- Note we're using v-if here so it gets re-created each time and refreshes the list -->
    <save-config-dialog
      v-if="saveConfig"
      v-model="saveConfig"
      :configKey="configKey"
      @success="saveConfiguration"
    />
  </div>
</template>

<script>
// Putting large data into Vue data section causes lots of overhead
let dataExtractorRawData = []

import { Cable, OpenC3Api } from '@openc3/js-common/services'
import {
  Config,
  OpenConfigDialog,
  SaveConfigDialog,
  TargetPacketItemChooser,
  TopBar,
} from '@openc3/vue-common/components'
import { TimeFilters } from '@openc3/vue-common/util'

export default {
  components: {
    OpenConfigDialog,
    SaveConfigDialog,
    TargetPacketItemChooser,
    TopBar,
  },
  mixins: [Config, TimeFilters],
  data() {
    return {
      title: 'Data Extractor',
      configKey: 'data_extractor',
      openConfig: false,
      saveConfig: false,
      api: null,
      timeZone: 'local',
      progress: 0,
      packetsReceived: 0,
      totalPacketsReceived: 0,
      itemsReceived: 0,
      totalItemsReceived: 0,
      processButtonText: 'Process',
      todaysDate: null,
      startDate: null,
      startTime: null,
      endTime: null,
      endDate: null,
      startDateTime: null,
      endDateTime: null,
      startDateTimeFilename: '',
      rules: {
        required: (value) => !!value || 'Required',
      },
      cmdOrTlm: 'tlm',
      items: [],
      search: '',
      headers: [
        { title: 'Target', value: 'targetName' },
        { title: 'Packet', value: 'packetName' },
        { title: 'Item', value: 'itemName' },
        { title: 'Mode', value: 'mode' },
        { title: 'ValueType', value: 'valueType' },
        { title: 'ReducedType', value: 'reducedType' },
        { title: 'Edit', value: 'edit' },
        { title: 'Delete', value: 'delete' },
      ],
      itemsPerPage: 20,
      columnMap: {},
      delimiter: ',',
      columnMode: 'normal',
      fileCount: 0,
      skipIgnored: true,
      fillDown: false,
      matlabHeader: false,
      uniqueOnly: false,
      keyMap: {},
      modes: ['DECOM', 'REDUCED_MINUTE', 'REDUCED_HOUR', 'REDUCED_DAY'],
      valueTypes: ['CONVERTED', 'RAW', 'FORMATTED', 'WITH_UNITS'],
      reducedTypes: ['SAMPLE', 'MIN', 'MAX', 'AVG', 'STDDEV'],
      editAll: false,
      allItemMode: 'DECOM',
      allItemValueType: 'CONVERTED',
      allItemReducedType: 'SAMPLE',
      // uniqueIgnoreOptions: ['NO', 'YES'],
      cable: new Cable(),
      subscription: null,
    }
  },
  watch: {
    delimiter: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
    fillDown: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
    matlabHeader: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
    uniqueOnly: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
    columnNode: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
    cmdOrTlm: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
    items: {
      handler: function () {
        this.saveDefaultConfig(this.currentConfig)
      },
      deep: true,
    },
    itemsPerPage: function () {
      this.saveDefaultConfig(this.currentConfig)
    },
  },
  computed: {
    menus: function () {
      return [
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
            {
              divider: true,
            },
            {
              radioGroup: true,
              value: this.delimiter,
              command: (value) => {
                this.delimiter = value
              },
              choices: [
                {
                  label: 'Comma Delimited',
                  value: ',',
                },
                {
                  label: 'Tab Delimited',
                  value: '\t',
                },
              ],
            },
          ],
        },
        {
          label: 'Mode',
          // radioGroup: 'Normal Columns', // Default radio selected
          items: [
            // TODO: Currently unimplemented
            // {
            //   label: 'Skip Ignored on Add',
            //   checkbox: true,
            //   checked: true, // Skip Ignored is the default
            //   command: () => {
            //     this.skipIgnored = !this.skipIgnored
            //   },
            // },
            // {
            //   divider: true,
            // },
            {
              label: 'Fill Down',
              checkbox: true,
              checked: this.fillDown,
              command: () => {
                this.fillDown = !this.fillDown
              },
            },
            {
              label: 'Matlab Header',
              checkbox: true,
              checked: this.matlabHeader,
              command: (item) => {
                this.matlabHeader = !this.matlabHeader
              },
            },
            {
              label: 'Unique Only',
              checkbox: true,
              checked: this.uniqueOnly,
              command: (item) => {
                this.uniqueOnly = !this.uniqueOnly
              },
            },
            {
              divider: true,
            },
            {
              radioGroup: true,
              value: this.columnMode,
              command: (value) => {
                this.columnMode = value
              },
              choices: [
                {
                  label: 'Normal Columns',
                  value: 'normal',
                },
                {
                  label: 'Full Column Names',
                  value: 'full',
                },
              ],
            },
          ],
        },
      ]
    },
    currentConfig: function () {
      return {
        delimiter: this.delimiter,
        fillDown: this.fillDown,
        matlabHeader: this.matlabHeader,
        uniqueOnly: this.uniqueOnly,
        columnMode: this.columnMode,
        cmdOrTlm: this.cmdOrTlm,
        items: this.items,
        itemsPerPage: this.itemsPerPage,
      }
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
    this.todaysDate = this.formatDate(now, this.timeZone)
    this.startDate = this.formatDate(now - 3600000, this.timeZone) // last hr data
    this.startTime = this.formatTimeHMS(now - 3600000, this.timeZone) // last hr data
    this.endTime = this.formatTimeHMS(now, this.timeZone)
    this.endDate = this.formatDate(now, this.timeZone)
  },
  mounted: function () {
    // Called like /tools/dataextractor?config=config
    if (this.$route.query && this.$route.query.config) {
      this.openConfiguration(this.$route.query.config, true) // routed
    } else {
      let config = this.loadDefaultConfig()
      // Only apply the config if it's not an empty object (config does not exist)
      if (JSON.stringify(config) !== '{}') {
        this.applyConfig(config)
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
    resetConfig: function () {
      this.delimiter = ','
      this.fillDown = false
      this.matlabHeader = false
      this.uniqueOnly = false
      this.columnMode = 'normal'
      let now = new Date()
      this.startDate = this.formatDate(now - 3600000, this.timeZone) // last hr data
      this.startTime = this.formatTimeHMS(now - 3600000, this.timeZone) // last hr data
      this.endTime = this.formatTimeHMS(now, this.timeZone)
      this.endDate = this.formatDate(now, this.timeZone)
      this.cmdOrTlm = 'tlm'
      this.items = []
      this.itemsPerPage = 20
      this.applyConfig(this.currentConfig)
    },
    applyConfig: function (config) {
      this.delimiter = config.delimiter || ','
      this.menus[0].radioGroup =
        this.delimiter === ',' ? 'Comma Delimited' : 'Tab Delimited'
      this.fillDown = config.fillDown
      this.menus[1].items[0].checked = this.fillDown || false
      this.matlabHeader = config.matlabHeader
      this.menus[1].items[1].checked = this.matlabHeader || false
      this.uniqueOnly = config.uniqueOnly
      this.menus[1].items[2].checked = this.uniqueOnly || false
      this.columnMode = config.columnMode
      this.menus[1].radioGroup =
        this.columnMode === 'normal' ? 'Normal Columns' : 'Full Column Names'
      this.cmdOrTlm = config.cmdOrTlm
      this.items = config.items
      this.itemsPerPage = config.itemsPerPage
    },
    openConfiguration: function (name, routed = false) {
      this.openConfigBase(name, routed, (config) => {
        this.applyConfig(config)
        this.startDate = config.startDate
        this.startTime = config.startTime
        this.endTime = config.endTime
        this.endDate = config.endDate
        this.saveDefaultConfig(this.currentConfig)
      })
    },
    saveConfiguration: function (name) {
      let config = this.currentConfig
      config.startDate = this.startDate
      config.startTime = this.startTime
      config.endTime = this.endTime
      config.endDate = this.endDate
      this.saveConfigBase(name, config)
    },
    addItem: function (item) {
      // Traditional for loop so we can return if we find a match
      for (const listItem of this.items) {
        if (
          listItem.itemName === item.itemName &&
          listItem.packetName === item.packetName &&
          listItem.targetName === item.targetName &&
          listItem.valueType === 'CONVERTED' &&
          listItem.reducedType === 'SAMPLE' &&
          listItem.mode === 'DECOM'
        ) {
          this.$notify.caution({
            body: 'This item has already been added!',
          })
          return
        }
      }
      item.cmdOrTlm = this.cmdOrTlm.toUpperCase()
      item.edit = false
      item.valueType = 'CONVERTED'
      item.reducedType = 'SAMPLE'
      item.mode = 'DECOM'
      // item.uniqueIgnoreAdd = 'NO'
      this.items.push(item)
    },
    deleteItem: function (item) {
      let index = this.items.indexOf(item)
      this.items.splice(index, 1)
    },
    deleteAll: function () {
      this.items = []
    },
    editAllItems: function () {
      this.editAll = false
      for (let item of this.items) {
        item.mode = this.allItemMode
        item.valueType = this.allItemValueType
        item.reducedType = this.allItemReducedType
      }
    },
    getItemLabel: function (item) {
      let label = [`${item.targetName} - ${item.packetName} - ${item.itemName}`]
      if (item.mode !== 'DECOM') {
        label.push(`{ ${item.mode} }`)
      }
      if (item.valueType !== 'CONVERTED') {
        label.push(`( ${item.valueType} )`)
      }
      if (item.reducedType !== 'SAMPLE') {
        label.push(`[ ${item.reducedType} ]`)
      }
      return label.join(' ')
    },
    setTimestamps: function () {
      this.startDateTimeFilename = this.startDate + '_' + this.startTime
      // Replace the colons, dashes and periods with underscores in the filename
      this.startDateTimeFilename = this.startDateTimeFilename.replace(
        /(:|-|\.)\s*/g,
        '_',
      )
      let startTemp
      let endTemp
      try {
        if (this.timeZone === 'local') {
          startTemp = new Date(this.startDate + ' ' + this.startTime)
          endTemp = new Date(this.endDate + ' ' + this.endTime)
        } else {
          startTemp = new Date(this.startDate + ' ' + this.startTime + 'Z')
          endTemp = new Date(this.endDate + ' ' + this.endTime + 'Z')
          this.startDateTimeFilename += '_UTC'
        }
      } catch (e) {
        return
      }
      this.startDateTime = startTemp.getTime() * 1000000 // TODO: eslint parser doesn't like 1_000_000
      this.endDateTime = endTemp.getTime() * 1000000
    },
    processItems: function () {
      // Check for a process in progress
      if (this.processButtonText === 'Cancel') {
        this.finished()
        return
      }
      // Check for an empty time period
      this.setTimestamps()
      if (!this.startDateTime || !this.endDateTime) {
        this.$notify.caution({
          body: 'Invalid date/time selected!',
        })
        return
      }
      if (this.startDateTime === this.endDateTime) {
        this.$notify.caution({
          body: 'Start date/time is equal to end date/time!',
        })
        return
      }
      if (this.endDateTime - this.startDateTime < 0) {
        this.$notify.caution({
          body: 'Start date/time is greater then end date/time!',
        })
        return
      }
      // Check for a future End Time
      if (new Date(this.endDateTime / 1000000) > Date.now()) {
        this.$notify.caution({
          title: 'Note',
          body: `End date/time is greater than current date/time. Data will
            continue to stream in real-time until
            ${new Date(this.endDateTime / 1000000).toISOString()} is reached.`,
        })
      }

      this.progress = 0
      this.processButtonText = 'Cancel'
      this.cable
        .createSubscription('StreamingChannel', window.openc3Scope, {
          received: (data) => this.received(data),
          connected: () => this.onConnected(),
          disconnected: () => {
            this.$notify.caution({
              body: 'OpenC3 backend connection disconnected.',
            })
          },
          rejected: () => {
            this.$notify.caution({
              body: 'OpenC3 backend connection rejected.',
            })
          },
        })
        .then((subscription) => {
          this.subscription = subscription
        })
    },
    resetAllVars: function () {
      this.fileCount = 0
      this.totalPacketsReceived = 0
      this.totalItemsReceived = 0
      this.columnHeaders = []
      this.columnMap = {}
      this.keyMap = {}
      this.resetPerFileVars()
    },
    resetPerFileVars: function () {
      dataExtractorRawData = []
      this.packetsReceived = 0
      this.itemsReceived = 0
    },
    onConnected: function () {
      this.resetAllVars()
      let items = []
      this.items.forEach((item, index) => {
        let key = `${item.mode}__${item.cmdOrTlm}__${item.targetName}__${item.packetName}__${item.itemName}__${item.valueType}`
        if (item.reducedType !== 'SAMPLE') {
          key = key + '__' + item.reducedType
        }
        let indexString = String(index)
        this.keyMap[indexString] = key
        items.push([key, indexString])
      })
      OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(
        (refreshed) => {
          if (refreshed) {
            OpenC3Auth.setTokens()
          }
          this.subscription.perform('add', {
            scope: window.openc3Scope,
            token: localStorage.openc3Token,
            items: items,
            start_time: this.startDateTime,
            end_time: this.endDateTime,
          })
        },
      )
    },
    received: function (data) {
      this.cable.recordPing()
      if (data.error) {
        this.$notify.serious({
          body: data.error,
        })
        return
      }
      this.packetsReceived += data.length
      this.totalPacketsReceived += data.length
      // Initially we just build up the list of data
      if (data.length > 0) {
        // Get all the items present in the data to pass to buildHeaders
        let keys = new Set()
        for (let packet of data) {
          let packetKeys = Object.keys(packet)
          packetKeys.forEach(keys.add, keys)
          this.itemsReceived += packetKeys.length - 2 // Don't count __type and __time
          this.totalItemsReceived += packetKeys.length - 2
        }
        keys.delete('__type')
        keys.delete('__time')
        this.buildHeaders([...keys])
        dataExtractorRawData.push(data)
        this.progress = Math.ceil(
          (100 * (data[0]['__time'] - this.startDateTime)) /
            (this.endDateTime - this.startDateTime),
        )

        let delimiterOverhead = this.columnHeaders.length * this.packetsReceived
        let estimatedSize = delimiterOverhead + this.itemsReceived * 8 // Assume average of 8 bytes per item
        if (estimatedSize > 100000000) {
          this.createFile()
        }
      } else {
        this.finished()
      }
      data = null
    },
    buildHeaders: function (itemKeys) {
      // Normal column mode has the target and packet listed for each item
      if (this.columnHeaders.length === 0 && this.columnMode === 'normal') {
        this.columnHeaders.push('TIME')
        this.columnHeaders.push('TARGET')
        this.columnHeaders.push('PACKET')
      }
      itemKeys.forEach((item) => {
        if (item.slice(0, 2) === '__') return
        if (this.columnMap[item]) return
        this.columnMap[item] = this.columnHeaders.length // Uses short name
        item = this.keyMap[item] // Decode to full name
        const [
          mode,
          cmdTlm,
          targetName,
          packetName,
          itemName,
          valueType,
          reducedType,
        ] = item.split('__')
        let name = itemName
        if (this.columnMode === 'full') {
          name = targetName + ' ' + packetName + ' ' + itemName
        }
        if (mode && mode !== 'DECOM') {
          name = name + ' {' + mode + '}'
        }
        if (valueType && valueType !== 'CONVERTED') {
          name = name + ' (' + valueType + ')'
        }
        if (reducedType) {
          name = name + ' [' + reducedType + ']'
        }
        this.columnHeaders.push(name)
      })
    },
    createFile: async function () {
      let rawData = dataExtractorRawData.flat()
      let columnHeaders = this.columnHeaders
      let columnMap = this.columnMap
      let outputFile = []
      this.resetPerFileVars()

      let headers = ''
      if (this.matlabHeader) {
        headers += '% '
      }
      headers += columnHeaders.join(this.delimiter)
      outputFile.push(headers)

      // Sort everything by time so we can output in order
      await this.yieldToMain()
      rawData.sort((a, b) => a.__time - b.__time)
      await this.yieldToMain()

      let currentValues = []
      let row = []
      let previousRow = null
      let count = 0
      for (let packet of rawData) {
        // Flag tracks if anything has changed for uniqueOnly mode
        let changed = false

        // Start a new row with either the previous row data (fillDown) or a blank row
        if (this.fillDown && previousRow) {
          row = [...previousRow] // Copy the previous
        } else {
          row = []
        }

        // regularKey is any non-metadata key to get the targetName and packetName from
        let regularKey = ''

        // Get all the values from this packet
        Object.keys(packet).forEach((key) => {
          if (key.slice(0, 2) === '__') return // Skip metadata

          // Update regularKey for use when we build the beginning of the row
          regularKey = key

          let columnIndex = columnMap[key]
          // Get the value and put it into the correct column
          if (typeof packet[key] === 'object') {
            if (packet[key] === null) {
              row[columnIndex] = ''
            } else if (Array.isArray(packet[key])) {
              row[columnIndex] = '"[' + packet[key] + ']"'
            } else {
              let rawVal = packet[key]['raw']
              if (Array.isArray(rawVal)) {
                let hexString = ''
                rawVal.forEach((val) => {
                  hexString += val.toString(16)
                })
                row[columnIndex] = hexString
              } else {
                row[columnIndex] = "'" + rawVal + "'"
              }
            }
          } else {
            row[columnIndex] = packet[key]
          }
          if (
            this.uniqueOnly &&
            currentValues[columnIndex] !== row[columnIndex]
          ) {
            changed = true
          }
          currentValues[columnIndex] = row[columnIndex]
        })

        // Copy row before pushing on target / packet names
        if (this.fillDown) {
          previousRow = [...row]
        }

        if (!this.uniqueOnly || changed) {
          // Normal column mode means each row has time / target name / packet name
          if (this.columnMode === 'normal') {
            regularKey = this.keyMap[regularKey] // Decode to full name
            const [
              mode,
              cmdTlm,
              targetName,
              packetName,
              itemName,
              valueType,
              reducedType,
            ] = regularKey.split('__')
            row[0] = new Date(packet['__time'] / 1000000).toISOString()
            row[1] = targetName
            row[2] = packetName
          }
          outputFile.push(row.join(this.delimiter))
        }
        count += 1
        if (count % 1000 == 0) {
          await this.yieldToMain()
        }
      }

      let downloadFileExtension = '.csv'
      let type = 'text/csv'
      if (this.delimiter === '\t') {
        downloadFileExtension = '.txt'
        type = 'text/tab-separated-values'
      }
      await this.yieldToMain()
      const blob = new Blob([outputFile.join('\n')], {
        type: type,
      })
      await this.yieldToMain()
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute(
        'download',
        this.startDateTimeFilename +
          '_' +
          this.fileCount +
          downloadFileExtension,
      )
      link.click()

      this.fileCount += 1
    },
    yieldToMain: function () {
      return new Promise((resolve) => {
        setTimeout(resolve, 0)
      })
    },
    finished: async function () {
      this.progress = 95 // Indicate we're almost done
      this.subscription.unsubscribe()

      if (dataExtractorRawData.length !== 0) {
        await this.createFile()
      } else if (this.fileCount === 0) {
        let start = new Date(this.startDateTime / 1000000).toISOString()
        let end = new Date(this.endDateTime / 1000000).toISOString()
        this.$notify.caution({
          body: `No data found for the items in the requested time range of ${start} to ${end}`,
        })
      }

      this.progress = 100
      this.processButtonText = 'Process'
    },
  },
}
</script>

<style lang="scss" scoped>
.title-font {
  font-size: 1.125rem;
}
// Disable transition animations to allow bar to grow faster
.v-progress-linear__determinate {
  transition: none !important;
}
</style>
