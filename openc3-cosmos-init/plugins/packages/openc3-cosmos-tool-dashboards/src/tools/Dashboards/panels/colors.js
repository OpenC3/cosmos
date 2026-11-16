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

import { itemOption } from './options'

// The first 3 are the AstroUX DS data visualization colors
// (--color-data-visualization-1 through 3, as Graph.vue uses). Astro's 4 to 8
// are lighter tints of those, too alike to tell lines apart, so the rest are
// distinct hues, softer than the saturated status colors so a line doesn't
// read as a limits state. Hex rather than the CSS variables because uPlot and
// Leaflet draw on canvas, and these are what the color picker offers. Items
// can override theirs with ITEM_SETTING COLOR.
export const SERIES_COLORS = [
  '#00c7cb', // Astro data viz 1, cyan
  '#938bdb', // Astro data viz 2, purple
  '#4dacff', // Astro data viz 3, blue
  '#ff7eb6', // pink
  '#f6a25b', // orange
  '#9fdc6a', // light green
  '#d4b483', // tan
  '#f0f0f0', // white
]

export function seriesColor(panel, item, index) {
  return (
    itemOption(panel, item, 'COLOR') ||
    SERIES_COLORS[index % SERIES_COLORS.length]
  )
}
