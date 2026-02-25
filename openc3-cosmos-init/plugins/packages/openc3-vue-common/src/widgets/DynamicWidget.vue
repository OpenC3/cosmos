<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <component :is="widgetType" v-bind="{ ...$props, ...$attrs }"></component>
</template>

<script>
export default {
  props: {
    name: { type: String, default: null },
  },
  data() {
    return {
      widgetType: null,
    }
  },
  computed: {
    url: function () {
      return `${window.location.origin}/tools/widgets/${this.name}/${this.name}.umd.min.js`
    },
  },
  async mounted() {
    try {
      this.widgetType = await System.import(/* webpackIgnore: true */ this.url)
    } catch (e) {
      throw new Error(`Unknown widget: ${this.name}: ${e}`)
    }
  },
}
</script>
