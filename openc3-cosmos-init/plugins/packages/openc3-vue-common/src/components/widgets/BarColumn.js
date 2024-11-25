/*
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
*/

import Widget from './Widget'
import { OpenC3Api } from '../../services/openc3-api.js'

export default {
  mixins: [Widget],
  data() {
    return {
      minValue: null,
      maxValue: null,
      redLow: 0,
      yellowLow: 0,
      greenLow: 0,
      greenHigh: 0,
      yellowHigh: 0,
      redHigh: 0,
      blue: 0,
      api: null,
      limitsSettings: {
        DEFAULT: [],
      },
      currentLimitsSet: 'DEFAULT',
      currentSetRefreshInterval: null,
    }
  },
  computed: {
    cssProps: function () {
      let value = this.screenValues[this.valueId][0]
      let limits = this.modifyLimits(
        this.limitsSettings[this.selectedLimitsSet],
      )
      this.calcLimits(limits)
      return {
        '--height': this.height + 'px',
        '--width': this.width + 'px',
        '--container-height': this.height - 5 + 'px',
        '--position': this.calcPosition(value, limits) + '%',
        '--redlow-width': this.redLow + '%',
        '--redhigh-width': this.redHigh + '%',
        '--yellowlow-width': this.yellowLow + '%',
        '--yellowhigh-width': this.yellowHigh + '%',
        '--greenlow-width': this.greenLow + '%',
        '--greenhigh-width': this.greenHigh + '%',
        '--blue-width': this.blue + '%',
      }
    },
    selectedLimitsSet: function () {
      return this.limitsSettings.hasOwnProperty(this.currentLimitsSet)
        ? this.currentLimitsSet
        : 'DEFAULT'
    },
  },
  created() {
    this.api = new OpenC3Api()
    this.api
      .get_limits(this.parameters[0], this.parameters[1], this.parameters[2])
      .then((data) => {
        this.limitsSettings = data
      })
    this.getCurrentLimitsSet()
    this.currentSetRefreshInterval = setInterval(
      this.getCurrentLimitsSet,
      60 * 1000,
    )

    this.appliedSettings.forEach((setting) => {
      if (setting[0] === 'MIN_VALUE') {
        this.minValue = parseInt(setting[1])
      }
      if (setting[0] === 'MAX_VALUE') {
        this.maxValue = parseInt(setting[1])
      }
    })
    this.width = this.setWidth(this.parameters[4], 'px', this.width)
    this.height = this.setHeight(this.parameters[5], 'px', this.height)
    // Always pass CONVERTED so we can calculate the value against the limits (in converted units)
    this.valueId = `${this.parameters[0]}__${this.parameters[1]}__${this.parameters[2]}__CONVERTED`

    this.$emit('addItem', this.valueId)
  },
  destroyed() {
    this.$emit('deleteItem', this.valueId)
    clearInterval(this.currentSetRefreshInterval)
  },
  methods: {
    modifyLimits(limitsSettings) {
      // By default the red bars take 10% of the display
      this.redLow = 10
      this.redHigh = 10

      // Modify values to respect the user defined minimum
      if (this.minValue !== null) {
        if (limitsSettings[0] <= this.minValue) {
          limitsSettings[0] = this.minValue
          // No red low will be displayed
          this.redLow = 0
        }
        if (limitsSettings[1] <= this.minValue) {
          limitsSettings[1] = this.minValue
        }
        if (limitsSettings[2] <= this.minValue) {
          limitsSettings[2] = this.minValue
        }
        if (limitsSettings[3] <= this.minValue) {
          limitsSettings[3] = this.minValue
        }
        if (limitsSettings.length > 4 && limitsSettings[4] <= this.minValue) {
          limitsSettings[4] = this.minValue
        }
        if (limitsSettings.length > 4 && limitsSettings[5] <= this.minValue) {
          limitsSettings[5] = this.minValue
        }
      }
      if (this.maxValue !== null) {
        if (limitsSettings[0] >= this.maxValue) {
          limitsSettings[0] = this.maxValue
        }
        if (limitsSettings[1] >= this.maxValue) {
          limitsSettings[1] = this.maxValue
        }
        if (limitsSettings[2] >= this.maxValue) {
          limitsSettings[2] = this.maxValue
        }
        if (limitsSettings[3] >= this.maxValue) {
          limitsSettings[3] = this.maxValue
          // No red high will be displayed
          this.redHigh = 0
        }
        if (limitsSettings.length > 4 && limitsSettings[4] >= this.maxValue) {
          limitsSettings[4] = this.maxValue
        }
        if (limitsSettings.length > 4 && limitsSettings[5] >= this.maxValue) {
          limitsSettings[5] = this.maxValue
        }
      }
      // If the red low matches yellow low there is no yellow low
      if (limitsSettings[0] == limitsSettings[1]) {
        this.yellowLow = 0
      }
      // If the red high matches yellow high there is no yellow high
      if (limitsSettings[2] == limitsSettings[3]) {
        this.yellowHigh = 0
      }

      let divisor = 80
      if (this.redLow == 0) {
        divisor += 10
      }
      if (this.redHigh == 0) {
        divisor += 10
      }
      this.scale = (limitsSettings[3] - limitsSettings[0]) / divisor

      return limitsSettings
    },
    calcPosition(value, limitsSettings) {
      if (!value || !limitsSettings) {
        return
      }
      let lowValue = limitsSettings[0] - 10 * this.scale
      if (this.minValue && this.minValue == limitsSettings[0]) {
        lowValue = limitsSettings[0]
      }
      let highValue = limitsSettings[3] - 10 * this.scale
      if (this.maxValue && this.maxValue == limitsSettings[3]) {
        highValue = limitsSettings[3]
      }

      if (value.raw) {
        if (value.raw === '-Infinity') {
          return 0
        } else {
          // NaN and Infinity
          return 100
        }
      }
      if (value < this.min) {
        return 0
      } else if (value > this.max) {
        return 100
      } else {
        const result = parseInt((value - lowValue) / this.scale)
        if (result > 100) {
          return 100
        } else if (result < 0) {
          return 0
        } else {
          return result
        }
      }
    },
    calcLimits(limitsSettings) {
      if (!limitsSettings) {
        return
      }
      this.yellowLow = Math.round(
        (limitsSettings[1] - limitsSettings[0]) / this.scale,
      )
      this.yellowHigh = Math.round(
        (limitsSettings[3] - limitsSettings[2]) / this.scale,
      )
      if (limitsSettings.length > 4) {
        this.greenLow = Math.round(
          (limitsSettings[4] - limitsSettings[1]) / this.scale,
        )
        this.greenHigh = Math.round(
          (limitsSettings[2] - limitsSettings[5]) / this.scale,
        )
        this.blue = Math.round(
          100 -
            this.redLow -
            this.yellowLow -
            this.greenLow -
            this.greenHigh -
            this.yellowHigh -
            this.redHigh,
        )
      } else {
        this.greenLow = Math.round(
          100 - this.redLow - this.yellowLow - this.yellowHigh - this.redHigh,
        )
        this.greenHigh = 0
        this.blue = 0
      }
    },
    getCurrentLimitsSet: function () {
      this.api.get_limits_set().then((result) => {
        this.currentLimitsSet = result
      })
    },
  },
}
