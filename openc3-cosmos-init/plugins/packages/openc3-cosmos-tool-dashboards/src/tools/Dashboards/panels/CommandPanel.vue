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
              :model-value="values[param.name]"
              :param="param"
              @update:model-value="setValue(param.name, $event)"
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

<script setup>
import { computed, inject, onUnmounted, ref, watch } from 'vue'
import { Api, OpenC3Api } from '@openc3/js-common/services'
import { CriticalCmdDialog } from '@openc3/vue-common/components'
import { convertToValue, removeQuotes } from '@openc3/vue-common/util'
import StatusSymbol from '../components/StatusSymbol.vue'
import CommandParamField from './CommandParamField.vue'
import { panelProps, usePanel } from './panelBase'
import { option } from './options'
import { loadCommandParams, unsetRequired as findUnset } from './commandParams'
import { clock } from '../composables/format'

const HOLD_MS = 800
const HOLD_HAZARDOUS_MS = 2000

// Module scope, so each panel's field ids stay unique
let nextUid = 1

// The script's run endpoint. The path comes from the dashboard file, so each
// segment is encoded and dot segments, which would walk out of /scripts, are
// refused.
function scriptRunUrl(script) {
  const segments = String(script).split('/')
  if (segments.some((s) => s === '' || s === '.' || s === '..')) {
    throw new Error(`Invalid script path ${script}`)
  }
  return `/script-api/scripts/${segments.map(encodeURIComponent).join('/')}/run`
}

// Sends one command with parameters preset from PARAMETER lines, or runs a
// script (SCRIPT). CONFIRM HOLD requires holding the button (longer when
// hazardous), CLICK sends on click and asks for confirmation when hazardous.
// Critical commands go through the standard critical command approval dialog.
// Nothing is sent while editing (isEditing) or during playback.
const props = defineProps(panelProps)

const { timeZone, isEditing, isPlayback, rect } = usePanel(props)
const dialog = inject('dialog')

const api = new OpenC3Api()

const uid = `cmd${nextUid++}`
const command = ref(null)
const params = ref([])
const values = ref({})
const loaded = ref(false)
const sending = ref(false)
const holding = ref(false)
const status = ref('')
const scriptId = ref(null)
// The server's answer for the current parameters: null while checking
const serverHazard = ref(null)
const critical = ref({ show: false, uuid: null, cmdString: null, user: null })
let holdTimer = null
let hazardTimer = null
let hazardRequest = 0

