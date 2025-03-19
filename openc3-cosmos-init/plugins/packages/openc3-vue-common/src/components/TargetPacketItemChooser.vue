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
  <div class="pt-4 pb-4">
    <v-row :no-gutters="!vertical">
      <v-col :cols="colSize" class="tpic-select pr-4" data-test="select-target">
        <v-autocomplete
          label="Select Target"
          hide-details
          density="compact"
          variant="outlined"
          @update:model-value="targetNameChanged"
          :items="targetNames"
          item-title="label"
          item-value="value"
          v-model="selectedTargetName"
        />
      </v-col>
      <v-col :cols="colSize" class="tpic-select pr-4" data-test="select-packet">
        <v-autocomplete
          label="Select Packet"
          hide-details
          density="compact"
          variant="outlined"
          @update:model-value="packetNameChanged"
          :disabled="packetsDisabled || autocompleteDisabled"
          :items="packetNames"
          item-title="label"
          item-value="value"
          v-model="selectedPacketName"
        >
          <template v-if="includeLatestPacketInDropdown" v-slot:prepend-item>
            <v-list-item title="LATEST" @click="packetNameChanged('LATEST')" />
            <v-divider />
          </template>
        </v-autocomplete>
      </v-col>
      <v-col
        v-if="chooseItem"
        :cols="colSize"
        class="tpic-select pr-4"
        data-test="select-item"
      >
        <v-autocomplete
          label="Select Item"
          hide-details
          density="compact"
          variant="outlined"
          @update:model-value="itemNameChanged($event)"
          :disabled="itemsDisabled || autocompleteDisabled"
          :items="itemNames"
          item-title="label"
          item-value="value"
          v-model="selectedItemName"
        />
      </v-col>
      <!-- min-width: 105px is enough to display a 2 digit index -->
      <v-col
        v-if="chooseItem && itemIsArray()"
        cols="1"
        class="tpic-select pr-4"
        data-test="array-index"
        style="min-width: 105px"
      >
        <v-combobox
          label="Index"
          hide-details
          density="compact"
          variant="outlined"
          @update:model-value="indexChanged($event)"
          :disabled="itemsDisabled || autocompleteDisabled"
          :items="arrayIndexes()"
          item-title="label"
          item-value="value"
          v-model="selectedArrayIndex"
        />
      </v-col>
      <v-col v-if="buttonText" :cols="colSize" style="max-width: 140px">
        <v-btn
          :disabled="buttonDisabled"
          color="primary"
          data-test="select-send"
          @click="buttonPressed"
        >
          {{ actualButtonText }}
        </v-btn>
      </v-col>
    </v-row>
    <v-row no-gutters v-if="selectTypes" class="pt-6">
      <v-col :cols="colSize" class="tpic-select pr-4" data-test="data-type">
        <v-autocomplete
          label="Value Type"
          hide-details
          density="compact"
          variant="outlined"
          :items="valueTypes"
          v-model="selectedValueType"
        />
      </v-col>
      <v-col :cols="colSize" class="tpic-select pr-4" data-test="reduced">
        <v-autocomplete
          label="Reduced"
          hide-details
          density="compact"
          variant="outlined"
          :items="reductionModes"
          v-model="selectedReduced"
        />
      </v-col>
      <v-col :cols="colSize" class="tpic-select pr-4" data-test="reduced-type">
        <v-autocomplete
          label="Reduced Type"
          hide-details
          density="compact"
          variant="outlined"
          :disabled="selectedReduced === 'DECOM'"
          :items="reducedTypes"
          v-model="selectedReducedType"
        />
      </v-col>
      <v-col :cols="colSize" style="max-width: 140px"> </v-col>
    </v-row>
    <v-row no-gutters class="pa-3">
      <v-col :cols="colSize" :class="{ 'openc3-yellow': hazardous }">
        Description: {{ description }}
        <template v-if="hazardous"> (HAZARDOUS) </template>
      </v-col>
    </v-row>
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'

