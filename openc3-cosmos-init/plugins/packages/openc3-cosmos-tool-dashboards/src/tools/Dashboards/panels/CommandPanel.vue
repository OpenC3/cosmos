<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div
    :class="[
      'command-panel d-flex flex-column flex-grow-1 min-h-0 px-4',
      compact ? 'pb-2' : isScript ? 'ga-1 pt-1 pb-3' : 'ga-2 pt-2 pb-3',
    ]"
  >
    <div
      v-if="!panel.command && !panel.script"
      class="text-caption text-medium-emphasis"
    >
      Nothing to send. Pick a command or script for this panel.
    </div>
    <template v-else>
      <v-chip
        v-if="hazardous && !compact"
        size="small"
        variant="tonal"
        color="warning"
        class="align-self-start font-weight-bold"
        :title="command?.hazardous_description"
        data-test="command-hazardous"
      >
        <status-symbol level="serious" decorative class="mr-2" />
        Hazardous
      </v-chip>
      <div
        v-if="!compact"
        class="d-flex flex-column ga-2 overflow-y-auto flex-grow-1 min-h-0"
      >
        <div
          v-if="details"
          class="text-pre-line text-body-2 text-medium-emphasis"
          data-test="command-details"
        >
          {{ details }}
        </div>
        <div
          v-if="shownParams.length"
          class="param-grid"
          :style="{ '--param-cols': columns, '--label-chars': labelChars }"
        >
          <div v-for="param in shownParams" :key="param.name" class="param-row">
            <label
              :for="`${uid}-${param.name}`"
              class="param-label flex-shrink-0 mono text-caption text-medium-emphasis text-truncate"
              :title="
                [param.name, param.description].filter(Boolean).join(': ')
              "
            >
              {{ param.name }}
            </label>
            <command-param-field
              :id="`${uid}-${param.name}`"
              v-model="values[param.name]"
              :param="param"
            />
          </div>
        </div>
        <div
          v-if="!isScript && loaded && !shownParams.length"
          class="text-caption text-medium-emphasis"
        >
          {{ params.length ? 'All parameters are preset' : 'No parameters' }}
        </div>
      </div>
      <!-- The button sits at the bottom with its status above it. Scripts
           and 2-row panels get a slim one. -->
      <div :class="['d-flex flex-column mt-auto', slim ? 'ga-1' : 'ga-2']">
        <div
          :class="[
            'status text-caption text-medium-emphasis',
            { 'text-truncate slim': slim },
          ]"
          :title="statusText"
          aria-live="polite"
          data-test="command-status"
        >
          {{ statusText }}
          <a
            v-if="scriptId"
            :href="`/tools/scriptrunner/${scriptId}`"
            target="_blank"
            class="ml-1"
          >
            Open script {{ scriptId }}
          </a>
        </div>
        <button
          v-if="confirm === 'HOLD'"
          type="button"
          :class="[
            'hold d-flex align-center justify-center position-relative overflow-hidden rounded-lg border text-body-2',
            'w-100',
            { slim, holding, hz: hazardous },
          ]"
          :disabled="!ready || sending"
          :title="buttonTitle"
          data-test="command-send"
          @pointerdown="startHold"
          @pointerup="cancelHold"
          @pointerleave="cancelHold"
          @keydown.space.prevent="startHold"
          @keydown.enter.prevent="startHold"
          @keyup="cancelHold"
        >
          <span
            class="hold-fill position-absolute"
            :style="{ transitionDuration: holding ? `${holdMs}ms` : '0ms' }"
          />
          <span
            class="d-inline-flex align-center ga-2 position-relative font-weight-bold"
          >
            <v-icon :icon="icon" :size="slim ? 16 : 18" />
            {{ holdLabel }}
          </span>
        </button>
        <v-btn
          v-else
          block
          :size="slim ? 'small' : 'large'"
          :color="hazardous ? 'warning' : 'primary'"
          :prepend-icon="icon"
          :disabled="!ready"
          :loading="sending"
          :title="buttonTitle"
          data-test="command-send"
          @click="clickSend"
        >
          {{ isScript ? 'Run' : 'Send' }}
        </v-btn>
      </div>
    </template>
    <critical-cmd-dialog
      v-model="critical.show"
      :uuid="critical.uuid"
      :cmd-string="critical.cmdString"
      :cmd-user="critical.user"
    />
  </div>
</template>

