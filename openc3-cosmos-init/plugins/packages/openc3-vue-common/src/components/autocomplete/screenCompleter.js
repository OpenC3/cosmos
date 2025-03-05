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

import { Api, OpenC3Api } from '@openc3/js-common/services'

// Test data useful for testing ScreenCompleter
// let autocompleteData = [
//   {
//     caption: 'HORIZONTAL',
//     meta: 'Places the widgets it encapsulates horizontally',
//     snippet: 'HORIZONTAL ${1:<Margin>}',
//   },
//   {
//     caption: 'LABELVALUE',
//     meta: 'Displays a LABEL with the item name followed by a VALUE',
//     value: 'LABELVALUE ',
//     command: 'startAutocomplete',
//     params: [
//       { 'Target name': 1 },
//       { 'Packet name': 1 },
//       { 'Item name': 1 },
//       { RAW: 'raw description', CONVERTED: 1, FORMATTED: 1, WITH_UNITS: 1 },
//       { '<Number of characters>': 'characters description' },
//     ],
//   },
// ]

export default class ScreenCompleter {
  constructor() {
    // See openc3-cosmos-cmd-tlm-api/app/controllers/script_autocomplete_controller.rb
    // for how the autocompleteData is built

    Api.get(`/openc3-api/autocomplete/data/screen`).then((response) => {
      this.autocompleteData = response.data
    })
    this.api = new OpenC3Api()
  }

  async getCompletions(editor, session, pos, prefix, callback) {
    let line = session.getLine(pos.row)
    let lineBefore = line.slice(0, pos.column)
    let parsedLine = lineBefore.trimStart().split(/ (?![^<]*>)/)
    let suggestions = this.autocompleteData
    // If we have more than 1 we've selected a keyword
    if (parsedLine.length > 1) {
      suggestions = suggestions.find((x) => x.caption === parsedLine[0])
    }
    let result = {}
    let more = true
    // If we found suggestions and the suggestions have params
    // then we do logic to substitute suggestions using the actual
    // target, packet, item data
    if (suggestions && suggestions['params']) {
      // Check if this is the last autocomplete parameter
      if (suggestions['params'].length == parsedLine.length - 1) {
        more = false
      }
      // parsedLine.length - 2 because the last element is blank
      // e.g. ['LABELVALUE', 'INST', '']
      let current = suggestions['params'][parsedLine.length - 2]
      // Check for Target name, Packet name, and Item name and use
      // api calls to substitute actual values for suggestions
      if (current['Target name']) {
        let target_names = await this.api.get_target_names()
        suggestions = target_names.reduce(
          (acc, curr) => ((acc[curr] = 1), acc),
          {},
        )
      } else if (current['Packet name']) {
        let target_name = parsedLine[parsedLine.length - 2]
        let packets = await this.api.get_all_tlm(target_name)
        suggestions = packets.reduce(
          (acc, pkt) => ((acc[pkt.packet_name] = pkt.description), acc),
          {},
        )
      } else if (current['Item name']) {
        let target_name = parsedLine[parsedLine.length - 3]
        let packet_name = parsedLine[parsedLine.length - 2]
        let packet = await this.api.get_tlm(target_name, packet_name)
        suggestions = packet.items.reduce(
          (acc, item) => ((acc[item.name] = item.description), acc),
          {},
        )
      } else {
        // Not a special case so just use the param as is
        suggestions = current
      }

      result = Object.keys(suggestions || {}).map((x) => {
        let completions = {
          value: x + (more ? ' ' : ''),
          // We want the autoComplete to continue right up
          // to the last parameter
          command: more && 'startAutocomplete',
        }
        // Only add the meta (description) if we have a string
        // This prevents adding (Object) descriptions
        if (typeof suggestions[x] === 'string') {
          completions['meta'] = suggestions[x]
        }
        return completions
      })
    } else {
      // The snippet case where we just inject the snippet
      result = suggestions
    }
    callback(null, result)
  }
}
