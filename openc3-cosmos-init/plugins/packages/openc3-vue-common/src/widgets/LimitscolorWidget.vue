<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div ref="container" class="d-flex flex-row" :style="myComputedStyle">
    <v-tooltip v-if="!tooltipText" :open-delay="600" location="top">
      <template #activator="{ props }">
        <div
          v-if="!astro"
          :class="ledClass"
          :style="cssProps"
          v-bind="props"
          @contextmenu="showContextMenu"
        ></div>
        <div
          v-else
          class="astroled align-self-center"
          :class="staleClass"
          v-bind="props"
          @contextmenu="showContextMenu"
        >
          <rux-status :status="astroStatus" />
        </div>
      </template>
      <span>{{ fullName }}</span>
    </v-tooltip>
    <div
      v-else-if="!astro"
      :class="ledClass"
      :style="cssProps"
      @contextmenu="showContextMenu"
    ></div>
    <div
      v-else
      class="astroled align-self-center"
      :class="staleClass"
      @contextmenu="showContextMenu"
    >
      <rux-status :status="astroStatus" />
    </div>
    <label-widget
      v-if="displayLabel"
      :parameters="labelName"
      :settings="appliedSettings"
      :style="computedStyle"
      :widget-index="1"
    />

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
import VWidget from './VWidget'
export default {
  components: {
    DetailsDialog,
  },
  mixins: [VWidget],
  data() {
    return {
      astro: false,
      radius: 15,
      fullLabelDisplay: false,
      displayLabel: true,
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
                encodeURIComponent(this.parameters[2]) +
                '/',
              '_blank',
            )
          },
        },
      ],
    }
  },
  computed: {
    labelName() {
      // LabelWidget uses index 0 from the parameters prop
      // so create an array with the label text in the first position
      if (this.fullLabelDisplay) {
        return [
          this.parameters[0] +
            ' ' +
            this.parameters[1] +
            ' ' +
            this.parameters[2],
        ]
      } else {
        return [this.parameters[2]]
      }
    },
    fullName() {
      return (
        this.parameters[0] + ' ' + this.parameters[1] + ' ' + this.parameters[2]
      )
    },
    ledClass() {
      let result = `led align-self-center ${this.limitsColor}`
      if (this._limitsState === 'STALE') {
        result += ' stale'
      }
      return result
    },
    cssProps() {
      return {
        '--height': this.radius + 'px',
        '--width': this.radius + 'px',
      }
    },
    staleClass() {
      if (this._limitsState === 'STALE') {
        return 'stale'
      }
      return ''
    },
    myComputedStyle() {
      // Remove the flex property from the computedStyle object
      // because if they choose not to display the label
      // the flex property makes it difficult to line up a custom LABEL widget
      const style = { ...this.computedStyle }
      delete style.flex
      return style
    },
  },
  created() {
    this.appliedSettings.forEach((setting) => {
      if (setting[0] === 'ASTRO') {
        this.astro = setting[1]?.toLowerCase() !== 'false'
      }
    })
    if (this.parameters[4]) {
      this.radius = Number.parseInt(this.parameters[4])
    }
    if (this.parameters[5]) {
      if (this.parameters[5].toLowerCase() === 'true') {
        this.fullLabelDisplay = true
      } else if (this.parameters[5].toLowerCase() === 'nil') {
        this.displayLabel = false
      } else if (this.parameters[5].toLowerCase() === 'none') {
        this.displayLabel = false
      }
    }
  },
  methods: {
    getType() {
      let type = 'CONVERTED'
      if (this.parameters[3]) {
        type = this.parameters[3]
      }
      return type
    },
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
.led {
  height: var(--height);
  width: var(--width);
  background-color: var(--color);
  border-radius: 50%;
}
/* The background-colors match the values in LimitsbarWidget.vue */
.red {
  background-color: rgb(255, 45, 45);
}
.yellow {
  background-color: rgb(255, 220, 0);
}
.green {
  background-color: rgb(0, 200, 0);
}
.blue {
  background-color: rgb(0, 153, 255);
}
.purple {
  background-color: rgb(200, 0, 200);
}
.astroled {
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.stale {
  filter: blur(2px) brightness(0.6);
}
</style>
