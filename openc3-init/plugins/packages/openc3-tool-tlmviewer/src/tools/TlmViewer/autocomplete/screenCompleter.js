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
*/

import Api from '@openc3/tool-common/src/services/api'

const getKeywords = (type) => {
  return Api.get(`/openc3-api/autocomplete/keywords/${type}`)
}

const getAutocompleteData = (type) => {
  return Api.get(`/openc3-api/autocomplete/data/${type}`)
}

const toMethodCallSyntaxRegex = (word) => {
  return new RegExp(`^\\s*${word}\\s?$`) // ensure end of line because it's sliced to the current cursor position
}

export default class ScreenCompleter {
  constructor() {
    this.keywordExpressions = [] // Keywords that trigger the autocomplete feature
    this.autocompleteData = [] // Data to populate the autocomplete list

    getKeywords('screen').then((response) => {
      console.log('keywords:')
      console.log(response)
      this.keywordExpressions = response.data.map(toMethodCallSyntaxRegex)
      console.log(this.keywordExpressions)
    })
    getAutocompleteData('screen').then((response) => {
      console.log('autocomplete:')
      console.log(response)
      this.autocompleteData = response.data
    })
  }

  getCompletions = function (editor, session, position, prefix, callback) {
    let matches = []
    const lineBeforeCursor = session.doc.$lines[position.row].slice(
      0,
      position.column
    )
    console.log(lineBeforeCursor)
    if (
      this.keywordExpressions.some((regex) => lineBeforeCursor.match(regex))
    ) {
      console.log('match!')
      matches = this.autocompleteData
    } else {
      matches = this.autocompleteData
    }

    callback(null, [...matches])
  }
}