export default {
  props: {
    allowAll: {
      type: Boolean,
      default: false,
    },
    allowAllTargets: {
      type: Boolean,
      default: false,
    },
    buttonText: {
      type: String,
      default: null,
    },
    chooseItem: {
      type: Boolean,
      default: false,
    },
    disabled: {
      type: Boolean,
      default: false,
    },
    initialTargetName: {
      type: String,
      default: '',
    },
    initialPacketName: {
      type: String,
      default: '',
    },
    initialItemName: {
      type: String,
      default: '',
    },
    selectTypes: {
      type: Boolean,
      default: false,
    },
    showLatest: {
      type: Boolean,
      default: false,
    },
    mode: {
      type: String,
      default: 'tlm',
      // TODO: add validators throughout
      validator: (propValue) => {
        return ['cmd', 'tlm'].includes(propValue)
      },
    },
    unknown: {
      type: Boolean,
      default: false,
    },
    vertical: {
      type: Boolean,
      default: false,
    },
    hidden: {
      type: Boolean,
      default: false,
    },
  },
  data() {
    return {
      targetNames: [],
      selectedTargetName: this.initialTargetName?.toUpperCase(),
      packetNames: [],
      selectedPacketName: this.initialPacketName?.toUpperCase(),
      itemNames: [],
      selectedItemName: this.initialItemName?.toUpperCase(),
      valueTypes: ['CONVERTED', 'RAW'],
      selectedValueType: 'CONVERTED',
      reductionModes: [
        // Map NONE to DECOM for clarity
        { title: 'NONE', value: 'DECOM' },
        { title: 'REDUCED_MINUTE', value: 'REDUCED_MINUTE' },
        { title: 'REDUCED_HOUR', value: 'REDUCED_HOUR' },
        { title: 'REDUCED_DAY', value: 'REDUCED_DAY' },
      ],
      selectedArrayIndex: null,
      selectedReduced: 'DECOM',
      reducedTypes: ['MIN', 'MAX', 'AVG', 'STDDEV'],
      selectedReducedType: 'AVG',
      description: '',
      hazardous: false,
      internalDisabled: false,
      packetsDisabled: false,
      itemsDisabled: false,
      api: null,
      ALL: {
        label: '[ ALL ]',
        value: 'ALL',
        description: 'ALL',
      }, // Constant to indicate all packets or items
      UNKNOWN: {
        label: '[ UNKNOWN ]',
        value: 'UNKNOWN',
        description: 'UNKNOWN',
      },
    }
  },
  created() {
    this.internalDisabled = true
    this.api = new OpenC3Api()
    this.api.get_target_names().then((result) => {
      this.targetNames = result.flatMap((target) => {
        // Ignore the UNKNOWN target as it doesn't make sense to select this
        if (target == 'UNKNOWN') {
          return []
        }
        return { label: target, value: target }
      })
      // TODO: This is a nice enhancement but results in logs of API calls for many targets
      // See if we can reduce this to a single API call
      // Filter out any targets without packets
      // for (let i = this.targetNames.length - 1; i >= 0; i--) {
      //   const cmd =
      //     this.mode === 'tlm' ? 'get_all_tlm_names' : 'get_all_cmd_names'
      //   await this.api[cmd](this.targetNames[i].value).then((names) => {
      //     if (names.length === 0) {
      //       this.targetNames.splice(i, 1)
      //     }
      //   })
      // }
      if (this.allowAllTargets) {
        this.targetNames.unshift(this.ALL)
      }
      // If the initial target name is not set, default to the first target
      // which also updates packets and items as needed
      if (!this.selectedTargetName) {
        this.selectedTargetName = this.targetNames[0].value
        this.targetNameChanged(this.selectedTargetName)
      } else {
        // Selected target name was set but we still have to update packets
        this.updatePackets()
      }
      if (this.unknown) {
        this.targetNames.push(this.UNKNOWN)
      }
    })
  },
  computed: {
    actualButtonText: function () {
      if (this.selectedPacketName === 'ALL') {
        return 'Add Target'
      }
      if (this.selectedItemName === 'ALL') {
        return 'Add Packet'
      }
      return this.buttonText
    },
    autocompleteDisabled: function () {
      return this.disabled || this.internalDisabled
    },
    buttonDisabled: function () {
      return (
        this.disabled ||
        this.internalDisabled ||
        this.selectedTargetName === null ||
        this.selectedPacketName === null ||
        this.selectedItemNameWIndex === null
      )
    },
    colSize: function () {
      return this.vertical ? 12 : false
    },
    selectedItemNameWIndex: function () {
      if (
        this.itemIsArray() &&
        this.selectedArrayIndex !== null &&
        this.selectedArrayIndex !== this.ALL.label
      ) {
        return `${this.selectedItemName}[${this.selectedArrayIndex}]`
      } else {
        return this.selectedItemName
      }
    },
    includeLatestPacketInDropdown: function () {
      return this.showLatest && this.mode === 'tlm' // because LATEST cmd doesn't have much use and thus isn't currently implemented
    },
  },
  watch: {
    initialTargetName: function (val) {
      // These three "initial" watchers are here in case the parent component doesn't figure out its initial values
      // until after this component has already been created. All this logic incl. the "on-set" events could be
      // simplified with a refactor to use named v-models, but that's probably a significant breaking change.
      if (val) {
        this.selectedTargetName = val.toUpperCase()
      }
    },
    initialPacketName: function (val) {
      if (val) {
        this.selectedPacketName = val.toUpperCase()
      }
    },
    initialItemName: function (val) {
      if (val) {
        this.selectedItemName = val.toUpperCase()
      }
    },
    mode: function (newVal, oldVal) {
      this.selectedPacketName = null
      this.selectedItemName = null
      // This also updates packets and items as needed
      this.targetNameChanged(this.selectedTargetName)
    },
    chooseItem: function (newVal, oldVal) {
      if (newVal) {
        this.updateItems()
      } else {
        this.itemNames = []
      }
    },
  },
  methods: {
    updatePackets: function () {
      if (this.selectedTargetName === 'UNKNOWN') {
        this.packetNames = [this.UNKNOWN]
        this.selectedPacketName = this.packetNames[0].value
        this.updatePacketDetails(this.UNKNOWN.value)
        this.description = 'UNKNOWN'
        return
      }
      if (this.selectedTargetName === 'ALL') {
        this.packetNames = [this.ALL]
        this.selectedPacketName = this.packetNames[0].value
        this.updatePacketDetails(this.ALL.value)
        this.description = 'ALL'
        return
      }
      this.internalDisabled = true
      const cmd =
        this.mode === 'tlm' ? 'get_all_tlm_names' : 'get_all_cmd_names'
      this.api[cmd](this.selectedTargetName, this.hidden).then((names) => {
        this.packetNames = names.map((name) => {
          return {
            label: name,
            value: name,
          }
        })
        if (this.allowAll) {
          this.packetNames.unshift(this.ALL)
        }
        if (!this.selectedPacketName) {
          this.selectedPacketName = this.packetNames[0].value
        }
        this.updatePacketDetails(this.selectedPacketName)
        const item = this.packetNames.find((packet) => {
          return packet.value === this.selectedPacketName
        })
        if (item && this.chooseItem) {
          this.updateItems()
        }
        this.internalDisabled = false
      })
    },

    updateItems: function () {
      if (this.selectedPacketName === 'ALL') {
        return
      }
      this.internalDisabled = true

      if (this.selectedPacketName === 'LATEST') {
        this.api
          .get_all_tlm_item_names(this.selectedTargetName)
          .then((items) => {
            this.itemNames = items.map((item) => {
              return {
                label: item,
                value: item,
                description: `LATEST ${item}`,
                // Don't handle array for LATEST
              }
            })
            this.finishUpdateItems()
          })
      } else {
        const cmd = this.mode === 'tlm' ? 'get_tlm' : 'get_cmd'
        this.api[cmd](this.selectedTargetName, this.selectedPacketName).then(
          (packet) => {
            this.itemNames = packet.items.map((item) => {
              let label = item.name
              if (item.data_type == 'DERIVED') {
                label += ' *'
              }
              return {
                label: label,
                value: item.name,
                description: item.description,
                array: item.array_size / item.bit_size,
              }
            })
            this.itemNames.sort((a, b) => (a.label > b.label ? 1 : -1))
            this.finishUpdateItems()
          },
        )
      }
    },
    finishUpdateItems: function () {
      if (this.allowAll) {
        this.itemNames.unshift(this.ALL)
      }
      if (!this.selectedItemName) {
        this.selectedItemName = this.itemNames[0].value
      }
      this.description = this.itemNames[0].description
      this.itemIsArray()
      this.$emit('on-set', {
        targetName: this.selectedTargetName,
        packetName: this.selectedPacketName,
        itemName: this.selectedItemNameWIndex,
        valueType: this.selectedValueType,
        reduced: this.selectedReduced,
        reducedType: this.selectedReducedType,
      })
      this.internalDisabled = false
    },
    itemIsArray: function () {
      let i = this.itemNames.findIndex(
        (item) => item.value === this.selectedItemName,
      )
      if (i === -1) {
        this.selectedArrayIndex = null
        return false
      }
      if (isNaN(this.itemNames[i].array)) {
        this.selectedArrayIndex = null
        return false
      } else {
        if (this.selectedArrayIndex === null) {
          this.selectedArrayIndex = 0
        }
        return true
      }
    },
    arrayIndexes: function () {
      let i = this.itemNames.findIndex(
        (item) => item.value === this.selectedItemName,
      )
      let indexes = [...Array(this.itemNames[i].array).keys()]
      if (this.allowAll) {
        indexes.unshift(this.ALL.label)
      }
      return indexes
    },

    targetNameChanged: function (value) {
      this.selectedTargetName = value
      this.selectedPacketName = ''
      this.selectedItemName = ''
      // When the target name is completed deleted in the v-autocomplete
      // the @change handler is fired but the value is null
      // In this case we don't want to update packets
      if (value !== null) {
        this.updatePackets()
      }
    },

    packetNameChanged: function (value) {
      this.selectedItemName = ''
      // When the packet name is completed deleted in the v-autocomplete
      // the @change handler is fired but the value is null
      // In this case we don't want to update packet details
      if (value !== null) {
        this.updatePacketDetails(value)
      }
    },

    updatePacketDetails: function (value) {
      if (value === 'ALL') {
        this.itemsDisabled = true
        this.internalDisabled = false
      } else if (value === 'LATEST') {
        this.itemsDisabled = false
        this.selectedPacketName = 'LATEST'
      } else {
        this.itemsDisabled = false
        const packet = this.packetNames.find((packet) => {
          return value === packet.value
        })
        if (packet) {
          this.selectedPacketName = packet.value
          const cmd = this.mode === 'tlm' ? 'get_tlm' : 'get_cmd'
          this.api[cmd](this.selectedTargetName, this.selectedPacketName).then(
            (packet) => {
              this.description = packet.description
              this.hazardous = packet.hazardous
            },
          )
        }
      }
      if (this.chooseItem) {
        this.updateItems()
      } else {
        this.$emit('on-set', {
          targetName: this.selectedTargetName,
          packetName: this.selectedPacketName,
          itemName: this.selectedItemNameWIndex,
          valueType: this.selectedValueType,
          reduced: this.selectedReduced,
          reducedType: this.selectedReducedType,
        })
      }
    },

    itemNameChanged: function (value) {
      const item = this.itemNames.find((item) => {
        return value === item.value
      })
      if (item) {
        this.itemIsArray()
        this.selectedItemName = item.value
        this.description = item.description
        this.$emit('on-set', {
          targetName: this.selectedTargetName,
          packetName: this.selectedPacketName,
          itemName: this.selectedItemNameWIndex,
          valueType: this.selectedValueType,
          reduced: this.selectedReduced,
          reducedType: this.selectedReducedType,
        })
      }
    },

    indexChanged: function (value) {
      this.$emit('on-set', {
        targetName: this.selectedTargetName,
        packetName: this.selectedPacketName,
        itemName: this.selectedItemNameWIndex,
        valueType: this.selectedValueType,
        reduced: this.selectedReduced,
        reducedType: this.selectedReducedType,
      })
    },

    buttonPressed: function () {
      if (this.selectedPacketName === 'ALL') {
        this.allTargetPacketItems()
      } else if (this.selectedItemName === 'ALL') {
        this.allPacketItems()
      } else if (this.chooseItem) {
        this.$emit('addItem', {
          targetName: this.selectedTargetName,
          packetName: this.selectedPacketName,
          itemName: this.selectedItemNameWIndex,
          valueType: this.selectedValueType,
          reduced: this.selectedReduced,
          reducedType: this.selectedReducedType,
        })
      } else {
        this.$emit('addItem', {
          targetName: this.selectedTargetName,
          packetName: this.selectedPacketName,
          valueType: this.selectedValueType,
          reduced: this.selectedReduced,
          reducedType: this.selectedReducedType,
        })
      }
    },

    allTargetPacketItems: function () {
      this.packetNames.forEach((packetName) => {
        if (packetName === this.ALL) return
        const cmd = this.mode === 'tlm' ? 'get_tlm' : 'get_cmd'
        this.api[cmd](this.selectedTargetName, packetName.value).then(
          (packet) => {
            packet.items.forEach((item) => {
              this.$emit('addItem', {
                targetName: this.selectedTargetName,
                packetName: packetName.value,
                itemName: item['name'],
                valueType: this.selectedValueType,
                reduced: this.selectedReduced,
                reducedType: this.selectedReducedType,
              })
            })
          },
        )
      })
    },

    allPacketItems: function () {
      this.itemNames.forEach((item) => {
        if (item === this.ALL) return
        this.$emit('addItem', {
          targetName: this.selectedTargetName,
          packetName: this.selectedPacketName,
          itemName: item.value,
          valueType: this.selectedValueType,
          reduced: this.selectedReduced,
          reducedType: this.selectedReducedType,
        })
      })
    },
  },
}
</script>
<style scoped>
.button {
  padding: 4px;
}
.tpic-select {
  max-width: 300px;
}
</style>
