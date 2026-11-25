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
  <div class="cmd-sender d-flex flex-column ga-3">
    <top-bar :menus="menus" :title="title" />
    <!-- Hazardous commands ring the panel, as Dashboards marks a panel
         that needs attention, so nothing above the table moves -->
    <section
      :class="[
        'cs-panel cs-command rounded-lg',
        { 'ring-caution': sendHazardous },
      ]"
      aria-label="Command"
    >
      <command-editor
        ref="commandEditor"
        v-model:show-ignored-params="showIgnoredParams"
        class="cs-editor"
        :initial-target-name="$route.params.target"
        :initial-packet-name="$route.params.packet"
        :send-disabled="sendDisabled"
        :read-only="readOnlyUser"
        :states-in-hex="statesInHex"
        :cmd-raw="cmdRaw"
        :ignore-range-checks="ignoreRangeChecks"
        :show-command-button="false"
        :show-hazardous="false"
        @command-changed="commandChanged($event)"
        @command-loaded="onCommandLoaded($event)"
        @params-changed="paramsChanged"
      />
      <!-- The form's command as scripted, rebuilt as it changes. Pasting or
           editing a command there loads it into the form above. -->
      <command-line
        ref="commandLine"
        class="px-4 pt-6"
        :command="commandLine"
        :load="loadCommandLine"
        :loading="loadingCommand || (!!commandName && !commandReady)"
        @dirty="lineDirty = $event"
      />
      <!-- The only way to send: loading a command from the history or the
           command line fills in the form above but never sends it -->
      <div class="cs-send-bar d-flex align-center ga-2 px-4 pb-4 pt-2">
        <div
          class="cs-status flex-grow-1 min-w-0 text-body-2"
          aria-live="polite"
          data-test="sender-status"
        >
          {{ status }}
        </div>
        <v-chip
          v-if="sendHazardous"
          size="small"
          variant="tonal"
          prepend-icon="mdi-alert"
          class="cs-hazard openc3-yellow flex-shrink-1 font-weight-bold"
          :title="hazardTitle"
          data-test="command-hazardous"
        >
          <span class="text-truncate">{{ hazardText }}</span>
        </v-chip>
        <v-tooltip :disabled="!sendTooltip" :open-delay="600" location="top">
          <template #activator="{ props }">
            <div v-bind="props" class="flex-shrink-0">
              <v-btn
                size="large"
                :color="sendHazardous ? 'warning' : 'primary'"
                :prepend-icon="sendHazardous ? 'mdi-alert' : 'mdi-send-outline'"
                :disabled="!canSend"
                :loading="sendInFlight"
                class="cs-send"
                data-test="select-send"
                @click="buildCmd"
              >
                Send
              </v-btn>
            </div>
          </template>
          <span>{{ sendTooltip }}</span>
        </v-tooltip>
      </div>
    </section>
    <div class="cs-lower d-flex ga-3 align-start">
      <command-history
        ref="commandHistory"
        class="flex-grow-1 flex-shrink-1"
        :entries="historyEntries"
        :selected-id="selectedHistoryId"
        :time-zone="timeZone"
        @select="selectHistory"
        @clear="clearHistory"
      />
      <section
        v-if="screenDefinition"
        class="cs-panel cs-screen rounded-lg"
        aria-label="Related telemetry"
      >
        <openc3-screen
          :target="screenTarget"
          :screen="screenName"
          :definition="screenDefinition"
          :keywords="keywords"
          :count="screenCount"
          :show-close="false"
        />
      </section>
    </div>

    <help-dialog v-if="helpOpen" v-model="helpOpen" :topic="helpTopic" />

    <critical-cmd-dialog
      v-model="displayCriticalCmd"
      :uuid="criticalCmdUuid"
      :cmd-string="criticalCmdString"
      :cmd-user="criticalCmdUser"
    />

    <!-- This dialog is informational, should not be persistent -->
    <v-dialog v-model="displayErrorDialog" max-width="600">
      <v-card class="cs-dialog">
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
      <v-card class="cs-dialog">
        <v-toolbar height="24">
          <v-spacer />
          <span> Hazardous Warning </span>
          <v-spacer />
        </v-toolbar>
        <v-card-text class="mt-6">
          Warning: {{ hazardousMessage }}. Send?
          <div v-if="hazardousDialogDescription" class="mt-1">
            Description: {{ hazardousDialogDescription }}
          </div>
          <div
            v-if="hazardousDialogHazardousDescription"
            class="openc3-yellow font-weight-bold mt-2"
            data-test="hazardous-description"
          >
            <v-icon class="mr-1">mdi-alert</v-icon>
            Hazardous: {{ hazardousDialogHazardousDescription }}
          </div>
        </v-card-text>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn variant="outlined" @click="cancelHazardousCmd"> Cancel </v-btn>
          <v-btn variant="flat" @click="sendHazardousCmd"> Send </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import '@fontsource/ibm-plex-sans/400.css'
