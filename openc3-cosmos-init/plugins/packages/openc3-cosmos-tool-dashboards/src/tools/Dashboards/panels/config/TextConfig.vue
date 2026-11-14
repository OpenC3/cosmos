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
    <div class="d-flex align-center mb-1">
      <div class="text-subtitle-2">Text</div>
      <v-spacer />
      <v-btn-toggle
        v-model="mode"
        mandatory
        density="compact"
        variant="outlined"
        divided
        class="db-toggle"
        data-test="text-config-mode"
      >
        <v-btn value="write" size="small">Write</v-btn>
        <v-btn value="preview" size="small">Preview</v-btn>
      </v-btn-toggle>
    </div>
    <div class="text-caption text-medium-emphasis mb-2">
      Written in markdown.
      <a
        href="https://www.markdownguide.org/basic-syntax/"
        target="_blank"
        rel="noopener noreferrer"
      >
        Markdown syntax guide
        <v-icon icon="mdi-open-in-new" size="12" />
      </a>
    </div>
    <v-textarea
      v-if="mode === 'write'"
      :model-value="text"
      placeholder="## Notes&#10;&#10;Check **TEMP1** before each collect."
      rows="8"
      auto-grow
      max-rows="20"
      variant="outlined"
      hide-details
      class="mono"
      data-test="text-config-input"
      @update:model-value="setText"
    />
    <!-- eslint-disable vue/no-v-html -- sanitized in renderMarkdown -->
    <div
      v-else-if="text"
      class="db-markdown border rounded pa-3"
      data-test="text-config-preview"
      v-html="html"
    />
    <!-- eslint-enable vue/no-v-html -->
    <div v-else class="text-caption text-medium-emphasis border rounded pa-3">
      Nothing to preview yet.
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import { option, withOption } from '../options'
import { renderMarkdown } from '../markdown'

// The panel dialog editor for a TEXT panel: its markdown, with a preview
const props = defineProps({
  panel: { type: Object, required: true },
})
const emit = defineEmits(['update'])

const mode = ref('write')
const text = computed(() => option(props.panel, 'TEXT') || '')
const html = computed(() =>
  mode.value === 'preview' ? renderMarkdown(text.value) : '',
)

function setText(value) {
  emit('update', { settings: withOption(props.panel, 'TEXT', value) })
}
</script>
