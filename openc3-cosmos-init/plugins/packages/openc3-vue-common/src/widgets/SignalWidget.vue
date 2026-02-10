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
  <v-btn
    :icon="displayedIcon"
    variant="text"
    :style="computedStyle"
    aria-label="Signal Strength"
    @click="clickHandler"
  />
</template>

<script>
import VWidget from './VWidget'

export default {
  mixins: [VWidget],
  props: {
    value: {
      type: [Number, String],
      default: null,
    },
  },
  emits: ['open'],
  data: function () {
    return {
      item: null,
      oneBar: 30,
      twoBar: 60,
      threeBar: 90,
    }
  },
  computed: {
    displayedIcon: function () {
      let icon = 'mdi-signal-cellular-outline'
      if (this._value >= this.oneBar) {
        icon = 'mdi-signal-cellular-1'
      }
      if (this._value >= this.twoBar) {
        icon = 'mdi-signal-cellular-2'
      }
      if (this._value >= this.threeBar) {
        icon = 'mdi-signal-cellular-3'
      }
      return icon
    },
  },
  created() {
    this.appliedSettings.forEach((setting) => {
      switch (setting[0].toUpperCase()) {
        // Create a link to an existing screen
        case 'SCREEN':
          this.screenTarget = setting[1]
          this.screenName = setting[2]
          break

        // Override the values where we switch icons
        case 'VALUES':
          this.oneBar = Number.parseFloat(setting[1])
          this.twoBar = Number.parseFloat(setting[2])
          this.threeBar = Number.parseFloat(setting[3])
          break
      }
    })
  },
  methods: {
    // Override VWidget base method to set CONVERTED by default
    getType() {
      let type = 'CONVERTED'
      if (this.parameters[3] == 'RAW') {
        type = 'RAW'
      }
      return type
    },
    clickHandler() {
      if (this.screenTarget && this.screenName) {
        this.$emit('open', this.screenTarget, this.screenName)
      }
    },
  },
}
</script>
