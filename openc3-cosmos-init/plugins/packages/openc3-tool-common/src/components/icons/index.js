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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import AstroIcon from './AstroIcon'
import AstroStatusIndicator from './AstroStatusIndicator'

const AstroIconLibrary = [
  // These are from the IDs in the default RuxIcon library: https://github.com/RocketCommunicationsInc/astro-components/blob/master/static/icons/astro.svg
  'altitude',
  'antenna',
  'antenna-off',
  'antenna-receive',
  'antenna-transmit',
  'equipment',
  'mission',
  'payload',
  'processor',
  'processor-alt',
  'netcom',
  'propulsion-power',
  'thermal',
  'satellite-off',
  'satellite-receive',
  'satellite-transmit',
  'add-large',
  'add-small',
  'close-large',
  'close-small',
  'collapse',
  'expand',
  'lock',
  'unlock',
  'search',
  'caution',
  'maintenance',
  'notifications',
  'settings',

  // These are in that SVG file, but they're broken in RuxIcon:
  // 'twitter', // the twitter logo
  // 'progress', // circle
  // 'resources', // filing cabinet
  // 'solar', // grid
]

const UnknownToAstroStatus = {
  fatal: 'fatal',
  FATAL: 'fatal',
  error: 'critical',
  ERROR: 'critical',
  warn: 'serious',
  WARN: 'serious',
  info: 'normal',
  INFO: 'normal',
  debug: 'off',
  DEBUG: 'off',
  critical: 'critical',
  CRITICAL: 'critical',
  serious: 'serious',
  SERIOUS: 'serious',
  caution: 'caution',
  CAUTION: 'caution',
  normal: 'normal',
  NORMAL: 'normal',
  standby: 'standby',
  STANDBY: 'standby',
  off: 'off',
  OFF: 'OFF',
}

const UnknownToCosmosStatus = {
  fatal: 'FATAL',
  FATAL: 'FATAL',
  error: 'ERROR',
  ERROR: 'ERROR',
  warn: 'WARN',
  WARN: 'WARN',
  info: 'INFO',
  INFO: 'INFO',
  debug: 'DEBUG',
  DEBUG: 'DEBUG',
  critical: 'ERROR',
  CRITICAL: 'ERROR',
  serious: 'WARN',
  SERIOUS: 'WARN',
  caution: 'WARN',
  CAUTION: 'WARN',
  normal: 'INFO',
  NORMAL: 'INFO',
  standby: 'INFO',
  STANDBY: 'INFO',
  off: 'INFO',
  OFF: 'INFO',
}

const AstroStatusColors = {
  fatal: '#ff69B4',
  critical: '#ff3838',
  serious: '#ffb302',
  caution: '#fce83a',
  normal: '#56f000',
  standby: '#2dccff',
  off: '#9ea7ad',
}

const getStatusColorContrast = function (severity) {
  const black = '#000000'
  const white = '#ffffff'

  const statusColor = AstroStatusColors[UnknownToAstroStatus[severity]]
  if (statusColor) {
    const r = Number(`0x${statusColor.slice(1, 3)}`)
    const g = Number(`0x${statusColor.slice(3, 5)}`)
    const b = Number(`0x${statusColor.slice(5, 7)}`)
    const brightness = (r * 299 + g * 587 + b * 114) / 1000 // https://www.w3.org/TR/AERT/#color-contrast

    if (brightness > 128) return black
  }
  return white
}

const AstroStatuses = Object.keys(AstroStatusColors)

const AstroRegularIcons = AstroIconLibrary.reduce((values, icon) => {
  return {
    [`astro-${icon}`]: {
      component: AstroIcon,
      props: {
        icon,
      },
    },
    ...values,
  }
}, {})
const AstroStatusIcons = AstroStatuses.reduce((values, status) => {
  return {
    [`astro-status-${status}`]: {
      component: AstroStatusIndicator,
      props: {
        status: status,
      },
    },
    ...values,
  }
}, {})
const AstroIconVuetifyValues = { ...AstroRegularIcons, ...AstroStatusIcons }

export {
  AstroIconLibrary,
  AstroIconVuetifyValues,
  AstroStatuses,
  AstroStatusColors,
  getStatusColorContrast,
  UnknownToAstroStatus,
  UnknownToCosmosStatus,
}
