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
  <v-avatar
    :size="size"
    rounded="lg"
    :color="color || 'secondary'"
    variant="tonal"
    class="flex-shrink-0"
  >
    <v-icon :icon="icon" :size="Math.round(size * 0.55)" />
  </v-avatar>
</template>

<script>
import { DEFAULT_ICON } from '../dashboardStyle'

// A dashboard's icon on a tile of its color
export default {
  props: {
    icon: { type: String, default: DEFAULT_ICON },
    color: { type: String, default: null },
    size: { type: Number, default: 44 },
  },
}
</script>
