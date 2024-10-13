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
      </v-row>

      <v-row data-test="limits-row" class="my-0 ml-1 mr-1">
        <div class="pa-1 mt-1 mr-2 label" style="width: 170px">Timestamp</div>
        <div class="pa-1 mt-1 mr-2 label" style="width: 200px">Item Name</div>
        <div class="pa-1 mt-1 mr-2 label" style="width: 200px">Value</div>
        <div class="pa-1 mt-1 mr-2 label" style="width: 180px">Limits Bar</div>
        <div class="pa-1 mt-1 mr-2 label">Controls</div>
      </v-row>
      <div v-for="(item, index) in items" :key="item.key">
        <v-row data-test="limits-row" class="my-0 ml-1 mr-1">
          <div class="pa-1 mt-1 mr-2 label" style="width: 170px">
            {{ item.timestamp }}
          </div>
          <labelvaluelimitsbar-widget
            v-if="item.limits"
            :parameters="item.parameters"
            :settings="widgetSettings"
            :screenValues="screenValues"
            :screenTimeZone="timeZone"
            v-on:add-item="addItem"
            v-on:delete-item="deleteItem"
          />
          <labelvalue-widget
            v-else
            :parameters="item.parameters"
            :settings="widgetSettings"
            :screenValues="screenValues"
            :screenTimeZone="timeZone"
            v-on:add-item="addItem"
            v-on:delete-item="deleteItem"
          />
          <v-tooltip location="bottom">
            <template v-slot:activator="{ props }">
              <v-btn
                icon="mdi-close-circle-multiple"
                variant="text"
                density="compact"
                class="mr-2"
                @click="ignorePacket(item.key)"
                v-bind="props"
              />
            </template>
            <span>Ignore Entire Packet</span>
          </v-tooltip>
          <v-tooltip location="bottom">
            <template v-slot:activator="{ props }">
              <v-btn
                icon="mdi-close-circle"
                variant="text"
                density="compact"
                class="mr-2"
                @click="ignoreItem(item.key)"
                v-bind="props"
              />
            </template>
            <span>Ignore Item</span>
          </v-tooltip>
          <v-tooltip location="bottom">
            <template v-slot:activator="{ props }">
              <v-btn
                icon="mdi-eye-off"
                variant="text"
                density="compact"
                class="mr-2"
                @click="removeItem(item.key)"
                v-bind="props"
              />
            </template>
            <span>Temporarily Hide Item</span>
          </v-tooltip>
        </v-row>
        <v-divider v-if="index < items.length" :key="index" />
      </div>
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
        <v-card-actions>
          <v-btn variant="outlined" @click="clearAll"> Clear All </v-btn>
          <v-spacer />
          <v-btn
            @click="ignoredItemsDialog = false"
            class="mx-2"
            color="primary"
          >
            Ok
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'
import Cable from '@openc3/tool-common/src/services/cable.js'
import LabelvalueWidget from '@openc3/tool-common/src/components/widgets/LabelvalueWidget'
import LabelvaluelimitsbarWidget from '@openc3/tool-common/src/components/widgets/LabelvaluelimitsbarWidget'
import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters.js'

export default {
  components: {
    LabelvalueWidget,
    LabelvaluelimitsbarWidget,
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
      widgetSettings: [
        ['WIDTH', '580px'], // Total of three subwidgets
        ['0', 'WIDTH', '200px'],
        ['1', 'WIDTH', '200px'],
        ['2', 'WIDTH', '180px'],
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
      // TODO: fix for vuetify 3 icon sets
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
      for (let message of messages) {
        message = JSON.parse(message['event'])

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
</style>
