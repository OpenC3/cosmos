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
  <!-- Full width bar marking that telemetry shown is played back, not live.
       Shown above PlaybackControls by the tools that offer playback. -->
  <v-alert
    class="playback text-overline w-100 py-0 align-center justify-center flex-0-0"
    type="warning"
    variant="tonal"
    density="compact"
    border="start"
    :icon="false"
    data-test="playback-banner"
  >
    <span class="d-inline-flex align-center">
      <v-icon icon="mdi-play-circle-outline" size="16" class="mr-2" />
      Playback Mode
    </span>
  </v-alert>
</template>

<style scoped>
.playback :deep(.v-alert__content) {
  /* v-alert pads content to fit its default 28px icon; ours is 18px */
  padding-block: 0;
}
</style>
