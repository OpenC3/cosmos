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
  <!-- eslint-disable vue/no-v-html -- sanitized in renderMarkdown -->
  <div
    v-if="html"
    class="db-markdown flex-grow-1 min-h-0 overflow-auto px-4 pb-3 pt-1"
    data-test="text-panel"
    v-html="html"
  />
  <!-- eslint-enable vue/no-v-html -->
  <div v-else class="pa-4 text-caption text-medium-emphasis">
    No text. Configure this panel to write some.
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { panelProps, usePanel } from './panelBase'
import { option } from './options'
import { renderMarkdown } from './markdown'

// Notes, procedures, links and headings written in markdown. Shows no
// telemetry, so it reports no status.
const props = defineProps(panelProps)
usePanel(props)

const html = computed(() => {
  const text = option(props.panel, 'TEXT')
  return text ? renderMarkdown(text) : ''
})
</script>
