<!--
# Copyright 2022 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <component
    :is="widgetType"
    ref="dynamic"
    :config="currentConfig"
    v-bind="{ ...$props, ...$attrs }"
    @config="(config) => (currentConfig = config)"
  ></component>
</template>

<script>
import { DataViewerComponent } from '@openc3/vue-common/components'

export default {
  mixins: [DataViewerComponent],
  props: {
    name: {
      type: String,
      default: null,
    },
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
  watch: {
    latestData: function (data) {
      if (typeof this.$refs['dynamic'].receive === 'function') {
        this.$refs['dynamic'].receive(data)
      }
    },
  },
  async mounted() {
    try {
      this.widgetType = await System.import(this.url)
    } catch (e) {
      throw new Error(`Unknown widget: ${this.name}: ${e}`)
    }
  },
}
</script>
