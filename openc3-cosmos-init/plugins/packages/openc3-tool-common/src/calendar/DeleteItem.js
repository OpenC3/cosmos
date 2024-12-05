/*
# Copyright 2023 OpenC3, Inc.
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

import { Api } from '@openc3/js-common/services'

export default {
  methods: {
    deleteItem(item) {
      let start = null
      let api = ''
      switch (item.type.toLowerCase()) {
        case 'activity':
          api = 'activity'
          start = item.activity.start
          break
        case 'metadata':
          api = 'metadata'
          start = item.metadata.start
          break
        case 'note':
          api = 'notes'
          start = item.note.start
          break
      }
      this.$dialog
        .confirm(
          `Are you sure you want to remove ${item.typeStr} at ${item.startStr}`,
          {
            okText: 'Delete',
            cancelText: 'Cancel',
          },
        )
        .then(() => {
          return Api.delete(`/openc3-api/${api}/${start}`)
        })
        .then(() => {
          this.$emit('delete', item)
          this.$notify.normal({
            title: `Deleted ${item.typeStr}`,
            body: `Deleted ${item.typeStr} at ${item.startStr}`,
          })
        })
        .catch(() => {})
    },
  },
}
