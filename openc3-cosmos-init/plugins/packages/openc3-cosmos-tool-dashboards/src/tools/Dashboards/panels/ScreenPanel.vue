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
    />
  </div>
</template>

<script setup>
import { computed, ref, useTemplateRef, watch } from 'vue'
import { Openc3Screen } from '@openc3/vue-common/components'
import { panelProps, usePanel } from './panelBase'
import { stateToLevel, worstLevel } from '../status'
import { loadScreen, screenKey as keyOf, screenRevisions } from './screens'

// A Telemetry Viewer screen inside a panel. The screen polls its own items
// (Openc3Screen does) and follows playback. Its definition is edited from
// the panel dialog (ScreenConfig); saving there reloads it here.
const props = defineProps(panelProps)

const { timeZone, isEditing, isPlayback, playbackTime } = usePanel(
  props,
  // Worst limits state of the items on the screen
  { panelLevel: () => screenLevel.value },
)

const screen = useTemplateRef('screen')
const definition = ref(null)
const error = ref(null)

const screenKey = computed(() => keyOf(props.panel.screen))
const revision = computed(() => screenRevisions[screenKey.value] || 0)
const message = computed(() => {
  if (!screenKey.value) return 'Pick a screen'
  if (error.value) return error.value
  return definition.value === null ? 'Loading screen…' : null
})
// Null while no screen is shown (load() clears the definition first)
const screenLevel = computed(() => {
  const values = screen.value?.screenValues
  if (!values) return null
  return worstLevel(
    Object.values(values).map((value) => stateToLevel(value?.[1])),
  )
})

// Fetches the definition: the screen picked comes from the panel prop and a
// save bumps the revision from ScreenConfig, with no event here to hook
watch([screenKey, revision], load, { immediate: true })

async function load() {
  definition.value = null
  error.value = null
  const key = screenKey.value
  if (!key) return
  try {
    const text = await loadScreen(props.panel.screen)
    if (key === screenKey.value) definition.value = text
  } catch {
    if (key === screenKey.value) error.value = `Screen ${key} not found`
  }
}

// Openc3Screen calls these on its $parent. Screen buttons that open other
// screens open them in Telemetry Viewer.
function showScreen(target, screenName) {
  window.open(
    `/tools/tlmviewer/${encodeURIComponent(target)}/${encodeURIComponent(screenName)}`,
    '_blank',
  )
}
function closeScreenByName() {}
function closeAll() {}

defineExpose({ showScreen, closeScreenByName, closeAll })
</script>

<style scoped>
/* Screens keep the COSMOS font, not the dashboard's */
.screen-panel {
  font-family: 'Open Sans', 'Helvetica Neue', sans-serif;
  font-size: 14px;
}
</style>
