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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import Widget from './Widget'
export default {
  mixins: [Widget],
  props: {
    widgets: {
      type: Array,
      default: () => [],
    },
  },
  methods: {
    getTooltipText(widget) {
      const setting = widget.settings?.find((s) => s[0] === 'TOOLTIP')
      return setting ? setting[1] : null
    },
    getTooltipDelay(widget) {
      const setting = widget.settings?.find((s) => s[0] === 'TOOLTIP')
      return setting && setting[2] ? parseInt(setting[2]) : 600
    },
    getTooltipActivatorProps(widget) {
      // Check if widget has explicit width set - if so, don't apply flex grow
      const hasWidthSetting = widget.settings?.some(
        (s) =>
          s[0] === 'WIDTH' ||
          (s[0]?.startsWith?.('RAW') &&
            s[1]?.toUpperCase?.().includes('WIDTH')),
      )
      // VALUE widget always has a default width
      const isValueWidget = widget.type === 'ValueWidget'
      // Only apply flex: 1 1 auto if widget doesn't have explicit width
      return hasWidthSetting || isValueWidget ? {} : { style: 'flex: 1 1 auto' }
    },
  },
}
