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
      <div style="padding: 10px">
        <target-packet-item-chooser
          :initial-target-name="this.$route.params.target"
          :initial-packet-name="this.$route.params.packet"
          @on-set="commandChanged($event)"
          @addItem="buildCmd($event)"
          :disabled="sendDisabled"
          button-text="Send"
          mode="cmd"
        />
      </div>

      <v-card v-if="rows.length !== 0">
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
          :items="rows"
          :search="search"
          :items-per-page="-1"
          hide-default-footer
          multi-sort
          density="compact"
          @contextmenu:row="showContextMenu"
        >
          <template v-slot:item.val="{ item }">
            <command-parameter-editor
              v-model="item.val"
              :states="item.states"
              :states-in-hex="statesInHex"
            />
          </template>
        </v-data-table>
      </v-card>
      <div class="pa-3">Status: {{ status }}</div>
    </v-card>
    <div style="height: 15px" />
    <v-row>
      <v-col>
        <v-card class="pb-2">
          <v-card-subtitle>
            <v-row>
              <v-col class="pt-6">
                Editable Command History: (Pressing Enter on the line
                re-executes the command)
              </v-col>
              <v-col>
                <v-tooltip location="top">
                  <template v-slot:activator="{ props }">
                    <div v-bind="props" class="float-right">
                      <v-btn
                        icon="mdi-delete"
                        variant="text"
                        data-test="clear-history"
                        @click="clearHistory"
                      />
                    </div>
                  </template>
                  <span> Clear History </span>
                </v-tooltip>
              </v-col>
            </v-row>
          </v-card-subtitle>
          <v-row class="mt-2 mb-2">
            <pre ref="editor" class="editor" data-test="sender-history"></pre>
          </v-row>
        </v-card>
      </v-col>
      <v-col v-if="screenDefinition" md="auto">
        <openc3-screen
          :target="screenTarget"
          :screen="screenName"
          :definition="screenDefinition"
          :keywords="keywords"
          :count="screenCount"
          :showClose="false"
        />
      </v-col>
    </v-row>
    <div style="height: 15px" />

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
      :target-name="targetName"
      :packet-name="commandName"
      :item-name="parameterName"
      :type="'cmd'"
      v-model="viewDetails"
    />

    <v-dialog v-model="displayErrorDialog" max-width="600">
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span> Error </span>
          <v-spacer />
        </v-system-bar>
        <v-card-text>
          <div class="mx-1">
            <v-row class="my-2">
              <v-card-text>
                <span v-text="status" />
              </v-card-text>
            </v-row>
            <v-row>
              <v-spacer />
              <v-btn
                @click="displayErrorDialog = false"
                color="primary"
                data-test="error-dialog-ok"
              >
                Ok
              </v-btn>
            </v-row>
          </div>
        </v-card-text>
      </v-card>
    </v-dialog>

    <v-dialog v-model="displaySendHazardous" max-width="600">
      <v-card>
        <v-system-bar absolute>
          <v-spacer />
          <span> Hazardous Warning </span>
          <v-spacer />
        </v-system-bar>
        <v-card-text class="mt-6">
          Warning: Command {{ hazardousCommand }} is Hazardous. Send?
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn @click="cancelHazardousCmd" variant="outlined"> Cancel </v-btn>
          <v-btn @click="sendHazardousCmd" class="bg-primary mx-1">
            Send
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="displaySendRaw" max-width="600">
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span> Send Raw </span>
          <v-spacer />
        </v-system-bar>
        <v-card-text>
          <div class="mx-1">
            <v-row class="my-2">
              <v-col>Interface:</v-col>
              <v-col>
                <v-select
                  variant="solo"
                  hide-details
                  density="compact"
                  :items="interfaces"
                  item-title="label"
                  item-value="value"
                  v-model="selectedInterface"
                />
              </v-col>
            </v-row>
            <v-row no-gutters>
              <v-col>Filename:</v-col>
              <v-col>
                <input type="file" @change="selectRawCmdFile($event)" />
              </v-col>
            </v-row>
            <v-row>
              <v-spacer />
              <v-btn
                @click="cancelRawCmd"
                variant="outlined"
                data-test="raw-cancel"
              >
                Cancel
              </v-btn>
              <v-btn @click="sendRawCmd" class="bg-primary" data-test="raw-ok">
                Ok
              </v-btn>
            </v-row>
          </div>
        </v-card-text>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/mode-ruby'
