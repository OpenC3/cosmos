<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <rux-icon :size="size" :icon="icon" :style="colorStyle" />
</template>

<script>
// This component is a Vue wrapper around Astro RuxIcon so that it works as a Vuetify icon set
export default {
  props: {
    icon: {
      type: String,
      default: null,
    },
    size: {
      type: String,
      default: 'small',
    },
    color: {
      type: String,
      default: 'white',
    },
  },
  computed: {
    colorStyle: function () {
      return {
        '--iconColor': this.color,
      }
    },
  },
}
</script>

<style scoped>
rux-icon {
  color: var(--iconColor);
}
</style>
