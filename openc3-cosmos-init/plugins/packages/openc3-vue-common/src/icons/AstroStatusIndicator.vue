<!--
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
-->

<template>
  <div :style="iconStyle" />
</template>

<script>
import { AstroStatuses, UnknownToAstroStatus } from '.'
import dark from '../../public/icons/status-dark.png'

export default {
  props: {
    status: {
      type: String,
      required: true,
    },
    large: {
      type: Boolean,
    },
    small: {
      type: Boolean,
    },
    scale: {
      type: Number,
    },
  },
  computed: {
    icons: function () {
      return dark // TODO: check theme
    },
    scaleFactor: function () {
      if (this.scale) {
        return this.scale
      } else if (this.large) {
        return 1
      } else if (this.small) {
        return 0.3
      } else {
        return 0.5
      }
    },
    iconStyle: function () {
      const offset = AstroStatuses.indexOf(UnknownToAstroStatus[this.status])
      // Scale according to severity ... offset 1 is most severe (critical)
      // We knock off 5% for every less severe value
      const relativeScale = 1 - (offset - 1) * 0.05
      // The original png dimensions are 224x32 px
      const bgWidth = 224 * this.scaleFactor * relativeScale
      const bgHeight = 32 * this.scaleFactor * relativeScale
      const iconWidth = 32 * this.scaleFactor * relativeScale // Each icon in the png is 32px wide with no space in between
      return [
        `background-image: url(${this.icons});`,
        `background-position-x: -${offset * iconWidth}px;`,
        `background-size: ${bgWidth}px ${bgHeight}px;`,
        `height: ${iconWidth}px;`,
        `width: ${iconWidth}px;`,
        `padding-top: ${offset - 1}px;`,
      ].join('')
    },
  },
}
</script>
