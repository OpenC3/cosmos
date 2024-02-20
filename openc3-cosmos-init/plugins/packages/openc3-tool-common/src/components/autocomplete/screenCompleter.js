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

import Api from '../../services/api'

var tpi_data = {
  INST: {
    HEALTH_STATUS: {
      TEMP1: {},
      TEMP2: {},
      TEMP3: {},
      TEMP4: {},
    },
    MECH: {
      SLPNL1: {},
      SLPNL2: {},
    },
    PARAMS: {
      PARAM1: {},
    },
  },
  SYSTEM: {
    PKT: {
      ITEM: {},
    },
  },
}

var keywords = [
  {
    caption: 'HORIZONTAL',
    meta: 'Places the widgets it encapsulates horizontally',
    snippet: 'HORIZONTAL ${1:<Margin>}',
  },
  {
    caption: 'LABELVALUE',
    meta: 'Displays a LABEL with the item name followed by a VALUE',
    value: 'LABELVALUE ',
    command: 'startAutocomplete',
    params: [
      { RAW: {}, CONVERTED: {}, FORMATTED: {}, WITH_UNITS: {} },
      { '<Number of characters>': {} },
      { '<Something else>': 1 },
    ],
  },
  {
    caption: 'LABELVALUEDESC',
    meta: 'Displays a LABEL with the item description followed by a VALUE',
    command: 'startAutocomplete',
    params: [
      { RAW: {}, CONVERTED: {}, FORMATTED: {}, WITH_UNITS: {} },
      { '<Number of characters>': 1 },
    ],
  },
]

export default class ScreenCompleter {
  constructor() {
    Api.get(`/openc3-api/autocomplete/data/screen`).then((response) => {
      this.autocompleteData = response.data
    })
  }

  getCompletions = function (editor, session, pos, prefix, callback) {
    var line = session.getLine(pos.row)
    var lineBefore = line.slice(0, pos.column)
    var parsedLine = lineBefore.trimStart().split(/ (?![^<]*>)/)
    var suggestions = keywords
    // If we have more than 1 we've selected a keyword ... let the fun begin
    if (parsedLine.length > 1) {
      suggestions = suggestions.find((x) => x.caption === parsedLine[0])
    }
    let result = {}
    if (suggestions && suggestions['params']) {
      switch (parsedLine.length) {
        case 2:
          suggestions = tpi_data
          break
        case 3:
          suggestions = tpi_data[parsedLine[1]]
          break
        case 4:
          suggestions = tpi_data[parsedLine[1]][parsedLine[2]]
          break
        default:
          // Additional parameters are an array of items in the 'tgt_pkt_item_type' key
          suggestions = suggestions['params'][parsedLine.length - 5]
          break
      }
      result = Object.keys(suggestions || {}).map((x) => {
        var hasChildren = typeof suggestions[x] == 'object'
        return {
          value: x + (hasChildren ? ' ' : ''),
          command: hasChildren && 'startAutocomplete',
        }
      })
    } else {
      result = suggestions
    }
    callback(null, result)
  }
}
