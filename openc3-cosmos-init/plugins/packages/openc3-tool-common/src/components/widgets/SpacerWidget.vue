<!--
# Copyright 2024 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div :style="computedStyle" />
</template>

<script>
/*
  TODO: this is somehow getting `flex: 0 10 100%` even if you try to hardcode it away or completely remove this
  style prop

  I think it comes from computedStyle() in Widget.js and it might be some sort of race condition related to
  appliedSettings. You can see this by adding a console.log where it applies that flex property (line ~87) to log
  `this.line` (so you can find the log message when it's processing the SPACER widget). It WON'T log for this widget,
  which is correct since WIDTH gets set here in created() so it shouldn't enter that if block, but that style gets
  applied anyway. If you comment out the line in computedStyle() where is sets flex, this widget renders correctly,
  but that then breaks widgets that rely on the flex style being applied.

  The fact that this div still gets that flex style even if you remove `:style=...` here or hardcode it to
  `style="flex: unset"` baffles me.

  Unsure if this issue is also happening to other widgets, but it seems likely.
 */
import Widget from './Widget'

export default {
  mixins: [Widget],
  data() {
    return {
      componentSettings: [
        ['WIDTH', this.parameters[0]],
        ['HEIGHT', this.parameters[1]],
      ],
    }
  },
}
</script>