const isScript = computed(() => !!props.panel.script)
// 2 or 3 rows tall: only the button and its status, which is too
// small for a usable form. Commands send their PARAMETER values; DETAILS
// shows as the button's tooltip. rect follows a resize while it's
// dragged, so the layout switches live.
const compact = computed(() => rect.value.h <= 3)
// Scripts, and 2-row panels that only fit a slim button
const slim = computed(() => isScript.value || rect.value.h <= 2)
const buttonTitle = computed(() => (compact.value ? details.value : undefined))
const hidden = computed(() => option(props.panel, 'HIDE'))
// Parameters with a field in the panel; hidden ones still send their
// preset or default
const shownParams = computed(() =>
  params.value.filter((param) => !hidden.value.includes(param.name)),
)
// Parameters per line from the panel's grid width: 1 up to 3 columns,
// 2 up to 6, 3 up to 9, 4 up to 12. The CSS still drops to fewer when
// fields would get too narrow, e.g. on phones.
const columns = computed(() =>
  Math.max(1, Math.min(4, Math.ceil(rect.value.w / 3))),
)
// Every label gets the longest name's width so the fields line up
const labelChars = computed(() =>
  Math.max(4, ...shownParams.value.map((p) => p.name.length)),
)
// Required parameters without a value that the panel has no field for:
// all of them in a compact panel, otherwise the hidden ones
const unsetRequired = computed(() =>
  findUnset(params.value, values.value, compact.value ? null : hidden.value),
)
const statusText = computed(() => {
  if (isPlayback.value) return 'Off during playback'
  if (unsetRequired.value.length) {
    const fix = compact.value
      ? 'make the panel taller to set it, or preset it'
      : 'preset or unhide it in the panel settings'
    return `Needs ${unsetRequired.value.join(', ')}: ${fix}`
  }
  return status.value
})
const icon = computed(() => (isScript.value ? 'mdi-play' : 'mdi-send-outline'))
const confirm = computed(() => option(props.panel, 'CONFIRM'))
const details = computed(() => option(props.panel, 'DETAILS'))
// The server decides (get_cmd_hazardous covers the command, hazardous
// states and anything else it knows); until it answers, the definition
const hazardous = computed(() => {
  if (isScript.value) return false
  return serverHazard.value ?? hazardousFromDefinition()
})
const checking = computed(
  () => !isScript.value && !!command.value && serverHazard.value === null,
)
// Loaded, its hazard known, not editing and not in playback
const ready = computed(
  () =>
    loaded.value &&
    !checking.value &&
    !isEditing.value &&
    !isPlayback.value &&
    !unsetRequired.value.length,
)
const holdMs = computed(() => (hazardous.value ? HOLD_HAZARDOUS_MS : HOLD_MS))
const holdLabel = computed(() => {
  const verb = isScript.value ? 'run' : 'send'
  if (checking.value) return 'Checking…'
  if (sending.value) return isScript.value ? 'Starting…' : 'Sending…'
  if (holding.value) return 'Keep holding…'
  return hazardous.value ? `Hold 2 s to ${verb}` : `Hold to ${verb}`
})

// The command and presets come from the panel prop (the panel dialog
// replaces them), with no event here to hook: reload the definition, and
// reset the values to the presets. The command is replaced whole when it
// changes, never edited in place.
watch(() => [props.panel.command, props.panel.script], load)
watch(() => props.panel.parameters, applyDefaults, { deep: true })

load()

onUnmounted(() => {
  clearTimeout(holdTimer)
  clearTimeout(hazardTimer)
})

async function load() {
  loaded.value = false
  params.value = []
  command.value = null
  status.value = ''
  scriptId.value = null
  if (isScript.value) {
    loaded.value = true
    return
  }
  if (!props.panel.command) return
  const { targetName, commandName } = props.panel.command
  try {
    const loadedParams = await loadCommandParams(api, targetName, commandName)
    command.value = loadedParams.command
    params.value = loadedParams.params
    applyDefaults()
    loaded.value = true
  } catch (error) {
    status.value = `Unable to load ${targetName} ${commandName}: ${error.message || error}`
  }
}

function applyDefaults() {
  const defaults = {}
  for (const param of params.value) {
    const preset = props.panel.parameters[param.name]
    if (preset !== undefined) {
      defaults[param.name] = preset
    } else if (param.required) {
      defaults[param.name] = ''
    } else if (param.states) {
      defaults[param.name] =
        Object.keys(param.states).find(
          (s) => param.states[s].value === param.default,
        ) || ''
    } else {
      defaults[param.name] =
        param.default === undefined || param.default === null
          ? ''
          : String(param.default)
    }
  }
  values.value = defaults
  valuesChanged()
}

function setValue(name, value) {
  values.value[name] = value
  valuesChanged()
}

// Ask the server whether these values make the command hazardous, shortly
// after they stop changing
function valuesChanged() {
  serverHazard.value = null
  clearTimeout(hazardTimer)
  hazardTimer = setTimeout(checkHazard, 300)
}

function paramList() {
  const list = {}
  for (const param of params.value) {
    const value = values.value[param.name]
    if (value === '' || value === undefined) {
      if (param.required) throw new Error(`${param.name} is required`)
      continue
    }
    if (param.states || param.type === 'STRING' || param.type === 'BLOCK') {
      // States send their name, strings are sent as typed
      list[param.name] = param.states ? value : removeQuotes(String(value))
    } else {
      list[param.name] = convertToValue({
        val: String(value),
        type: param.type,
      })
    }
  }
  return list
}

