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
  <div id="messages" class="mt-2">
    <div v-if="showDebug" id="debug" class="pa-0">
      <v-row no-gutters>
        <v-btn
          color="primary"
          style="width: 100px"
          class="mr-4"
          text="Step"
          append-icon="mdi-step-forward"
          :disabled="!scriptId"
          data-test="step-button"
          @click="$emit('step')"
        />
        <v-text-field
          ref="debugInput"
          v-model="debug"
          class="mb-2"
          variant="outlined"
          density="compact"
          hide-details
          label="Debug"
          data-test="debug-text"
          @keydown="handleKeydown"
        />
      </v-row>
    </div>
    <script-log-messages
      id="log-messages"
      v-model="messages"
      @sort="$emit('message-sort-order', $event)"
    />
  </div>
</template>

<script setup>
import { ref, nextTick } from 'vue'
import ScriptLogMessages from '@/tools/scriptrunner/ScriptLogMessages.vue'

const props = defineProps({
  showDebug: {
    type: Boolean,
    default: false,
  },
  scriptId: {
    type: String,
    default: null,
  },
})

const messages = defineModel('messages', { type: Array, required: true })
const debug = defineModel('debug', { type: String, required: true })

const emit = defineEmits(['step', 'execute-debug', 'message-sort-order'])

const debugInput = ref(null)
const debugHistory = ref([])
const debugHistoryIndex = ref(0)

function handleKeydown(event) {
  if (event.key === 'Escape') {
    debug.value = ''
    debugHistoryIndex.value = debugHistory.value.length
  } else if (event.key === 'Enter') {
    if (props.debug && props.debug.trim()) {
      debugHistory.value.push(props.debug)
      debugHistoryIndex.value = debugHistory.value.length
      // Emit event for parent to handle the API call
      emit('execute-debug', props.debug)
      debug.value = ''
    }
  } else if (event.key === 'ArrowUp') {
    event.preventDefault()
    debugHistoryIndex.value -= 1
    if (debugHistoryIndex.value < 0) {
      debugHistoryIndex.value = debugHistory.value.length - 1
    }
    if (debugHistory.value[debugHistoryIndex.value]) {
      debug.value = debugHistory.value[debugHistoryIndex.value]
    }
  } else if (event.key === 'ArrowDown') {
    event.preventDefault()
    debugHistoryIndex.value += 1
    if (debugHistoryIndex.value >= debugHistory.value.length) {
      debugHistoryIndex.value = 0
    }
    if (debugHistory.value[debugHistoryIndex.value]) {
      debug.value = debugHistory.value[debugHistoryIndex.value]
    }
  }
}

function focus() {
  nextTick(() => {
    debugInput.value?.focus()
  })
}

defineExpose({
  focus,
})
</script>
