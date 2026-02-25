<!--
# Copyright 2025 OpenC3, Inc.
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
  <span class="cosmos-custom-icon">
    <!-- Camel case props because svg -->
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      preserveAspectRatio="xMidYMid meet"
      focusable="false"
    >
      <use :href="iconSrc" />
    </svg>
  </span>
</template>

<script>
const ICON_LIBRARY = '/icons/customIcons.svg'

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
    iconSrc: function () {
      return ICON_LIBRARY + '#' + this.icon
    },
  },
}
</script>

<style scoped>
.cosmos-custom-icon {
  fill: v-bind(color);
}
</style>
