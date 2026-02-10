<!--
# Copyright 2026 OpenC3, Inc.
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
  <v-tooltip v-if="!hideTooltip" :open-delay="600" location="top">
    <template #activator="{ props }">
      <div class="limitsbar" :style="barStyle" v-bind="props">
        <div class="limitsbar__container">
          <div class="limitsbar__redlow" />
          <div class="limitsbar__redhigh" />
          <div class="limitsbar__yellowlow" />
          <div class="limitsbar__yellowhigh" />
          <div class="limitsbar__greenlow" />
          <div class="limitsbar__greenhigh" />
          <div class="limitsbar__blue" />
          <div class="limitsbar__line" />
          <div class="limitsbar__arrow" />
        </div>
      </div>
    </template>
    <span>{{ limitsTooltip }}</span>
  </v-tooltip>
  <div v-else class="limitsbar" :style="barStyle">
    <div class="limitsbar__container">
      <div class="limitsbar__redlow" />
      <div class="limitsbar__redhigh" />
      <div class="limitsbar__yellowlow" />
      <div class="limitsbar__yellowhigh" />
      <div class="limitsbar__greenlow" />
      <div class="limitsbar__greenhigh" />
      <div class="limitsbar__blue" />
      <div class="limitsbar__line" />
      <div class="limitsbar__arrow" />
    </div>
  </div>
</template>

<script>
export default {
  props: {
    redLow: {
      type: Number,
      required: true,
    },
    yellowLow: {
      type: Number,
      required: true,
    },
    yellowHigh: {
      type: Number,
      required: true,
    },
    redHigh: {
      type: Number,
      required: true,
    },
    greenLow: {
      type: Number,
      default: null,
    },
    greenHigh: {
      type: Number,
      default: null,
    },
    value: {
      type: Number,
      default: null,
    },
    width: {
      type: Number,
      default: 160,
    },
    height: {
      type: Number,
      default: 22,
    },
    // Optional pre-computed style overrides (used by BarColumn for MIN_VALUE/MAX_VALUE support)
    computedStyle: {
      type: Object,
      default: null,
    },
    // Hide the built-in tooltip (used when parent provides a TOOLTIP setting)
    hideTooltip: {
      type: Boolean,
      default: false,
    },
  },
  computed: {
    hasGreenLimits() {
      return this.greenLow !== null && this.greenHigh !== null
    },
    limitsTooltip() {
      if (this.hasGreenLimits) {
        return `RL/${this.redLow} YL/${this.yellowLow} YH/${this.yellowHigh} RH/${this.redHigh} GL/${this.greenLow} GH/${this.greenHigh}`
      } else {
        return `RL/${this.redLow} YL/${this.yellowLow} YH/${this.yellowHigh} RH/${this.redHigh}`
      }
    },
    barStyle() {
      // If pre-computed style is provided, use it (for BarColumn MIN_VALUE/MAX_VALUE support)
      if (this.computedStyle) {
        return this.computedStyle
      }

      // Red zones take 10% each by default
      const redLowWidth = 10
      const redHighWidth = 10
      const divisor = 80 // 100 - 10 - 10
      const scale = (this.redHigh - this.redLow) / divisor

      const yellowLowWidth = Math.round((this.yellowLow - this.redLow) / scale)
      const yellowHighWidth = Math.round(
        (this.redHigh - this.yellowHigh) / scale,
      )

      let greenLowWidth, greenHighWidth, blueWidth
      if (this.hasGreenLimits) {
        greenLowWidth = Math.round((this.greenLow - this.yellowLow) / scale)
        greenHighWidth = Math.round((this.yellowHigh - this.greenHigh) / scale)
        blueWidth = Math.round(
          100 -
            redLowWidth -
            yellowLowWidth -
            greenLowWidth -
            greenHighWidth -
            yellowHighWidth -
            redHighWidth,
        )
      } else {
        greenLowWidth = Math.round(
          100 - redLowWidth - yellowLowWidth - yellowHighWidth - redHighWidth,
        )
        greenHighWidth = 0
        blueWidth = 0
      }

      // Calculate position for current value
      let position = 50 // default to middle
      if (this.value !== null && Number.isFinite(this.value)) {
        const lowValue = this.redLow - 10 * scale
        position = Math.round((this.value - lowValue) / scale)
        if (position > 100) position = 100
        if (position < 0) position = 0
      }

      return {
        '--width': this.width + 'px',
        '--height': this.height + 'px',
        '--container-height': this.height - 5 + 'px',
        '--redlow-width': redLowWidth + '%',
        '--redhigh-width': redHighWidth + '%',
        '--yellowlow-width': yellowLowWidth + '%',
        '--yellowhigh-width': yellowHighWidth + '%',
        '--greenlow-width': greenLowWidth + '%',
        '--greenhigh-width': greenHighWidth + '%',
        '--blue-width': blueWidth + '%',
        '--position': position + '%',
      }
    },
  },
}
</script>

<style lang="scss" scoped>
.limitsbar {
  cursor: default;
  display: flex;
  justify-content: center;
  align-items: center;
  margin-top: 6px;
  padding: 5px;
  width: var(--width);
}
.limitsbar__container {
  position: relative;
  flex: 1;
  height: var(--container-height);
  border: 1px solid black;
  background-color: white;
}
/* The background-colors match the values in LimitscolorWidget.vue */
.limitsbar__redlow {
  position: absolute;
  top: -1px;
  left: 0px;
  width: var(--redlow-width);
  height: var(--container-height);
  background-color: rgb(255, 45, 45);
}
.limitsbar__redhigh {
  position: absolute;
  top: -1px;
  right: 0px;
  width: var(--redhigh-width);
  height: var(--container-height);
  background-color: rgb(255, 45, 45);
}
.limitsbar__yellowlow {
  position: absolute;
  top: -1px;
  left: var(--redlow-width);
  width: var(--yellowlow-width);
  height: var(--container-height);
  background-color: rgb(255, 220, 0);
}
.limitsbar__yellowhigh {
  position: absolute;
  top: -1px;
  right: var(--redhigh-width);
  width: var(--yellowhigh-width);
  height: var(--container-height);
  background-color: rgb(255, 220, 0);
}
.limitsbar__greenlow {
  position: absolute;
  top: -1px;
  left: calc(var(--redlow-width) + var(--yellowlow-width));
  width: var(--greenlow-width);
  height: var(--container-height);
  background-color: rgb(0, 200, 0);
}
.limitsbar__greenhigh {
  position: absolute;
  top: -1px;
  right: calc(var(--redhigh-width) + var(--yellowhigh-width));
  width: var(--greenhigh-width);
  height: var(--container-height);
  background-color: rgb(0, 200, 0);
}
.limitsbar__blue {
  position: absolute;
  top: -1px;
  left: calc(
    var(--redlow-width) + var(--yellowlow-width) + var(--greenlow-width)
  );
  width: var(--blue-width);
  height: var(--container-height);
  background-color: rgb(0, 153, 255);
}
.limitsbar__line {
  position: absolute;
  left: var(--position);
  width: 1px;
  height: var(--container-height);
  background-color: rgb(128, 128, 128);
}
$arrow-size: 5px;
.limitsbar__arrow {
  position: absolute;
  top: -$arrow-size;
  left: var(--position);
  width: 0;
  height: 0;
  transform: translateX(-$arrow-size); // Transform so it sits over the line
  border-left: $arrow-size solid transparent;
  border-right: $arrow-size solid transparent;
  border-top: $arrow-size solid rgb(128, 128, 128);
}
</style>
