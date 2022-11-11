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

import Api from '@openc3/tool-common/src/services/api'

export default class ScreenCompleter {
  constructor() {
    Api.get(`/openc3-api/autocomplete/data/screen`).then(
      (response) => (this.autocompleteData = response.data)
    )
  }
  getCompletions = function (editor, session, position, prefix, callback) {
    callback(null, [...this.autocompleteData])
  }
}
