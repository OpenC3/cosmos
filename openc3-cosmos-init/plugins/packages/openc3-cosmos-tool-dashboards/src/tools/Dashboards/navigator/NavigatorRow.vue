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
  <v-list-item
    :class="['row px-4', { current, highlighted }]"
    :active="false"
    data-test="navigator-item"
    @click="$emit('open')"
  >
    <template #prepend>
      <dashboard-avatar
        :icon="info?.icon"
        :color="info?.color"
        :size="32"
        class="mr-3"
      />
    </template>
    <div class="d-flex align-center ga-2">
      <span
        class="text-body-1 font-weight-medium text-high-emphasis text-truncate"
      >
        {{ info?.title || name }}
      </span>
      <v-chip
        v-if="current"
        size="x-small"
        color="secondary"
        variant="flat"
        label
      >
        Open
      </v-chip>
    </div>
    <div class="d-flex align-center text-body-2 text-medium-emphasis">
      <span class="mono text-truncate">
        <button
          v-if="showFolder"
          type="button"
          class="folder text-secondary"
          :title="`Show ${target}/`"
          data-test="navigator-row-folder"
          @click.stop="$emit('folder')"
        >
          {{ target }}/</button
        >{{ file }}
      </span>
      <span v-if="info" class="flex-shrink-0 text-no-wrap">
        &nbsp;· {{ info.panels }} panel{{ info.panels === 1 ? '' : 's' }}
      </span>
    </div>
    <template #append>
      <div class="d-flex align-center">
        <v-btn
          v-if="!lean"
          icon="mdi-content-copy"
          variant="text"
          size="small"
          class="duplicate text-medium-emphasis"
          :aria-label="`Duplicate ${dashboardKey}`"
          title="Duplicate"
          data-test="navigator-duplicate"
          @click.stop="$emit('duplicate')"
        />
        <v-btn
          :icon="starred ? 'mdi-star' : 'mdi-star-outline'"
          :color="starred ? 'warning' : undefined"
          :class="{ 'text-medium-emphasis': !starred }"
          variant="text"
          size="small"
          :aria-label="
            starred ? `Unstar ${dashboardKey}` : `Star ${dashboardKey}`
          "
          :aria-pressed="starred"
          :title="starred ? 'Unstar' : 'Star'"
          data-test="navigator-star"
          @click.stop="$emit('star')"
        />
      </div>
    </template>
  </v-list-item>
</template>

<script>
import DashboardAvatar from '../components/DashboardAvatar.vue'
import { loadInfo, navigator } from './navigatorStore'

// One dashboard in the navigator: its title, and where it's saved
// (TARGET/name.txt). Fetches its title and icon the first time it's shown.
export default {
  components: { DashboardAvatar },
  props: {
    dashboardKey: { type: String, required: true },
    starred: Boolean,
    current: Boolean,
    highlighted: Boolean,
    // Outside a folder, show which folder it's in
    showFolder: Boolean,
    lean: Boolean,
  },
  emits: ['open', 'star', 'duplicate', 'folder'],
  computed: {
    target() {
      return this.dashboardKey.split('/')[0]
    },
    name() {
      return this.dashboardKey.split('/')[1]
    },
    file() {
      return `${this.name.toLowerCase()}.txt`
    },
    info() {
      return navigator.info[this.dashboardKey]
    },
  },
  watch: {
    // Virtual scrolling reuses rows, so watch the key rather than mounted
    dashboardKey: {
      immediate: true,
      handler: loadInfo,
    },
  },
}
</script>

<style scoped>
.row {
  min-height: 56px;
}
.highlighted {
  background: rgba(var(--v-theme-on-surface), 0.06);
}
.folder:hover {
  text-decoration: underline;
}
/* Duplicate shows on hover, focus or the keyboard's row, so hundreds of rows
   aren't hundreds of icons */
.duplicate {
  opacity: 0;
}
.row:hover .duplicate,
.highlighted .duplicate,
.duplicate:focus-visible {
  opacity: 1;
}
</style>
