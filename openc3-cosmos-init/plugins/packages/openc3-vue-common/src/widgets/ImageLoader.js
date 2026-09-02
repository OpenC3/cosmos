/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { Api } from '@openc3/js-common/services'
import TargetFiles from './TargetFiles'

export default {
  mixins: [TargetFiles],
  props: {
    target: {
      type: String,
      require: true,
    },
  },
  methods: {
    getPresignedUrl: async function (fileName) {
      // targetFileRoot tells us where the image lives without probing for it.
      // If the file doesn't exist at all we get a 404 when actually retrieving
      // it, which is a real error worth seeing in the console.
      const filePath = `${this.target}/public/${fileName}`
      const targets = await this.targetFileRoot(filePath)
      const response = await Api.get(
        `/openc3-api/storage/download/${encodeURIComponent(
          `${window.openc3Scope}/${targets}/${filePath}`,
        )}?bucket=OPENC3_CONFIG_BUCKET`,
      )
      return response.data.url
    },
  },
}