<script>
import { Api, OpenC3Api } from '@openc3/js-common/services'
import { CriticalCmdDialog } from '@openc3/vue-common/components'
import { CmdUtilities } from '@openc3/vue-common/util'
import StatusSymbol from '../components/StatusSymbol.vue'
import CommandParamField from './CommandParamField.vue'
import panelBase from './panelBase'
import { option } from './options'
import { loadCommandParams, unsetRequired as findUnset } from './commandParams'
import { clock } from '../composables/format'

const HOLD_MS = 800
const HOLD_HAZARDOUS_MS = 2000

let nextUid = 1

// Sends one command with parameters preset from PARAMETER lines, or runs a
// script (SCRIPT). CONFIRM HOLD requires holding the button (longer when
// hazardous), CLICK sends on click and asks for confirmation when hazardous.
// Critical commands go through the standard critical command approval dialog.
export default {
  components: { CommandParamField, CriticalCmdDialog, StatusSymbol },
  // panelBase: nothing is sent while editing (isEditing) or during playback
  mixins: [panelBase, CmdUtilities],
  data() {
    return {
      uid: `cmd${nextUid++}`,
      cmdRaw: false, // used by CmdUtilities.convertToValue
      command: null,
      params: [],
      values: {},
      loaded: false,
      sending: false,
      holding: false,
      holdTimer: null,
      status: '',
      scriptId: null,
      // The server's answer for the current parameters: null while checking
      serverHazard: null,
      hazardRequest: 0,
      critical: { show: false, uuid: null, cmdString: null, user: null },
    }
  },
  computed: {
    isScript() {
      return !!this.panel.script
    },
    // 2 or 3 rows tall: only the button and its status, which is too
    // small for a usable form. Commands send their PARAMETER values; DETAILS
    // shows as the button's tooltip. rect follows a resize while it's
    // dragged, so the layout switches live.
    compact() {
      return this.rect.h <= 3
    },
    // Scripts, and 2-row panels that only fit a slim button
    slim() {
      return this.isScript || this.rect.h <= 2
    },
    buttonTitle() {
      return this.compact ? this.details : undefined
    },
    hidden() {
      return option(this.panel, 'HIDE')
    },
    // Parameters with a field in the panel; hidden ones still send their
    // preset or default
    shownParams() {
      return this.params.filter((param) => !this.hidden.includes(param.name))
    },
    // Parameters per line from the panel's grid width: 1 up to 3 columns,
    // 2 up to 6, 3 up to 9, 4 up to 12. The CSS still drops to fewer when
    // fields would get too narrow, e.g. on phones.
    columns() {
      return Math.max(1, Math.min(4, Math.ceil(this.rect.w / 3)))
    },
    // Every label gets the longest name's width so the fields line up
    labelChars() {
      return Math.max(4, ...this.shownParams.map((p) => p.name.length))
    },
    // Required parameters without a value that the panel has no field for:
    // all of them in a compact panel, otherwise the hidden ones
    unsetRequired() {
      return findUnset(
        this.params,
        this.values,
        this.compact ? null : this.hidden,
      )
    },
    statusText() {
      if (this.isPlayback) return 'Off during playback'
      if (this.unsetRequired.length) {
        const fix = this.compact
          ? 'make the panel taller to set it, or preset it'
          : 'preset or unhide it in the panel settings'
        return `Needs ${this.unsetRequired.join(', ')}: ${fix}`
      }
      return this.status
    },
    icon() {
      return this.isScript ? 'mdi-play' : 'mdi-send-outline'
    },
    confirm() {
      return option(this.panel, 'CONFIRM')
    },
    details() {
      return option(this.panel, 'DETAILS')
    },
    // The server decides (get_cmd_hazardous covers the command, hazardous
    // states and anything else it knows); until it answers, the definition
    hazardous() {
      if (this.isScript) return false
      return this.serverHazard ?? this.hazardousFromDefinition()
    },
    checking() {
      return !this.isScript && !!this.command && this.serverHazard === null
    },
    // Loaded, its hazard known, not editing and not in playback
    ready() {
      return (
        this.loaded &&
        !this.checking &&
        !this.isEditing &&
        !this.isPlayback &&
        !this.unsetRequired.length
      )
    },
    holdMs() {
      return this.hazardous ? HOLD_HAZARDOUS_MS : HOLD_MS
    },
    holdLabel() {
      const verb = this.isScript ? 'run' : 'send'
      if (this.checking) return 'Checking…'
      if (this.sending) return this.isScript ? 'Starting…' : 'Sending…'
      if (this.holding) return 'Keep holding…'
      return this.hazardous ? `Hold 2 s to ${verb}` : `Hold to ${verb}`
    },
  },
  watch: {
    // Replaced whole when the command changes, never edited in place
    'panel.command'() {
      this.load()
    },
    'panel.script'() {
      this.load()
    },
    'panel.parameters': {
      deep: true,
      handler() {
        this.applyDefaults()
      },
    },
    // Ask the server whether these values make the command hazardous, shortly
    // after they stop changing
    values: {
      deep: true,
      handler() {
        this.serverHazard = null
        clearTimeout(this.hazardTimer)
        this.hazardTimer = setTimeout(() => this.checkHazard(), 300)
      },
    },
  },
  created() {
    this.api = new OpenC3Api()
    this.load()
  },
  unmounted() {
    clearTimeout(this.holdTimer)
    clearTimeout(this.hazardTimer)
  },
  methods: {
    async load() {
      this.loaded = false
      this.params = []
      this.command = null
      this.status = ''
      this.scriptId = null
      if (this.isScript) {
        this.loaded = true
        return
      }
      if (!this.panel.command) return
      const { targetName, commandName } = this.panel.command
      try {
        const { command, params } = await loadCommandParams(
          this.api,
          targetName,
          commandName,
        )
        this.command = command
        this.params = params
        this.applyDefaults()
        this.loaded = true
      } catch (error) {
        this.status = `Unable to load ${targetName} ${commandName}: ${error.message || error}`
      }
    },
    applyDefaults() {
      const values = {}
      for (const param of this.params) {
        const preset = this.panel.parameters[param.name]
        if (preset !== undefined) {
          values[param.name] = preset
        } else if (param.required) {
          values[param.name] = ''
        } else if (param.states) {
          values[param.name] =
            Object.keys(param.states).find(
              (s) => param.states[s].value === param.default,
            ) || ''
        } else {
          values[param.name] =
            param.default === undefined || param.default === null
              ? ''
              : String(param.default)
        }
      }
      this.values = values
    },
    paramList() {
      const list = {}
      for (const param of this.params) {
        const value = this.values[param.name]
        if (value === '' || value === undefined) {
          if (param.required) throw new Error(`${param.name} is required`)
          continue
        }
        if (param.states || param.type === 'STRING' || param.type === 'BLOCK') {
          // States send their name, strings are sent as typed
          list[param.name] = param.states
            ? value
            : this.removeQuotes(String(value))
        } else {
          list[param.name] = this.convertToValue({
            val: String(value),
            type: param.type,
          })
        }
      }
      return list
    },
    async checkHazard() {
      if (this.isScript || !this.command) return
      const { targetName, commandName } = this.panel.command
      const request = ++this.hazardRequest
      let hazardous
      try {
        hazardous = !!(await this.api.get_cmd_hazardous(
          targetName,
          commandName,
          this.paramList(),
          { 'Ignore-Errors': '500' },
        ))
      } catch {
        // A required value is missing or the check failed: go by the
        // definition rather than blocking sends
        hazardous = this.hazardousFromDefinition()
      }
      // Ignore an answer for values that have since changed
      if (request === this.hazardRequest) this.serverHazard = hazardous
    },
    hazardousFromDefinition() {
      if (this.command?.hazardous) return true
      return this.params.some(
        (param) =>
          param.states && param.states[this.values[param.name]]?.hazardous,
      )
    },
    startHold(event) {
      if (event.repeat || this.holding || this.sending || !this.loaded) return
      if (!this.ready) return
      this.holding = true
      this.holdTimer = setTimeout(() => {
        this.holding = false
        this.send(this.hazardous)
      }, this.holdMs)
    },
    cancelHold() {
      if (!this.holding) return
      clearTimeout(this.holdTimer)
      this.holding = false
      this.status = `Released early, ${this.isScript ? 'script not started' : 'command not sent'}`
    },
    async clickSend() {
      if (this.hazardous) {
        const description = this.command?.hazardous_description
        try {
          await this.$dialog.confirm(
            `${this.panel.command.targetName} ${this.panel.command.commandName} is hazardous.` +
              (description ? ` ${description}.` : '') +
              ' Send it?',
            { okText: 'Send', cancelText: 'Cancel', okClass: 'error' },
          )
        } catch {
          this.status = 'Hazardous command not sent'
          return
        }
      }
      this.send(this.hazardous)
    },
    send(confirmedHazardous) {
      return this.isScript
        ? this.runScript()
        : this.sendCommand(confirmedHazardous)
    },
    async runScript() {
      this.sending = true
      this.scriptId = null
      try {
        const response = await Api.post(
          `/script-api/scripts/${this.panel.script}/run`,
          { data: { environment: [] } },
        )
        this.scriptId = response.data
        this.status = `Started ${clock(Date.now(), this.timeZone)}`
        if (option(this.panel, 'OPEN_SCRIPT')) {
          window.open(`/tools/scriptrunner/${this.scriptId}`, '_blank')
        }
      } catch (error) {
        this.status = `Error: ${error.response?.data?.message || error.message || error}`
      } finally {
        this.sending = false
      }
    },
    async sendCommand(confirmedHazardous) {
      const { targetName, commandName } = this.panel.command
      let params
      try {
        params = this.paramList()
      } catch (error) {
        this.status = error.message
        return
      }
      this.sending = true
      const method = confirmedHazardous ? 'cmd_no_hazardous_check' : 'cmd'
      try {
        await this.api[method](targetName, commandName, params, {
          'Ignore-Errors': '428 500',
        })
        this.status = `Sent ${targetName} ${commandName} at ${clock(Date.now(), this.timeZone)}`
      } catch (error) {
        this.handleError(error)
      } finally {
        this.sending = false
      }
    },
    handleError(error) {
      const message = error.message || String(error)
      if (message.includes('CriticalCmdError')) {
        const vars = error.object?.data?.instance_variables || {}
        this.critical = {
          show: true,
          uuid: vars['@uuid'],
          cmdString: vars['@command']?.cmd_string,
          user: vars['@command']?.username,
        }
        this.status = 'Critical command queued for approval'
      } else if (message.includes('is Hazardous')) {
        // The server knows about hazards we didn't (e.g. a hazardous range)
        this.status = `Hazardous: ${message}. Confirm and send again.`
        if (this.command) this.command.hazardous = true
      } else {
        this.status = `Error: ${message}`
      }
    },
  },
}
</script>

