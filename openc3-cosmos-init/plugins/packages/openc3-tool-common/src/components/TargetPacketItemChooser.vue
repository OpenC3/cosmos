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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <!-- tgt-pkt-item-chooser class used by Graph.vue to size the graph -->
  <div class="pt-4 tgt-pkt-item-chooser">
    <v-row>
      <v-col :cols="colSize" class="select" data-test="select-target">
        <v-autocomplete
          label="Select Target"
          hide-details
          dense
          outlined
          @change="targetNameChanged"
          :items="targetNames"
          item-text="label"
          item-value="value"
          v-model="selectedTargetName"
        />
      </v-col>
      <v-col :cols="colSize" class="select" data-test="select-packet">
        <v-autocomplete
          label="Select Packet"
          hide-details
          dense
          outlined
          @change="packetNameChanged"
          :disabled="packetsDisabled || buttonDisabled"
          :items="packetNames"
          item-text="label"
          item-value="value"
          v-model="selectedPacketName"
        />
      </v-col>
      <v-col
        v-if="chooseItem && !buttonDisabled"
        :cols="colSize"
        class="select"
        data-test="select-item"
      >
        <v-autocomplete
          label="Select Item"
          hide-details
          dense
          outlined
          @change="itemNameChanged($event)"
          :disabled="itemsDisabled || buttonDisabled"
          :items="itemNames"
          item-text="label"
          item-value="value"
          v-model="selectedItemName"
        />
      </v-col>
      <v-col
        v-if="itemIsArray()"
        :cols="colSize"
        class="select"
        data-test="array-index"
      >
        <v-combobox
          label="Array Index"
          hide-details
          dense
          outlined
          :disabled="itemsDisabled || buttonDisabled"
          :items="arrayIndexes()"
          item-text="label"
          item-value="value"
          v-model="selectedArrayIndex"
        />
      </v-col>
      <v-col v-if="buttonText" :cols="colSize" style="max-width: 0px">
        <v-btn
          :disabled="buttonDisabled"
          block
          color="primary"
          data-test="select-send"
          @click="buttonPressed"
        >
          {{ actualButtonText }}
        </v-btn>
      </v-col>
    </v-row>
    <v-row v-if="selectTypes">
      <v-col :cols="colSize" class="select" data-test="data-type">
        <v-autocomplete
          label="Value Type"
          hide-details
          dense
          outlined
          :items="valueTypes"
          v-model="selectedValueType"
        />
      </v-col>
      <v-col :cols="colSize" class="select" data-test="reduced">
        <v-autocomplete
          label="Reduced"
          hide-details
          dense
          outlined
          :items="reductionModes"
          v-model="selectedReduced"
        />
      </v-col>
      <v-col :cols="colSize" class="select" data-test="reduced-type">
        <v-autocomplete
          label="Reduced Type"
          hide-details
          dense
          outlined
          :disabled="selectedReduced === 'DECOM'"
          :items="reducedTypes"
          v-model="selectedReducedType"
        />
      </v-col>
      <v-col :cols="colSize" style="max-width: 0px"> </v-col>
    </v-row>
    <v-row no-gutters class="pt-1">
      <v-col v-if="hazardous" :cols="colSize" class="openc3-yellow"
        >Description: {{ description }} (HAZARDOUS)</v-col
      >
      <v-col v-else :cols="colSize">Description: {{ description }} </v-col>
    </v-row>
  </div>
</template>