import '@fontsource/ibm-plex-sans/500.css'
import '@fontsource/ibm-plex-sans/600.css'
import '@fontsource/ibm-plex-mono/400.css'
import '@fontsource/ibm-plex-mono/500.css'
import { Api, OpenC3Api } from '@openc3/js-common/services'
import {
  CriticalCmdDialog,
  CommandEditor,
  AceEditorUtils,
  Openc3Screen,
  TopBar,
} from '@openc3/vue-common/components'
import {
  CmdUtilities,
  getCachedSetting,
  parseCmdLine,
} from '@openc3/vue-common/util'
import CommandHistory from './CommandHistory.vue'
import CommandLine from './CommandLine.vue'
import HelpDialog from './HelpDialog.vue'
import { useCommandHistory } from './useCommandHistory'
import { formatCmd, formatFormCmd } from './commandLine'

export default {
  components: {
    CommandHistory,
    CommandLine,
    CriticalCmdDialog,
    CommandEditor,
    Openc3Screen,
    HelpDialog,
    TopBar,
  },
  mixins: [CmdUtilities],
  setup() {
    const history = useCommandHistory()
    return {
      historyEntries: history.entries,
      addHistory: history.add,
      clearHistoryEntries: history.clear,
    }
  },
  data() {
    return {
      title: 'Command Sender',
      targetName: '',
      commandName: '',
      commandDescription: '',
      hazardousDescription: '',
      queueName: null,
      // The selected command's parameters are loaded, so Send can build it
      commandReady: false,
      // A command from the history or the command line is being loaded
      loadingCommand: false,
      // The latest load, so a load it replaced doesn't clear its state
      loadPromise: null,
      // The selected command's definition is HAZARDOUS
      commandHazardous: false,
      // Target and command whose screen is shown, so reloading the same
      // command (e.g. from the history) doesn't rebuild it
      screenCommand: null,
      // The command waiting on the hazardous confirmation
      pendingCmd: null,
      ignoreRangeChecks: false,
      statesInHex: false,
      showIgnoredParams: false,
      cmdRaw: false,
      disableCommandValidation: false,
      status: '',
      timeZone: 'local',
      selectedHistoryId: null,
      // The form's command as scripted, for the command line
      commandLine: '',
      // The command line has edits that aren't loaded into the form
      lineDirty: false,
      // Help menu dialogs: 'shortcuts' or 'guide'
      helpOpen: false,
      helpTopic: 'shortcuts',
      // The server's answer to whether the form's command is hazardous,
      // null while checking or unknown. Colors the Send button.
      hazardPreview: null,
      hazardTimer: null,
      hazardRequest: 0,
      hazardousCommand: '',
      commandIsHazardous: false,
      hazardousDialogDescription: '',
      hazardousDialogHazardousDescription: '',
      displaySendHazardous: false,
      displayErrorDialog: false,
      displayCriticalCmd: false,
      criticalCmdUuid: null,
      criticalCmdString: null,
      criticalCmdUser: null,
      // uuid => interval watching a critical command waiting for approval
      criticalCmdWatchers: {},
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
    // Modes that make every command hazardous, e.g. 'range checks are ignored'
    hazardousModes() {
      const modes = []
      if (this.ignoreRangeChecks) {
        modes.push('range checks are ignored')
      }
      if (this.cmdRaw) {
        modes.push('parameter conversions are disabled')
      }
      return modes.join(' and ')
    },
    hazardousMessage() {
      const command = `Command ${this.hazardousCommand}`
      if (!this.hazardousModes) {
        return `${command} is Hazardous`
      } else if (this.commandIsHazardous) {
        return `${command} is Hazardous and ${this.hazardousModes}`
      } else {
        return `${command} is considered Hazardous because ${this.hazardousModes}`
      }
    },
    // The command or its values are hazardous, from the server's answer for
    // the current values or, until it answers, the definition
    commandIsHazardousNow() {
      return this.hazardPreview ?? this.commandHazardous
    },
    // Waiting on the server, not on the user confirming in a dialog
    sendInFlight() {
      return (
        this.sendDisabled &&
        !this.displaySendHazardous &&
        !this.displayCriticalCmd
      )
    },
    // Send will ask to confirm
    sendHazardous() {
      return this.commandIsHazardousNow || !!this.hazardousModes
    },
    // The chip shows the command's hazardous description, if any; the
    // tooltip also says why when it's only the Mode menu
    hazardText() {
      if (this.commandIsHazardousNow && this.hazardousDescription) {
        return `Hazardous: ${this.hazardousDescription}`
      }
      return 'Hazardous'
    },
    hazardTitle() {
      if (!this.commandIsHazardousNow) {
        return `Hazardous because ${this.hazardousModes}`
      }
      return this.hazardousDescription
        ? `Hazardous: ${this.hazardousDescription}`
        : 'Hazardous'
    },
    // Not while a history entry or the command line loads, or while the
    // command line has edits that aren't loaded, so Send only ever sends
    // the command shown in the form and the command line
    canSend() {
      return (
        !this.readOnlyUser &&
        !this.sendDisabled &&
        !this.loadingCommand &&
        !this.lineDirty &&
        this.commandReady &&
        !!this.targetName &&
        !!this.commandName
      )
    },
    sendTooltip() {
      if (this.readOnlyUser) return 'Viewers cannot send commands'
      if (this.lineDirty) {
        return 'Press Enter in the command line to load it, or Esc to undo'
      }
      return ''
    },
    // The scripting method the Mode menu sends with, as the history shows it
    sendMethod() {
      const raw = this.cmdRaw ? '_raw' : ''
      return this.ignoreRangeChecks ? `cmd${raw}_no_range_check` : `cmd${raw}`
    },
    readOnlyUser: function () {
      const roles = OpenC3Auth.userroles() || []
      return roles.length > 0 && roles.every((role) => role === 'viewer')
    },
    menus: function () {
      return [
        {
          label: 'File',
          items: [
            {
              label: 'Paste Command',
              icon: 'mdi-clipboard-text-outline',
              shortcut: 'Mod+V',
              command: () => {
                this.$refs.commandLine.focus()
              },
            },
            {
              label: 'Clear History',
              icon: 'mdi-delete-sweep',
              command: () => {
                this.clearHistory()
              },
            },
          ],
        },
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
                // Send waits for the reloaded rows (command-loaded)
                this.commandReady = false
                this.$refs.commandEditor.triggerUpdateCmdParams()
              },
            },
            {
              label: 'Disable Parameter Conversions',
              checkbox: true,
              checked: this.cmdRaw,
              command: () => {
                this.cmdRaw = !this.cmdRaw
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
        {
          label: 'Help',
          items: [
            {
              label: 'Keyboard Shortcuts',
              icon: 'mdi-keyboard-outline',
              command: () => this.openHelp('shortcuts'),
            },
            {
              label: 'Using Command Sender',
              icon: 'mdi-information-outline',
              command: () => this.openHelp('guide'),
            },
          ],
        },
      ]
    },
    // A dialog or menu is open, so page shortcuts stand aside
    overlayOpen() {
      return (
        this.helpOpen ||
        this.displaySendHazardous ||
        this.displayErrorDialog ||
        this.displayCriticalCmd
      )
    },
  },
  watch: {
    // The Mode menu and queue are part of the command line
    sendMethod() {
      this.updateCommandLine()
    },
    disableCommandValidation() {
      this.updateCommandLine()
    },
    queueName() {
      this.updateCommandLine()
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
    getCachedSetting('time_zone').then((timeZone) => {
      if (timeZone) {
        this.timeZone = timeZone
      }
    })
  },
  mounted() {
    window.addEventListener('paste', this.onPaste)
    window.addEventListener('keydown', this.onKeydown)
  },
  beforeUnmount() {
    window.removeEventListener('paste', this.onPaste)
    window.removeEventListener('keydown', this.onKeydown)
    clearTimeout(this.hazardTimer)
    for (const watcher of Object.values(this.criticalCmdWatchers)) {
      clearTimeout(watcher)
    }
    this.criticalCmdWatchers = {}
  },
  methods: {
    openHelp(topic) {
      this.helpTopic = topic
      this.helpOpen = true
    },

    // Shortcuts only apply to the page itself, not while typing in a field
    // (where Mod+V pastes and Alt+arrows move the cursor) or in a dialog
    pageHasFocus(event) {
      return (
        !this.overlayOpen &&
        !event.target?.closest?.(
          'input, textarea, select, [contenteditable], .v-overlay__content',
        )
      )
    },

    // Mod+V on the page loads the clipboard's command through the command
    // line, which shows any error. The paste event carries the text without
    // the clipboard API, which only exists in secure contexts.
    onPaste(event) {
      if (this.sendDisabled || !this.pageHasFocus(event)) return
      const text = event.clipboardData?.getData('text')?.trim()
      if (!text) return
      event.preventDefault()
      // The command line shows its own errors
      void this.$refs.commandLine.loadText(text)
    },

    // Alt+Down / Alt+Up load the next older / newer history command
    onKeydown(event) {
      if (!event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) {
        return
      }
      if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return
      if (!this.pageHasFocus(event)) return
      event.preventDefault()
      this.stepHistory(event.key === 'ArrowDown' ? 1 : -1)
    },

    // The history is newest first, so down (+1) is older. With nothing
    // loaded from it yet, either direction starts at the newest.
    stepHistory(direction) {
      const entries = this.historyEntries
      if (!entries.length || this.loadingCommand || this.sendDisabled) return
      const current = entries.findIndex(
        (entry) => entry.id === this.selectedHistoryId,
      )
      const index =
        current === -1
          ? 0
          : Math.min(Math.max(current + direction, 0), entries.length - 1)
      if (index === current) return
      const entry = entries[index]
      this.$refs.commandHistory.scrollToEntry(entry.id)
      // selectHistory reports its own errors in the status
      void this.selectHistory(entry)
    },

    commandChanged(event) {
      if (
        this.targetName !== event.targetName ||
        this.commandName !== event.packetName
      ) {
        this.targetName = event.targetName
        this.commandName = event.packetName
        this.commandReady = false
        this.hazardPreview = null
        // Drop an answer still in flight for the previous command
        this.hazardRequest++
        // The user picked a different command: drop the history selection
        // and the status, which describes the previous command. Loading
        // from the history or the command line sets its own status.
        if (!this.loadingCommand) {
          this.selectedHistoryId = null
          this.status = ''
        }
        this.updateRoute()
      }
      // Update queue selection if it changed
      if (event.queueName !== undefined) {
        this.queueName = event.queueName
      }
    },

    updateRoute() {
      const params =
        this.targetName && this.commandName
          ? { target: this.targetName, packet: this.commandName }
          : undefined
      this.$router
        .replace({ name: 'CommandSender', params })
        // catch the error in case we route to where we already are
        .catch((err) => {})
    },

    onCommandLoaded(command) {
      this.commandReady = !!command
      this.commandHazardous = !!command?.hazardous
      this.checkHazard()
      this.updateCommandLine()
      const screenCommand = command
        ? `${command.target_name} ${command.packet_name}`
        : null
      // The same command reloaded, e.g. from the history: keep its screen
      if (command && screenCommand === this.screenCommand) {
        this.commandDescription = command.description
        this.hazardousDescription = command.hazardous_description || ''
        return
      }
      this.screenCommand = screenCommand
      if (command) {
        this.commandDescription = command.description
        this.hazardousDescription = command.hazardous_description || ''
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
              screenDefinition += `LABELVALUE '${item[0]}' '${item[1]}' '${item[2]}' FORMATTED 20\n`
            }
            this.screenDefinition = screenDefinition
          } else {
            this.screenTarget = null
            this.screenName = null
            this.screenDefinition = null
          }
          this.screenCount += 1
        }
      } else {
        this.commandDescription = ''
        this.hazardousDescription = ''
        this.screenTarget = null
        this.screenName = null
        this.screenDefinition = null
        this.screenCount += 1
      }
    },

    paramsChanged() {
      this.checkHazard()
      this.updateCommandLine()
    },

    // Rebuild the command line from the form. While a command loads it keeps
    // the last one (shown loading) rather than an empty command.
    updateCommandLine() {
      const editor = this.$refs.commandEditor
      if (!editor?.targetName || !editor?.commandName) {
        this.commandLine = ''
        return
      }
      if (!this.commandReady) return
      // The editor's names, which change with its rows: this.targetName is
      // only set once a load from the command line or history finishes
      this.commandLine = formatFormCmd(
        this.sendMethod,
        editor.targetName,
        editor.commandName,
        editor.getRows(),
        {
          raw: this.cmdRaw,
          queueName: this.queueName,
          disableCommandValidation: this.disableCommandValidation,
          python: this.scriptingPython(),
        },
      )
    },

    scriptingPython() {
      return AceEditorUtils.getDefaultScriptingLanguage() === 'python'
    },

    // Ask the server whether the form's command is hazardous, shortly after
    // the values stop changing, to color the Send button before it's pressed
    // The last answer stays until the new one arrives so the button doesn't
    // flicker; commandChanged clears it for a different command.
    checkHazard() {
      clearTimeout(this.hazardTimer)
      if (!this.commandReady || !this.targetName || !this.commandName) return
      this.hazardTimer = setTimeout(() => this.previewHazard(), 300)
    },

    async previewHazard() {
      const request = ++this.hazardRequest
      let paramList
      try {
        paramList = this.createParamList()
      } catch {
        // An invalid value, Send reports it
        return
      }
      try {
        const hazardous = await this.api.get_cmd_hazardous(
          this.targetName,
          this.commandName,
          paramList,
          { 'Ignore-Errors': '500' },
        )
        // Ignore an answer for values that have since changed
        if (request === this.hazardRequest) {
          this.hazardPreview = !!hazardous
        }
      } catch {
        // E.g. a value out of range: leave it unknown, Send reports it
      }
    },

    createParamList() {
      let paramList = {}
      const hidden = []
      for (const row of this.$refs.commandEditor.getRows()) {
        // A null val marks a required parameter the user hasn't set (see
        // CommandEditor). Omit it entirely so the backend reports it as "not
        // given" rather than receiving an empty value and reporting that it is
        // "not one of" the valid states.
        if (row.val === null) {
          // Loaded from the history, which hides the value: never send the
          // default in its place
          if (row.obfuscated) hidden.push(row.parameter_name)
          continue
        }
        paramList[row.parameter_name] = this.convertToValue(row)
      }
      if (hidden.length) {
        throw new Error(
          `Enter ${hidden.join(', ')}: the history hides obfuscated values`,
        )
      }
      return paramList
    },

    buildCmd() {
      if (!this.canSend) return
      let paramList
      try {
        paramList = this.createParamList()
      } catch (e) {
        this.status = e.message
        this.displayErrorDialog = true
        return
      }
      this.sendCmd({
        targetName: this.targetName,
        commandName: this.commandName,
        paramList,
        queueName: this.queueName,
        // For the hazardous dialog, as shown when Send was pressed
        description: this.commandDescription,
        hazardousDescription: this.hazardousDescription,
      })
    },

    sendCmd(cmdInfo) {
      const { targetName, commandName, paramList } = cmdInfo
      if (this.readOnlyUser) {
        this.status = 'Viewers cannot send commands'
        return
      }
      // Kept for the hazardous confirmation, which sends exactly this
      this.pendingCmd = cmdInfo
      this.sendDisabled = true
      this.api.get_cmd_hazardous(targetName, commandName, paramList).then(
        (hazardous) => {
          // Ignoring range checks allows arbitrary values (e.g. manually
          // entered states) and disabling conversions bypasses any that make
          // a command safe so treat every command as hazardous
          if (hazardous || this.hazardousModes) {
            this.commandIsHazardous = hazardous
            this.hazardousCommand = `${targetName} ${commandName}`
            this.hazardousDialogDescription = cmdInfo.description
            this.hazardousDialogHazardousDescription =
              cmdInfo.hazardousDescription
            this.displaySendHazardous = true
          } else {
            this.executeCmd(cmdInfo, false)
          }
        },
        (error) => {
          this.processCmdError(targetName, commandName, error)
        },
      )
    },

    sendHazardousCmd() {
      this.displaySendHazardous = false
      this.executeCmd(this.pendingCmd, true)
    },

    // Sends the command described by cmdInfo using the api method matching the
    // current raw and range check settings. skipHazardousCheck is true once the
    // user has confirmed the hazardous command dialog.
    executeCmd(cmdInfo, skipHazardousCheck) {
      const { targetName, commandName, paramList, queueName } = cmdInfo
      // Snapshot the settings used to send so the history entry matches even
      // if they change before a critical command is approved
      const sendOptions = {
        queueName,
        disableCommandValidation: this.disableCommandValidation,
      }
      let kwparams = {}
      if (this.disableCommandValidation) {
        kwparams.validate = false
      }
      // Add queue parameter if a queue is selected
      if (queueName !== null) {
        kwparams.queue = queueName
      }
      const raw = this.cmdRaw ? '_raw' : ''
      // The no_hazardous_check variants are an implementation detail of the
      // confirmation dialog so the history shows the checked equivalent
      const cmd = this.sendMethod
      let method
      if (this.ignoreRangeChecks) {
        method = skipHazardousCheck
          ? `cmd${raw}_no_checks`
          : `cmd${raw}_no_range_check`
      } else {
        method = skipHazardousCheck
          ? `cmd${raw}_no_hazardous_check`
          : `cmd${raw}`
      }
      // Range checked requests could be denied due to out of range but since
      // we're explicitly handling it we don't want the interceptor to fire
      const headers = {
        'Ignore-Errors': this.ignoreRangeChecks ? '428' : '428 500',
      }
      this.api[method](
        targetName,
        commandName,
        paramList,
        headers,
        kwparams,
      ).then(
        (response) => {
          this.processCmdSuccess(cmd, response, sendOptions)
          this.sendDisabled = false
        },
        (error) => {
          this.processCmdError(targetName, commandName, error)
          if (error.message?.includes('CriticalCmdError')) {
            this.watchCriticalCmd(
              cmd,
              error.object.data.instance_variables,
              sendOptions,
            )
          }
        },
      )
    },

    // Critical commands aren't sent until enough users approve them, which can
    // happen long after the approval dialog is closed. Watch for the final
    // status so approved commands are added to the history like any other.
    // Polling backs off from 1s to 30s and gives up after an hour.
    watchCriticalCmd(cmd, criticalError, sendOptions) {
      const uuid = criticalError['@uuid']
      const command = criticalError['@command']
      if (!uuid || !command || uuid in this.criticalCmdWatchers) return
      const deadline = Date.now() + 60 * 60 * 1000
      let delay = 1000
      const stop = () => {
        clearTimeout(this.criticalCmdWatchers[uuid])
        delete this.criticalCmdWatchers[uuid]
      }
      const schedule = () => {
        // Stopped while the request was in flight, e.g. the tool was closed
        if (!(uuid in this.criticalCmdWatchers)) return
        if (Date.now() + delay > deadline) {
          stop()
          return
        }
        this.criticalCmdWatchers[uuid] = setTimeout(poll, delay)
        delay = Math.min(delay * 2, 30000)
      }
      const poll = () => {
        // The approval dialog polls this command itself while it's open.
        // Check again shortly so the result is picked up once it closes.
        if (this.displayCriticalCmd && this.criticalCmdUuid === uuid) {
          delay = 1000
          schedule()
          return
        }
        Api.get('/openc3-api/criticalcmd/status/' + uuid, {
          // Keep failed polls out of the error banner, they're retried
          headers: {
            Accept: 'application/json',
            'Ignore-Errors': '404 500 502 503 504',
          },
        })
          .then((response) => {
            // Stopped while the request was in flight, e.g. the tool was closed
            if (!(uuid in this.criticalCmdWatchers)) return
            if (response.data.status === 'APPROVED') {
              stop()
              // APPROVED only means the command was released to the interface,
              // which can still fail to send it (e.g. disconnected), so don't
              // claim it was sent
              const msg = this.formatCmd(cmd, command, sendOptions)
              this.addHistory(msg)
              const released = response.data.interface_name
                ? ` and released to ${response.data.interface_name}`
                : ''
              this.status = `Critical command approved${released}: ${msg}`
            } else if (response.data.status === 'REJECTED') {
              stop()
              this.status = `Critical command rejected: ${command.cmd_string}`
            } else {
              schedule()
            }
          })
          .catch((error) => {
            if (!(uuid in this.criticalCmdWatchers)) return
            // The critical command no longer exists, e.g. critical commanding
            // was turned off. Keep watching through transient errors.
            if (error.response?.status === 404) {
              stop()
            } else {
              schedule()
            }
          })
      }
      this.criticalCmdWatchers[uuid] = null
      schedule()
    },

    cancelHazardousCmd() {
      this.displaySendHazardous = false
      this.status = 'Hazardous command not sent'
      this.sendDisabled = false
    },

    processCmdSuccess(cmd_sent, response, sendOptions) {
      let msg = this.formatCmd(cmd_sent, response, sendOptions)
      this.addHistory(msg)
      msg += ' sent.'
      // Add the number of commands sent to the status message
      if (this.status.includes(msg)) {
        let parts = this.status.split('sent.')
        if (parts[1].includes('(')) {
          let num = Number.parseInt(
            parts[1].substr(2, parts[1].indexOf(')') - 2),
          )
          msg = parts[0] + 'sent. (' + (num + 1) + ')'
        } else {
          msg += ' (2)'
        }
      }
      this.status = msg
    },

    // Format the sent command the way the user would script it
    formatCmd(cmdSent, response, sendOptions) {
      return formatCmd(cmdSent, response, {
        ...sendOptions,
        python: this.scriptingPython(),
      })
    },

    processCmdError(targetName, commandName, response) {
      const context = 'sending ' + targetName + ' ' + commandName
      this.displayError(context, response, true)
      this.sendDisabled = false
    },

    clearHistory() {
      this.clearHistoryEntries()
      this.selectedHistoryId = null
    },

    async selectHistory(entry) {
      this.selectedHistoryId = entry.id
      const error = await this.loadCommand(entry.cmd)
      // Ignore the error of a load replaced by another entry, which is
      // selected and loading now
      if (error && this.selectedHistoryId === entry.id) {
        this.selectedHistoryId = null
        this.status = error
      }
    },

    // For CommandLine: resolves to an error message, or null once loaded.
    // An edit of the form's line keeps obfuscated values the form has.
    async loadCommandLine(text, { edited }) {
      const error = await this.loadCommand(text, {
        keepObfuscated: edited,
      })
      if (!error) {
        this.selectedHistoryId = null
      }
      return error
    },

    // Load a command as scripted, e.g. cmd("INST COLLECT with TYPE 'NORMAL'"),
    // into the form without sending it. The Mode menu still decides how it's
    // sent. Resolves to an error message, or null once loaded.
    // keepObfuscated: see CommandEditor.setCommand
    loadCommand(text, { keepObfuscated = false } = {}) {
      // The form is what's being sent (or confirmed), so leave it alone
      if (this.sendDisabled) {
        return Promise.resolve('Wait for the command being sent to finish')
      }
      let parsed
      try {
        parsed = parseCmdLine(text)
      } catch (error) {
        return Promise.resolve(error.message)
      }
      const editor = this.$refs.commandEditor
      // The command's queue, or None (null) without a queue keyword: None
      // sends no queue keyword either, so the server uses its default queue
      // just as it would for the command as written. queue: false (skip the
      // default queue) has no choice in the queue list, None is the closest.
      const queue =
        parsed.queue === undefined || parsed.queue === false
          ? null
          : parsed.queue
      this.loadingCommand = true
      // setCommand fills in the form off screen and swaps it in at once. It
      // also turns on Show Ignored Parameters (v-model) if the command sets
      // ignored parameters, so the form matches it exactly.
      const load = editor
        .setCommand({ ...parsed, queue, keepObfuscated })
        .then((result) => {
          const targetName = parsed.target.toUpperCase()
          const commandName = parsed.command.toUpperCase()
          if (
            targetName !== this.targetName ||
            commandName !== this.commandName
          ) {
            // The previous command's hazard answer doesn't apply, and one
            // still in flight mustn't land on this command
            this.hazardPreview = null
            this.hazardRequest++
          }
          this.targetName = targetName
          this.commandName = commandName
          // The chooser only reports its queue once its packet list loads,
          // so take it now in case Send is pressed before then
          this.queueName = result.unknownQueue === null ? queue : null
          this.commandReady = true
          this.updateRoute()
          this.status = this.loadedStatus(parsed, result)
          this.checkHazard()
          return null
        })
        .catch((error) => {
          // setCommand changes nothing when the command doesn't exist
          const reason = error?.message || String(error)
          return `Unable to load ${parsed.target} ${parsed.command}: ${reason}`
        })
        .finally(() => {
          // A load replaced by a newer one leaves the newer one loading
          if (this.loadPromise === load) {
            this.loadingCommand = false
            this.loadPromise = null
          }
        })
      this.loadPromise = load
      return load
    },

    loadedStatus(parsed, result) {
      const name = `${parsed.target.toUpperCase()} ${parsed.command.toUpperCase()}`
      const notes = []
      if (parsed.method) {
        // How the Mode menu would have written it: the no_hazardous_check
        // variants only skip the confirmation, which Send always asks for
        const written = parsed.method
          .replace('_no_hazardous_check', '')
          .replace('_no_checks', '_no_range_check')
        if (written !== this.sendMethod) {
          notes.push(
            `it was written as ${parsed.method} but the Mode menu sends ${this.sendMethod}`,
          )
        }
      }
      if (
        parsed.validate !== undefined &&
        parsed.validate === this.disableCommandValidation
      ) {
        notes.push(
          `validate ${parsed.validate} was not applied, use Mode > Disable Command Validation`,
        )
      }
      if (parsed.queue === false) {
        notes.push('queue false is not supported here, the queue is None')
      } else if (result.queueLookupFailed) {
        notes.push(
          `the queue list couldn't be loaded to check queue "${result.unknownQueue}", the queue is None`,
        )
      } else if (result.unknownQueue) {
        notes.push(
          `queue "${result.unknownQueue}" doesn't exist, the queue is None`,
        )
      }
      if (parsed.ignored.length) {
        notes.push(`${parsed.ignored.join(', ')} not applied`)
      }
      if (result.unknown.length) {
        notes.push(
          `${result.unknown.join(', ')} not parameters of ${name}, skipped`,
        )
      }
      if (result.obfuscated.length) {
        notes.push(
          `set ${result.obfuscated.join(', ')}, the history hides the value`,
        )
      }
      const loaded = `Loaded ${name}, press Send to send it`
      return notes.length
        ? `${loaded}. Note: ${notes.join('; ')}.`
        : `${loaded}.`
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
  },
}
</script>

