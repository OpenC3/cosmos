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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license 
# if purchased from OpenC3, Inc.
*/

import { ConfigParserError } from '@openc3/tool-common/src/services/config-parser'

export default {
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
    line: {
      type: String,
      default: ''
    },
    lineNumber: {
      type: Number,
      default: 0,
    }
  },
  computed: {
    computedStyle() {
      let style = {}
      this.settings.forEach((setting) => {
        const index = parseInt(setting[0])
        if (this.widgetIndex !== null) {
          if (this.widgetIndex === index) {
            setting = setting.slice(1)
          } else {
            return
          }
        }
        switch (setting[0]) {
          case 'TEXTALIGN':
            style['text-align'] = setting[1].toLowerCase()
            break
          case 'PADDING':
            style['padding'] = setting[1] + 'px !important'
            break
          case 'MARGIN':
            style['margin'] = setting[1] + 'px !important'
            break
          case 'BACKCOLOR':
            style['background-color'] = this.getColor(setting.slice(1))
            break
          case 'TEXTCOLOR':
            style['color'] = this.getColor(setting.slice(1))
            break
          case 'BORDERCOLOR':
            style['border-width'] = '1px'
            style['border-style'] = 'solid'
            style['border-color'] = this.getColor(setting.slice(1))
            break
          case 'WIDTH':
            style['width'] = setting[1] + 'px !important'
            break
          case 'HEIGHT':
            style['height'] = setting[1] + 'px !important'
            break
          case 'RAW':
            style[setting[1].toLowerCase()] = setting[2]
            break
        }
      })
      return style
    },
  },
  methods: {
    verifyNumParams(keyword, min_num_params, max_num_params, usage = '') {
      let parser = { line: this.line, lineNumber: this.lineNumber, keyword: keyword, parameters: this.parameters }

      // This syntax works with 0 because each doesn't return any values
      // for a backwards range
      for (var index = 1; index <= min_num_params; index++) {
        // If the parameter is nil (0 based) then we have a problem
        if (this.parameters[index - 1] === undefined) {
          throw new ConfigParserError(
            parser,
            `Not enough parameters for ${keyword}.`,
            usage,
            'https://openc3.com/docs/v5'
          )
        }
      }
      // If they pass null for max_params we don't check for a maximum number
      if (max_num_params && !this.parameters[max_num_params] === undefined) {
        throw new ConfigParserError(
          parser,
          `Too many parameters for ${keyword}.`,
          usage,
          'https://openc3.com/docs/v5'
        )
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