<script>
import { OpenC3Api } from '../services/openc3-api'
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
        { text: 'NONE', value: 'DECOM' },
        { text: 'REDUCED_MINUTE', value: 'REDUCED_MINUTE' },
        { text: 'REDUCED_HOUR', value: 'REDUCED_HOUR' },
        { text: 'REDUCED_DAY', value: 'REDUCED_DAY' },
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
      if (this.allowAllTargets) {
        this.targetNames.unshift(this.ALL)
      }
      if (!this.selectedTargetName) {
        this.selectedTargetName = this.targetNames[0].value
        this.targetNameChanged(this.selectedTargetName)
      }
      this.updatePackets()
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
    buttonDisabled: function () {
      return this.disabled || this.internalDisabled
    },
    colSize: function () {
      return this.vertical ? 12 : false
    },
    selectedItemNameWIndex: function () {
      if (
        this.selectedArrayIndex !== null &&
        this.selectedArrayIndex !== this.ALL.label
      ) {
        return `${this.selectedItemName}[${this.selectedArrayIndex}]`
      } else {
        return this.selectedItemName
      }
    },
  },
  watch: {
    mode: function (newVal, oldVal) {
      this.selectedPacketName = null
      this.selectedItemName = null
      this.updatePackets()
    },
  },
  methods: {
    updatePackets: function () {
      if (this.selectedTargetName === 'UNKNOWN') {
        this.packetNames = [this.UNKNOWN]
        this.selectedPacketName = this.packetNames[0].value
        this.packetNameChanged(this.UNKNOWN.value)
        this.description = 'UNKNOWN'
        return
      }
      if (this.selectedTargetName === 'ALL') {
        this.packetNames = [this.ALL]
        this.selectedPacketName = this.packetNames[0].value
        this.packetNameChanged(this.ALL.value)
        this.description = 'ALL'
        return
      }
      this.internalDisabled = true
      const cmd =
        this.mode === 'tlm' ? 'get_all_tlm_names' : 'get_all_cmd_names'
      this.api[cmd](this.selectedTargetName).then((names) => {
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
        this.packetNameChanged(this.selectedPacketName)
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
      const cmd = this.mode === 'tlm' ? 'get_tlm' : 'get_cmd'
      this.api[cmd](this.selectedTargetName, this.selectedPacketName).then(
        (packet) => {
          this.itemNames = packet.items
            .map((item) => {
              return [
                {
                  label: item.name,
                  value: item.name,
                  description: item.description,
                  array: item.array_size / item.bit_size,
                },
              ]
            })
            .reduce((result, item) => {
              return result.concat(item)
            }, [])
          if (this.allowAll) {
            this.itemNames.unshift(this.ALL)
          }
          if (!this.selectedItemName) {
            this.selectedItemName = this.itemNames[0].value
          }
          this.description = this.itemNames[0].description
          this.internalDisabled = false
          this.$emit('on-set', {
            targetName: this.selectedTargetName,
            packetName: this.selectedPacketName,
            itemName: this.selectedItemNameWIndex,
            valueType: this.selectedValueType,
            reduced: this.selectedReduced,
            reducedType: this.selectedReducedType,
          })
        }
      )
    },
    itemIsArray: function () {
      let i = this.itemNames.findIndex(
        (item) => item.value === this.selectedItemName
      )
      if (i === -1) {
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
        (item) => item.value === this.selectedItemName
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
      this.updatePackets()
    },

    packetNameChanged: function (value) {
      if (value === 'ALL') {
        this.itemsDisabled = true
        this.internalDisabled = false
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
            }
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

    buttonPressed: function () {
      if (this.selectedPacketName === 'ALL') {
        this.allTargetPacketItems()
      } else if (this.selectedItemName === 'ALL') {
        this.allPacketItems()
      } else if (this.chooseItem) {
        this.$emit('click', {
          targetName: this.selectedTargetName,
          packetName: this.selectedPacketName,
          itemName: this.selectedItemNameWIndex,
          valueType: this.selectedValueType,
          reduced: this.selectedReduced,
          reducedType: this.selectedReducedType,
        })
      } else {
        this.$emit('click', {
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
              this.$emit('click', {
                targetName: this.selectedTargetName,
                packetName: packetName.value,
                itemName: item['name'],
                valueType: this.selectedValueType,
                reduced: this.selectedReduced,
                reducedType: this.selectedReducedType,
              })
            })
          }
        )
      })
    },

    allPacketItems: function () {
      this.itemNames.forEach((item) => {
        if (item === this.ALL) return
        this.$emit('click', {
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
.select {
  max-width: 300px;
}
.row + .row {
  margin-top: 0px;
}
</style>
