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
    <div class="text-subtitle-2 mb-1">Screen</div>
    <div class="text-caption text-medium-emphasis mb-3">
      A Telemetry Viewer screen, shown as it is in Telemetry Viewer
    </div>
    <div class="d-flex ga-3">
      <v-autocomplete
        :model-value="target"
        :items="Object.keys(screens)"
        label="Target"
        density="compact"
        variant="outlined"
        hide-details
        style="max-width: 240px"
        data-test="config-screen-target"
        @update:model-value="selectTarget"
      />
      <v-autocomplete
        :model-value="panel.screen?.screenName"
        :items="screens[target] || []"
        label="Screen"
        density="compact"
        variant="outlined"
        hide-details
        :disabled="!target"
        data-test="config-screen-name"
        @update:model-value="selectScreen"
      />
    </div>
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  props: {
    panel: { type: Object, required: true },
  },
  emits: ['update'],
  data() {
    return {
      // TARGET => [SCREEN, ...]
      screens: {},
      target: this.panel.screen?.targetName || null,
    }
  },
  async created() {
    const response = await Api.get('/openc3-api/screens')
    const screens = {}
    for (const path of response.data) {
      const [target, , file] = path.split('/')
      ;(screens[target] ||= []).push(file.replace(/\.txt$/, '').toUpperCase())
    }
    this.screens = screens
  },
  methods: {
    selectTarget(target) {
      this.target = target
      // A target with one screen needs no second pick
      const names = this.screens[target] || []
      this.selectScreen(names.length === 1 ? names[0] : null)
    },
    selectScreen(screenName) {
      this.$emit('update', {
        screen: screenName ? { targetName: this.target, screenName } : null,
      })
    },
  },
}
</script>
