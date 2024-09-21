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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
*/

import { createVuetify } from 'vuetify'
import * as components from 'vuetify/components'
import * as directives from 'vuetify/directives'
import { mdi } from 'vuetify/iconsets/mdi'
import { VTreeview } from 'vuetify/labs/VTreeview'
import { AstroIconVuetifySets } from '../../../packages/openc3-tool-common/src/components/icons/index.js'
import cosmosDark from '../../../packages/openc3-tool-common/src/plugins/cosmosThemeDark'

import '@astrouxds/astro-web-components/dist/astro-web-components/astro-web-components.css'

export default createVuetify({
  components: {
    ...components,
    VTreeview,
  },
  directives,
  theme: {
    defaultTheme: 'cosmosDark',
    themes: {
      cosmosDark,
    },
  },
  icons: {
    defaultSet: 'mdi',
    sets: {
      mdi,
      ...AstroIconVuetifySets,
    },
  },
})
