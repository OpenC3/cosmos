<!--
# Copyright 2024 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <rux-monitoring-icon
    v-bind="attrs"
    v-on="on"
    class="rux-icon"
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
      default: null,
    },
  },
  data: function () {
    return {
      valueId: null,
      icon: '',
      label: '',
      subLabel: '',
      items: [],
    }
  },
  computed: {
    status: function () {
      let state = 'off'
      if (this.screen) {
        // Calculate the overall state of all the items we care about
        for (const item of this.items) {
          let limitsState = this.screen.screenValues[item][1]
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
      } else {
        state = 'off'
      }
      return state
    },
  },
  created: function () {
    this.icon = this.parameters[0]
    this.label = this.parameters[1]
    this.subLabel = this.parameters[2]

    // Dynamically import the rux icon they requested
    import(
      `@astrouxds/astro-web-components/dist/components/rux-icon-${this.icon}`
    ).then((module) => {
      // First key of the module is the name of the class
      let name = Object.keys(module)[0]
      try {
        customElements.define(`rux-icon-${this.icon}`, module[name])
      } catch (e) {
        // Catch the fact that the icon probably already exists and move on
      }
    })

    this.settings.forEach((setting) => {
      switch (setting[0].toUpperCase()) {
        // Create a link to an existing screen
        case 'SCREEN':
          this.screenTarget = setting[1]
          this.screenName = setting[2]
          break

        // Create the list of rollup telemetry
        case 'TLM':
          let type = 'CONVERTED'
          if (setting[4]) {
            type = setting[4]
          }
          let item = `${setting[1]}__${setting[2]}__${setting[3]}__${type}`
          this.items.push(item)
          if (this.screen) {
            this.screen.addItem(item)
          }
          break
      }
    })
  },
  destroyed: function () {
    if (this.screen) {
      this.items.forEach((item) => {
        this.screen.deleteItem(item)
      })
    }
  },
  methods: {
    clickHandler() {
      if (this.screenTarget && this.screenName) {
        this.screen.open(this.screenTarget, this.screenName)
      }
    },
  },
}
</script>
