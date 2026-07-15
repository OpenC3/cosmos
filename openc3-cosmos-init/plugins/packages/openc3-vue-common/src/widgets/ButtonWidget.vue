<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-btn
      class="ma-1"
      color="primary"
      :style="computedStyle"
      :loading="running"
      @click="onClick"
    >
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
              <v-btn variant="outlined" @click="cancelHazardousCmd">
                Cancel
              </v-btn>
              <v-btn class="bg-primary mx-1" @click="sendHazardousCmd">
                Send
              </v-btn>
            </v-row>
          </div>
        </v-card-text>
      </v-card>
    </v-dialog>
    <critical-cmd-dialog
      v-model="displayCriticalCmd"
      :uuid="criticalCmdUuid"
      :cmd-string="criticalCmdString"
      :cmd-user="criticalCmdUser"
    />
  </div>
</template>

<script>
import { Api, OpenC3Api } from '@openc3/js-common/services'
import { CriticalCmdDialog } from '@/components'
import { runButtonScript } from '@/util'
import Widget from './Widget'

export default {
  components: {
    CriticalCmdDialog,
  },
  mixins: [Widget],
  data() {
    return {
      api: null,
      running: false,
      displaySendHazardous: false,
      hazardousResolve: null,
      criticalCmdUuid: null,
      criticalCmdString: null,
      criticalCmdUser: null,
      displayCriticalCmd: false,
      abortController: null,
    }
  },
  computed: {
    buttonText() {
      return this.parameters[0]
    },
  },
  created() {
    this.api = new OpenC3Api()
  },
  beforeUnmount() {
    // Tear down any in-flight sandbox run if the screen closes mid-execution
    this.abortController?.abort()
  },
  methods: {
    // The button's action (parameters[1]) is author-supplied JavaScript. It is
    // NOT eval'd here in the main window (that was a stored, cross-user XSS -
    // author JS could read localStorage.openc3Token). Instead it runs in an
    // opaque-origin sandbox iframe with no token/DOM/network access, and calls
    // back to these token-bearing objects over a postMessage bridge.
    async onClick() {
      if (this.running) return
      this.running = true
      this.abortController = new AbortController()
      try {
        await runButtonScript({
          code: this.parameters[1],
          api: this.api,
          screen: this.screen,
          runScript: this.runScript,
          setNamedWidgetValue: (name, value) =>
            this.setNamedWidgetValue(name, value),
          snapshot: this.namedWidgetsSnapshot(),
          screenValues: this.screenValues,
          screenTimeZone: this.screenTimeZone,
          onHazardous: this.onHazardous,
          onCritical: this.onCritical,
          signal: this.abortController.signal,
        })
      } catch (error) {
        if (error?.name !== 'AbortError') {
          // eslint-disable-next-line no-console
          console.error(error)
        }
      } finally {
        this.running = false
        this.abortController = null
        this.displaySendHazardous = false
        this.hazardousResolve = null
      }
    },
    // Called by the bridge when a command throws a hazardous error. Shows the
    // confirmation dialog and resolves true (Send) or false (Cancel).
    onHazardous() {
      return new Promise((resolve) => {
        this.hazardousResolve = resolve
        this.displaySendHazardous = true
      })
    },
    // Called by the bridge when a command throws a CriticalCmdError.
    onCritical(error) {
      this.criticalCmdUuid = error.object.data.instance_variables['@uuid']
      this.criticalCmdString =
        error.object.data.instance_variables['@cmd_string']
      this.criticalCmdUser = error.object.data.instance_variables['@username']
      this.displayCriticalCmd = true
    },
    sendHazardousCmd() {
      this.displaySendHazardous = false
      const resolve = this.hazardousResolve
      this.hazardousResolve = null
      resolve?.(true)
    },
    cancelHazardousCmd() {
      this.displaySendHazardous = false
      const resolve = this.hazardousResolve
      this.hazardousResolve = null
      resolve?.(false)
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
