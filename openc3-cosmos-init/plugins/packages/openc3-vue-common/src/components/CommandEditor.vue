<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card>
    <div style="padding: 10px">
      <target-packet-item-chooser
        ref="targetPacketChooser"
        :initial-target-name="targetName"
        :initial-packet-name="commandName"
        :disabled="sendDisabled || commandLoading"
        :disable-button-text="readOnly ? 'Viewers cannot send commands' : null"
        :button-text="showCommandButton ? 'Send' : null"
        :show-queue-select="showQueueSelect"
        :parameter-hazardous="hasHazardousParameter"
        :show-hazardous="showHazardous"
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
        item-value="key"
        class="parameters-table"
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
              :disabled="item.disabled"
              :allow-manual-entry="ignoreRangeChecks"
              @hazardous-change="onParameterHazardousChange(item, $event)"
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
import { findKey } from 'lodash'
import TargetPacketItemChooser from './TargetPacketItemChooser.vue'
import CommandParameterEditor from './CommandParameterEditor.vue'
import DetailsDialog from './DetailsDialog.vue'
import { CmdUtilities } from '../util'
import {
  paramValueFromText,
  parseCmdTextLenient,
} from '../util/cmdStringParser'

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
    readOnly: {
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
    ignoreRangeChecks: {
      type: Boolean,
      default: false,
    },
    // Show the chooser's hazardous warning below the description
    showHazardous: {
      type: Boolean,
      default: true,
    },
  },
  emits: [
    'command-changed',
    'build-cmd',
    'command-loaded',
    'params-changed',
    'update:showIgnoredParams',
  ],
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
      // Incremented by every updateCmdParams so a slow response for a
      // previously selected command doesn't overwrite the current one
      loadId: 0,
      // Incremented by every setCommand so only the newest of overlapping
      // calls loads, whichever finishes fetching first
      setCommandId: 0,
      // TARGET COMMAND the rows were built for
      rowsCommand: null,
      parsedParameters: null,
      targetName: '',
      commandName: '',
      commandDescription: '',
      // Keep Send disabled until the selected command's parameters and
      // descriptions are loaded so we never send with stale values
      commandLoading: false,
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
      hazardousParameters: {},
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
  computed: {
    paramValues() {
      return this.computedRows.map((row) => row.val)
    },
    hasHazardousParameter() {
      return Object.values(this.hazardousParameters).some((v) => v === true)
    },
  },
  watch: {
    // Only the values, not a deep walk of every row's states, which is slow
    // for commands with many parameters and states
    paramValues() {
      this.$emit('params-changed')
    },
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
    onParameterHazardousChange(item, isHazardous) {
      this.hazardousParameters[item.parameter_name] = isHazardous
    },
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
    // Resolves once the parameters are loaded (or failed to load)
    updateCmdParams() {
      // Reloading the same command (e.g. Show Ignored Parameters toggled)
      // keeps the values in the form, including obfuscated values still
      // waiting to be entered, so nothing reverts to its default
      const keep =
        this.rowsCommand === `${this.targetName} ${this.commandName}`
          ? new Map(this.computedRows.map((row) => [row.parameter_name, row]))
          : null
      this.ignoredParams = []
      this.computedRows = []
      this.hazardousParameters = {}
      const loadId = ++this.loadId
      const targetName = this.targetName
      const commandName = this.commandName
      if (targetName && commandName) {
        this.commandLoading = true
        return this.api
          .get_target(targetName)
          .then(
            (target) => {
              if (loadId !== this.loadId) return null
              this.ignoredParams = target.ignored_parameters
              return this.api.get_cmd(targetName, commandName)
            },
            (error) => {
              console.error('Error getting ignored parameters:', error)
            },
          )
          .then(
            (command) => {
              // Another command was selected while this one loaded
              if (loadId !== this.loadId) return
              this.commandLoading = false
              if (command) {
                const rows = this.buildRows(command)
                for (const row of keep ? rows : []) {
                  const previous = keep.get(row.parameter_name)
                  if (previous) {
                    row.val = previous.val
                    row.obfuscated = previous.obfuscated
                  }
                }
                this.computedRows = rows
                this.rowsCommand = `${targetName} ${commandName}`
                this.commandDescription = command.description

                // Populate with parsed parameters if available
                this.populateParametersFromParsed()
                this.$emit('command-loaded', command)
              } else {
                this.$emit('command-loaded', null)
              }
            },
            (error) => {
              if (loadId !== this.loadId) return
              this.commandLoading = false
              console.error('Error getting command parameters:', error)
              this.$emit('command-loaded', null)
            },
          )
      } else {
        this.$emit('command-loaded', null)
        return Promise.resolve()
      }
    },
    // The table rows for a command definition, with default values.
    // showIgnored overrides the showIgnoredParams prop.
    // ignoredParams and keyId default to the editor's; setCommand passes the
    // new command's before committing them.
    buildRows(
      command,
      showIgnored = this.showIgnoredParams,
      ignoredParams = this.ignoredParams,
      keyId = this.loadId,
    ) {
      // Identify length fields that are auto-managed by variable_bit_size arrays
      // These should be shown but disabled - they will be set when the array is written
      const autoLengthFields = new Set()
      command.items.forEach((parameter) => {
        if (parameter.variable_bit_size) {
          autoLengthFields.add(
            parameter.variable_bit_size.length_item_name.toUpperCase(),
          )
        }
      })

      const rows = []
      command.items.forEach((parameter) => {
        if (this.reservedItemNames.includes(parameter.name)) return
        if (
          !parameter.hidden &&
          (!ignoredParams.includes(parameter.name) || showIgnored)
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
          if (Object.prototype.toString.call(val).slice(8, -1) === 'Object') {
            val = this.convertToString(val)
          }
          let range = 'N/A'
          if (parameter.minimum != null && parameter.maximum != null) {
            if (parameter.data_type === 'FLOAT') {
              if (parameter.minimum < -1e6) {
                parameter.minimum = parameter.minimum.toExponential(3)
              }
              if (parameter.maximum > 1e6) {
                parameter.maximum = parameter.maximum.toExponential(3)
              }
            }
            range = `${parameter.minimum}..${parameter.maximum}`
          }
          rows.push({
            // Unique per load so the table doesn't reuse a parameter editor
            // (and its local state) from the previous command
            key: `${keyId}-${parameter.name}`,
            parameter_name: parameter.name,
            val: val,
            states: parameter.states,
            description: parameter.description,
            range: range,
            units: parameter.units,
            type: parameter.data_type,
            // Disable auto-managed length fields for variable_bit_size arrays
            disabled: autoLengthFields.has(parameter.name.toUpperCase()),
            // OBFUSCATE: shown as ***** in logs and the history
            obfuscate: !!parameter.obfuscate,
          })
        }
      })
      return rows
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
            const stateKey = findKey(
              row.states,
              (state) => state.value === row.val,
            )
            if (stateKey) {
              // Although not always necessary, always quote states
              cmd += ` ${row.parameter_name} '${stateKey}',`
              continue
            }
          }
          // We only put the param value in quotes if it is a string with spaces
          // Check for array syntax because we do NOT quote arrays
          let value = this.convertToString(row.val)
          if (
            value.includes(' ') &&
            !this.isArray(value) &&
            this.removeQuotes(value) === value
          ) {
            cmd += ` ${row.parameter_name} '${value}',`
          } else {
            cmd += ` ${row.parameter_name} ${value},`
          }
        }
      }
      // Remove trailing comma
      return cmd.slice(0, -1)
    },
    // Parse "TARGET COMMAND with PARAM1 value1, PARAM2 value2" into
    // { target, command, params }, with empty names if it's malformed
    parseCmdString(cmdString) {
      // Lenient so unquoted values with spaces, as some callers write them,
      // still load
      return (
        parseCmdTextLenient(cmdString) || {
          target: '',
          command: '',
          params: {},
        }
      )
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
      // Called once the parameters are loaded
      if (this.parsedParameters) {
        this.applyParameters(this.parsedParameters)
        this.parsedParameters = null
      }
    },
    // Load a command into the editor, e.g. one pasted or picked from the
    // Command Sender history. parsed is { target, command, params, queue }
    // from parseCmdLine with params as written in the command string.
    // The definition is fetched and the rows built and filled in before
    // anything on screen changes, then swapped in at once so the table
    // doesn't empty and refill. Rejects if the target or command doesn't
    // exist, leaving the current command alone. Ignored parameters the
    // command sets are shown (emitting update:showIgnoredParams) so the form
    // matches it exactly. Resolves to the names that couldn't be set (see
    // applyParameters) plus unknownQueue: the queue, if it isn't one of the
    // queues (it's left as None), else null.
    async setCommand({ target, command, params = {}, queue }) {
      const targetName = target.toUpperCase()
      const commandName = command.toUpperCase()
      // Taking over loadId only once the definition has loaded means a load
      // that fails (e.g. an unknown command) doesn't cancel the one in
      // progress, which would leave the editor loading
      const startId = this.loadId
      const request = ++this.setCommandId
      const headers = { 'Ignore-Errors': '500' }
      const definition = await this.api.exec(
        'get_cmd',
        [targetName, commandName],
        {},
        headers,
      )
      const targetInfo = await this.api.exec(
        'get_target',
        [targetName],
        {},
        headers,
      )
      // The queue list loads when the chooser is created, so a queue can
      // only be checked against it once it has
      const queuesLoaded = await this.$refs.targetPacketChooser.queuesReady
      // A newer setCommand, or a command picked in the chooser, replaced this
      // one. Without the request check, an older call that finished first
      // would take loadId and make the newer one fail instead.
      if (request !== this.setCommandId || startId !== this.loadId) {
        throw new Error('Another command was selected while loading')
      }
      const ignoredParams = targetInfo?.ignored_parameters || []
      const showIgnored =
        this.showIgnoredParams ||
        Object.keys(params).some((name) =>
          ignoredParams.includes(name.toUpperCase()),
        )
      // Build and fill in the rows before changing anything, so a value
      // that can't be converted leaves the editor (and any reload in
      // progress) as it was
      const rows = this.buildRows(
        definition,
        showIgnored,
        ignoredParams,
        this.loadId + 1,
      )
      const result = this.applyParameters(params, rows, ignoredParams)

      this.loadId++
      this.ignoredParams = ignoredParams
      this.rowsCommand = `${targetName} ${commandName}`
      this.parsedParameters = null
      this.targetName = targetName
      this.commandName = commandName
      this.hazardousParameters = {}
      this.computedRows = rows
      this.commandDescription = definition.description
      this.commandLoading = false
      if (showIgnored && !this.showIgnoredParams) {
        this.$emit('update:showIgnoredParams', true)
      }
      const queueSelected = this.$refs.targetPacketChooser.setSelection(
        targetName,
        commandName,
        queue,
      )
      // A queue that isn't in the queue list is left off (None), as is one
      // that couldn't be checked because the queue list failed to load
      result.unknownQueue = queueSelected ? null : queue
      result.queueLookupFailed = !queueSelected && !queuesLoaded
      this.$emit('command-loaded', definition)
      return result
    },
    // Set row values from { NAME: 'value as written' }. Returns the names
    // that couldn't be set: unknown (not a parameter of the command), hidden
    // (an ignored parameter that isn't shown) and obfuscated (shown as *****
    // in the history, so the value is unknown and left unset).
    applyParameters(
      params,
      rows = this.computedRows,
      ignoredParams = this.ignoredParams,
    ) {
      const result = { unknown: [], hidden: [], obfuscated: [] }
      const byName = new Map(
        rows.map((row) => [row.parameter_name.toUpperCase(), row]),
      )
      for (const [name, text] of Object.entries(params)) {
        const upcaseName = name.toUpperCase()
        const row = byName.get(upcaseName)
        if (!row) {
          if (ignoredParams.includes(upcaseName)) {
            result.hidden.push(upcaseName)
          } else {
            result.unknown.push(upcaseName)
          }
          continue
        }
        const value = String(text)
        if (row.obfuscate && this.removeQuotes(value) === '*****') {
          // The history's mask for an obfuscated value (a literal ***** for
          // any other parameter is kept). Unset, like a required parameter,
          // and flagged so Send asks for it rather than send the default.
          row.val = null
          row.obfuscated = true
          result.obfuscated.push(row.parameter_name)
          continue
        }
        row.val = this.parsedValue(row, value)
      }
      return result
    },
    // A value as written in a command string to the form a row holds
    parsedValue(row, value) {
      return paramValueFromText(row, value)
    },
  },
}
</script>

<style scoped>
.parameters-table {
  max-height: 50vh;
}
</style>
