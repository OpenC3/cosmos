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
  <rux-monitoring-icon
    class="rux-icon"
    :style="[pointerStyle, computedStyle]"
    :icon="icon"
    :status="status"
    :label="label"
    :sublabel="subLabel"
    @click="clickHandler"
  ></rux-monitoring-icon>
</template>

<script>
import Widget from './Widget'

export default {
  mixins: [Widget],
  props: {
    value: {
      type: [Number, String],
      default: null,
    },
  },
  emits: ['addItem', 'deleteItem', 'open'],
  data: function () {
    return {
      valueId: null,
      icon: '',
      label: '',
      subLabel: '',
      items: [],
      screenTarget: null,
      screenName: null,
    }
  },
  computed: {
    status: function () {
      let state = 'off'
      // Calculate the overall state of all the items we care about
      for (const item of this.items) {
        let limitsState = this.screenValues[item][1]
        if (limitsState) {
          if (
            (limitsState.includes('BLUE') || limitsState.includes('GREEN')) &&
            state != 'caution' &&
            state != 'critical'
          ) {
            state = 'normal'
          }
          if (limitsState.includes('YELLOW') && state != 'critical') {
            state = 'caution'
          }
          if (limitsState.includes('RED')) {
            state = 'critical'
          }
        }
      }
      return state
    },
    pointerStyle() {
      if (this.screenTarget && this.screenName) {
        return {
          cursor: 'pointer',
        }
      } else {
        return {
          cursor: 'default',
        }
      }
    },
  },
  created: function () {
    this.icon = this.parameters[0]
    this.label = this.parameters[1]
    this.subLabel = this.parameters[2]

    // Supported icons are imported in openc3-cosmos-init/plugins/openc3-vue-common/src/plugins/vuetify.js
    // Dynamic importing as requested was attempted, but this caused webpack to process too many files

    this.appliedSettings.forEach((setting) => {
      switch (setting[0].toUpperCase()) {
        // Create a link to an existing screen
        case 'SCREEN':
          this.screenTarget = setting[1]
          this.screenName = setting[2]
          break

        // Create the list of rollup telemetry
        case 'TLM': {
          let type = 'CONVERTED'
          if (setting[4]) {
            type = setting[4]
          }
          let item = `${setting[1]}__${setting[2]}__${setting[3]}__${type}`
          this.items.push(item)
          this.$emit('addItem', item)
          break
        }
      }
    })
  },
  unmounted: function () {
    this.items.forEach((item) => {
      this.$emit('deleteItem', item)
    })
  },
  methods: {
    clickHandler() {
      if (this.screenTarget && this.screenName) {
        this.$emit('open', this.screenTarget, this.screenName)
      }
    },
  },
}
</script>
