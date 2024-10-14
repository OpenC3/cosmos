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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-banner class="boxbanner" :style="computedStyle" single-line>{{
      parameters[0]
    }}</v-banner>
    <horizontal-widget
      v-bind="$attrs"
      :parameters="parameters.slice(1)"
      :settings="settings"
      :widgets="widgets"
      :screen-values="screenValues"
      :screen-time-zone="screenTimeZone"
    />
  </div>
</template>

<script>
import HorizontalWidget from './HorizontalWidget'
import Layout from './Layout'
export default {
  mixins: [Layout],
  components: {
    HorizontalWidget,
  },
}
</script>

<style scoped>
.boxbanner >>> .v-banner__wrapper {
  padding: 4px !important;
}
.boxbanner >>> .v-banner__text {
  font-weight: 600;
  font-size: 16px;
}
</style>
