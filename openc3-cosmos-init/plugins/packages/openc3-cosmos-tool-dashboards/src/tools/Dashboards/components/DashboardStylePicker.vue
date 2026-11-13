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
  <v-menu :close-on-content-click="false" location="bottom start">
    <template #activator="{ props: activatorProps }">
      <button
        v-bind="activatorProps"
        type="button"
        class="picker-btn rounded-lg pa-0 border-0 bg-transparent cursor-pointer"
        aria-label="Dashboard icon and color"
        title="Dashboard icon and color"
        data-test="dashboard-style"
      >
        <dashboard-avatar :icon="style.icon" :color="style.color" :size="40" />
      </button>
    </template>
    <v-card class="pa-3" width="372">
      <div class="text-subtitle-2 mb-2">Icon</div>
      <div class="icon-grid mb-3">
        <v-btn
          v-for="icon in icons"
          :key="icon"
          :icon="icon"
          size="small"
          :variant="icon === style.icon ? 'tonal' : 'text'"
          :color="icon === style.icon ? style.color || 'secondary' : undefined"
          :aria-label="icon.replace('mdi-', '')"
          :aria-pressed="icon === style.icon"
          @click="update({ icon })"
        />
      </div>
      <div class="text-subtitle-2 mb-2">Color</div>
      <color-swatches
        :colors="colors"
        :model-value="style.color"
        :size="26"
        allow-default
        default-above
        class="mb-3"
        @update:model-value="(color) => update({ color })"
      />
      <!-- Any other color -->
      <v-color-picker
        :model-value="style.color || pickerStart"
        mode="hex"
        :modes="['hex']"
        hide-inputs
        elevation="0"
        width="348"
        @update:model-value="(color) => update({ color: color.slice(0, 7) })"
      />
    </v-card>
  </v-menu>
</template>

<script setup>
import { computed } from 'vue'
import { useTheme } from 'vuetify'
import ColorSwatches from './ColorSwatches.vue'
import DashboardAvatar from './DashboardAvatar.vue'
import {
  DASHBOARD_COLORS,
  DASHBOARD_ICONS,
  dashboardStyle,
  withDashboardStyle,
} from '../dashboardStyle'

// Pick a dashboard's icon and color; emits the dashboard's new settings
const props = defineProps({
  settings: { type: Object, required: true },
})
const emit = defineEmits(['update'])

const icons = DASHBOARD_ICONS
const colors = DASHBOARD_COLORS

const style = computed(() => dashboardStyle(props.settings))
const theme = useTheme()
// The wheel starts at the default color, the theme's secondary
const pickerStart = computed(
  () => theme.current.value.colors.secondary || colors[0],
)

function update(change) {
  emit(
    'update',
    withDashboardStyle(props.settings, { ...style.value, ...change }),
  )
}
</script>

<style scoped>
.picker-btn:focus-visible {
  outline: 2px solid rgb(var(--v-theme-primary));
  outline-offset: 2px;
}
.icon-grid {
  display: grid;
  grid-template-columns: repeat(8, 1fr);
  gap: 2px;
}
</style>
