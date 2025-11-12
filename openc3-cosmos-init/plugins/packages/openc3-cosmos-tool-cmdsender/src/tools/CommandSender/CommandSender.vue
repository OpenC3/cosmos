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
    <top-bar :menus="menus" :title="title" />
    <command-editor
      ref="commandEditor"
      :initial-target-name="$route.params.target"
      :initial-packet-name="$route.params.packet"
      :send-disabled="sendDisabled"
      :states-in-hex="statesInHex"
      :show-ignored-params="showIgnoredParams"
      :cmd-raw="cmdRaw"
      @command-changed="commandChanged($event)"
      @build-cmd="buildCmd($event)"
    />
    <v-card class="pa-3">Status: {{ status }}</v-card>
    <div style="height: 15px" />
    <v-row no-gutters>
      <v-col class="pr-4">
        <v-card class="pb-2">
          <v-card-subtitle>
            <v-row>
              <v-col class="pt-6">
                Editable Command History: (Pressing Enter on the line
                re-executes the command)
              </v-col>
              <v-col>
                <v-tooltip :open-delay="600" location="top">
                  <template #activator="{ props }">
                    <div v-bind="props" class="float-right">
                      <v-btn
                        icon="mdi-delete-sweep"
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
          <v-row no-gutters class="mt-2 mb-2">
            <v-col>
              <pre ref="editor" class="editor" data-test="sender-history"></pre>
            </v-col>
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
          :show-close="false"
        />
      </v-col>
    </v-row>
    <div style="height: 15px" />

    <critical-cmd-dialog
      v-model="displayCriticalCmd"
      :uuid="criticalCmdUuid"
      :cmd-string="criticalCmdString"
      :cmd-user="criticalCmdUser"
    />

    <!-- This dialog is informational, should not be persistent -->
    <v-dialog v-model="displayErrorDialog" max-width="600">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span> Error </span>
          <v-spacer />
        </v-toolbar>
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
                color="primary"
                data-test="error-dialog-ok"
                @click="displayErrorDialog = false"
              >
                Ok
              </v-btn>
            </v-row>
          </div>
        </v-card-text>
      </v-card>
    </v-dialog>

    <v-dialog
      v-model="displaySendHazardous"
      max-width="600"
      persistent
      @keydown.esc="cancelHazardousCmd"
    >
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span> Hazardous Warning </span>
          <v-spacer />
        </v-toolbar>
        <v-card-text class="mt-6">
          Warning: Command {{ hazardousCommand }} is Hazardous. Send?
          <br />
          <span class="openc3-yellow">
            Description: {{ commandDescription }}
          </span>
        </v-card-text>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn variant="outlined" @click="cancelHazardousCmd"> Cancel </v-btn>
          <v-btn variant="flat" @click="sendHazardousCmd"> Send </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog
      v-model="displaySendRaw"
      max-width="600"
      persistent
      @keydown.esc="cancelRawCmd"
    >
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span> Send Raw </span>
          <v-spacer />
        </v-toolbar>
        <v-card-text>
          <div class="mx-1">
            <v-row class="my-2">
              <v-col>Interface:</v-col>
              <v-col>
                <v-select
                  v-model="selectedInterface"
                  variant="solo"
                  hide-details
                  density="compact"
                  :items="interfaces"
                  item-title="label"
                  item-value="value"
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
                variant="outlined"
                data-test="raw-cancel"
                @click="cancelRawCmd"
              >
                Cancel
              </v-btn>
              <v-btn class="bg-primary" data-test="raw-ok" @click="sendRawCmd">
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
import { Api, OpenC3Api } from '@openc3/js-common/services'
import {
  CriticalCmdDialog,
  CommandEditor,
  AceEditorUtils,
  Openc3Screen,
  TopBar,
} from '@openc3/vue-common/components'
import { CmdUtilities } from '@openc3/vue-common/util'

