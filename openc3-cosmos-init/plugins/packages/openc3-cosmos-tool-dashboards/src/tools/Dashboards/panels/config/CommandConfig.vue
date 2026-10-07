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
        vertical
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
        default.
      </div>
      <div class="d-flex flex-column ga-2">
        <v-select
          v-for="param in params.filter((p) => p.states)"
          :key="param.name"
          :model-value="panel.parameters[param.name] ?? null"
          :items="Object.keys(param.states)"
          :label="param.name"
          clearable
          density="compact"
          variant="outlined"
          hide-details
          @update:model-value="(value) => setParameter(param.name, value)"
        />
        <v-text-field
          v-for="param in params.filter((p) => !p.states)"
          :key="param.name"
          :model-value="panel.parameters[param.name] ?? ''"
          :label="param.name"
          :suffix="param.units"
          :placeholder="
            param.default === undefined ? '' : String(param.default)
          "
          density="compact"
          variant="outlined"
          hide-details
          @update:model-value="(value) => setParameter(param.name, value)"
        />
      </div>
    </template>
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'
import { loadCommandParams } from '../commandParams'
import {
  ScriptChooser,
  TargetPacketItemChooser,
} from '@openc3/vue-common/components'

// What a COMMAND panel sends: a command with preset parameters, or a script.
// How it confirms is a panel option (see registry.js).
export default {
  components: { ScriptChooser, TargetPacketItemChooser },
  props: {
    panel: { type: Object, required: true },
  },
  emits: ['update'],
  data() {
    return { params: [], scriptMode: !!this.panel.script }
  },
  computed: {
    mode() {
      return this.panel.script || this.scriptMode ? 'script' : 'command'
    },
  },
  watch: {
    'panel.command': {
      immediate: true,
      handler() {
        this.loadParams()
      },
    },
  },
  methods: {
    setMode(mode) {
      this.scriptMode = mode === 'script'
      if (mode === 'command' && this.panel.script) {
        this.$emit('update', { script: null })
      }
    },
    selectCommand({ targetName, packetName }) {
      this.$emit('update', {
        command: { targetName, commandName: packetName },
        script: null,
        parameters: {},
      })
    },
    async loadParams() {
      this.params = []
      if (!this.panel.command) return
      const { targetName, commandName } = this.panel.command
      const { params } = await loadCommandParams(
        new OpenC3Api(),
        targetName,
        commandName,
      )
      this.params = params
    },
    setParameter(name, value) {
      const parameters = { ...this.panel.parameters }
      if (value === null || value === '') {
        delete parameters[name]
      } else {
        parameters[name] = value
      }
      this.$emit('update', { parameters })
    },
  },
}
</script>
