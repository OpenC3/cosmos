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

const VALID_THEMES = new Set(['cosmosDark', 'cosmosDarkCobalt', 'cosmosDarkIndigo', 'cosmosDarkSlate', 'cosmosDarkEmerald'])

export default {
  created: function () {
    const api = new OpenC3Api()
    api
      .get_setting('theme')
      .then((response) => {
        if (!VALID_THEMES.has(response)) return
        switch (response) {
          case 'cosmosDarkCobalt':
            this.$vuetify.theme.global.name = 'cosmosDarkCobalt'
            document.documentElement.classList.add('theme-dark-cobalt')
            break
          case 'cosmosDarkIndigo':
            this.$vuetify.theme.global.name = 'cosmosDarkIndigo'
            document.documentElement.classList.add('theme-dark-indigo')
            break
          case 'cosmosDarkSlate':
            this.$vuetify.theme.global.name = 'cosmosDarkSlate'
            document.documentElement.classList.add('theme-dark-slate')
            break
          case 'cosmosDarkEmerald':
            this.$vuetify.theme.global.name = 'cosmosDarkEmerald'
            document.documentElement.classList.add('theme-dark-emerald')
            break
          // default: cosmosDark — no action needed, it's the default theme
        }
      })
      .catch((error) => {
        // Do nothing - default theme remains active
      })
  },
}
</script>