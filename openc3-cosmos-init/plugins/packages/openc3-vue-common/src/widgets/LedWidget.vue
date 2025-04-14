<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-tooltip location="top">
      <template #activator="{ props }">
        <div
          :class="getClass"
          :style="[cssProps, computedStyle]"
          v-bind="props"
          @contextmenu="showContextMenu"
        ></div>
      </template>
      <span>{{ fullName }}</span>
    </v-tooltip>

    <v-menu v-model="contextMenuShown" :target="[x, y]" style="z-index: 3000">
      <v-list>
        <v-list-item
          v-for="(item, index) in contextMenuOptions"
          :key="index"
          @click.stop="item.action"
        >
          <v-list-item-title>{{ item.title }}</v-list-item-title>
        </v-list-item>
      </v-list>
    </v-menu>

    <details-dialog
      v-model="viewDetails"
      :target-name="parameters[0]"
      :packet-name="parameters[1]"
      :item-name="parameters[2]"
    />
  </div>
</template>

<script>
import { DetailsDialog } from '@/components'
import Widget from './Widget'
export default {
  components: {
    DetailsDialog,
  },
  mixins: [Widget],
  data() {
    return {
      valueId: null,
      colors: {
        TRUE: 'openc3-green',
        FALSE: 'openc3-red',
      },
      viewDetails: false,
      contextMenuShown: false,
      x: 0,
      y: 0,
      contextMenuOptions: [
        {
          title: 'Details',
          action: () => {
            this.contextMenuShown = false
            this.viewDetails = true
          },
        },
        {
          title: 'Graph',
          action: () => {
            window.open(
              '/tools/tlmgrapher/' +
                encodeURIComponent(this.parameters[0]) +
                '/' +
                encodeURIComponent(this.parameters[1]) +
                '/' +
                encodeURIComponent(this.parameters[2]),
              '_blank',
            )
          },
        },
      ],
    }
  },
  computed: {
    width() {
      return this.parameters[4] ? parseInt(this.parameters[4]) : 20
    },
    height() {
      return this.parameters[5] ? parseInt(this.parameters[5]) : 20
    },
    cssProps() {
      let value = this.screenValues[this.valueId][0]
      let color = this.colors[value]
      if (!color) {
        color = this.colors.ANY
      }
      if (!color) {
        color = 'openc3-black'
      }
      return {
        '--color': color,
      }
    },
    fullName() {
      return (
        this.parameters[0] + ' ' + this.parameters[1] + ' ' + this.parameters[2]
      )
    },
    getClass() {
      let result = 'ledwidget mt-2'
      if (this.screenValues[this.valueId][1] === 'STALE') {
        result += ' stale'
      }
      return result
    },
  },
  // Note Vuejs still treats this synchronously, but this allows us to dispatch
  // the store mutation and return the array index.
  // What this means practically is that future lifecycle hooks may not have valueId set.
  created() {
    this.appliedSettings.forEach((setting) => {
      switch (setting[0]) {
        case 'LED_COLOR':
          this.colors[setting[1]] = setting[2]
          break
      }
    })
    // Throw width and height into the appliedSettings so they are set
    // and we don't get the default flex value
    this.appliedSettings.push(['WIDTH', this.width])
    this.appliedSettings.push(['HEIGHT', this.height])

    if (!this.parameters[3]) {
      this.parameters[3] = 'CONVERTED'
    }
    this.valueId = `${this.parameters[0]}__${this.parameters[1]}__${this.parameters[2]}__${this.parameters[3]}`
    this.$emit('addItem', this.valueId)
  },
  unmounted() {
    this.$emit('deleteItem', this.valueId)
  },
  methods: {
    showContextMenu(e) {
      e.preventDefault()
      this.contextMenuShown = false
      this.x = e.clientX
      this.y = e.clientY
      this.$nextTick(() => {
        this.contextMenuShown = true
      })
    },
  },
}
</script>

<style scoped>
.ledwidget {
  background-color: var(--color);
  border-radius: 50%;
}
.stale {
  filter: blur(2px) brightness(0.6);
}
</style>
