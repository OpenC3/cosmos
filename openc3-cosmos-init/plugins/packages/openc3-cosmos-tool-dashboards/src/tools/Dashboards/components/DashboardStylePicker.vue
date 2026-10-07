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
    <template #activator="{ props }">
      <button
        v-bind="props"
        type="button"
        class="picker-btn rounded-lg"
        aria-label="Dashboard icon and color"
        title="Dashboard icon and color"
        data-test="dashboard-style"
      >
        <dashboard-avatar :icon="style.icon" :color="style.color" :size="40" />
      </button>
    </template>
    <v-card class="pa-3" width="316">
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
      <div class="d-flex flex-wrap ga-2">
        <button
          type="button"
          :class="['swatch default rounded', { selected: !style.color }]"
          aria-label="Default color"
          title="Default"
          @click="update({ color: null })"
        />
        <button
          v-for="color in colors"
          :key="color"
          type="button"
          :class="['swatch rounded', { selected: color === style.color }]"
          :style="{ background: color }"
          :aria-label="color"
          @click="update({ color })"
        />
      </div>
    </v-card>
  </v-menu>
</template>

<script>
import DashboardAvatar from './DashboardAvatar.vue'
import {
  DASHBOARD_COLORS,
  DASHBOARD_ICONS,
  dashboardStyle,
  withDashboardStyle,
} from '../dashboardStyle'

// Pick a dashboard's icon and color; emits the dashboard's new settings
export default {
  components: { DashboardAvatar },
  props: {
    settings: { type: Object, required: true },
  },
  emits: ['update'],
  data() {
    return { icons: DASHBOARD_ICONS, colors: DASHBOARD_COLORS }
  },
  computed: {
    style() {
      return dashboardStyle(this.settings)
    },
  },
  methods: {
    update(change) {
      this.$emit(
        'update',
        withDashboardStyle(this.settings, { ...this.style, ...change }),
      )
    },
  },
}
</script>

<style scoped>
.picker-btn {
  border: 0;
  background: none;
  padding: 0;
  cursor: pointer;
}
.picker-btn:focus-visible {
  outline: 2px solid rgb(var(--v-theme-primary));
  outline-offset: 2px;
}
.icon-grid {
  display: grid;
  grid-template-columns: repeat(8, 1fr);
  gap: 2px;
}
.swatch {
  width: 26px;
  height: 26px;
  cursor: pointer;
  border: 2px solid transparent;
}
.swatch.default {
  background: rgb(var(--v-theme-secondary));
}
.swatch.selected {
  border-color: rgb(var(--v-theme-on-surface));
}
</style>
