/*
# Copyright 2022 OpenC3, Inc.
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

const fileIcon = function (filename) {
  if (filename && filename.includes('.')) {
    let ext = filename.split('.').pop()
    if (ext === 'py') {
      return 'mdi-language-python'
    } else if (ext === 'rb') {
      return 'mdi-language-ruby'
    } else if (ext === 'js') {
      return 'mdi-language-javascript'
    } else if (ext === 'csv') {
      return 'mdi-file-delimited'
    } else if (ext === 'txt') {
      return 'mdi-file-document'
    } else if (ext === 'png' || ext === 'gif' || ext === 'jpg') {
      return 'mdi-file-image'
    }
  }
  return 'mdi-file'
}

export { fileIcon }
