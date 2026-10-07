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
  <div class="playback-bar border-b" data-test="playback-bar">
    <v-progress-linear
      :active="loading"
      indeterminate
      color="secondary"
      height="2"
      absolute
    />
    <div class="d-flex flex-wrap align-center ga-3 px-4 py-2">
      <span class="d-inline-flex align-center ga-2 font-weight-bold">
        <v-icon icon="mdi-history" size="18" />
        Playback
      </span>
      <!-- The same controls as Telemetry Viewer's playback mode -->
      <playback-controls
        :model-value="time"
        :time-zone="timeZone"
        :loading="loading"
        storage-key="dashboards"
        @update:model-value="(value) => $emit('update:time', value)"
      />
      <span v-if="time" class="text-body-2 text-medium-emphasis">
        All panels show
        <b class="num text-high-emphasis" data-test="playback-showing">
          {{ formatDateTime(time, timeZone) }}
        </b>
      </span>
      <span v-else class="text-body-2 text-medium-emphasis">
        Pick a start time and press play
      </span>
      <v-spacer />
      <v-btn
        variant="outlined"
        prepend-icon="mdi-broadcast"
        data-test="playback-live"
        @click="$emit('live')"
      >
        Back to live
      </v-btn>
    </div>
  </div>
</template>

<script>
import { PlaybackControls } from '@openc3/vue-common/components'
import { TimeFilters } from '@openc3/vue-common/util'

// Playback for the whole dashboard: Telemetry Viewer's playback controls plus
// the time every panel is showing and a way back to live
export default {
  components: { PlaybackControls },
  mixins: [TimeFilters],
  props: {
    time: { type: Date, default: null },
    loading: Boolean,
    timeZone: { type: String, default: 'local' },
  },
  emits: ['update:time', 'live'],
}
</script>

<style scoped>
.playback-bar {
  position: relative;
  background: rgba(var(--v-theme-secondary), 0.08);
}
</style>
