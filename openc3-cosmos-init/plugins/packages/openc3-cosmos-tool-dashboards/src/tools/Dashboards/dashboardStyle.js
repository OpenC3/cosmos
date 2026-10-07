/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

// A dashboard's icon and color, saved in its file so everyone sees them:
//
//   DASHBOARD "INST Overview"
//     SETTING ICON mdi-satellite-variant
//     SETTING COLOR "#d95926"

import { SERIES_COLORS } from './panels/colors'

export const DEFAULT_ICON = 'mdi-view-dashboard-outline'

export const DASHBOARD_ICONS = [
  DEFAULT_ICON,
  'mdi-satellite-variant',
  'mdi-rocket-launch-outline',
  'mdi-earth',
  'mdi-radar',
  'mdi-antenna',
  'mdi-access-point',
  'mdi-thermometer',
  'mdi-flash-outline',
  'mdi-battery-outline',
  'mdi-solar-panel',
  'mdi-engine-outline',
  'mdi-gauge',
  'mdi-chart-line',
  'mdi-heart-pulse',
  'mdi-shield-check-outline',
  'mdi-alert-outline',
  'mdi-cog-outline',
  'mdi-wrench-outline',
  'mdi-flask-outline',
  'mdi-camera-outline',
  'mdi-server',
  'mdi-lan',
  'mdi-home-outline',
]

export const DASHBOARD_COLORS = SERIES_COLORS

function first(settings, name) {
  return settings?.[name]?.[0] || null
}

// { icon, color } from a dashboard's settings; color null = theme default
export function dashboardStyle(settings) {
  const color = first(settings, 'COLOR')
  return {
    icon: first(settings, 'ICON') || DEFAULT_ICON,
    color:
      color && /^#?[0-9a-f]{6}$/i.test(color)
        ? `#${color.replace('#', '').toLowerCase()}`
        : null,
  }
}

// Settings with ICON / COLOR changed; defaults are left out of the file
export function withDashboardStyle(settings, { icon, color }) {
  const result = { ...settings }
  if (icon && icon !== DEFAULT_ICON) result.ICON = [icon]
  else delete result.ICON
  if (color) result.COLOR = [color]
  else delete result.COLOR
  return result
}
