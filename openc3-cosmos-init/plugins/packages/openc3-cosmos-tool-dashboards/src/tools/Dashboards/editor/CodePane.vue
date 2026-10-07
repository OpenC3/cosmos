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
      v-model="value"
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

<script>
import { parseDashboard } from '../dashboardParser'

const APPLY_DELAY_MS = 500

// Live DASHBOARD text. Typing re-parses after a short pause and applies the
// result when it has no errors, so a half typed line never wipes out the
// layout. While the text has focus the grid doesn't overwrite it.
export default {
  props: {
    text: { type: String, required: true },
    path: { type: String, default: '' },
    hint: {
      type: String,
      default: 'Edits here and on the grid change the same lines',
    },
    // parseDashboard for a whole dashboard, parsePanel for one panel
    parse: { type: Function, default: parseDashboard },
    rows: { type: Number, default: 18 },
  },
  emits: ['apply'],
  data() {
    return { value: this.text, errors: [], focused: false, timer: null }
  },
  watch: {
    text(text) {
      if (!this.focused) this.value = text
    },
  },
  unmounted() {
    clearTimeout(this.timer)
  },
  methods: {
    changed() {
      clearTimeout(this.timer)
      this.timer = setTimeout(() => this.apply(), APPLY_DELAY_MS)
    },
    apply() {
      const { model, errors } = this.parse(this.value)
      this.errors = errors
      if (!errors.length) this.$emit('apply', model)
    },
    blur() {
      this.focused = false
      clearTimeout(this.timer)
      this.apply()
      // Show the canonical text once the applied edit comes back as `text`
      this.$nextTick(() => {
        if (!this.errors.length) this.value = this.text
      })
    },
  },
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
