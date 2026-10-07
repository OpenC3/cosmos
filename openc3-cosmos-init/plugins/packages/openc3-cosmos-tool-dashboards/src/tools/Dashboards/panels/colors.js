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

// Series colors from the style system, in the order new items take them.
// Items can override theirs with ITEM_SETTING COLOR.
export const SERIES_COLORS = [
  '#3987e5',
  '#d95926',
  '#199e70',
  '#b36ae2',
  '#e2b13c',
  '#3fb8c4',
  '#e05c8a',
  '#8a9a3a',
]

export function seriesColor(panel, item, index) {
  return (
    itemOption(panel, item, 'COLOR') ||
    SERIES_COLORS[index % SERIES_COLORS.length]
  )
}
