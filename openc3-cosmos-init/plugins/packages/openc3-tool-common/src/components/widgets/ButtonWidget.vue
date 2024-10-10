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
    <v-btn class="ma-1" color="primary" :style="computedStyle" @click="onClick">
      {{ buttonText }}
    </v-btn>
    <v-dialog v-model="displaySendHazardous" max-width="300">
      <v-card>
        <v-card-title>Hazardous</v-card-title>
        <v-card-text>
          <div class="mx-1">
            <v-row class="my-2">
              <span> Warning: Command is Hazardous. Send? </span>
            </v-row>
            <v-row>
              <v-spacer />
              <v-btn @click="cancelHazardousCmd" outlined> Cancel </v-btn>
              <v-btn @click="sendHazardousCmd" class="primary mx-1">
                Send
              </v-btn>
            </v-row>
          </div>
        </v-card-text>
      </v-card>
    </v-dialog>
    <critical-cmd-dialog
      :uuid="criticalCmdUuid"
      :cmdString="criticalCmdString"
      :cmdUser="criticalCmdUser"
      v-model="displayCriticalCmd"
    />
  </div>
</template>

<script>
import { OpenC3Api } from '../../services/openc3-api'
import Api from '../../services/api'
import Widget from './Widget'
import CriticalCmdDialog from '@openc3/tool-common/src/components/CriticalCmdDialog'

export default {
  mixins: [Widget],
  components: {
    CriticalCmdDialog,
  },
  data() {
    return {
      api: null,
      screen: null,
      displaySendHazardous: false,
      lastCmd: '',
      criticalCmdUuid: null,
      criticalCmdString: null,
      criticalCmdUser: null,
      displayCriticalCmd: false,
    }
  },
  computed: {
    buttonText() {
      return this.parameters[0]
    },
    eval() {
      return this.parameters[1]
    },
  },
  created() {
    this.api = new OpenC3Api()
  },
  methods: {
    async onClick() {
      const lines = this.eval.split(';;')
      // Create local references to variables so users don't need to use 'this'
      const self = this // needed for $emit
      const screen = this.screen
      const api = this.api
      const run_script = this.runScript // TODO: deprecate this in favor of runScript?
      const runScript = this.runScript
      for (let i = 0; i < lines.length; i++) {
        try {
          const result = eval(lines[i].trim())
          if (result instanceof Promise) {
            await result
          }
        } catch (error) {
          // This text is in top_level.rb HazardousError.to_s
          if (error.message.includes('CriticalCmdError')) {
            this.criticalCmdUuid = error.object.data.instance_variables['@uuid']
            this.criticalCmdString =
              error.object.data.instance_variables['@cmd_string']
            this.criticalCmdUser =
              error.object.data.instance_variables['@username']
            this.displayCriticalCmd = true
          }
          if (error.message.includes('is Hazardous')) {
            this.lastCmd = error.message.split('\n').pop()
            this.displaySendHazardous = true
            while (this.displaySendHazardous) {
              await new Promise((resolve) => setTimeout(resolve, 500))
            }
          }
        }
      }
    },
    async sendHazardousCmd() {
      // TODO: This only handles basic cmd() calls in buttons, do we need to handle other? cmd_raw()?
      this.lastCmd = this.lastCmd.replace(
        'cmd(',
        'this.api.cmd_no_hazardous_check(',
      )

      try {
        const result = eval(this.lastCmd)

        if (result instanceof Promise) {
          await result
        }
      } catch (error) {
        // This text is in top_level.rb HazardousError.to_s
        if (error.message.includes('CriticalCmdError')) {
          this.criticalCmdUuid = error.object.data.instance_variables['@uuid']
          this.criticalCmdString =
            error.object.data.instance_variables['@cmd_string']
          this.criticalCmdUser =
            error.object.data.instance_variables['@username']
          this.displayCriticalCmd = true
        }
      }

      this.displaySendHazardous = false
    },
    cancelHazardousCmd() {
      this.displaySendHazardous = false
    },
    runScript(scriptName, openScript = true, env = {}) {
      let envArray = []
      for (const key in env) {
        envArray.push({ key: key, value: env[key], readonly: false })
      }
      Api.post(`/script-api/scripts/${scriptName}/run`, {
        data: { environment: envArray },
      }).then((response) => {
        if (openScript) {
          window.open(`/tools/scriptrunner/${response.data}`, '_blank')
        }
      })
    },
  },
}
</script>
