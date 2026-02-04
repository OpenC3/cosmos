<!--
# Copyright 2026, OpenC3, Inc.
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
  <div id="sr-controls">
    <v-row no-gutters justify="space-between">
      <v-icon v-if="showDisconnect" class="mt-2" color="red">
        mdi-connection
      </v-icon>
      <div class="d-flex align-center mr-1">
        <v-tooltip :open-delay="600" location="top">
          <template #activator="{ props: activatorProps }">
            <v-btn
              v-if="!scriptId"
              v-bind="activatorProps"
              icon="mdi-cached"
              variant="text"
              density="compact"
              :disabled="filename === newFilename"
              aria-label="Reload File"
              @click="$emit('reload-file')"
            />
            <v-btn
              v-else
              v-bind="activatorProps"
              icon="mdi-arrow-left"
              variant="text"
              density="compact"
              @click="$emit('back-to-new-script')"
            />
          </template>
          <span v-if="!scriptId"> Reload File </span>
          <span v-else> Back to New Script </span>
        </v-tooltip>
      </div>
      <v-tooltip
        location="bottom"
        :text="filenameSelect"
        :disabled="!filenameSelect || filenameSelect.length <= 45"
      >
        <template #activator="{ props: activatorProps }">
          <div v-bind="activatorProps" style="width: 32rem">
            <v-select
              id="filename"
              :model-value="filenameSelect"
              :items="fileList"
              :disabled="fileList.length <= 1"
              label="Filename"
              data-test="filename"
              density="compact"
              variant="outlined"
              hide-details
              @update:model-value="$emit('file-name-changed', $event)"
            />
          </div>
        </template>
      </v-tooltip>
      <v-text-field
        :model-value="scriptId"
        label="Script ID"
        data-test="id"
        class="shrink ml-2 script-state"
        style="max-width: 100px"
        density="compact"
        variant="outlined"
        readonly
        hide-details
      />
      <v-text-field
        :model-value="stateTimer"
        label="Script State"
        data-test="state"
        :class="['shrink', 'ml-2', 'script-state', stateColorClass]"
        style="max-width: 120px"
        density="compact"
        variant="outlined"
        readonly
        hide-details
      />
      <v-progress-circular
        v-if="state === 'Connecting...'"
        :size="40"
        class="mx-2"
        indeterminate
        color="primary"
      />
      <div v-else style="width: 40px; height: 40px" class="mx-2"></div>

      <v-spacer />
      <div v-if="startOrGoButton === 'Start'">
        <v-tooltip v-if="overridesCount > 0" :open-delay="600" location="top">
          <template #activator="{ props: activatorProps }">
            <v-btn
              v-bind="activatorProps"
              class="mr-4"
              icon
              variant="text"
              density="compact"
              data-test="tlm-override-button"
              aria-label="TLM Overrides"
              @click="$emit('toggle-overrides')"
            >
              <v-badge
                :content="overridesCount > 99 ? '99+' : overridesCount"
                floating
                color="primary"
              >
                <v-icon icon="mdi-application-cog-outline" />
              </v-badge>
            </v-btn>
          </template>
          <span> TLM Overrides ({{ overridesCount }}) </span>
        </v-tooltip>
        <v-tooltip :open-delay="600" location="top">
          <template #activator="{ props: activatorProps }">
            <v-btn
              v-bind="activatorProps"
              class="mr-2"
              icon
              variant="text"
              density="compact"
              :disabled="envDisabled"
              data-test="env-button"
              aria-label="Script Environment"
              @click="$emit('toggle-environment')"
            >
              <v-badge :model-value="environmentModified" floating dot>
                <v-icon icon="mdi-application-variable" />
              </v-badge>
            </v-btn>
          </template>
          <span>
            Script Environment
            <template v-if="environmentModified"> (modified) </template>
          </span>
        </v-tooltip>
        <v-btn
          class="mx-1"
          color="primary"
          text="Start"
          data-test="start-button"
          :disabled="startOrGoDisabled || !executeUser"
          :hidden="suiteRunner"
          @click="$emit('start')"
        />
      </div>
      <div v-else>
        <v-btn
          color="primary"
          class="mr-2"
          text="Go"
          :disabled="startOrGoDisabled"
          data-test="go-button"
          @click="$emit('go')"
        />
        <v-btn
          color="primary"
          class="mr-2"
          :text="pauseOrRetryButton"
          :disabled="pauseOrRetryDisabled"
          data-test="pause-retry-button"
          @click="$emit('pause-or-retry')"
        />
        <v-btn
          color="primary"
          text="Stop"
          data-test="stop-button"
          :disabled="stopDisabled"
          @click="$emit('stop')"
        />
      </div>
    </v-row>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  showDisconnect: {
    type: Boolean,
    default: false,
  },
  scriptId: {
    type: String,
    default: null,
  },
  filename: {
    type: String,
    required: true,
  },
  newFilename: {
    type: String,
    required: true,
  },
  fileList: {
    type: Array,
    required: true,
  },
  waitingTime: {
    type: Number,
    required: true,
  },
  state: {
    type: String,
    required: true,
  },
  startOrGoButton: {
    type: String,
    required: true,
  },
  startOrGoDisabled: {
    type: Boolean,
    default: false,
  },
  envDisabled: {
    type: Boolean,
    default: false,
  },
  pauseOrRetryButton: {
    type: String,
    required: true,
  },
  pauseOrRetryDisabled: {
    type: Boolean,
    default: false,
  },
  stopDisabled: {
    type: Boolean,
    default: false,
  },
  overridesCount: {
    type: Number,
    default: 0,
  },
  environmentModified: {
    type: Boolean,
    default: false,
  },
  executeUser: {
    type: Boolean,
    default: true,
  },
  suiteRunner: {
    type: Boolean,
    default: false,
  },
})

defineEmits([
  'reload-file',
  'back-to-new-script',
  'file-name-changed',
  'toggle-overrides',
  'toggle-environment',
  'start',
  'go',
  'pause-or-retry',
  'stop',
])

const filenameSelect = defineModel({ type: String, required: true })

const stateTimer = computed(() => {
  if (props.state === 'waiting' || props.state === 'paused') {
    return `${props.state} ${props.waitingTime}s`
  }
  // Map completed_errors to completed for display
  // it will be colored via the stateColorClass
  if (props.state === 'completed_errors') {
    return 'completed'
  }
  return props.state
})

const stateColorClass = computed(() => {
  // All possible states: spawning, init, running, paused, waiting, breakpoint,
  // error, crashed, stopped, completed, completed_errors, killed
  if (['error', 'crashed', 'killed'].includes(props.state)) {
    return 'script-state-red'
  } else if (props.state === 'completed_errors') {
    return 'script-state-orange'
  } else if (props.state === 'completed') {
    return 'script-state-green'
  } else {
    return ''
  }
})
</script>

<style scoped>
#sr-controls {
  margin: 0px;
}
</style>

<style scoped>
.script-state :deep(.v-field) {
  background-color: var(--color-background-base-default);
}

.script-state :deep(input) {
  text-transform: capitalize;
}

/* Taken from the various status-symbol-color-fill classes
   on https://www.astrouxds.com/design-tokens/component/ */
.script-state-red :deep(input) {
  color: #ff3838 !important;
}

.script-state-orange :deep(input) {
  color: #ffb302 !important;
}

.script-state-green :deep(input) {
  color: #56f000 !important;
}
</style>
