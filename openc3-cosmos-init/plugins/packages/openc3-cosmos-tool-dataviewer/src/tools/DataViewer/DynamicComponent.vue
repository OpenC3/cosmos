<!--
# Copyright 2022 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <component
    ref="dynamic"
    :is="widgetType"
    :config="currentConfig"
    @config="(config) => (currentConfig = config)"
    v-bind="{ ...$props, ...$attrs }"
  ></component>
</template>

<script>
import Component from '@openc3/tool-common/src/components/dataviewer/Component'

export default {
  mixins: [Component],
  data() {
    return {
      widgetType: null,
    }
  },
  props: {
    name: { default: null },
  },
  computed: {
    url: function () {
      return `${window.location.origin}/tools/widgets/${this.name}/${this.name}.umd.min.js`
    },
  },
  watch: {
    lastReceived: function (data) {
      this.$refs['dynamic'].receive(data)
    },
  },
  async mounted() {
    try {
      /* eslint-disable-next-line */
      this.widgetType = await System.import(/* webpackIgnore: true */ this.url)
    } catch (e) {
      throw new Error(`Unknown widget: ${this.name}`)
    }
  },
}
</script>
