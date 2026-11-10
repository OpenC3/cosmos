/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { OpenC3Api } from '@openc3/js-common/services'

let names = null

// Target names for pickers, sorted and without UNKNOWN, fetched once per
// page. A failed fetch is retried on the next call.
export function targetNames() {
  names ||= new OpenC3Api()
    .get_target_names()
    .then((list) => list.filter((name) => name !== 'UNKNOWN').sort())
    .catch((error) => {
      names = null
      throw error
    })
  return names
}