<style scoped>
/* The Dashboards type and surfaces: IBM Plex, 13px, flat bordered panels */
.cmd-sender {
  font-family: 'IBM Plex Sans', system-ui, sans-serif;
  font-size: 13px;
  line-height: 1.4;
  padding-bottom: 16px;
}
/* Vuetify's typography classes (text-body-2, text-caption) set Roboto, so
   keep their sizes but use the Command Sender type */
.cmd-sender :deep(.text-body-2),
.cmd-sender :deep(.text-caption) {
  font-family: inherit;
}
.cmd-sender :deep(.mono) {
  font-family: 'IBM Plex Mono', ui-monospace, monospace;
}
.cmd-sender :deep(.num) {
  font-variant-numeric: tabular-nums;
}
.cmd-sender :deep(.min-w-0) {
  min-width: 0;
}
.cmd-sender :deep(.cs-panel) {
  border: thin solid rgba(var(--v-border-color), var(--v-border-opacity));
  /* The theme's card color (Astro's surface token, as COSMOS cards use), not
     Vuetify's surface, which is a neutral gray */
  background: var(
    --color-background-surface-default,
    rgb(var(--v-theme-surface))
  );
}
.cmd-sender :deep(.cs-panel-header) {
  min-height: 40px;
  padding-top: 4px;
}
.cmd-sender :deep(.cs-panel-title) {
  font-size: 14px;
  font-weight: 700;
}
/* CommandEditor's cards sit flat inside the panel */
.cs-editor,
.cs-editor :deep(.v-card) {
  background: transparent;
  box-shadow: none;
}
.cs-editor :deep(.v-card-title) {
  padding: 4px 16px;
  font-size: 14px;
  font-weight: 700;
}
.cs-editor :deep(.parameters-table) {
  background: transparent;
  font-size: 13px;
  /* The whole table, the page scrolls: CommandEditor caps it at 50vh for
     the dialogs it's used in, which would scroll it inside the page */
  max-height: none;
}
/* Wide enough for state names like NORMAL in the 13px type; the editor's
   inline 120px truncates them */