import 'ace-builds/src-min-noconflict/theme-twilight'
import Api from '@openc3/tool-common/src/services/api'
import TargetPacketItemChooser from '@openc3/tool-common/src/components/TargetPacketItemChooser'
import CommandParameterEditor from '@/tools/CommandSender/CommandParameterEditor'
import Utilities from '@/tools/CommandSender/utilities'
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'
import DetailsDialog from '@openc3/tool-common/src/components/DetailsDialog'
import TopBar from '@openc3/tool-common/src/components/TopBar'
import Openc3Screen from '@openc3/tool-common/src/components/Openc3Screen'
import 'sprintf-js'

export default {
  mixins: [Utilities],
  components: {
    DetailsDialog,
    TargetPacketItemChooser,
    CommandParameterEditor,
    TopBar,
    Openc3Screen,
  },
  data() {
    return {
      title: 'Command Sender',
      search: '',
      headers: [
        { title: 'Name', value: 'parameter_name' },
        { title: 'Value or State', value: 'val' },
        { title: 'Units', value: 'units' },
        { title: 'Range', value: 'range' },
        { title: 'Description', value: 'description' },
      ],
      editor: null,
      targetName: '',
      commandName: '',
      paramList: '',
      lastTargetName: '',
      lastCommandName: '',
      lastParamList: '',
      ignoreRangeChecks: false,
      statesInHex: false,
      showIgnoredParams: false,
      cmdRaw: false,
      ignoredParams: [],
      rows: [],
      interfaces: [],
      selectedInterface: '',
      rawCmdFile: null,
      status: '',
      history: '',
      hazardousCommand: '',
      displaySendHazardous: false,
      displayErrorDialog: false,
      displaySendRaw: false,
      sendDisabled: false,
      api: null,
      viewDetails: false,
      contextMenuShown: false,
      parameterName: '',
      reservedItemNames: [],
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
      keywords: [],
      screenTarget: null,
      screenName: null,
      screenDefinition: null,
      screenCount: 0,
    }
  },
  computed: {
    menus: function () {
      return [
        // TODO: Implement send raw
        // {
        //   label: 'File',
        //   items: [
        //     {
        //       label: 'Send Raw',
        //       command: () => {
        //         this.setupRawCmd()
        //       },
        //     },
        //   ],
        // },
        {
          label: 'Mode',
          items: [
            {
              label: 'Ignore Range Checks',
              checkbox: true,
              checked: this.ignoreRangeChecks,
              command: () => {
                this.ignoreRangeChecks = !this.ignoreRangeChecks
              },
            },
            {
              label: 'Display State Values in Hex',
              checkbox: true,
              checked: this.statesInHex,
              command: () => {
                this.statesInHex = !this.statesInHex
              },
            },
            {
              label: 'Show Ignored Parameters',
              checkbox: true,
              checked: this.showIgnoredParams,
              command: () => {
                this.showIgnoredParams = !this.showIgnoredParams
                // TODO: Maybe we don't need to do this if the data-table
                // can render the whole thing and we just display with v-if
                this.updateCmdParams()
              },
            },
            {
              label: 'Disable Parameter Conversions',
              checkbox: true,
              checked: this.cmdRaw,
              command: () => {
                this.cmdRaw = !this.cmdRaw.checked
              },
            },
          ],
        },
      ]
    },
  },
  created() {
    Api.get(`/openc3-api/autocomplete/reserved-item-names`).then((response) => {
      this.reservedItemNames = response.data
    })
    this.api = new OpenC3Api()
    // If we're passed in the route then manually call commandChanged to update
    if (this.$route.params.target && this.$route.params.packet) {
      this.commandChanged({
        targetName: this.$route.params.target.toUpperCase(),
        packetName: this.$route.params.packet.toUpperCase(),
      })
    }
    Api.get('/openc3-api/autocomplete/keywords/screen').then((response) => {
      this.keywords = response.data
    })
  },
  mounted() {
    this.editor = ace.edit(this.$refs.editor)
    this.editor.setTheme('ace/theme/twilight')
    this.editor.session.setMode('ace/mode/ruby')
    this.editor.session.setTabSize(2)
    this.editor.session.setUseWrapMode(true)
    this.editor.setHighlightActiveLine(false)
    this.editor.setValue(localStorage['command_sender__history'])
    this.history = this.editor.getValue().trim()
    this.editor.clearSelection()
    this.editor.focus()
    this.editor.setAutoScrollEditorIntoView(true)
    // This only limits the displayed lines, history can grow in a scrollable window
    this.editor.setOption('maxLines', 30)
    this.editor.setOption('minLines', 1)
    this.editor.container.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault()
        let command = this.editor.session.getLine(
          this.editor.getCursorPosition().row,
        )
        // Blank commands can happen if typing return on a blank line
        if (command === '') {
          return
        }
        // Remove the cmd("") wrapper
        let firstQuote = command.indexOf('"')
        let lastQuote = command.lastIndexOf('"')
        command = command.substr(firstQuote + 1, lastQuote - firstQuote - 1)
        this.sendCmd(command)
      }
    })
  },
  beforeUnmount() {
    this.editor.destroy()
    this.editor.container.remove()
  },
  methods: {
    showContextMenu(e, row) {
      e.preventDefault()
      this.parameterName = row.item.parameter_name
      this.contextMenuShown = false
      this.x = e.clientX
      this.y = e.clientY
      this.$nextTick(() => {
        this.contextMenuShown = true
      })
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

      var str = param.val
      var quotesRemoved = this.removeQuotes(str)
      if (str === quotesRemoved) {
        var upcaseStr = str.toUpperCase()
        if (
          (param.type === 'STRING' || param.type === 'BLOCK') &&
          upcaseStr.startsWith('0X')
        ) {
          var hexStr = upcaseStr.slice(2)
          if (hexStr.length % 2 !== 0) {
            hexStr = '0' + hexStr
          }
          var jstr = { json_class: 'String', raw: [] }
          for (var i = 0; i < hexStr.length; i += 2) {
            var nibble = hexStr.charAt(i) + hexStr.charAt(i + 1)
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
            return parseInt(str)
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

    commandChanged(event) {
      if (
        this.targetName !== event.targetName ||
        this.commandName !== event.packetName
      ) {
        this.targetName = event.targetName
        this.commandName = event.packetName
        // Only updateCmdParams if we're not already in the middle of an update
        if (this.sendDisabled === false) {
          this.updateCmdParams()
        }
        this.$router
          .replace({
            name: 'CommandSender',
            params: {
              target: this.targetName,
              packet: this.commandName,
            },
          })
          // catch the error in case we route to where we already are
          .catch((err) => {})
      }
    },

    updateCmdParams() {
      this.sendDisabled = true
      this.ignoredParams = []
      this.rows = []
      this.api
        .get_target(this.targetName)
        .then(
          (target) => {
            this.ignoredParams = target.ignored_parameters
            return this.api.get_cmd(this.targetName, this.commandName)
          },
          (error) => {
            this.displayError('getting ignored parameters', error)
            this.sendDisabled = false
          },
        )
        .then(
          (command) => {
            command.items.forEach((parameter) => {
              if (this.reservedItemNames.includes(parameter.name)) return
              if (
                !this.ignoredParams.includes(parameter.name) ||
                this.showIgnoredParams
              ) {
                let val = parameter.default
                // If the parameter is a string and the default is a string
                // (rather than object for binary) then we quote the string
                // However we don't do this is the parameter has states
                // because that messes up the state selection logic
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
                // check using != because compare with null
                if (parameter.minimum != null && parameter.maximum != null) {
                  if (parameter.data_type === 'FLOAT') {
                    // This is basically to handle the FLOAT MIN and MAX so they
                    // don't print out the huge exponential
                    if (parameter.minimum < -1e6) {
                      parameter.minimum = parameter.minimum.toExponential(3)
                    }
                    if (parameter.maximum > 1e6) {
                      parameter.maximum = parameter.maximum.toExponential(3)
                    }
                  }
                  range = `${parameter.minimum}..${parameter.maximum}`
                }
                this.rows.push({
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
            if (command.screen) {
              this.loadScreen(command.screen[0], command.screen[1]).then(
                (response) => {
                  this.screenTarget = command.screen[0]
                  this.screenName = command.screen[1]
                  this.screenDefinition = response.data
                  this.screenCount += 1
                },
              )
            } else {
              if (command.related_items) {
                this.screenTarget = 'LOCAL'
                this.screenName = 'CMDSENDER'
                let screenDefinition = 'SCREEN AUTO AUTO 1.0\n'
                for (var i = 0; i < command.related_items.length; i++) {
                  screenDefinition += `LABELVALUE '${command.related_items[i][0]}' '${command.related_items[i][1]}' '${command.related_items[i][2]}' WITH_UNITS 20\n`
                }
                this.screenDefinition = screenDefinition
              } else {
                this.screenTarget = null
                this.screenName = null
                this.screenDefinition = null
              }
              this.screenCount += 1
            }
            this.sendDisabled = false
            this.status = ''
          },
          (error) => {
            this.displayError('getting command parameters', error)
            this.sendDisabled = false
          },
        )
    },

    createParamList() {
      let paramList = {}
      for (var i = 0; i < this.rows.length; i++) {
        paramList[this.rows[i].parameter_name] = this.convertToValue(
          this.rows[i],
        )
      }
      return paramList
    },

    buildCmd() {
      this.sendCmd(this.targetName, this.commandName, this.createParamList())
    },

    // Note targetName can also be the entire command to send, e.g. "INST ABORT" or
    // "INST COLLECT with TYPE 0, DURATION 1, OPCODE 171, TEMP 10" when being
    // sent from the history. In that case commandName and paramList are undefined
    // and the api calls handle that.
    sendCmd(targetName, commandName, paramList) {
      // Store what was actually sent for use in resending hazardous commands
      this.lastTargetName = targetName
      this.lastCommandName = commandName
      this.lastParamList = paramList

      this.sendDisabled = true
      let hazardous = false
      let cmd = ''
      this.api.get_cmd_hazardous(targetName, commandName, paramList).then(
        (response) => {
          hazardous = response

          if (hazardous) {
            // If it was sent from history it's all in targetName
            if (commandName === undefined) {
              this.hazardousCommand = targetName
                .split(' ')
                .slice(0, 2)
                .join(' ')
            } else {
              this.hazardousCommand = `${targetName} ${commandName}`
            }
            this.displaySendHazardous = true
          } else {
            let obs
            if (this.cmdRaw) {
              if (this.ignoreRangeChecks) {
                cmd = 'cmd_raw_no_range_check'
                obs = this.api.cmd_raw_no_range_check(
                  targetName,
                  commandName,
                  paramList,
                )
              } else {
                cmd = 'cmd_raw'
                obs = this.api.cmd_raw(targetName, commandName, paramList, {
                  // This request could be denied due to out of range but since
                  // we're explicitly handling it we don't want the interceptor to fire
                  'Ignore-Errors': '500',
                })
              }
            } else {
              if (this.ignoreRangeChecks) {
                cmd = 'cmd_no_range_check'
                obs = this.api.cmd_no_range_check(
                  targetName,
                  commandName,
                  paramList,
                )
              } else {
                cmd = 'cmd'
                obs = this.api.cmd(targetName, commandName, paramList, {
                  // This request could be denied due to out of range but since
                  // we're explicitly handling it we don't want the interceptor to fire
                  'Ignore-Errors': '500',
                })
              }
            }

            obs.then(
              (response) => {
                this.processCmdResponse(
                  true,
                  targetName,
                  commandName,
                  cmd,
                  response,
                )
              },
              (error) => {
                this.processCmdResponse(
                  false,
                  targetName,
                  commandName,
                  cmd,
                  error,
                )
              },
            )
          }
        },
        (error) => {
          this.processCmdResponse(false, targetName, commandName, cmd, error)
        },
      )
    },

    sendHazardousCmd() {
      this.displaySendHazardous = false
      let obs = ''
      let cmd = ''
      if (this.cmdRaw) {
        if (this.ignoreRangeChecks) {
          cmd = 'cmd_raw_no_range_check'
          obs = this.api.cmd_raw_no_checks(
            this.lastTargetName,
            this.lastCommandName,
            this.lastParamList,
          )
        } else {
          cmd = 'cmd_raw'
          obs = this.api.cmd_raw_no_hazardous_check(
            this.lastTargetName,
            this.lastCommandName,
            this.lastParamList,
            {
              // This request could be denied due to out of range but since
              // we're explicitly handling it we don't want the interceptor to fire
              'Ignore-Errors': '500',
            },
          )
        }
      } else {
        if (this.ignoreRangeChecks) {
          cmd = 'cmd_no_range_check'
          obs = this.api.cmd_no_checks(
            this.lastTargetName,
            this.lastCommandName,
            this.lastParamList,
          )
        } else {
          cmd = 'cmd'
          obs = this.api.cmd_no_hazardous_check(
            this.lastTargetName,
            this.lastCommandName,
            this.lastParamList,
            {
              // This request could be denied due to out of range but since
              // we're explicitly handling it we don't want the interceptor to fire
              'Ignore-Errors': '500',
            },
          )
        }
      }

      obs.then(
        (response) => {
          this.processCmdResponse(
            true,
            this.lastTargetName,
            this.lastCommandName,
            cmd,
            response,
          )
        },
        (error) => {
          this.processCmdResponse(
            false,
            this.lastTargetName,
            this.lastCommandName,
            cmd,
            error,
          )
        },
      )
    },

    cancelHazardousCmd() {
      this.displaySendHazardous = false
      this.status = 'Hazardous command not sent'
      this.sendDisabled = false
    },

    processCmdResponse(success, targetName, commandName, cmd_sent, response) {
      // If it was sent from history it's all in targetName, see sendCmd for details
      if (commandName === undefined) {
        ;[targetName, commandName] = targetName.split(' ').slice(0, 2)
      }
      var msg = ''
      if (success) {
        msg = `${cmd_sent}("${response[0]} ${response[1]}`
        var keys = Object.keys(response[2])
        if (keys.length > 0) {
          msg += ' with '
          for (var i = 0; i < keys.length; i++) {
            var key = keys[i]
            var value = this.convertToString(response[2][key])
            // If the response has unquoted string data we add quotes
            if (
              typeof response[2][key] === 'string' &&
              value.charAt(0) !== "'" &&
              value.charAt(0) !== '"'
            ) {
              value = `'${value}'`
            }
            msg += key + ' ' + value
            if (i < keys.length - 1) {
              msg += ', '
            }
          }
        }
        msg += '")'
        if (!this.history.includes(msg)) {
          value = msg
          if (this.history.length !== 0) {
            value += `\n${this.history}`
          }
          this.editor.setValue(value)
          this.editor.moveCursorTo(0, 0)
        }
        msg += ' sent.'
        // Add the number of commands sent to the status message
        if (this.status.includes(msg)) {
          let parts = this.status.split('sent.')
          if (parts[1].includes('(')) {
            let num = parseInt(parts[1].substr(2, parts[1].indexOf(')') - 2))
            msg = parts[0] + 'sent. (' + (num + 1) + ')'
          } else {
            msg += ' (2)'
          }
        }
        this.status = msg
      } else {
        var context = 'sending ' + targetName + ' ' + commandName
        this.displayError(context, response, true)
      }
      // Make a copy of the history
      this.history = this.editor.getValue()
      localStorage['command_sender__history'] = this.editor.getValue()
      this.sendDisabled = false
    },

    clearHistory() {
      this.editor.setValue('')
      this.history = ''
      localStorage.removeItem('command_sender__history')
    },

    displayError(context, error, showDialog = false) {
      this.status = `Error ${context} due to ${error.name}`
      if (error.message && error.message !== '') {
        this.status += ': '
        this.status += error.message
      }
      if (showDialog) {
        this.displayErrorDialog = true
      }
    },

    loadScreen(target, screen) {
      return Api.get('/openc3-api/screen/' + target + '/' + screen, {
        headers: {
          Accept: 'text/plain',
        },
      })
    },

    // setupRawCmd() {
    //   this.api.get_interface_names().then(
    //     (response) => {
    //       var interfaces = []
    //       for (var i = 0; i < response.length; i++) {
    //         interfaces.push({ label: response[i], value: response[i] })
    //       }
    //       this.interfaces = interfaces
    //       this.selectedInterface = interfaces[0].value
    //       this.displaySendRaw = true
    //     },
    //     (error) => {
    //       this.displaySendRaw = false
    //       this.displayError('getting interface names', error, true)
    //     }
    //   )
    // },

    // selectRawCmdFile(event) {
    //   this.rawCmdFile = event.target.files[0]
    // },

    // onLoad(event) {
    //   var bufView = new Uint8Array(event.target.result)
    //   var jstr = { json_class: 'String', raw: [] }
    //   for (var i = 0; i < bufView.length; i++) {
    //     jstr.raw.push(bufView[i])
    //   }

    //   this.api.send_raw(this.selectedInterface, jstr).then(
    //     () => {
    //       this.displaySendRaw = false
    //       this.status =
    //         'Sent ' +
    //         bufView.length +
    //         ' bytes to interface ' +
    //         this.selectedInterface
    //     },
    //     (error) => {
    //       this.displaySendRaw = false
    //       this.displayError('sending raw data', error, true)
    //     }
    //   )
    // },

    // sendRawCmd() {
    //   var self = this
    //   var reader = new FileReader()
    //   reader.onload = function (e) {
    //     self.onLoad(e)
    //   }
    //   reader.onerror = function (e) {
    //     self.displaySendRaw = false
    //     var target = e.target
    //     self.displayError('sending raw data', target.error, true)
    //   }
    //   // TBD - use the other event handlers to implement a progress bar for the
    //   // file upload.  Handle abort as well?
    //   //reader.onloadstart = function(e) {}
    //   //reader.onprogress = function(e) {}
    //   //reader.onloadend = function(e) {}
    //   //reader.onabort = function(e) {}

    //   reader.readAsArrayBuffer(this.rawCmdFile)
    // },

    // cancelRawCmd() {
    //   this.displaySendRaw = false
    //   this.status = 'Raw command not sent'
    // },
  },
}
</script>
<style scoped>
.editor {
  margin-left: 30px;
  height: 50px;
  width: 95%;
  position: relative;
  font-size: 16px;
}

.v-system-bar {
  top: 0 !important;
}
</style>
