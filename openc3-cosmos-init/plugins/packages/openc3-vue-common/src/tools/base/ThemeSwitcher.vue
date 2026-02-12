<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<script>
import { OpenC3Api } from '@openc3/js-common/services'

export default {
  created: function () {
    const api = new OpenC3Api()
    api
      .get_setting('theme')
      .then((response) => {
        if (response === 'cosmosDarkGrey') {
          this.$vuetify.theme.global.name = 'cosmosDarkGrey'
          document.documentElement.classList.add('theme-dark-grey')
        }
      })
      .catch((error) => {
        // Do nothing - default theme remains active
      })
  },
}
</script>
