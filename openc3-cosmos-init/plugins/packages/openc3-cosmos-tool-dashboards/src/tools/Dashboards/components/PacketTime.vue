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
  <!-- Panels pass their padding, data-test and container query class -->
  <div
    class="d-flex flex-0-0 align-center justify-end ga-1 text-caption text-medium-emphasis num"
    :title="`Packet time ${time}`"
  >
    <v-icon icon="mdi-clock-outline" size="12" />
    <span class="text-truncate">{{ time }}</span>
  </div>
</template>

<script setup>
// Packet time footer for single value panels (PACKET_TIME option)
defineProps({
  time: { type: String, default: '' },
})
</script>
