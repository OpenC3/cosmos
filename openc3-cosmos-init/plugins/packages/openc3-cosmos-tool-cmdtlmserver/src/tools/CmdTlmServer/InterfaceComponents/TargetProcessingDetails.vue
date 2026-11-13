<!-- Copyright 2026 OpenC3, Inc. All Rights Reserved. See LICENSE.md. -->

<template>
  <v-card
    max-height="80vh"
    class="d-flex flex-column"
    data-test="target-processing-details"
  >
    <v-card-title class="d-flex align-center flex-shrink-0">
      Target Processing: {{ name }}
      <v-btn
        :icon="paused ? 'mdi-play' : 'mdi-pause'"
        :aria-label="paused ? 'Resume metrics' : 'Pause metrics'"
        variant="text"
        data-test="pause"
        @click="togglePause"
      />
      <v-spacer />
      <v-btn
        icon="mdi-close"
        aria-label="Close"
        variant="text"
        data-test="close"
        @click="$emit('close')"
      />
    </v-card-title>
    <v-card-text class="overflow-y-auto pa-0">
      <FlowMetricsPanel :health="paused ? snapshot : health" />
    </v-card-text>
  </v-card>
</template>

<script setup>
import { ref } from 'vue'
import FlowMetricsPanel from './FlowMetricsPanel.vue'

const props = defineProps({
  name: { type: String, required: true },
  health: { type: Object, required: true },
})
defineEmits(['close'])
const paused = ref(false)
const snapshot = ref(null)
function togglePause() {
  snapshot.value = props.health
  paused.value = !paused.value
}
</script>
