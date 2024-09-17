// Import and define the individual astro components we use
import { RuxClock } from '@astrouxds/astro-web-components/dist/components/rux-clock'
import { RuxIcon } from '@astrouxds/astro-web-components/dist/components/rux-icon'
import { RuxMonitoringIcon } from '@astrouxds/astro-web-components/dist/components/rux-monitoring-icon'
import { RuxStatus } from '@astrouxds/astro-web-components/dist/components/rux-status'
import { RuxProgress } from '@astrouxds/astro-web-components/dist/components/rux-progress'

import '@astrouxds/astro-web-components/dist/astro-web-components/astro-web-components.css'

const registerAstroComponents = function () {
  Object.entries({
    'rux-clock': RuxClock,
    'rux-icon': RuxIcon,
    'rux-monitoring-icon': RuxMonitoringIcon,
    'rux-status': RuxStatus,
    'rux-progress': RuxProgress,
  }).forEach((component) => {
    window.customElements.define(...component)
  })
}

export { registerAstroComponents }
