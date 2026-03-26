/*
# Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

export function limitsColor(limitsState) {
  if (limitsState != null) {
    switch (limitsState) {
      case 'GREEN':
      case 'GREEN_HIGH':
      case 'GREEN_LOW':
        return 'green'
      case 'YELLOW':
      case 'YELLOW_HIGH':
      case 'YELLOW_LOW':
        return 'yellow'
      case 'RED':
      case 'RED_HIGH':
      case 'RED_LOW':
        return 'red'
      case 'BLUE':
        return 'blue'
      case 'STALE':
        return 'purple'
      default:
        return 'white'
    }
  }
  return ''
}

export function astroStatus(color) {
  switch (color) {
    case 'green':
      return 'normal'
    case 'yellow':
      return 'caution'
    case 'red':
      return 'critical'
    case 'blue':
      // This one is a little weird but it matches our color scheme
      return 'standby'
    default:
      return null
  }
}
