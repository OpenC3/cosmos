<!--
# Copyright 2025, OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card>
    <div style="padding: 10px">
      <target-packet-item-chooser
        :initial-target-name="initialTargetName"
        :initial-packet-name="initialPacketName"
        :disabled="sendDisabled"
        button-text="Send"
        mode="cmd"
        @on-set="commandChanged($event)"
        @add-item="buildCmd($event)"
      />
    </div>

    <v-card v-if="computedRows.length !== 0">
      <v-card-title class="d-flex align-center justify-content-space-between">
        Parameters
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
        :items="computedRows"
        :search="search"
        :items-per-page="-1"
        hide-default-footer
        multi-sort
        density="compact"
        @contextmenu:row="showContextMenu"
      >
        <template #item.val="{ item }">
          <slot
            name="parameter-editor"
            :item="item"
            :states-in-hex="statesInHex"
          >
            <!-- Default parameter editor if slot not provided -->
            <command-parameter-editor
              v-model="item.val"
              :states="item.states"
              :states-in-hex="statesInHex"
            />
          </slot>
        </template>
      </v-data-table>
    </v-card>

    <v-menu v-model="contextMenuShown" :target="[x, y]">
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

    <details-dialog
      v-model="viewDetails"
      :target-name="targetName"
      :packet-name="commandName"
      :item-name="parameterName"
      :type="'cmd'"
    />
  </v-card>
</template>

<script>
import 'sprintf-js'
import { Api, OpenC3Api } from '@openc3/js-common/services'
import TargetPacketItemChooser from './TargetPacketItemChooser.vue'
import CommandParameterEditor from './CommandParameterEditor.vue'
import DetailsDialog from './DetailsDialog.vue'
import { CmdUtilities } from '../util'

