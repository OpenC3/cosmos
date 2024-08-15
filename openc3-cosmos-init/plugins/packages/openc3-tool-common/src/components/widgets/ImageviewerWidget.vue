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
  <img
    :src="src"
    :alt="itemFullName"
    :width="parameters[4]"
    :height="parameters[5]"
    :style="computedStyle"
  />
</template>

<script>
import Widget from '@openc3/tool-common/src/components/widgets/Widget'

export default {
  mixins: [Widget],
  data: function () {
    return {
      valueId: null,
      imageData: '',
    }
  },
  computed: {
    src: function () {
      return `data:image/${this.parameters[3]};base64, ${this.screen.screenValues[this.valueId][0]}`
    },
  },
  created: function () {
    // TODO: We're hard coding CONVERTED because the existing 4th parameter is the image format
    // Future breaking change would be to put the type as 4th and format as fifth
    this.valueId = `${this.parameters[0]}__${this.parameters[1]}__${this.parameters[2]}__CONVERTED`
    this.screen.addItem(this.valueId)
  },
  destroyed: function () {
    this.screen.deleteItem(this.valueId)
  },
}
</script>