.cs-editor :deep(.v-autocomplete[data-test='cmd-param-select']) {
  min-width: 160px !important;
}
.cs-editor :deep(.parameters-table thead th) {
  font-weight: 600;
}
.cs-editor :deep(.parameters-table tbody td:first-child) {
  font-family: 'IBM Plex Mono', ui-monospace, monospace;
}
/* Command Sender's own dialogs are teleported out of .cmd-sender, so they
   set the type themselves. (The critical command dialog is shared with
   Script Runner and keeps the standard type.) */
.cs-dialog {
  font-family: 'IBM Plex Sans', system-ui, sans-serif;
  font-size: 14px;
  line-height: 1.5;
}
/* Dashboards' caution ring (dashboards.scss .panel-frame.ring-caution) */
.cs-command {
  transition:
    border-color 0.2s,
    box-shadow 0.2s;
}
.cs-command.ring-caution {
  border-color: color-mix(
    in srgb,
    var(--color-status-caution) 60%,
    transparent
  );
  box-shadow:
    0 0 0 1px color-mix(in srgb, var(--color-status-caution) 25%, transparent),
    0 10px 30px -14px
      color-mix(in srgb, var(--color-status-caution) 60%, transparent);
}
.cs-hazard {
  max-width: 40%;
}
.cs-status {
  min-height: 20px;
  overflow-wrap: anywhere;
}
.cs-send {
  min-width: 120px;
}
/* The related screen keeps its own width (up to half) and long history
   commands wrap instead of squeezing it */
.cs-screen {
  flex: 0 0 auto;
  max-width: 50%;
  overflow: auto;
}
</style>
