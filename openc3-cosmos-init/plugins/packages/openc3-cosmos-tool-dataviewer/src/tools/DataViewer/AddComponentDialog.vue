<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addstopums as found in the LICENSE.txt
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
    <v-dialog v-model="show" width="800">
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span> Configure Component </span>
          <v-spacer />
        </v-system-bar>
        <v-card-text>
          <v-container>
            <v-row align="center">
              <v-col>Select Component:</v-col>
              <v-col>
                <v-select
                  hide-details
                  dense
                  outlined
                  :items="components"
                  item-text="label"
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
                  row
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
                  @click="addPacket"
                  button-text="Add Packet"
                  :mode="newPacketCmdOrTlm"
                  unknown
                />
              </v-col>
            </v-row>
            <v-row>
              <v-col>
                <v-radio-group v-model="newPacketMode" row hide-details>
                  <v-radio
                    label="Raw"
                    value="RAW"
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
                  :search="search"
                  :items-per-page="itemsPerPage"
                  @update:items-per-page="itemsPerPage = $event"
                  :footer-props="{
                    itemsPerPageOptions: [10, 100],
                    showFirstLastPage: true,
                    firstIcon: 'mdi-page-first',
                    lastIcon: 'mdi-page-last',
                    prevIcon: 'mdi-chevron-left',
                    nextIcon: 'mdi-chevron-right',
                  }"
                  calculate-widths
                  multi-sort
                  dense
                >
                  <template v-slot:item.delete="{ item }">
                    <v-tooltip bottom>
                      <template v-slot:activator="{ on, attrs }">
                        <v-icon
                          @click="deleteItem(item)"
                          v-bind="attrs"
                          v-on="on"
                        >
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
        <v-card-actions>
          <v-spacer />
          <v-btn
            outlined
            class="mx-2"
            data-test="cancel-component"
            @click="cancelAddComponent"
          >
            Cancel
          </v-btn>
          <v-btn
            color="primary"
            class="mx-2"
            data-test="add-component"
            :disabled="notValid"
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
import TargetPacketItemChooser from '@openc3/tool-common/src/components/TargetPacketItemChooser'

export default {
  components: {
    TargetPacketItemChooser,
  },
  props: {
    value: Boolean, // value is the default prop when using v-model
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
      headers: [
        { text: 'Cmd/Tlm', value: 'cmdOrTlm' },
        { text: 'Target', value: 'targetName' },
        { text: 'Packet', value: 'packetName' },
        { text: 'Mode', value: 'mode' },
        { text: 'ValueType', value: 'valueType' },
        { text: 'Delete', value: 'delete' },
      ],
      itemsPerPage: 20,
      packets: [],
    }
  },
  computed: {
    notValid: function () {
      if (this.selectedComponent === null || this.packets.length === 0) {
        return true
      } else {
        return false
      }
    },
    disableRadioOptions: function () {
      if (this.newPacket) {
        return this.newPacket.packet === 'UNKNOWN'
      }
      return false
    },
    show: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
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
  },
  methods: {
    addPacket: function (event) {
      let type = this.newPacketValueType
      if (this.newPacketMode === 'RAW') {
        type = 'N/A'
      }
      this.packets.push({
        cmdOrTlm: this.newPacketCmdOrTlm.toUpperCase(),
        targetName: event.targetName,
        packetName: event.packetName,
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
      var index = this.packets.indexOf(item)
      this.packets.splice(index, 1)
    },
    cancelAddComponent: function () {
      this.$emit('cancel', {})
    },
  },
}
</script>
