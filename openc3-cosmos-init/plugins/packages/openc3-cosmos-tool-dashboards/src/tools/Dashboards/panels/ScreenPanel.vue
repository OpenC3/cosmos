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
  <!-- Inert while editing: values keep updating, but clicks arrange panels
       instead of pressing the screen's buttons -->
  <div
    class="screen-panel flex-grow-1 overflow-auto"
    :inert="isEditing"
    data-test="screen-panel"
  >
    <div
      v-if="message"
      class="d-flex align-center justify-center h-100 pa-4 text-body-2 text-medium-emphasis text-center"
    >
      {{ message }}
    </div>
    <!-- load() clears the definition first, so a saved screen remounts -->
    <openc3-screen
      v-else
      ref="screen"
      :key="screenKey"
      :target="panel.screen.targetName"
      :screen="panel.screen.screenName"
      :definition="definition"
      :time-zone="timeZone"
      :playback-mode="isPlayback ? 'playback' : 'realtime'"
      :playback-date-time="playbackTime"
      :show-close="false"
      inline
      @vue:mounted="trackLevel"
    />
  </div>
</template>

<script>
import { Openc3Screen } from '@openc3/vue-common/components'
import panelBase from './panelBase'
import { stateToLevel, worstLevel } from '../status'
import { loadScreen, screenKey, screenRevisions } from './screens'

// A Telemetry Viewer screen inside a panel. The screen polls its own items
// (Openc3Screen does) and follows playback. Its definition is edited from
// the panel dialog (ScreenConfig); saving there reloads it here.
export default {
  components: { Openc3Screen },
  mixins: [panelBase],
  data() {
    return { definition: null, error: null, screenLevel: null }
  },
  computed: {
    screenKey() {
      return screenKey(this.panel.screen)
    },
    revision() {
      return screenRevisions[this.screenKey] || 0
    },
    message() {
      if (!this.screenKey) return 'Pick a screen'
      if (this.error) return this.error
      return this.definition === null ? 'Loading screen…' : null
    },
    // Worst limits state of the items on the screen
    panelLevel() {
      return this.screenLevel
    },
  },
  watch: {
    screenKey: {
      immediate: true,
      handler() {
        this.load()
      },
    },
    revision() {
      this.load()
    },
  },
  methods: {
    async load() {
      this.definition = null
      this.error = null
      this.screenLevel = null
      const key = this.screenKey
      if (!key) return
      try {
        const text = await loadScreen(this.panel.screen)
        if (key === this.screenKey) this.definition = text
      } catch {
        if (key === this.screenKey) this.error = `Screen ${key} not found`
      }
    },
    trackLevel() {
      this.stopLevel?.()
      const screen = this.$refs.screen
      if (!screen) return
      this.stopLevel = this.$watch(
        () =>
          worstLevel(
            Object.values(screen.screenValues).map((value) =>
              stateToLevel(value?.[1]),
            ),
          ),
        (level) => {
          this.screenLevel = level
        },
        { immediate: true },
      )
    },
    // Screen buttons that open other screens open them in Telemetry Viewer
    showScreen(target, screen) {
      window.open(`/tools/tlmviewer/${target}/${screen}`, '_blank')
    },
    closeScreenByName() {},
    closeAll() {},
  },
}
</script>

<style scoped>
/* Screens keep the COSMOS font, not the dashboard's */
.screen-panel {
  font-family: 'Open Sans', 'Helvetica Neue', sans-serif;
  font-size: 14px;
}
</style>