<style scoped>
/* Room for one line, so the button and its status fit 2 rows */
.status {
  min-height: 18px;
  min-width: 0;
}
.status.slim {
  min-height: 16px;
  line-height: 16px;
}
/* Narrow panels put parameter labels above their inputs */
.command-panel {
  container-type: inline-size;
}
/* Compact inputs to match the dashboard text size */
.command-panel :deep(.v-field__input) {
  font-size: 13px;
}
.param-grid {
  /* At most --param-cols per line, each at least 160px wide (or the whole
     line when the panel is narrower than that) */
  display: grid;
  grid-template-columns: repeat(
    auto-fill,
    minmax(
      max(
        min(160px, 100%),
        calc((100% - (var(--param-cols) - 1) * 16px) / var(--param-cols))
      ),
      1fr
    )
  );
  gap: 8px 16px;
}
.param-row {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: 12px;
}
/* As wide as the longest name (labels are monospace, so ch fits), leaving
   the field at least 100px; longer names truncate with the full name as a
   tooltip */
.param-label {
  width: min(calc(var(--label-chars) * 1ch + 2px), calc(100% - 112px));
}
@container (max-width: 300px) {
  .command-panel :deep(.v-field__input) {
    font-size: 12px;
  }
  .param-row {
    flex-direction: column;
    align-items: stretch;
    gap: 2px;
  }
  .param-label {
    width: auto;
  }
}
.hold {
  user-select: none;
  touch-action: none;
  min-height: 44px;
  cursor: pointer;
  /* The theme's colors: a primary tint and fill, with the text and outline
     in secondary, the lighter partner every theme gives primary (primary
     itself is too dark to read on a dark panel). Warning for hazardous. */
  --hold-color: var(--v-theme-primary);
  --hold-ink: var(--v-theme-secondary);
  color: rgb(var(--hold-ink));
  background: rgba(var(--hold-color), 0.12);
  border-color: rgba(var(--hold-ink), 0.5) !important;
}
.hold.hz {
  --hold-color: var(--v-theme-warning);
  --hold-ink: var(--v-theme-warning);
}
/* Scripts have little else in the panel, so their button is slim */
.hold.slim {
  min-height: 28px;
  font-size: 12px;
}
.hold:disabled {
  opacity: 0.5;
  cursor: default;
}
.hold-fill {
  inset: 0 auto 0 0;
  width: 0;
  /* The lighter ink color, so the fill stands out from the primary tint
     (hazardous is unchanged: its ink is warning too) */
  background: rgba(var(--hold-ink), 0.35);
  transition-property: width;
  transition-timing-function: linear;
}
.hold.holding .hold-fill {
  width: 100%;
}
.hold:focus-visible {
  outline: 2px solid rgb(var(--v-theme-on-surface));
  outline-offset: 2px;
}
</style>
