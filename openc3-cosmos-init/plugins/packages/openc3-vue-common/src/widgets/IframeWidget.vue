<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <iframe
    title="IFrameWidget"
    :src="url"
    :width="width"
    :height="height"
    :style="computedStyle"
  />
</template>

<script>
import { sanitizeUrl } from '@braintree/sanitize-url'
import Widget from './Widget'

export default {
  mixins: [Widget],
  data: function () {
    return {
      width: 800,
      height: 600,
      url: sanitizeUrl(this.parameters[0]),
    }
  },
  created: function () {
    this.setWidth(this.parameters[1], 'px', this.width)
    this.setHeight(this.parameters[2], 'px', this.height)
  },
}
</script>
