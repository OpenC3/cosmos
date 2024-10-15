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

import { ConfigParserError } from '@openc3/tool-common/src/services/config-parser'
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
      appliedSettings: [],
      // We make style a data attribute so as we recurse through nested
      // widgets we can check to see if style attributes have been applied
      // at any level of the widget, i.e. if LABELVALUE applies a style
      // to the VALUE component then we don't want the VALUE widget to think
      // it doesn't have a style when it renders.
      style: {},
    }
  },
  computed: {
    computedStyle() {
      this.appliedSettings.forEach((setting) => {
        const index = parseInt(setting[0])
        if (this.widgetIndex !== null) {
          if (this.widgetIndex === index) {
            setting = setting.slice(1)
          } else {
            return
          }
        }
        this.applySetting(this.style, setting)
      })
      // If nothing has yet defined a width then we add flex to the style
      if (this.style['width'] === undefined) {
        // This flex allows for alignment in our widgets
        // The value of '0 10 100%' was achieved through trial and error
        // The larger flex-shrink value was critical for success
        this.style['flex'] = '0 10 100%' // flex-grow, flex-shrink, flex-basis
      }
      return this.style
    },
  },
  created() {
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
        // this effectively promotes'the subsetting to a setting
        // on the current widget
        if (this.widgetIndex === index) {
          return setting.slice(1)
        }
      })
      // Remove any settings that we filtered out with null
      .filter((setting) => setting !== undefined)
  },
  methods: {
    applySetting(style, setting) {
      switch (setting[0]) {
        case 'TEXTALIGN':
          style['text-align'] = setting[1].toLowerCase() + ' !important'
          style['--text-align'] = setting[1].toLowerCase()
          break
        case 'PADDING':
          if (!isNaN(Number(setting[1]))) {
            setting[1] += 'px'
          }
          style['padding'] = setting[1] + ' !important'
          break
        case 'MARGIN':
          if (!isNaN(Number(setting[1]))) {
            setting[1] += 'px'
          }
          style['margin'] = setting[1] + ' !important'
          break
        case 'BACKCOLOR':
          style['background-color'] =
            this.getColor(setting.slice(1)) + ' !important'
          break
        case 'TEXTCOLOR':
          style['color'] = this.getColor(setting.slice(1)) + ' !important'
          break
        case 'BORDERCOLOR':
          style['border-width'] = '1px!important'
          style['border-style'] = 'solid!important'
          style['border-color'] =
            this.getColor(setting.slice(1)) + ' !important'
          break
        case 'WIDTH':
          if (!isNaN(Number(setting[1]))) {
            setting[1] += 'px'
          }
          style['width'] = setting[1] + ' !important'
          break
        case 'HEIGHT':
          if (!isNaN(Number(setting[1]))) {
            setting[1] += 'px'
          }
          style['height'] = setting[1] + ' !important'
          break
        case 'RAW':
          style[setting[1].toLowerCase()] = setting[2] + ' !important'
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
      let foundSetting = null
      if (this.widgetIndex !== null) {
        foundSetting = this.appliedSettings.find(
          (setting) =>
            parseInt(setting[0]) === this.widgetIndex && setting[1] === 'WIDTH',
        )
      } else {
        foundSetting = this.appliedSettings.find(
          (setting) => setting[0] === 'WIDTH',
        )
      }
      if (foundSetting) {
        return foundSetting['WIDTH']
      } else {
        if (width) {
          let setting = ['WIDTH', `${width}${units}`]
          // If we have a widgetIndex apply that so we apply the width to ourselves
          if (this.widgetIndex !== null) {
            setting.unshift(this.widgetIndex)
          }
          this.appliedSettings.push(setting)
          return parseInt(width)
        } else {
          let setting = ['WIDTH', `${defaultWidth}${units}`]
          if (this.widgetIndex !== null) {
            setting.unshift(this.widgetIndex)
          }
          this.appliedSettings.push(setting)
          return parseInt(defaultWidth)
        }
      }
    },
    setHeight(height, units = 'px', defaultHeight = '20') {
      // Don't set the height if someone has already set it
      let foundSetting = null
      if (this.widgetIndex !== null) {
        foundSetting = this.appliedSettings.find(
          (setting) =>
            parseInt(setting[0]) === this.widgetIndex &&
            setting[1] === 'HEIGHT',
        )
      } else {
        foundSetting = this.appliedSettings.find(
          (setting) => setting[0] === 'HEIGHT',
        )
      }
      if (foundSetting) {
        return foundSetting['HEIGHT']
      } else {
        if (height) {
          let setting = ['HEIGHT', `${height}${units}`]
          // If we have a widgetIndex apply that so we apply the height to ourselves
          if (this.widgetIndex !== null) {
            setting.unshift(this.widgetIndex)
          }
          this.appliedSettings.push(setting)
          return parseInt(height)
        } else {
          let setting = ['HEIGHT', `${defaultHeight}${units}`]
          if (this.widgetIndex !== null) {
            setting.unshift(this.widgetIndex)
          }
          this.appliedSettings.push(setting)
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
  },
}
