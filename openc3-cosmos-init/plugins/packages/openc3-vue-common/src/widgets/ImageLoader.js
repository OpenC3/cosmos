/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { Api } from '@openc3/js-common/services'

export default {
  props: {
    target: {
      type: String,
      require: true,
    },
  },
  methods: {
    getPresignedUrl: async function (fileName) {
      let targets = 'targets_modified'
      await Api.get(
        `/openc3-api/storage/exists/${encodeURIComponent(
          `${window.openc3Scope}/${targets}/${this.target}/public/${fileName}`,
        )}?bucket=OPENC3_CONFIG_BUCKET`,
        {
          headers: {
            Accept: 'application/json',
            // Since we're just checking for existence, 404 is possible so ignore it
            'Ignore-Errors': '404',
          },
        },
      ).catch((error) => {
        // If response fails then 'targets_modified' doesn't exist
        // so switch to 'targets' and then just try to get the URL
        // If the file doesn't exist it will throw a 404 when it is actually retrieved
        targets = 'targets'
      })
      let response = await Api.get(
        `/openc3-api/storage/download/${encodeURIComponent(
          `${window.openc3Scope}/${targets}/${this.target}/public/${fileName}`,
        )}?bucket=OPENC3_CONFIG_BUCKET`,
      )
      return response.data.url
    },
  },
}
