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

import { defineCustomElement } from 'vue'
import { createVuetify } from 'vuetify'
import * as components from 'vuetify/components'
import * as directives from 'vuetify/directives'
import { aliases, mdi } from 'vuetify/iconsets/mdi'
import { VTreeview } from 'vuetify/labs/VTreeview'
import { AstroIconVuetifySets } from '../../../packages/openc3-tool-common/src/components/icons/index.js'

// Import and define the individual astro components we use
import { RuxClock } from '@astrouxds/astro-web-components/dist/components/rux-clock'
window.customElements.define('rux-clock', defineCustomElement(RuxClock))
import { RuxIcon } from '@astrouxds/astro-web-components/dist/components/rux-icon'
window.customElements.define('rux-icon', defineCustomElement(RuxIcon))
import { RuxIconApps } from '@astrouxds/astro-web-components/dist/components/rux-icon-apps'
window.customElements.define('rux-icon-apps', defineCustomElement(RuxIconApps))
import { RuxIconNotifications } from '@astrouxds/astro-web-components/dist/components/rux-icon-notifications'
window.customElements.define(
  'rux-icon-notifications',
  defineCustomElement(RuxIconNotifications),
)
import { RuxIconWarning } from '@astrouxds/astro-web-components/dist/components/rux-icon-warning'
window.customElements.define(
  'rux-icon-warning',
  defineCustomElement(RuxIconWarning),
)
import { RuxIconPerson } from '@astrouxds/astro-web-components/dist/components/rux-icon-person'
window.customElements.define(
  'rux-icon-person',
  defineCustomElement(RuxIconPerson),
)
import { RuxMonitoringIcon } from '@astrouxds/astro-web-components/dist/components/rux-monitoring-icon'
window.customElements.define(
  'rux-monitoring-icon',
  defineCustomElement(RuxMonitoringIcon),
)
import { RuxStatus } from '@astrouxds/astro-web-components/dist/components/rux-status'
window.customElements.define('rux-status', defineCustomElement(RuxStatus))
import { RuxProgress } from '@astrouxds/astro-web-components/dist/components/rux-progress'
window.customElements.define('rux-progress', defineCustomElement(RuxProgress))
import '@astrouxds/astro-web-components/dist/astro-web-components/astro-web-components.css'
// Define all the 'astro' icons take from
// https://github.com/RocketCommunicationsInc/astro-components/blob/master/static/json/rux-icons.json
// It would be nice if this could be a list and be dynamic but that caueses issue with webpack
import { RuxIconAltitude } from '@astrouxds/astro-web-components/dist/components/rux-icon-altitude'
window.customElements.define(
  'rux-icon-altitude',
  defineCustomElement(RuxIconAltitude),
)
import { RuxIconAntenna } from '@astrouxds/astro-web-components/dist/components/rux-icon-antenna'
window.customElements.define(
  'rux-icon-antenna',
  defineCustomElement(RuxIconAntenna),
)
import { RuxIconAntennaOff } from '@astrouxds/astro-web-components/dist/components/rux-icon-antenna-off'
window.customElements.define(
  'rux-icon-antenna-off',
  defineCustomElement(RuxIconAntennaOff),
)
import { RuxIconAntennaReceive } from '@astrouxds/astro-web-components/dist/components/rux-icon-antenna-receive'
window.customElements.define(
  'rux-icon-antenna-receive',
  defineCustomElement(RuxIconAntennaReceive),
)
import { RuxIconAntennaTransmit } from '@astrouxds/astro-web-components/dist/components/rux-icon-antenna-transmit'
window.customElements.define(
  'rux-icon-antenna-transmit',
  defineCustomElement(RuxIconAntennaTransmit),
)
import { RuxIconEquipment } from '@astrouxds/astro-web-components/dist/components/rux-icon-equipment'
window.customElements.define(
  'rux-icon-equipment',
  defineCustomElement(RuxIconEquipment),
)
import { RuxIconMission } from '@astrouxds/astro-web-components/dist/components/rux-icon-mission'
window.customElements.define(
  'rux-icon-mission',
  defineCustomElement(RuxIconMission),
)
import { RuxIconNetcom } from '@astrouxds/astro-web-components/dist/components/rux-icon-netcom'
window.customElements.define(
  'rux-icon-netcom',
  defineCustomElement(RuxIconNetcom),
)
import { RuxIconPayload } from '@astrouxds/astro-web-components/dist/components/rux-icon-payload'
window.customElements.define(
  'rux-icon-payload',
  defineCustomElement(RuxIconPayload),
)
import { RuxIconProcessor } from '@astrouxds/astro-web-components/dist/components/rux-icon-processor'
window.customElements.define(
  'rux-icon-processor',
  defineCustomElement(RuxIconProcessor),
)
import { RuxIconProcessorAlt } from '@astrouxds/astro-web-components/dist/components/rux-icon-processor-alt'
window.customElements.define(
  'rux-icon-processor-alt',
  defineCustomElement(RuxIconProcessorAlt),
)
import { RuxIconPropulsionPower } from '@astrouxds/astro-web-components/dist/components/rux-icon-propulsion-power'
window.customElements.define(
  'rux-icon-propulsion-power',
  defineCustomElement(RuxIconPropulsionPower),
)
import { RuxIconSatelliteOff } from '@astrouxds/astro-web-components/dist/components/rux-icon-satellite-off'
window.customElements.define(
  'rux-icon-satellite-off',
  defineCustomElement(RuxIconSatelliteOff),
)
import { RuxIconSatelliteReceive } from '@astrouxds/astro-web-components/dist/components/rux-icon-satellite-receive'
window.customElements.define(
  'rux-icon-satellite-receive',
  defineCustomElement(RuxIconSatelliteReceive),
)
import { RuxIconSatelliteTransmit } from '@astrouxds/astro-web-components/dist/components/rux-icon-satellite-transmit'
window.customElements.define(
  'rux-icon-satellite-transmit',
  defineCustomElement(RuxIconSatelliteTransmit),
)
import { RuxIconSolar } from '@astrouxds/astro-web-components/dist/components/rux-icon-solar'
window.customElements.define(
  'rux-icon-solar',
  defineCustomElement(RuxIconSolar),
)
import { RuxIconThermal } from '@astrouxds/astro-web-components/dist/components/rux-icon-thermal'
window.customElements.define(
  'rux-icon-thermal',
  defineCustomElement(RuxIconThermal),
)

export default createVuetify({
  components: {
    ...components,
    VTreeview,
  },
  directives,
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
    defaultSet: 'mdi',
    aliases: {
      ...aliases,
    },
    sets: {
      mdi,
      ...AstroIconVuetifySets,
    },
  },
})