async function checkHazard() {
  if (isScript.value || !command.value) return
  const { targetName, commandName } = props.panel.command
  const request = ++hazardRequest
  let result
  try {
    result = !!(await api.get_cmd_hazardous(
      targetName,
      commandName,
      paramList(),
      { 'Ignore-Errors': '500' },
    ))
  } catch {
    // A required value is missing or the check failed: go by the
    // definition rather than blocking sends
    result = hazardousFromDefinition()
  }
  // Ignore an answer for values that have since changed
  if (request === hazardRequest) serverHazard.value = result
}

function hazardousFromDefinition() {
  if (command.value?.hazardous) return true
  return params.value.some(
    (param) =>
      param.states && param.states[values.value[param.name]]?.hazardous,
  )
}

function startHold(event) {
  if (event.repeat || holding.value || sending.value || !ready.value) return
  holding.value = true
  holdTimer = setTimeout(() => {
    holding.value = false
    send(hazardous.value)
  }, holdMs.value)
}

function cancelHold() {
  if (!holding.value) return
  clearTimeout(holdTimer)
  holding.value = false
  status.value = `Released early, ${isScript.value ? 'script not started' : 'command not sent'}`
}

async function clickSend() {
  if (hazardous.value) {
    const description = command.value?.hazardous_description
    try {
      await dialog.confirm(
        `${props.panel.command.targetName} ${props.panel.command.commandName} is hazardous.` +
          (description ? ` ${description}.` : '') +
          ' Send it?',
        { okText: 'Send', cancelText: 'Cancel', okClass: 'error' },
      )
    } catch {
      status.value = 'Hazardous command not sent'
      return
    }
  }
  send(hazardous.value)
}

function send(confirmedHazardous) {
  return isScript.value ? runScript() : sendCommand(confirmedHazardous)
}

async function runScript() {
  sending.value = true
  scriptId.value = null
  try {
    const response = await Api.post(scriptRunUrl(props.panel.script), {
      data: { environment: [] },
    })
    scriptId.value = response.data
    status.value = `Started ${clock(Date.now(), timeZone.value)}`
    if (option(props.panel, 'OPEN_SCRIPT')) {
      window.open(`/tools/scriptrunner/${scriptId.value}`, '_blank')
    }
  } catch (error) {
    status.value = `Error: ${error.response?.data?.message || error.message || error}`
  } finally {
    sending.value = false
  }
}

async function sendCommand(confirmedHazardous) {
  const { targetName, commandName } = props.panel.command
  let list
  try {
    list = paramList()
  } catch (error) {
    status.value = error.message
    return
  }
  sending.value = true
  const method = confirmedHazardous ? 'cmd_no_hazardous_check' : 'cmd'
  try {
    await api[method](targetName, commandName, list, {
      'Ignore-Errors': '428 500',
    })
    status.value = `Sent ${targetName} ${commandName} at ${clock(Date.now(), timeZone.value)}`
  } catch (error) {
    handleError(error)
  } finally {
    sending.value = false
  }
}

function handleError(error) {
  const message = error.message || String(error)
  if (message.includes('CriticalCmdError')) {
    const vars = error.object?.data?.instance_variables || {}
    critical.value = {
      show: true,
      uuid: vars['@uuid'],
      cmdString: vars['@command']?.cmd_string,
      user: vars['@command']?.username,
    }
    status.value = 'Critical command queued for approval'
  } else if (message.includes('is Hazardous')) {
    // The server knows about hazards we didn't (e.g. a hazardous range)
    // serverHazard too, as it wins over the definition until the
    // values change
    status.value = `Hazardous: ${message}. Confirm and send again.`
    if (command.value) command.value.hazardous = true
    serverHazard.value = true
  } else {
    status.value = `Error: ${message}`
  }
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
