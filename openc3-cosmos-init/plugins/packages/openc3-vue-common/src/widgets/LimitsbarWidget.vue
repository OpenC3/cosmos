<!--
# Copyright 2025 OpenC3, Inc.
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
  <v-tooltip :open-delay="600" location="top">
    <template #activator="{ props }">
      <div class="limitsbar" :style="[cssProps, computedStyle]" v-bind="props">
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
    <span>{{ limitsRange }}</span>
  </v-tooltip>
</template>

<script>
import BarColumn from './BarColumn'

export default {
  mixins: [BarColumn],
  data() {
    return {
      width: 160, // px
      height: 22, // px
    }
  },
  computed: {
    limitsRange() {
      let values = this.limitsSettings[this.selectedLimitsSet]
      if (values) {
        // Format like the DetailsDialog formatLimit function
        if (values.length === 4) {
          return `RL/${values[0]} YL/${values[1]} YH/${values[2]} RH/${values[3]}`
        } else {
          return `RL/${values[0]} YL/${values[1]} YH/${values[2]} RH/${values[3]} GL/${values[4]} GH/${values[5]}`
        }
      } else {
        // See errorCaptured in Openc3Screen.vue for how this is parsed
        throw {
          line: this.line,
          lineNumber: this.lineNumber,
          keyword: 'LIMITSBAR',
          parameters: this.parameters,
          message: 'Item has no limits settings',
          usage: 'Only items with limits',
        }
      }
    },
  },
  created() {
    this.verifyNumParams(
      'LIMITSBAR',
      3,
      6,
      'LIMITSBAR <TARGET> <PACKET> <ITEM> <TYPE> <WIDTH> <HEIGHT>',
    )
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
