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
  <v-card border flat class="rounded-lg" aria-label="Dashboard definition">
    <div class="d-flex flex-wrap align-center ga-2 px-3 py-2 border-b">
      <v-icon
        icon="mdi-file-document-outline"
        size="16"
        class="text-medium-emphasis"
      />
      <span class="mono text-caption text-no-wrap">{{ path }}</span>
      <v-spacer />
      <span class="text-caption text-medium-emphasis">
        {{ hint }}
      </span>
    </div>
    <v-textarea
      :model-value="value"
      class="mono code"
      variant="plain"
      :rows="rows"
      no-resize
      spellcheck="false"
      hide-details
      data-test="dashboard-code"
      @focus="focused = true"
      @blur="blur"
      @update:model-value="changed"
    />
    <div v-if="errors.length" class="px-3 pb-3 d-flex flex-column ga-1">
      <v-alert
        v-for="(error, index) in errors"
        :key="index"
        type="error"
        density="compact"
        variant="tonal"
        data-test="dashboard-code-error"
      >
        Line {{ error.lineNumber }}: {{ error.message }}
        <div v-if="error.usage" class="mono text-caption">
          Usage: {{ error.usage }}
        </div>
      </v-alert>
    </div>
  </v-card>
</template>

<script setup>
import { computed, nextTick, onUnmounted, ref } from 'vue'
import { parseDashboard } from '../dashboardParser'

const APPLY_DELAY_MS = 500

// Live DASHBOARD text. Typing re-parses after a short pause and applies the
// result when it has no errors, so a half typed line never wipes out the
// layout. While the text has focus the grid doesn't overwrite it.
const props = defineProps({
  text: { type: String, required: true },
  path: { type: String, default: '' },
  hint: {
    type: String,
    default: 'Edits here and on the grid change the same lines',
  },
  // parseDashboard for a whole dashboard, parsePanel for one panel
  parse: { type: Function, default: parseDashboard },
  rows: { type: Number, default: 18 },
})
const emit = defineEmits(['apply'])

const focused = ref(false)
// What's typed: { base, value, errors }, with `base` the text it was typed
// over and `errors` from the last parse (null until then)
const draft = ref(null)
let timer = null

// Typed text shows while focused, and after blur until the text changes
// (e.g. an edit on the grid replaces text left with errors)
const showingDraft = computed(
  () => !!draft.value && (focused.value || draft.value.base === props.text),
)
const value = computed(() =>
  showingDraft.value ? draft.value.value : props.text,
)
// The text can come in with problems (a file as it was written)
const errors = computed(() =>
  showingDraft.value && draft.value.errors
    ? draft.value.errors
    : props.parse(props.text).errors,
)

onUnmounted(() => {
  clearTimeout(timer)
})

function changed(typed) {
  draft.value = {
    base: props.text,
    value: typed,
    errors: draft.value?.errors ?? null,
  }
  clearTimeout(timer)
  timer = setTimeout(apply, APPLY_DELAY_MS)
}

function apply() {
  if (!draft.value) return
  const { model, errors: found } = props.parse(draft.value.value)
  draft.value.errors = found
  if (!found.length) emit('apply', model)
}

function blur() {
  focused.value = false
  clearTimeout(timer)
  apply()
  if (!draft.value) return
  if (draft.value.errors.length) {
    // Kept over the text it can't replace, until that text changes
    draft.value.base = props.text
    return
  }
  // Show the canonical text once the applied edit comes back as `text`
  nextTick(() => {
    draft.value = null
  })
}
</script>

<style scoped>
/* Vuetify fades the top of a textarea; code needs every line fully visible */
.code :deep(.v-field__input) {
  mask-image: none;
  -webkit-mask-image: none;
}
.code :deep(textarea) {
  font-family: 'IBM Plex Mono', ui-monospace, monospace;
  font-size: 12px;
  line-height: 20px;
  white-space: pre;
  overflow: auto;
  padding: 8px 12px;
}
</style>
