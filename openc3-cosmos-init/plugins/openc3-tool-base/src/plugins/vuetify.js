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

// Import and define the individual astro components we use
import { AstroIconVuetifyValues } from '../../../packages/openc3-tool-common/src/components/icons/index.js'
import { RuxClock } from '@astrouxds/astro-web-components/dist/components/rux-clock'
customElements.define('rux-clock', RuxClock)
import { RuxIcon } from '@astrouxds/astro-web-components/dist/components/rux-icon'
customElements.define('rux-icon', RuxIcon)
import { RuxIconApps } from '@astrouxds/astro-web-components/dist/components/rux-icon-apps'
customElements.define('rux-icon-apps', RuxIconApps)
import { RuxIconNotifications } from '@astrouxds/astro-web-components/dist/components/rux-icon-notifications'
customElements.define('rux-icon-notifications', RuxIconNotifications)
import { RuxIconWarning } from '@astrouxds/astro-web-components/dist/components/rux-icon-warning'
customElements.define('rux-icon-warning', RuxIconWarning)
import { RuxIconPerson } from '@astrouxds/astro-web-components/dist/components/rux-icon-person'
customElements.define('rux-icon-person', RuxIconPerson)
import { RuxMonitoringIcon } from '@astrouxds/astro-web-components/dist/components/rux-monitoring-icon'
customElements.define('rux-monitoring-icon', RuxMonitoringIcon)
import { RuxStatus } from '@astrouxds/astro-web-components/dist/components/rux-status'
customElements.define('rux-status', RuxStatus)
import { RuxProgress } from '@astrouxds/astro-web-components/dist/components/rux-progress'
customElements.define('rux-progress', RuxProgress)
import '@astrouxds/astro-web-components/dist/astro-web-components/astro-web-components.css'
// Define all the 'astro' icons take from
// https://github.com/RocketCommunicationsInc/astro-components/blob/master/static/json/rux-icons.json
// It would be nice if this could be a list and be dynamic but that caueses issue with webpack
import { RuxIconAltitude } from '@astrouxds/astro-web-components/dist/components/rux-icon-altitude'
customElements.define('rux-icon-altitude', RuxIconAltitude)
import { RuxIconAntenna } from '@astrouxds/astro-web-components/dist/components/rux-icon-antenna'
customElements.define('rux-icon-antenna', RuxIconAntenna)
import { RuxIconAntennaOff } from '@astrouxds/astro-web-components/dist/components/rux-icon-antenna-off'
customElements.define('rux-icon-antenna-off', RuxIconAntennaOff)
import { RuxIconAntennaReceive } from '@astrouxds/astro-web-components/dist/components/rux-icon-antenna-receive'
customElements.define('rux-icon-antenna-receive', RuxIconAntennaReceive)
import { RuxIconAntennaTransmit } from '@astrouxds/astro-web-components/dist/components/rux-icon-antenna-transmit'
customElements.define('rux-icon-antenna-transmit', RuxIconAntennaTransmit)
import { RuxIconEquipment } from '@astrouxds/astro-web-components/dist/components/rux-icon-equipment'
customElements.define('rux-icon-equipment', RuxIconEquipment)
import { RuxIconMission } from '@astrouxds/astro-web-components/dist/components/rux-icon-mission'
customElements.define('rux-icon-mission', RuxIconMission)
import { RuxIconNetcom } from '@astrouxds/astro-web-components/dist/components/rux-icon-netcom'
customElements.define('rux-icon-netcom', RuxIconNetcom)
import { RuxIconPayload } from '@astrouxds/astro-web-components/dist/components/rux-icon-payload'
customElements.define('rux-icon-payload', RuxIconPayload)
import { RuxIconProcessor } from '@astrouxds/astro-web-components/dist/components/rux-icon-processor'
customElements.define('rux-icon-processor', RuxIconProcessor)
import { RuxIconProcessorAlt } from '@astrouxds/astro-web-components/dist/components/rux-icon-processor-alt'
customElements.define('rux-icon-processor-alt', RuxIconProcessorAlt)
import { RuxIconPropulsionPower } from '@astrouxds/astro-web-components/dist/components/rux-icon-propulsion-power'
customElements.define('rux-icon-propulsion-power', RuxIconPropulsionPower)
import { RuxIconSatelliteOff } from '@astrouxds/astro-web-components/dist/components/rux-icon-satellite-off'
customElements.define('rux-icon-satellite-off', RuxIconSatelliteOff)
import { RuxIconSatelliteReceive } from '@astrouxds/astro-web-components/dist/components/rux-icon-satellite-receive'
customElements.define('rux-icon-satellite-receive', RuxIconSatelliteReceive)
import { RuxIconSatelliteTransmit } from '@astrouxds/astro-web-components/dist/components/rux-icon-satellite-transmit'
customElements.define('rux-icon-satellite-transmit', RuxIconSatelliteTransmit)
import { RuxIconSolar } from '@astrouxds/astro-web-components/dist/components/rux-icon-solar'
customElements.define('rux-icon-solar', RuxIconSolar)
import { RuxIconThermal } from '@astrouxds/astro-web-components/dist/components/rux-icon-thermal'
customElements.define('rux-icon-thermal', RuxIconThermal)

export default createVuetify({
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
