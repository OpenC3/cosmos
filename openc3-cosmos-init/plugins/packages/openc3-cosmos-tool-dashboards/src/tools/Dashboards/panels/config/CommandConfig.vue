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
  <div>
    <v-btn-toggle
      :model-value="mode"
      mandatory
      density="compact"
      variant="outlined"
      divided
      class="mb-2"
      data-test="config-mode"
      @update:model-value="setMode"
    >
      <v-btn value="command" prepend-icon="mdi-send-outline">Command</v-btn>
      <v-btn value="script" prepend-icon="mdi-script-text-outline"
        >Script</v-btn
      >
    </v-btn-toggle>
    <template v-if="mode === 'script'">
      <script-chooser
        :model-value="panel.script"
        data-test="config-script"
        @file="
          (script) =>
            script && $emit('update', { script, command: null, parameters: {} })
        "
      />
    </template>
    <template v-else>
      <target-packet-item-chooser
        mode="cmd"
        button-text="Select"
        @add-item="selectCommand"
      />
      <div
        v-if="panel.command"
        class="mono text-body-2 mb-4"
        data-test="config-command"
      >
        {{ panel.command.targetName }} {{ panel.command.commandName }}
      </div>
    </template>
    <template v-if="mode === 'command' && params.length">
      <div class="text-subtitle-2 mb-1">Preset parameters</div>
      <div class="text-caption text-medium-emphasis mb-3">
        Values shown in the panel when it opens. Leave blank to use the command
        default. Hidden parameters get no field in the panel and send their
        preset or default.
      </div>
      <div class="d-flex flex-column ga-2">
        <div
          v-for="param in params"
          :key="param.name"
          class="d-flex align-center ga-2"
        >
          <v-select
            v-if="param.states"
            :model-value="panel.parameters[param.name] ?? null"
            :items="Object.keys(param.states)"
            :label="param.name"
            clearable
            density="compact"
            variant="outlined"
            hide-details
            :data-test="`config-param-${param.name}`"
            @update:model-value="(value) => setParameter(param.name, value)"
          />
          <v-text-field
            v-else
            :model-value="panel.parameters[param.name] ?? ''"
            :label="param.name"
            :suffix="param.units"
            :placeholder="
              param.default === undefined ? '' : String(param.default)
            "
            density="compact"
            variant="outlined"
            hide-details
            :data-test="`config-param-${param.name}`"
            @update:model-value="(value) => setParameter(param.name, value)"
          />
          <v-btn
            :icon="isHidden(param) ? 'mdi-eye-off-outline' : 'mdi-eye-outline'"
            :color="isHidden(param) ? undefined : 'primary'"
            variant="text"
            size="small"
            :aria-pressed="isHidden(param)"
            :aria-label="`${isHidden(param) ? 'Show' : 'Hide'} ${param.name} in the panel`"
            :title="`${isHidden(param) ? 'Show' : 'Hide'} in the panel`"
            :data-test="`config-hide-${param.name}`"
            @click="toggleHidden(param)"
          />
        </div>
        <div
          v-if="hiddenUnset.length"
          class="text-caption text-warning"
          data-test="config-hidden-required"
        >
          {{ hiddenUnset.join(', ') }}
          {{ hiddenUnset.length === 1 ? 'is' : 'are' }} required: preset a value
          or the panel can't send
        </div>
      </div>
    </template>
  </div>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { OpenC3Api } from '@openc3/js-common/services'
import { loadCommandParams, unsetRequired } from '../commandParams'
import { option, withOption } from '../options'
import {
  ScriptChooser,
  TargetPacketItemChooser,
} from '@openc3/vue-common/components'

// What a COMMAND panel sends: a command with preset parameters, or a script.
// How it confirms is a panel option (see registry.js).
const props = defineProps({
  panel: { type: Object, required: true },
})
const emit = defineEmits(['update'])

const params = ref([])
const scriptMode = ref(!!props.panel.script)

const mode = computed(() =>
  props.panel.script || scriptMode.value ? 'script' : 'command',
)
const hidden = computed(() => option(props.panel, 'HIDE'))
// Hidden required parameters with nothing preset
const hiddenUnset = computed(() =>
  unsetRequired(params.value, props.panel.parameters, hidden.value),
)

function setMode(newMode) {
  scriptMode.value = newMode === 'script'
  if (newMode === 'command' && props.panel.script) {
    emit('update', { script: null })
  }
}

function selectCommand({ targetName, packetName }) {
  emit('update', {
    command: { targetName, commandName: packetName },
    script: null,
    parameters: {},
    settings: withOption(props.panel, 'HIDE', []),
  })
}

function isHidden(param) {
  return hidden.value.includes(param.name)
}

function toggleHidden(param) {
  const names = isHidden(param)
    ? hidden.value.filter((name) => name !== param.name)
    : [...hidden.value, param.name]
  emit('update', { settings: withOption(props.panel, 'HIDE', names) })
}

async function loadParams() {
  params.value = []
  if (!props.panel.command) return
  const { targetName, commandName } = props.panel.command
  try {
    const loaded = await loadCommandParams(
      new OpenC3Api(),
      targetName,
      commandName,
    )
    // Ignore an answer for a command that has since been replaced
    const current = props.panel.command
    if (
      current?.targetName === targetName &&
      current?.commandName === commandName
    ) {
      params.value = loaded.params
    }
  } catch (error) {
    console.error('Dashboards command parameters failed to load:', error)
  }
}

function setParameter(name, value) {
  const parameters = { ...props.panel.parameters }
  if (value === null || value === '') {
    delete parameters[name]
  } else {
    parameters[name] = value
  }
  emit('update', { parameters })
}

// Fetches the parameters of whichever command the panel has, however it
// got it (picked here, or edited in the Code tab)
watch(() => props.panel.command, loadParams, { immediate: true })
</script>
