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

var keywords = {
  HORIZONTAL: {
    caption: 'HORIZONTAL',
    meta: 'Places the widgets it encapsulates horizontally',
    snippet: 'HORIZONTAL ${1:<Margin>}',
  },
  LABELVALUE: {
    caption: 'LABELVALUE',
    meta: 'Displays a LABEL with the item name followed by a VALUE',
    tgt_pkt_item_type: [
      { '<Number of characters>': {} },
      { '<Something else>': 1 },
    ],
    // 'LABELVALUE ${1|<Target name>|} ${2:<Packet name>} ${3:<Item name>} ${4|RAW,CONVERTED,FORMATTED,WITH_UNITS|} ${5:<Number of characters>}',
  },
  LABELVALUEDESC: {
    caption: 'LABELVALUEDESC',
    meta: 'Displays a LABEL with the item description followed by a VALUE',
    tgt_pkt_item_type: 1,
    // snippet:
    //   'LABELVALUEDESC ${1|<Target name>|} ${2:<Packet name>} ${3:<Item name>} ${4|RAW,CONVERTED,FORMATTED,WITH_UNITS|} ${5:<Number of characters>}',
  },
}

export default class ScreenCompleter {
  constructor() {
    Api.get(`/openc3-api/autocomplete/data/screen`).then((response) => {
      console.log(response.data)
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
      suggestions = parsedLine[0] && suggestions && suggestions[parsedLine[0]]
    }
    var snippet = false
    console.log(suggestions)
    let result = {}
    if (suggestions['tgt_pkt_item_type']) {
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
        case 5:
          // If they specify additional values then add those to the TYPE keywords
          if (typeof suggestions['tgt_pkt_item_type'] == 'object') {
            suggestions = {
              RAW: suggestions['tgt_pkt_item_type'],
              CONVERTED: suggestions['tgt_pkt_item_type'],
              FORMATTED: suggestions['tgt_pkt_item_type'],
              WITH_UNITS: suggestions['tgt_pkt_item_type'],
            }
          } else {
            // Otherwise the TYPE keywords are the end of the line
            suggestions = { RAW: 1, CONVERTED: 1, FORMATTED: 1, WITH_UNITS: 1 }
          }
          break
        default:
          // Additional parameters are an array of items in the 'tgt_pkt_item_type' key
          suggestions = suggestions['tgt_pkt_item_type'][parsedLine.length - 6]
          break
      }
      result = Object.keys(suggestions || {}).map((x) => {
        var hasChildren = typeof suggestions[x] == 'object'
        return {
          value: x + (hasChildren ? ' ' : ''),
          command: hasChildren && 'startAutocomplete',
          snippet: !hasChildren && snippet,
        }
      })
    } else if (suggestions['snippet']) {
      console.log(suggestions['snippet'])
      result = suggestions
    } else {
      result = Object.keys(suggestions || {}).map((x) => {
        var hasChildren = typeof suggestions[x] == 'object'
        return {
          value: x + (hasChildren ? ' ' : ''),
          command: hasChildren && 'startAutocomplete',
          snippet: !hasChildren && snippet,
        }
      })
    }
    console.log(result)
    callback(
      null,
      result,
      // Object.keys(suggestions || {}).map((x) => {
      //   var hasChildren = typeof suggestions[x] == 'object'
      //   return {
      //     value: x + (hasChildren ? ' ' : ''),
      //     command: hasChildren && 'startAutocomplete',
      //     snippet: !hasChildren && snippet,
      //   }
      // }),
    )
  }
}
