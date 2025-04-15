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
    <v-card class="pa-5">
      <v-row class="ma-1">
        <v-text-field
          density="compact"
          variant="outlined"
          readonly
          hide-details
          label="Overall Limits State"
          :model-value="overallStateFormatted"
          :class="textFieldClass"
          style="margin-right: 10px; max-width: 280px"
          data-test="overall-state"
        >
          <template v-slot:prepend-inner v-if="astroStatus">
            <rux-status :status="astroStatus" />
          </template>
        </v-text-field>
        <v-text-field
          density="compact"
          variant="outlined"
          readonly
          hide-details
          label="Current Limits Set"
          :model-value="currentLimitsSet"
          style="max-width: 200px"
          data-test="limits-set"
        />
        <v-spacer></v-spacer>
        <v-text-field
          v-model="search"
          label="Search"
          prepend-inner-icon="mdi-magnify"
          clearable
          variant="outlined"
          density="compact"
          single-line
          hide-details
          style="max-width: 300px"
          data-test="search"
        />
      </v-row>

      <v-data-table
        :headers="headers"
        :items="items"
        :search="search"
        :custom-filter="customFilter"
        item-value="key"
        data-test="limits-table"
        class="limits-table"
        density="compact"
        v-model:items-per-page="itemsPerPage"
      >
        <template v-slot:item.timestamp="{ item }">
          {{ item.timestamp }}
        </template>
        <template v-slot:item.value="{ item }">
          <valuelimitsbar-widget
            v-if="item.limits"
            :parameters="item.parameters"
            :settings="valueLimitsBarWidgetSettings"
            :screen-values="screenValues"
            :screen-time-zone="timeZone"
            v-on:add-item="addItem"
            v-on:delete-item="deleteItem"
          />
          <value-widget
            v-else
            :parameters="item.parameters"
            :settings="valueWidgetSettings"
            :screen-values="screenValues"
            :screen-time-zone="timeZone"
            v-on:add-item="addItem"
            v-on:delete-item="deleteItem"
          />
        </template>
        <template v-slot:item.actions="{ item }">
          <v-menu>
            <template v-slot:activator="{ props: menuProps }">
              <v-btn
                icon="mdi-dots-horizontal"
                variant="text"
                density="compact"
                v-bind="menuProps"
              />
            </template>
            <v-list>
              <v-list-item @click="ignorePacket(item.key)">
                <template v-slot:prepend>
                  <v-icon>mdi-close-circle-multiple</v-icon>
                </template>
                <v-list-item-title>Ignore Entire Packet</v-list-item-title>
              </v-list-item>
              <v-list-item @click="ignoreItem(item.key)">
                <template v-slot:prepend>
                  <v-icon>mdi-close-circle</v-icon>
                </template>
                <v-list-item-title>Ignore Item</v-list-item-title>
              </v-list-item>
              <v-list-item @click="removeItem(item.key)">
                <template v-slot:prepend>
                  <v-icon>mdi-eye-off</v-icon>
                </template>
                <v-list-item-title>Temporarily Hide Item</v-list-item-title>
              </v-list-item>
            </v-list>
          </v-menu>
        </template>
        <template v-slot:item.limits="{ item }">
          <v-spacer></v-spacer>
        </template>
      </v-data-table>
      <div class="footer">
        Note: Timestamp is "now" for items currently out of limits when the page
        is loaded.
      </div>
    </v-card>
    <v-dialog v-model="ignoredItemsDialog" max-width="600">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span>Ignored Items</span>
          <v-spacer />
        </v-toolbar>
        <v-card-text class="mt-2">
          <div>
            <div v-for="(item, index) in ignoredFormatted" :key="index">
              <v-row class="ma-1 align-center">
                <span class="font-weight-black"> {{ item }} </span>
                <v-spacer />
                <v-btn
                  @click="restoreItem(index)"
                  icon="mdi-delete"
                  density="compact"
                  variant="text"
                  :data-test="`remove-ignore-${index}`"
                />
              </v-row>
              <v-divider
                v-if="index < ignoredFormatted.length - 1"
                :key="index"
              />
            </div>
          </div>
        </v-card-text>
        <v-card-actions class="px-2">
          <v-btn variant="outlined" @click="clearAll"> Clear All </v-btn>
          <v-spacer />
          <v-btn variant="flat" @click="ignoredItemsDialog = false"> Ok </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import { Cable, OpenC3Api } from '@openc3/js-common/services'
import { TimeFilters } from '@openc3/vue-common/util'
import {
  ValueWidget,
  ValuelimitsbarWidget,
} from '@openc3/vue-common/widgets'

