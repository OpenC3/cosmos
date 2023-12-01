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

import Vue from 'vue'
import Vuetify from 'vuetify'
// Import and define the individual astro components we use
import { AstroIconVuetifyValues } from '../../../packages/openc3-tool-common/src/components/icons/index.js'
import { RuxClock } from '@astrouxds/astro-web-components/dist/components/rux-clock'
customElements.define('rux-clock', RuxClock)
import { RuxIcon } from '@astrouxds/astro-web-components/dist/components/rux-icon'
customElements.define('rux-icon', RuxIcon)
import { RuxStatus } from '@astrouxds/astro-web-components/dist/components/rux-status'
customElements.define('rux-status', RuxStatus)
import { RuxProgress } from '@astrouxds/astro-web-components/dist/components/rux-progress'
customElements.define('rux-progress', RuxProgress)
import '@astrouxds/astro-web-components/dist/astro-web-components/astro-web-components.css'

Vue.use(Vuetify)

export default new Vuetify({
  theme: {
    dark: true,
    options: {
      customProperties: true,
    },
    themes: {
      dark: {
        primary: '#005A8F',
        secondary: '#4DACFF',
        tertiary: '#BBC1C9',
      },
      light: {
        primary: '#cce6ff',
        secondary: '#cce6ff',
      },
    },
  },
  icons: {
    values: {
      ...AstroIconVuetifyValues,
    },
  },
})
