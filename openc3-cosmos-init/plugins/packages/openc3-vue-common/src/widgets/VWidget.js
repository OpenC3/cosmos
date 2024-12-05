/*
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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { TimeFilters } from '@/util'
import Widget from './Widget'
import FormatValueBase from './FormatValueBase'
export default {
  mixins: [Widget, TimeFilters, FormatValueBase],
  // ValueWidget can either get it's value and limitsState directly through props
  // or it will register itself in the Vuex store and be updated asynchronously
  props: {
    value: {
      default: null,
    },
    limitsState: {
      type: String,
      default: null,
    },
    counter: {
      default: null,
    },
    formatString: null,
    timeZone: {
      type: String,
      default: 'local',
    },
  },
  emits: ['addItem', 'deleteItem', 'open'],
  data() {
    return {
      appliedTimeZone: 'local',
      curValue: null,
      prevValue: null,
      grayLevel: 80,
      grayRate: 5,
      valueId: null,
      arrayIndex: null,
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
  watch: {
    _counter: function (newVal, oldVal) {
      if (this.curValue !== this.prevValue) {
        this.grayLevel = 80
      } else {
        this.grayLevel -= this.grayRate
        if (this.grayLevel < 30) {
          this.grayLevel = 30
        }
      }
      this.prevValue = this.curValue
    },
  },
  computed: {
    _value: function () {
      this.curValue = this.value
      if (this.curValue === null) {
        // See store.js for how this is set
        if (this.screenValues) {
          if (this.screenValues[this.valueId]) {
            if (
              this.arrayIndex !== null &&
              this.screenValues[this.valueId][0]
            ) {
              this.curValue =
                this.screenValues[this.valueId][0][this.arrayIndex]
            } else {
              this.curValue = this.screenValues[this.valueId][0]
            }
          }
        } else {
          this.curValue = null
        }
      }
      this.curValue = this.formatValue(this.curValue)
      return this.curValue
    },
    _limitsState: function () {
      let limitsState = this.limitsState
      if (limitsState === null) {
        if (this.screenValues) {
          if (this.screenValues[this.valueId]) {
            limitsState = this.screenValues[this.valueId][1]
          }
        } else {
          limitsState = null
        }
      }
      return limitsState
    },
    _counter: function () {
      let counter = this.counter
      if (counter === null) {
        if (this.screenValues) {
          if (this.screenValues[this.valueId]) {
            counter = this.screenValues[this.valueId][2]
          }
        } else {
          counter = null
        }
      }
      return counter
    },
    valueClass: function () {
      return 'value shrink pa-1 ' + 'openc3-' + this.limitsColor
    },
    astroStatus() {
      switch (this.limitsColor) {
        case 'green':
          return 'normal'
        case 'yellow':
          return 'caution'
        case 'red':
          return 'critical'
        case 'blue':
          // This one is a little weird but it matches our color scheme
          return 'standby'
        default:
          return null
      }
    },
    limitsColor() {
      let limitsState = this._limitsState
      if (limitsState != null) {
        switch (limitsState) {
          case 'GREEN':
          case 'GREEN_HIGH':
          case 'GREEN_LOW':
            return 'green'
          case 'YELLOW':
          case 'YELLOW_HIGH':
          case 'YELLOW_LOW':
            return 'yellow'
          case 'RED':
          case 'RED_HIGH':
          case 'RED_LOW':
            return 'red'
          case 'BLUE':
            return 'blue'
          case 'STALE':
            return 'purple'
          default:
            return 'white'
        }
      }
      return ''
    },
    limitsLetter() {
      let limitsState = this._limitsState
      if (limitsState != null) {
        let c = limitsState.charAt(0)
        if (limitsState.endsWith('_LOW')) {
          c = c.toLowerCase()
        }
        return c
      }
      return ''
    },
  },
  created() {
    // If they're not passing us the value and limitsState we have to register
    if (this.value === null || this.limitsState === null) {
      // Remove double bracket escaping. This means they actually have an item
      // with a bracket in the name, not an array index.
      if (this.parameters[2].includes('[[')) {
        this.parameters[2] = this.parameters[2]
          .replace('[[', '[')
          .replace(']]', ']')
      } else if (this.parameters[2].includes('[')) {
        // Brackets mean array indexes (normally, but see above)
        let match = this.parameters[2].match(/\[(\d+)\]/)
        this.arrayIndex = parseInt(match[1])
        this.parameters[2] = this.parameters[2].replace(match[0], '')
      }
      this.valueId = `${this.parameters[0]}__${this.parameters[1]}__${
        this.parameters[2]
      }__${this.getType()}`

      this.$emit('addItem', this.valueId)
      if (this.screenTimeZone) {
        this.appliedTimeZone = this.screenTimeZone
      } else {
        this.appliedTimeZone = this.timeZone
      }
    }
  },
  destroyed() {
    if (this.value === null || this.limitsState === null) {
      this.$emit('deleteItem', this.valueId)
    }
  },
  methods: {
    getType() {
      let type = 'WITH_UNITS'
      if (this.parameters[3]) {
        type = this.parameters[3]
      }
      return type
    },
    formatValue(value) {
      if (
        value &&
        this.valueId &&
        (this.valueId.includes('PACKET_TIMEFORMATTED') ||
          this.valueId.includes('RECEIVED_TIMEFORMATTED'))
      ) {
        // Our dates have / rather than - which results in an invalid date on old browsers
        // when they call new Date(value)
        value = value.replaceAll('/', '-')
        return this.formatUtcToLocal(new Date(value), this.appliedTimeZone)
      }
      return this.formatValueBase(value, this.formatString)
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