export default {
  name: 'CommandEditor',
  components: {
    TargetPacketItemChooser,
    CommandParameterEditor,
    DetailsDialog,
  },
  mixins: [CmdUtilities],
  props: {
    initialTargetName: {
      type: String,
      default: null,
    },
    initialPacketName: {
      type: String,
      default: null,
    },
    sendDisabled: {
      type: Boolean,
      default: false,
    },
    statesInHex: {
      type: Boolean,
      default: false,
    },
    showIgnoredParams: {
      type: Boolean,
      default: false,
    },
    cmdRaw: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['command-changed', 'build-cmd'],
  data() {
    return {
      search: '',
      headers: [
        { title: 'Name', value: 'parameter_name' },
        { title: 'Value or State', value: 'val' },
        { title: 'Units', value: 'units' },
        { title: 'Range', value: 'range' },
        { title: 'Description', value: 'description' },
      ],
      api: null,
      targetName: '',
      commandName: '',
      commandDescription: '',
      ignoredParams: [],
      computedRows: [],
      reservedItemNames: [],
      contextMenuShown: false,
      viewDetails: false,
      parameterName: '',
      x: 0,
      y: 0,
      contextMenuOptions: [
        {
          title: 'Details',
          action: () => {
            this.contextMenuShown = false
            this.viewDetails = true
          },
        },
      ],
    }
  },
  created() {
    this.api = new OpenC3Api()
    Api.get(`/openc3-api/autocomplete/reserved-item-names`).then((response) => {
      this.reservedItemNames = response.data
    })
  },
  methods: {
    commandChanged(event) {
      if (
        this.targetName !== event.targetName ||
        this.commandName !== event.packetName
      ) {
        this.targetName = event.targetName
        this.commandName = event.packetName
        this.updateCmdParams()
      }
      this.$emit('command-changed', event)
    },
    buildCmd(event) {
      this.$emit('build-cmd', event)
    },
    showContextMenu(event, row) {
      event.preventDefault()
      this.parameterName = row.item.parameter_name
      this.contextMenuShown = false
      this.x = event.clientX
      this.y = event.clientY
      this.$nextTick(() => {
        this.contextMenuShown = true
      })
    },
    updateCmdParams() {
      this.ignoredParams = []
      this.computedRows = []
      if (this.targetName && this.commandName) {
        this.api
          .get_target(this.targetName)
          .then(
            (target) => {
              this.ignoredParams = target.ignored_parameters
              return this.api.get_cmd(this.targetName, this.commandName)
            },
            (error) => {
              // eslint-disable-next-line no-console
              console.error('Error getting ignored parameters:', error)
            },
          )
          .then(
            (command) => {
              if (command) {
                command.items.forEach((parameter) => {
                  if (this.reservedItemNames.includes(parameter.name)) return
                  if (
                    !this.ignoredParams.includes(parameter.name) ||
                    this.showIgnoredParams
                  ) {
                    let val = parameter.default
                    if (
                      !parameter.states &&
                      parameter.data_type === 'STRING' &&
                      typeof parameter.default === 'string'
                    ) {
                      val = `'${val}'`
                    }
                    if (parameter.required) {
                      val = ''
                    }
                    if (parameter.format_string) {
                      val = sprintf(parameter.format_string, parameter.default)
                    }
                    let range = 'N/A'
                    if (
                      parameter.minimum != null &&
                      parameter.maximum != null
                    ) {
                      if (parameter.data_type === 'FLOAT') {
                        if (parameter.minimum < -1e6) {
                          if (Number.isSafeInteger(parameter.minimum)) {
                            parameter.minimum =
                              parameter.minimum.toExponential(3)
                          }
                        }
                        if (parameter.maximum > 1e6) {
                          if (Number.isSafeInteger(parameter.maximum)) {
                            parameter.maximum =
                              parameter.maximum.toExponential(3)
                          }
                        }
                      }
                      range = `${parameter.minimum}..${parameter.maximum}`
                    }
                    this.computedRows.push({
                      parameter_name: parameter.name,
                      val: val,
                      states: parameter.states,
                      description: parameter.description,
                      range: range,
                      units: parameter.units,
                      type: parameter.data_type,
                    })
                  }
                })
                this.commandDescription = command.description
              }
            },
            (error) => {
              // eslint-disable-next-line no-console
              console.error('Error getting command parameters:', error)
            },
          )
      }
    },
    triggerUpdateCmdParams() {
      this.updateCmdParams()
    },
    getCurrentParameters() {
      return this.computedRows
    },
    convertToValue(param) {
      if (param.val !== undefined && param.states && !this.cmdRaw) {
        return Object.keys(param.states).find(
          (state) => param.states[state].value === param.val,
        )
      }
      if (typeof param.val !== 'string') {
        return param.val
      }

      let str = param.val
      let quotesRemoved = this.removeQuotes(str)
      if (str === quotesRemoved) {
        let upcaseStr = str.toUpperCase()
        if (
          (param.type === 'STRING' || param.type === 'BLOCK') &&
          upcaseStr.startsWith('0X')
        ) {
          let hexStr = upcaseStr.slice(2)
          if (hexStr.length % 2 !== 0) {
            hexStr = '0' + hexStr
          }
          let jstr = { json_class: 'String', raw: [] }
          for (let i = 0; i < hexStr.length; i += 2) {
            let nibble = hexStr.charAt(i) + hexStr.charAt(i + 1)
            jstr.raw.push(parseInt(nibble, 16))
          }
          return jstr
        } else {
          if (upcaseStr === 'INFINITY') {
            return Infinity
          } else if (upcaseStr === '-INFINITY') {
            return -Infinity
          } else if (upcaseStr === 'NAN') {
            return NaN
          } else if (this.isFloat(str)) {
            return parseFloat(str)
          } else if (this.isInt(str)) {
            // If this is a number that is too large for a JS number
            // then we convert it to a BigInt which gets serialized in openc3Api.js
            if (!Number.isSafeInteger(Number(str))) {
              return BigInt(str)
            } else {
              return parseInt(str)
            }
          } else if (this.isArray(str)) {
            return eval(str)
          } else {
            return str
          }
        }
      } else {
        return quotesRemoved
      }
    },
    createParamList() {
      let paramList = {}
      for (const row of this.computedRows) {
        paramList[row.parameter_name] = this.convertToValue(row)
      }
      return paramList
    },
  },
}
</script>
