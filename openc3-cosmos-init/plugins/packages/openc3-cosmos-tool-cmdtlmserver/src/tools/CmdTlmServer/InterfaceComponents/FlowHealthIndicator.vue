<!-- Copyright 2026 OpenC3, Inc. All Rights Reserved. See LICENSE.md. -->

<template>
  <button
    type="button"
    class="flow-health nodrag nopan"
    :class="`flow-health--${health.state}`"
    :title="`${health.label}. Click for processing metrics.`"
    :aria-label="`${name}: ${health.label}. View processing metrics`"
    data-test="flow-health"
    @click.stop="$emit('details')"
  >
    <v-icon size="14" :color="health.state === 'ok' ? 'success' : undefined">
      {{ health.icon }}
    </v-icon>
    {{ health.state === 'ok' ? 'View metrics' : health.label }}
    <v-icon size="14">mdi-chevron-right</v-icon>
  </button>
</template>

<script setup>
defineProps({
  health: { type: Object, required: true },
  name: { type: String, required: true },
})
defineEmits(['details'])
</script>

<style scoped>
.flow-health {
  position: absolute;
  bottom: 4px;
  left: 50%;
  transform: translateX(-50%);
  display: flex;
  align-items: center;
  gap: 3px;
  padding: 0 6px;
  border-radius: 4px;
  white-space: nowrap;
  font-size: 11px;
  line-height: 16px;
  cursor: pointer;
  color: #374151;
  background: #f3f4f6;
}
.flow-health--warning,
.flow-health--stale,
.flow-health--unavailable {
  background: #fff3cd;
  color: #713f12;
}
.flow-health--critical {
  background: #fee2e2;
  color: #991b1b;
}
.flow-health:focus-visible {
  outline: 2px solid #1d85e1;
  outline-offset: 2px;
}
</style>
