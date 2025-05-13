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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { h } from 'vue'
import AstroStatusIndicator from './AstroStatusIndicator.vue'
import CosmosRuxIcon from './CosmosRuxIcon.vue'
import CustomIcon from './CustomIcon.vue'

const UnknownToAstroStatus = {
  fatal: 'critical',
  FATAL: 'critical',
  error: 'critical',
  ERROR: 'critical',
  warn: 'caution',
  WARN: 'caution',
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
  off: '#a4abb6',
}

const getStatusColorContrast = function (severityLevel) {
  const black = '#000000'
  const white = '#ffffff'

  const statusColor = AstroStatusColors[UnknownToAstroStatus[severityLevel]]
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

const AstroIconVuetifySets = {
  astro: {
    component: (props) => {
      return h(CosmosRuxIcon, {
        ...props,
      })
    },
  },
  ['astro-status']: {
    component: (props) => {
      return h(AstroStatusIndicator, {
        ...props,
        status: props.icon,
      })
    },
  },
}

const CustomIconSet = {
  extras: {
    component: (props) => {
      return h(CustomIcon, {
        ...props,
      })
    },
  },
}

export {
  AstroIconVuetifySets,
  AstroStatuses,
  AstroStatusColors,
  AstroStatusIndicator,
  CustomIconSet,
  getStatusColorContrast,
  UnknownToAstroStatus,
  UnknownToCosmosStatus,
}
