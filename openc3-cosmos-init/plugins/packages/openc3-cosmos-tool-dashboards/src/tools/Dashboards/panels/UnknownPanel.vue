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
    class="d-flex flex-column align-center justify-center ga-2 flex-grow-1 pa-4 text-center text-medium-emphasis"
    data-test="unknown-panel"
  >
    <v-icon icon="mdi-puzzle-remove-outline" size="28" />
    <div class="text-body-2">
      <span class="mono">{{ panel.originalType }}</span> panels aren't installed
    </div>
    <div class="text-caption">
      Install the plugin that provides it. The panel is kept as written.
    </div>
  </div>
</template>

<script>
// Stands in for a panel whose type no installed plugin provides
export default {
  props: {
    panel: { type: Object, required: true },
  },
  emits: ['level'],
}
</script>
