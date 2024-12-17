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

import { ConfigParserError } from '@openc3/js-common/services'
import WidgetComponents from './WidgetComponents'

export default {
  mixins: [WidgetComponents],
  props: {
    widgetIndex: {
      type: Number,
      default: null,
    },
    parameters: {
      type: Array,
      default: () => [],
    },
    settings: {
      type: Array,
      default: () => [],
    },
    screenValues: {
      type: Object,
      default: () => {},
    },
    screenTimeZone: {
      type: String,
      default: 'local',
    },
    namedWidgets: {
      type: Object,
      default: {},
    },
    line: {
      type: String,
      default: '',
    },
    lineNumber: {
      type: Number,
      default: 0,
    },
  },
  data() {
    return {
      // The settings that apply to the current widget based on widgetIndex
      // Calculated in created, updated in setWidth & setHeight and used in computedStyle
      appliedSettings: [],
      // We make style a data attribute so as we recurse through nested
      // widgets we can check to see if style attributes have been applied
      // at any level of the widget, i.e. if LABELVALUE applies a style
      // to the VALUE component then we don't want the VALUE widget to think
      // it doesn't have a style when it renders.
      appliedStyle: {},
      widgetName: null,
      screenId: 'NO_SCREEN', // only used for named widgets - hopefully overwritten by settings value in created()
    }
  },
  computed: {
    computedStyle: function () {
      // Take all the COSMOS settings and create appliedStyle with actual css values
      this.appliedSettings.forEach((setting) => {
        this.applyStyleSetting(setting)
      })

      // If nothing has yet defined a width or height then we add flex to the style
      if (
        this.appliedStyle['width'] === undefined &&
        this.appliedStyle['height'] === undefined
      ) {
        // This flex allows for alignment in our widgets
        // The value of '0 10 100%' was achieved through trial and error
        // The larger flex-shrink value was critical for success
        this.appliedStyle['flex'] = '0 10 100%' // flex-grow, flex-shrink, flex-basis
      }
      return this.appliedStyle
    },
    screen: function () {
      // This exists for backwards compatibility of screen definitions since widgets no longer have a reference
      // to the Openc3Screen component instance
      const that = this
      return {
        getNamedWidget: function (widgetName) {
          return that.$store.getters.namedWidget(
            that.toQualifiedWidgetName(widgetName),
          )
        },
        open: function (target, screen) {
          that.$emit('open', target, screen)
        },
        close: function (target, screen) {
          that.$emit('close', target, screen)
        },
        closeAll: function () {
          that.$emit('closeAll')
        },
      }
    },
    listeners: function () {
      // Vue 3 deprecated $listeners, which was used to bubble up events to the Openc3Screen component. The new way is
      // to use v-bind="$attrs", but that also passes the `style` DOM attribute to children, which makes widgets
      // inherit styles from the layout like height and flex.
      // This is a workaround to let us v-bind to just the event listeners (which were previously in the $listeners
      // object in Vue 2).
      return Object.entries(this.$attrs).reduce((listeners, entry) => {
        if (entry[0].startsWith('on')) {
          return {
            ...listeners,
            [entry[0]]: entry[1],
          }
        }
        return listeners
      }, {})
    },
  },
  watch: {
    widgetName: function (newName, oldName) {
      this.$store.commit(
        'clearNamedWidget',
        this.toQualifiedWidgetName(oldName),
      )
      this.$store.commit('setNamedWidget', {
        [this.toQualifiedWidgetName(newName)]: this,
      })
    },
  },
  created() {
    // Look through the settings and get a reference to the screen
    this.screenId = this.settings
      .find((setting) => setting[0] === '__SCREEN_ID__')
      ?.at(1)

    this.widgetName = this.settings
      .find((setting) => setting[0] === 'NAMED_WIDGET')
      ?.at(1)

    // Figure out any subsettings that apply
    this.appliedSettings = this.settings
      .map((setting) => {
        const index = parseInt(setting[0])
        // If the first value isn't a number or if there isn't a widgetIndex
        // then it's not a subsetting so just return the setting
        if (isNaN(index) || this.widgetIndex === null) {
          return setting
        }
        // This is our setting so slice off the index and return
        // this effectively promotes the subsetting to a setting
        // on the current widget
        if (this.widgetIndex === index) {
          return setting.slice(1)
        }
      })
      // Remove any settings that we filtered out with null
      .filter((setting) => setting !== undefined)
  },
  beforeUnmount() {
    if (this.widgetName) {
      this.$store.commit(
        'clearNamedWidget',
        this.toQualifiedWidgetName(this.widgetName),
      )
    }
  },
  methods: {
    applyStyleSetting(setting) {
      switch (setting[0]) {
        case 'TEXTALIGN':
          this.appliedStyle['text-align'] =
            setting[1].toLowerCase() + ' !important'
          this.appliedStyle['--text-align'] = setting[1].toLowerCase()
          break
        case 'PADDING':
          if (!isNaN(Number(setting[1]))) {
            setting[1] += 'px'
          }
          this.appliedStyle['padding'] = setting[1] + ' !important'
          break
        case 'MARGIN':
          if (!isNaN(Number(setting[1]))) {
            setting[1] += 'px'
          }
          this.appliedStyle['margin'] = setting[1] + ' !important'
          break
        case 'BACKCOLOR':
          this.appliedStyle['background-color'] =
            this.getColor(setting.slice(1)) + ' !important'
          break
        case 'TEXTCOLOR':
          this.appliedStyle['color'] =
            this.getColor(setting.slice(1)) + ' !important'
          break
        case 'BORDERCOLOR':
          this.appliedStyle['border-width'] = '1px!important'
          this.appliedStyle['border-style'] = 'solid!important'
          this.appliedStyle['border-color'] =
            this.getColor(setting.slice(1)) + ' !important'
          break
        case 'WIDTH':
          if (!isNaN(Number(setting[1]))) {
            setting[1] += 'px'
          }
          this.appliedStyle['width'] = setting[1] + ' !important'
          break
        case 'HEIGHT':
          if (!isNaN(Number(setting[1]))) {
            setting[1] += 'px'
          }
          this.appliedStyle['height'] = setting[1] + ' !important'
          break
        case 'RAW':
          this.appliedStyle[setting[1].toLowerCase()] =
            setting[2] + ' !important'
          break
      }
    },
    verifyNumParams(keyword, min_num_params, max_num_params, usage = '') {
      let parser = {
        line: this.line,
        lineNumber: this.lineNumber,
        keyword: keyword,
        parameters: this.parameters,
      }

      // This syntax works with 0 because each doesn't return any values
      // for a backwards range
      for (let index = 1; index <= min_num_params; index++) {
        // If the parameter is nil (0 based) then we have a problem
        if (this.parameters[index - 1] === undefined) {
          throw new ConfigParserError(
            parser,
            `Not enough parameters for ${keyword}.`,
            usage,
            'https://docs.openc3.com/docs/configuration',
          )
        }
      }
      // If they pass null for max_params we don't check for a maximum number
      if (max_num_params !== null && this.parameters.length > max_num_params) {
        throw new ConfigParserError(
          parser,
          `Too many parameters for ${keyword}.`,
          usage,
          'https://docs.openc3.com/docs/configuration',
        )
      }
    },
    setWidth(width, units = 'px', defaultWidth = '120') {
      // Don't set the width if someone has already set it
      // This is important in PacketViewer which uses the value-widget
      // and passes an explicit width setting to use
      let foundSetting = this.appliedSettings.find(
        (setting) => setting[0] === 'WIDTH',
      )
      if (foundSetting) {
        return foundSetting['WIDTH']
      } else {
        if (width) {
          this.appliedSettings.push(['WIDTH', `${width}${units}`])
          return parseInt(width)
        } else {
          this.appliedSettings.push(['WIDTH', `${defaultWidth}${units}`])
          return parseInt(defaultWidth)
        }
      }
    },
    setHeight(height, units = 'px', defaultHeight = '20') {
      // Don't set the height if someone has already set it
      let foundSetting = null
      foundSetting = this.appliedSettings.find(
        (setting) => setting[0] === 'HEIGHT',
      )
      if (foundSetting) {
        return foundSetting['HEIGHT']
      } else {
        if (height) {
          this.appliedSettings.push(['HEIGHT', `${height}${units}`])
          return parseInt(height)
        } else {
          this.appliedSettings.push(['HEIGHT', `${defaultHeight}${units}`])
          return parseInt(defaultHeight)
        }
      }
    },
    // Expects an array, can either be a single color or 3 rgb values
    getColor(setting) {
      switch (setting.length) {
        case 1:
          return setting[0].toLowerCase()
        case 3:
          return `rgb(${setting[0]},${setting[1]},${setting[2]})`
      }
    },
    toQualifiedWidgetName(widgetName) {
      return `${this.screenId}:${widgetName}`
    },
  },
}
