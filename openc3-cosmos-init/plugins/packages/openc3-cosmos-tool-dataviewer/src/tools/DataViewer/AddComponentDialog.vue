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
    <!-- Dialog for adding a new component to a tab -->
    <!-- width chosen to fit target-packet-item-chooser at full width -->
    <v-dialog v-model="show" width="1200">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span> Configure Component </span>
          <v-spacer />
        </v-toolbar>
        <v-card-text>
          <v-container>
            <v-row align="center">
              <v-col>Select Component:</v-col>
              <v-col>
                <v-select
                  hide-details
                  density="compact"
                  variant="outlined"
                  :items="components"
                  item-title="label"
                  item-value="value"
                  v-model="selectedComponent"
                  return-object
                  data-test="select-component"
                />
              </v-col>
            </v-row>
            <v-row
              ><v-col>Add packets for this component to process.</v-col></v-row
            >
            <v-row>
              <v-col class="my-2">
                <v-radio-group
                  v-model="newPacketCmdOrTlm"
                  inline
                  hide-details
                  class="mt-0"
                >
                  <v-radio
                    label="Command"
                    value="cmd"
                    data-test="command-packet-radio"
                  />
                  <v-radio
                    label="Telemetry"
                    value="tlm"
                    data-test="telemetry-packet-radio"
                  />
                </v-radio-group>
              </v-col>
            </v-row>
            <v-row>
              <v-col>
                <target-packet-item-chooser
                  @add-item="addValue"
                  :button-text="chooseItem ? 'Add Item' : 'Add Packet'"
                  :mode="newPacketCmdOrTlm"
                  :chooseItem="chooseItem"
                />
              </v-col>
            </v-row>
            <v-row>
              <v-col>
                <v-radio-group v-model="newPacketMode" inline hide-details>
                  <v-radio
                    label="Raw"
                    value="RAW"
                    :disabled="disableRadioOptions"
                    data-test="new-packet-raw-radio"
                  />
                  <v-radio
                    label="Decom"
                    value="DECOM"
                    :disabled="disableRadioOptions"
                    data-test="new-packet-decom-radio"
                  />
                </v-radio-group>
              </v-col>
              <v-col>
                <v-select
                  v-if="newPacketMode === 'DECOM'"
                  v-model="newPacketValueType"
                  hide-details
                  label="Value Type"
                  data-test="add-packet-value-type"
                  :items="valueTypes"
                />
              </v-col>
            </v-row>
            <v-row
              ><v-col>
                <v-data-table
                  :headers="headers"
                  :items="packets"
                  v-model:items-per-page="itemsPerPage"
                  :items-per-page-options="[10, 100]"
                  multi-sort
                  density="compact"
                >
                  <template v-slot:item.delete="{ item }">
                    <v-tooltip location="top">
                      <template v-slot:activator="{ props }">
                        <v-icon @click="deleteItem(item)" v-bind="props">
                          mdi-delete
                        </v-icon>
                      </template>
                      <span>Delete Item</span>
                    </v-tooltip>
                  </template>
                </v-data-table>
              </v-col></v-row
            >
          </v-container>
        </v-card-text>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn
            variant="outlined"
            data-test="cancel-component"
            @click="cancelAddComponent"
          >
            Cancel
          </v-btn>
          <v-btn
            variant="flat"
            data-test="add-component"
            :disabled="!valid"
            @click="addComponent"
          >
            Create
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import { TargetPacketItemChooser } from '@openc3/vue-common/components'

export default {
  components: {
    TargetPacketItemChooser,
  },
  props: {
    modelValue: Boolean,
    components: Object,
  },
  data() {
    return {
      selectedComponent: this.components[0],
      newPacket: null,
      newPacketCmdOrTlm: 'tlm',
      newPacketMode: 'RAW',
      valueTypes: ['CONVERTED', 'RAW', 'FORMATTED', 'WITH_UNITS'],
      newPacketValueType: 'WITH_UNITS',
      chooseItem: false,
      disableRadioOptions: false,
      headers: [
        { title: 'Cmd/Tlm', value: 'cmdOrTlm' },
        { title: 'Target', value: 'targetName' },
        { title: 'Packet', value: 'packetName' },
        { title: 'Item', value: 'itemName' },
        { title: 'Mode', value: 'mode' },
        { title: 'ValueType', value: 'valueType' },
        { title: 'Delete', value: 'delete' },
      ],
      itemsPerPage: 20,
      packets: [],
    }
  },
  computed: {
    valid: function () {
      if (this.selectedComponent === null || this.packets.length === 0) {
        return false
      } else {
        return true
      }
    },
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
  },
  watch: {
    newPacketCmdOrTlm: {
      immediate: true,
      handler: function () {
        this.newPacket = null
      },
    },
    selectedComponent: {
      handler: function () {
        if (this.selectedComponent.items) {
          this.chooseItem = true
          this.newPacketMode = 'DECOM'
          this.disableRadioOptions = true
        } else {
          this.chooseItem = false
          this.newPacketMode = 'RAW'
          this.disableRadioOptions = false
        }
      },
    },
  },
  methods: {
    addValue: function (event) {
      let type = this.newPacketValueType
      if (this.newPacketMode === 'RAW') {
        type = 'N/A'
      }
      this.packets.push({
        cmdOrTlm: this.newPacketCmdOrTlm.toUpperCase(),
        targetName: event.targetName,
        packetName: event.packetName,
        itemName: event.itemName,
        mode: this.newPacketMode,
        valueType: type,
      })
    },
    addComponent: function (event) {
      this.$emit('add', {
        packets: this.packets,
        component: this.selectedComponent,
        mode: this.newPacketMode,
        valueType: this.newPacketValueType,
      })
    },
    deleteItem: function (item) {
      let index = this.packets.indexOf(item)
      this.packets.splice(index, 1)
    },
    cancelAddComponent: function () {
      this.$emit('cancel', {})
    },
  },
}
</script>