export default {
  components: {
    ValueWidget,
    ValuelimitsbarWidget,
  },
  props: {
    modelValue: {
      type: Array,
      default: () => [],
    },
    timeZone: {
      type: String,
      default: 'local',
    },
  },
  mixins: [TimeFilters],
  data() {
    return {
      api: null,
      cable: new Cable(),
      ignored: [],
      ignoredItemsDialog: false,
      overallState: 'GREEN',
      currentLimitsSet: '',
      items: [],
      itemList: [],
      screenItems: [],
      screenValues: {},
      updateCounter: 0,
      itemsPerPage: 25,
      search: '',
      headers: [
        {
          title: 'Timestamp',
          key: 'timestamp',
          width: '130px',
          sortable: true,
          nowrap: true },
        {
          title: 'Item',
          key: 'item',
          value: item => item.parameters[2],
          sortable: true,
          minWidth: '100px',
          width: '200px',
          maxWidth: '300px',
        },
        {
          title: 'Value',
          key: 'value',
          width: '380px',
          sortable: false
        },
        { title: 'Controls', key: 'actions', width: '80px', sortable: false },
        { title: '', key: 'limits', sortable: false }
      ],
      valueLimitsBarWidgetSettings: [
        ['WIDTH', '380px'], // Total of two subwidgets
        ['0', 'WIDTH', '200px'],
        ['1', 'WIDTH', '180px'],
      ],
      valueWidgetSettings: [
        ['WIDTH', '200px'],
      ],
    }
  },
  computed: {
    textFieldClass() {
      if (this.overallState) {
        return `textfield-${this.overallState.toLowerCase()}`
      } else {
        return ''
      }
    },
    overallStateFormatted() {
      if (this.ignored.length === 0) {
        return this.overallState
      } else {
        return `${this.overallState} (Some items ignored)`
      }
    },
    ignoredFormatted() {
      return this.ignored.map((x) => x.split('__').join(' '))
    },
    astroStatus() {
      switch (this.overallState) {
        case 'GREEN':
          return 'normal'
        case 'YELLOW':
          return 'caution'
        case 'RED':
          return 'critical'
        case 'BLUE':
          // This one is a little weird but it matches our color scheme
          return 'standby'
        default:
          return null
      }
    },
  },
  created() {
    this.api = new OpenC3Api()
    // Value is passed in as the list of ignored items
    for (let item of this.modelValue) {
      if (item.match(/.+__.+__.+/)) {
        // TARGET__PACKET__ITEM
        this.ignoreItem(item, true)
      } else {
        // TARGET__PACKET
        this.ignorePacket(item, true)
      }
    }
    this.updateOutOfLimits()
    this.getCurrentLimitsSet()
    this.currentSetRefreshInterval = setInterval(
      this.getCurrentLimitsSet,
      10 * 1000,
    )

    this.cable
      .createSubscription('LimitsEventsChannel', window.openc3Scope, {
        received: (parsed) => {
          this.cable.recordPing()
          this.handleMessages(parsed)
        },
      })
      .then((limitsSubscription) => {
        this.limitsSubscription = limitsSubscription
      })
    this.cable
      .createSubscription('ConfigEventsChannel', window.openc3Scope, {
        received: (data) => {
          this.cable.recordPing()
          const parsed = JSON.parse(data)
          this.handleConfigEvents(parsed)
        },
      })
      .then((configSubscription) => {
        this.configSubscription = configSubscription
      })
  },
  mounted() {
    this.updater = setInterval(() => {
      this.update()
    }, 1000)
  },
  unmounted() {
    if (this.updater != null) {
      clearInterval(this.updater)
      this.updater = null
    }
    if (this.limitsSubscription) {
      this.limitsSubscription.unsubscribe()
    }
    if (this.configSubscription) {
      this.configSubscription.unsubscribe()
    }
    this.cable.disconnect()
  },
  methods: {
    getCurrentLimitsSet: function () {
      this.api.get_limits_set().then((result) => {
        this.currentLimitsSet = result
      })
    },
    updateOutOfLimits() {
      this.items = []
      this.itemList = []

      this.api.get_out_of_limits().then((items) => {
        for (const item of items) {
          let itemName = item.join('__')
          // Skip ignored
          if (this.ignored.find((ignored) => itemName.includes(ignored))) {
            continue
          }

          this.itemList.push(itemName)
          let itemInfo = {
            key: item.slice(0, 3).join('__'),
            parameters: item.slice(0, 3),
            timestamp: this.formatDateTime(new Date(), this.timeZone),
          }
          if (item[3].includes('YELLOW') && this.overallState !== 'RED') {
            this.overallState = 'YELLOW'
          }
          if (item[3].includes('RED')) {
            this.overallState = 'RED'
          }
          if (item[3] == 'YELLOW' || item[3] == 'RED') {
            itemInfo['limits'] = false
          } else {
            itemInfo['limits'] = true
          }
          this.items.push(itemInfo)
        }
        this.calcOverallState()
      })
    },
    calcOverallState() {
      let overall = 'GREEN'
      for (let item of this.itemList) {
        if (this.ignored.find((ignored) => item.includes(ignored))) {
          continue
        }

        if (item.includes('YELLOW') && overall !== 'RED') {
          overall = 'YELLOW'
        }
        if (item.includes('RED')) {
          overall = 'RED'
          break
        }
      }
      this.overallState = overall
    },
    ignorePacket(item, noUpdate) {
      let [target_name, packet_name, item_name] = item.split('__')
      let newIgnored = `${target_name}__${packet_name}`
      this.ignored.push(newIgnored)
      noUpdate || this.updateIgnored()

      while (true) {
        let index = this.itemList.findIndex((item) => item.includes(newIgnored))
        if (index === -1) {
          break
        } else {
          let underIndex = this.itemList[index].lastIndexOf('__')
          this.removeItem(this.itemList[index].substring(0, underIndex))
        }
      }
      this.calcOverallState()
    },
    ignoreItem(item, noUpdate) {
      this.ignored.push(item)
      noUpdate || this.updateIgnored()
      this.removeItem(item)
      this.calcOverallState()
    },
    restoreItem(index) {
      this.ignored.splice(index, 1)
      this.updateIgnored()
      this.updateOutOfLimits()
    },
    removeItem(item) {
      const index = this.itemList.findIndex((arrayItem) =>
        arrayItem.includes(item),
      )
      this.items.splice(index, 1)
      this.itemList.splice(index, 1)
    },
    clearAll() {
      this.ignored = []
      this.updateIgnored()
      this.updateOutOfLimits()
    },
    updateIgnored() {
      this.$emit('update:modelValue', this.ignored)
    },
    handleConfigEvents(config) {
      for (let event of config) {
        // When a target is deleted we refresh the list of items
        if (event['kind'] === 'deleted' && event['type'] === 'target') {
          this.updateOutOfLimits()
        }
      }
    },
    handleMessages(messages) {
      for (let json of messages) {
        let message = JSON.parse(json['event'])

        // We only want to handle LIMITS_CHANGE messages
        // NOTE: The channel also sends LIMITS_SETTINGS and LIMITS_SET messages
        if (message.type != 'LIMITS_CHANGE') {
          continue
        }

        let itemName = `${message.target_name}__${message.packet_name}__${message.item_name}`
        const index = this.itemList.findIndex((arrayItem) =>
          arrayItem.includes(itemName),
        )
        // If we find an existing item we update the state and re-calc overall state
        if (index !== -1) {
          this.itemList[index] = `${itemName}__${message.new_limits_state}`
          this.calcOverallState()
          continue
        }
        // Skip ignored items
        if (this.ignored.find((ignored) => itemName.includes(ignored))) {
          continue
        }
        // Only process items who have gone out of limits
        if (
          message.new_limits_state &&
          !(
            message.new_limits_state.includes('YELLOW') ||
            message.new_limits_state.includes('RED')
          )
        ) {
          continue
        }
        let itemInfo = {
          key: itemName,
          timestamp: this.formatNanoseconds(message.time_nsec, this.timeZone),
          parameters: [
            message.target_name,
            message.packet_name,
            message.item_name,
          ],
        }
        if (
          message.new_limits_state == 'YELLOW' ||
          message.new_limits_state == 'RED'
        ) {
          itemInfo['limits'] = false
        } else {
          itemInfo['limits'] = true
        }
        this.itemList.push(`${itemName}__${message.new_limits_state}`)
        this.items.push(itemInfo)
        this.calcOverallState()
      }
    },
    update() {
      if (this.screenItems.length !== 0) {
        this.api.get_tlm_values(this.screenItems).then((data) => {
          this.updateValues(data)
        })
      }
    },
    updateValues: function (values) {
      this.updateCounter += 1
      for (let i = 0; i < values.length; i++) {
        values[i].push(this.updateCounter)
        this.screenValues[this.screenItems[i]] = values[i]
      }
    },
    addItem: function (valueId) {
      this.screenItems.push(valueId)
      this.screenValues[valueId] = [null, null, 0]
    },
    deleteItem: function (valueId) {
      let index = this.screenItems.indexOf(valueId)
      this.screenItems.splice(index, 1)
    },

    // Menu options
    showIgnored() {
      this.ignoredItemsDialog = true
    },

    // Search filter
    customFilter(value, search, item) {
      if (!search || search.trim() === '') return true

      search = search.toLowerCase()

      // Check if any parameter matches the search
      if (item.parameters && item.parameters.length > 0) {
        for (const param of item.parameters) {
          if (param.toLowerCase().includes(search)) {
            return true
          }
        }
      }

      // Check for timestamp match
      if (item.timestamp && item.timestamp.toLowerCase().includes(search)) {
        return true
      }

      // Check the key
      if (item.key && item.key.toLowerCase().includes(search)) {
        return true
      }

      return false
    },
  },
}
</script>

<style scoped>
.footer {
  padding-top: 5px;
}
.v-input {
  background-color: var(--color-background-base-default);
}

.textfield-green {
  color: rgb(0, 200, 0);
}

.textfield-yellow {
  color: rgb(255, 220, 0);
}

.textfield-red {
  color: rgb(255, 45, 45);
}

.limits-table {
  margin-top: 5px;
  margin-bottom: 10px;
}

.limits-table :deep(th) {
  font-weight: bold;
  background-color: var(--color-background-base-default);
}
</style>
