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
  <v-container class="pt-0">
    <span>Raw Packet Key / Values</span>
    <v-textarea
      ref="textarea"
      :value="displayText"
      readonly
      solo
      flat
      hide-details
      data-test="dump-component-text-area"
    />
  </v-container>
</template>

<script>
export default {
  data: function () {
    return {
      displayText: 'start',
    }
  },
  methods: {
    // Custom DataViewer widgets must implement receive() to function
    receive: function (data) {
      data.forEach((packet) => {
        this.displayText += Object.keys(packet)
          .filter((item) => item.slice(0, 2) != '__')
          .map((item) => `${item}: ${packet[item]}`)
          .join('\n')
      })
    },
  },
}
</script>
