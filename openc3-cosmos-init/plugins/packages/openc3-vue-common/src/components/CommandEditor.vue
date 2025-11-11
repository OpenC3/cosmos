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
        :initial-target-name="targetName"
        :initial-packet-name="commandName"
        :disabled="sendDisabled"
        :button-text="showCommandButton ? 'Send' : null"
        :show-queue-select="showQueueSelect"
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
import { OpenC3Api } from '@openc3/js-common/services'
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
    cmdString: {
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
    showCommandButton: {
      type: Boolean,
      default: true,
    },
    showQueueSelect: {
      type: Boolean,
      default: true,
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
      reservedItemNames: [
        'PACKET_TIMESECONDS',
        'PACKET_TIMEFORMATTED',
        'RECEIVED_TIMESECONDS',
        'RECEIVED_TIMEFORMATTED',
        'RECEIVED_COUNT',
      ],
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
    if (this.cmdString) {
      this.processCmdString()
    } else {
      this.targetName = this.initialTargetName
      this.commandName = this.initialPacketName
      this.updateCmdParams()
    }
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
                      val = null // Special marker for required parameters
                    }
                    if (parameter.format_string && parameter.default) {
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

                // Populate with parsed parameters if available
                this.populateParametersFromParsed()
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
    getRows() {
      return this.computedRows
    },
    getCmdString() {
      let cmd = `${this.targetName} ${this.commandName}`
      if (this.computedRows.length === 0) return cmd
      cmd += ' with'
      for (const row of this.computedRows) {
        // null value indicates required parameter not set, see updateCmdParams
        if (row.val === null) {
          throw new Error(`Required parameter ${row.parameter_name} not set`)
        }
        if (row.val !== null && row.val !== undefined && row.val !== '') {
          if (row.states) {
            // If states exist, find the state name for the value
            const stateEntry = Object.entries(row.states).find(
              ([, state]) => state.value === row.val,
            )
            if (stateEntry) {
              // Although not always necessary, always quote states
              cmd += ` ${row.parameter_name} '${stateEntry[0]}',`
              continue
            }
          }
          // We only put the param value in quotes if it is a string with spaces
          // Check for array syntax because we do NOT quote arrays
          let value = this.convertToString(row.val)
          if (value.includes(' ') && !this.isArray(value)) {
            cmd += ` ${row.parameter_name} '${value}',`
          } else {
            cmd += ` ${row.parameter_name} ${value},`
          }
        }
      }
      // Remove trailing comma
      return cmd.slice(0, -1)
    },
    parseCmdString(cmdString) {
      // Parse commands in format: "TARGET COMMAND with PARAM1 value1, PARAM2 value2"
      const parts = cmdString.split(' ')
      if (parts.length < 2) return { target: '', command: '', params: {} }
      if (parts.length === 2) {
        return { target: parts[0], command: parts[1], params: {} }
      }
      // Check for a malformed command string that doesn't have 'with'
      if (parts[2] !== 'with') return { target: '', command: '', params: {} }

      const target = parts[0]
      const command = parts[1]
      let params = {}

      const paramsString = cmdString.split(' with ')[1]
      let paramPairs = []
      let bracketLevel = 0
      let current = ''
      // Parse the params char by char to handle commas inside brackets
      for (let char of paramsString) {
        if (char === '[') {
          bracketLevel++
          current += char
        } else if (char === ']') {
          bracketLevel--
          current += char
        } else if (char === ',' && bracketLevel === 0) {
          paramPairs.push(current.trim())
          current = ''
        } else {
          current += char
        }
      }
      if (current.trim() !== '') {
        paramPairs.push(current.trim())
      }

      for (let pair of paramPairs) {
        let firstSpace = pair.indexOf(' ')
        if (firstSpace > 0) {
          let key = pair.substring(0, firstSpace).trim()
          let value = pair.substring(firstSpace + 1).trim()
          params[key] = value
        }
      }
      return { target: target, command: command, params: params }
    },
    processCmdString() {
      const parsed = this.parseCmdString(this.cmdString)
      if (parsed.target && parsed.command) {
        this.targetName = parsed.target
        this.commandName = parsed.command
        this.parsedParameters = parsed.params
        this.updateCmdParams()
      }
    },
    populateParametersFromParsed() {
      // Populate parameters after command parameters are loaded
      if (
        !this.parsedParameters ||
        Object.keys(this.parsedParameters).length === 0
      ) {
        return
      }

      this.$nextTick(() => {
        // Give time for parameters to load
        setTimeout(() => {
          this.computedRows.forEach((row) => {
            if (this.parsedParameters.hasOwnProperty(row.parameter_name)) {
              const value = this.parsedParameters[row.parameter_name]
              // Set the value based on parameter type
              if (row.states && typeof value === 'string') {
                // For state parameters, try to match the state name
                const stateKey = Object.keys(row.states).find(
                  (key) =>
                    key === value || key.toLowerCase() === value.toLowerCase(),
                )
                if (stateKey) {
                  row.val = row.states[stateKey].value
                } else {
                  row.val = value
                }
              } else if (row.type === 'STRING' && typeof value === 'string') {
                // For string parameters, add quotes if not present
                row.val =
                  value.startsWith("'") || value.startsWith('"')
                    ? value
                    : `'${value}'`
              } else {
                row.val = value
              }
            }
          })
        }, 100) // Shorter delay since we're already in the component
      })
    },
  },
}
</script>
