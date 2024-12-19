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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div class="limitsbar" :style="[cssProps, computedStyle]">
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
import BarColumn from './BarColumn'

export default {
  mixins: [BarColumn],
  data() {
    return {
      width: 22, // px
      height: 120, // users will override with px
    }
  },
  computed: {
    // TODO: Not sure why we have to reimplement this from BarColumn
    // strangely enough LimitsbarWidget.vue works fine without it
    cssProps: function () {
      let value = this.screenValues[this.valueId][0]
      let limits = this.modifyLimits(
        this.limitsSettings[this.selectedLimitsSet],
      )
      if (limits) {
        this.calcLimits(limits)
        return {
          '--height': this.height + 'px',
          '--width': this.width + 'px',
          '--container-width': this.width - 5 + 'px',
          '--position': this.calcPosition(value, limits) + '%',
          '--redlow-height': this.redLow + '%',
          '--redhigh-height': this.redHigh + '%',
          '--yellowlow-height': this.yellowLow + '%',
          '--yellowhigh-height': this.yellowHigh + '%',
          '--greenlow-height': this.greenLow + '%',
          '--greenhigh-height': this.greenHigh + '%',
          '--blue-height': this.blue + '%',
        }
      } else {
        throw new Error(
          `Item ${this.parameters.slice(0, 3).join(' ')} has no limits settings`,
        )
      }
    },
  },
}
</script>

<style lang="scss" scoped>
.limitsbar {
  cursor: default;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  padding: 5px;
  height: var(--height);
  margin-right: 5px;
}
.limitsbar__container {
  position: relative;
  flex: 1 1 100%;
  width: var(--container-width);
  border: 1px solid black;
  background-color: white;
}
.limitsbar__redlow {
  position: absolute;
  bottom: 0px;
  width: var(--container-width);
  height: var(--redlow-height);
  background-color: rgb(255, 45, 45);
}
.limitsbar__redhigh {
  position: absolute;
  top: 0px;
  width: var(--container-width);
  height: var(--redhigh-height);
  background-color: rgb(255, 45, 45);
}
.limitsbar__yellowlow {
  position: absolute;
  bottom: var(--redlow-height);
  height: var(--yellowlow-height);
  width: var(--container-width);
  background-color: rgb(255, 220, 0);
}
.limitsbar__yellowhigh {
  position: absolute;
  top: var(--redhigh-height);
  height: var(--yellowhigh-height);
  width: var(--container-width);
  background-color: rgb(255, 220, 0);
}
.limitsbar__greenlow {
  position: absolute;
  bottom: calc(var(--redlow-height) + var(--yellowlow-height));
  width: var(--container-width);
  height: var(--greenlow-height);
  background-color: rgb(0, 200, 0);
}
.limitsbar__greenhigh {
  position: absolute;
  top: calc(var(--redhigh-height) + var(--yellowhigh-height));
  width: var(--container-width);
  height: var(--greenhigh-height);
  background-color: rgb(0, 200, 0);
}
.limitsbar__blue {
  position: absolute;
  bottom: calc(
    var(--redlow-height) + var(--yellowlow-height) + var(--greenlow-height)
  );
  width: var(--container-width);
  height: var(--blue-height);
  background-color: rgb(0, 153, 255);
}
.limitsbar__line {
  position: absolute;
  bottom: var(--position);
  width: var(--container-width);
  height: 1px;
  background-color: rgb(128, 128, 128);
}
$arrow-size: 5px;
.limitsbar__arrow {
  position: absolute;
  bottom: var(--position);
  left: var(--container-width);
  width: 0;
  height: 0;
  transform: translateY($arrow-size); // Transform so it sits over the line
  border-top: $arrow-size solid transparent;
  border-bottom: $arrow-size solid transparent;
  border-right: $arrow-size solid rgb(128, 128, 128);
}
</style>