export default {
  components: {
    CriticalCmdDialog,
    CommandEditor,
    TopBar,
    Openc3Screen,
  },
  mixins: [CmdUtilities],
  data() {
    return {
      title: 'Command Sender',
      editor: null,
      targetName: '',
      commandName: '',
      commandDescription: '',
      paramList: '',
      queueName: null,
      validateParameter: null,
      lastTargetName: '',
      lastCommandName: '',
      lastParamList: '',
      lastQueueName: null,
      ignoreRangeChecks: false,
      statesInHex: false,
      showIgnoredParams: false,
      cmdRaw: false,
      disableCommandValidation: false,
      interfaces: [],
      selectedInterface: '',
      rawCmdFile: null,
      status: '',
      history: '',
      hazardousCommand: '',
      displaySendHazardous: false,
      displayErrorDialog: false,
      displaySendRaw: false,
      displayCriticalCmd: false,
      criticalCmdUuid: null,
      criticalCmdString: null,
      criticalCmdUser: null,
      sendDisabled: false,
      api: null,
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
                this.$refs.commandEditor.triggerUpdateCmdParams()
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
            {
              label: 'Disable Command Validation',
              checkbox: true,
              checked: this.disableCommandValidation,
              command: () => {
                this.disableCommandValidation = !this.disableCommandValidation
              },
            },
          ],
        },
      ]
    },
  },
  created() {
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
        // Parse queue parameter if present (e.g., cmd("...", queue: "Foo") or cmd("...", queue = "Foo")
        // or cmd("...", queue: false) or cmd("...", queue=False)
        // Reset queue to null first
        this.queueName = null
        const queueMatch = command.match(
          /,\s*queue(?::|\s*=)\s*(?:"([^"]+)"|([f|F]alse))/,
        )
        if (queueMatch) {
          this.queueName = queueMatch[1]
          // Remove the queue parameter from the command string
          command = command.replace(
            /,\s*queue(?::|\s*=)\s*(?:"([^"]+)"|([f|F]alse))/,
            '',
          )
        }
        // Parse validate parameter if present (e.g., cmd("...", validate: false) or cmd("...", validate=True)
        this.validateParameter = null
        const validateMatch = command.match(
          /,\s*validate(?::|\s*=)\s*(false|true)/i,
        )
        if (validateMatch) {
          this.validateParameter = validateMatch[1]
          // Remove the validate parameter from the command string
          command = command.replace(
            /,\s*validate(?::|\s*=)\s*(false|true)/i,
            '',
          )
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
    commandChanged(event) {
      if (
        this.targetName !== event.targetName ||
        this.commandName !== event.packetName
      ) {
        this.targetName = event.targetName
        this.commandName = event.packetName
        this.updateScreenInfo()
        if (this.targetName && this.commandName) {
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
        } else {
          // Handle targets with any commands
          this.$router
            .replace({
              name: 'CommandSender',
            })
            // catch the error in case we route to where we already are
            .catch((err) => {})
        }
      }
      // Update queue selection if it changed
      if (event.queueName !== undefined) {
        this.queueName = event.queueName
      }
    },

    updateScreenInfo() {
      if (this.targetName && this.commandName) {
        this.api.get_cmd(this.targetName, this.commandName).then(
          (command) => {
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
                for (const item of command.related_items) {
                  screenDefinition += `LABELVALUE '${item[0]}' '${item[1]}' '${item[2]}' WITH_UNITS 20\n`
                }
                this.screenDefinition = screenDefinition
              } else {
                this.screenTarget = null
                this.screenName = null
                this.screenDefinition = null
              }
              this.screenCount += 1
            }
          },
          (error) => {
            this.displayError('getting command for screen info', error)
          },
        )
      } else {
        this.screenTarget = null
        this.screenName = null
        this.screenDefinition = null
        this.screenCount += 1
      }
    },

    createParamList() {
      let paramList = {}
      for (const row of this.$refs.commandEditor.getRows()) {
        paramList[row.parameter_name] = this.convertToValue(row)
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
      this.lastQueueName = this.queueName

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
            let kwparams = {}
            if (this.validateParameter !== null) {
              kwparams.validate =
                this.validateParameter.toLowerCase() === 'true'
            } else if (this.disableCommandValidation) {
              kwparams.validate = false
            }
            // Add queue parameter if a queue is selected
            if (this.queueName) {
              kwparams.queue = this.queueName
            }
            if (this.cmdRaw) {
              if (this.ignoreRangeChecks) {
                cmd = 'cmd_raw_no_range_check'
                obs = this.api.cmd_raw_no_range_check(
                  targetName,
                  commandName,
                  paramList,
                  {
                    'Ignore-Errors': '428',
                  },
                  kwparams,
                )
              } else {
                cmd = 'cmd_raw'
                obs = this.api.cmd_raw(
                  targetName,
                  commandName,
                  paramList,
                  {
                    // This request could be denied due to out of range but since
                    // we're explicitly handling it we don't want the interceptor to fire
                    'Ignore-Errors': '428 500',
                  },
                  kwparams,
                )
              }
            } else {
              if (this.ignoreRangeChecks) {
                cmd = 'cmd_no_range_check'
                obs = this.api.cmd_no_range_check(
                  targetName,
                  commandName,
                  paramList,
                  {
                    'Ignore-Errors': '428',
                  },
                  kwparams,
                )
              } else {
                cmd = 'cmd'
                obs = this.api.cmd(
                  targetName,
                  commandName,
                  paramList,
                  {
                    // This request could be denied due to out of range but since
                    // we're explicitly handling it we don't want the interceptor to fire
                    'Ignore-Errors': '428 500',
                  },
                  kwparams,
                )
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
      let kwparams = {}
      if (this.validateParameter !== null) {
        kwparams.validate = this.validateParameter.toLowerCase() === 'true'
      } else if (this.disableCommandValidation) {
        kwparams.validate = false
      }
      // Add queue parameter if a queue is selected
      if (this.lastQueueName) {
        kwparams.queue = this.lastQueueName
      }
      if (this.cmdRaw) {
        if (this.ignoreRangeChecks) {
          cmd = 'cmd_raw_no_range_check'
          obs = this.api.cmd_raw_no_checks(
            this.lastTargetName,
            this.lastCommandName,
            this.lastParamList,
            {
              'Ignore-Errors': '428',
            },
            kwparams,
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
              'Ignore-Errors': '428 500',
            },
            kwparams,
          )
        }
      } else {
        if (this.ignoreRangeChecks) {
          cmd = 'cmd_no_range_check'
          obs = this.api.cmd_no_checks(
            this.lastTargetName,
            this.lastCommandName,
            this.lastParamList,
            {
              'Ignore-Errors': '428',
            },
            kwparams,
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
              'Ignore-Errors': '428 500',
            },
            kwparams,
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
      let msg = ''
      if (success) {
        msg = `${cmd_sent}("${response['target_name']} ${response['cmd_name']}`
        let keys = Object.keys(response['cmd_params'])
        if (keys.length > 0) {
          msg += ' with '
          for (let i = 0; i < keys.length; i++) {
            let key = keys[i]
            let value = ''
            if (response['obfuscated_items'].includes(key)) {
              value = '*****'
            } else {
              value = this.convertToString(response['cmd_params'][key])
            }
            // If the response has unquoted string data we add quotes
            if (
              typeof response['cmd_params'][key] === 'string' &&
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
        // Build the closing part with optional parameters
        let closingParams = []
        if (this.lastQueueName) {
          const language = AceEditorUtils.getDefaultScriptingLanguage()
          if (language === 'python') {
            closingParams.push(`queue="${this.lastQueueName}"`)
          } else {
            closingParams.push(`queue: "${this.lastQueueName}"`)
          }
        }
        if (this.disableCommandValidation || this.validateParameter !== null) {
          const language = AceEditorUtils.getDefaultScriptingLanguage()
          if (this.validateParameter !== null) {
            if (language === 'python') {
              closingParams.push(`validate=${this.validateParameter}`)
            } else {
              closingParams.push(`validate: ${this.validateParameter}`)
            }
          } else {
            if (language === 'python') {
              closingParams.push('validate=False')
            } else {
              closingParams.push('validate: false')
            }
          }
        }

        if (closingParams.length > 0) {
          msg += '", ' + closingParams.join(', ') + ')'
        } else {
          msg += '")'
        }
        if (!this.history.includes(msg)) {
          let value = msg
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
        let context = 'sending ' + targetName + ' ' + commandName
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
      if (this.status.includes('CriticalCmdError')) {
        this.status = `Critical Command Queued For Approval`
      }
      if (showDialog) {
        if (error.message.includes('CriticalCmdError')) {
          this.criticalCmdUuid = error.object.data.instance_variables['@uuid']
          this.criticalCmdString =
            error.object.data.instance_variables['@command']['cmd_string']
          this.criticalCmdUser =
            error.object.data.instance_variables['@command']['username']
          this.displayCriticalCmd = true
        } else {
          this.displayErrorDialog = true
        }
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
    //       let interfaces = []
    //       for (let i = 0; i < response.length; i++) {
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
    //   let bufView = new Uint8Array(event.target.result)
    //   let jstr = { json_class: 'String', raw: [] }
    //   for (let i = 0; i < bufView.length; i++) {
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
    //   let self = this
    //   let reader = new FileReader()
    //   reader.onload = function (e) {
    //     self.onLoad(e)
    //   }
    //   reader.onerror = function (e) {
    //     self.displaySendRaw = false
    //     let target = e.target
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

    cancelRawCmd() {
      this.displaySendRaw = false
      this.status = 'Raw command not sent'
    },
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
</style>
