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
      { '<Target Name>': 1 },
      { '<Packet Name>': 1 },
      { '<Item Name>': 1 },
      { RAW: 1, CONVERTED: 1, FORMATTED: 1, WITH_UNITS: 1 },
      { '<Number of characters>': 1 },
    ],
  },
  {
    caption: 'LABELVALUEDESC',
    meta: 'Displays a LABEL with the item description followed by a VALUE',
    value: 'LABELVALUEDESC ',
    command: 'startAutocomplete',
    params: [
      { '<Target Name>': 1 },
      { '<Packet Name>': 1 },
      { '<Item Name>': 1 },
      { RAW: 1, CONVERTED: 1, FORMATTED: 1, WITH_UNITS: 1 },
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
    var result = {}
    var more = true
    if (suggestions && suggestions['params']) {
      // Check if this is the last autocomplete parameter
      if (suggestions['params'].length == parsedLine.length - 1) {
        more = false
      }
      // parsedLine.length - 2 because the last element is blank
      // e.g. ['LABELVALUE', 'INST', '']
      var current = suggestions['params'][parsedLine.length - 2]
      if (current['<Target Name>']) {
        suggestions = tpi_data
      } else if (current['<Packet Name>']) {
        suggestions = tpi_data[parsedLine[1]]
      } else if (current['<Item Name>']) {
        suggestions = tpi_data[parsedLine[1]][parsedLine[2]]
      } else {
        suggestions = suggestions['params'][parsedLine.length - 2]
      }

      result = Object.keys(suggestions || {}).map((x) => {
        return {
          value: x + (more ? ' ' : ''),
          command: more && 'startAutocomplete',
        }
      })
    } else {
      result = suggestions
    }
    callback(null, result)
  }
}
