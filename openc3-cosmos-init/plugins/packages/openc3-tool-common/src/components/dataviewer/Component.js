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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

export default {
  props: {
    config: {
      type: Object,
    },
    packets: {
      type: Array, // of objects
    },
  },
  data: function () {
    return {
      currentConfig: {},
      currentPackets: [],
      // Components watch this to 'receive' all packets
      latestData: null,
    }
  },
  computed: {
    hasRaw: function () {
      for (let i = 0; i < this.currentPackets.length; i++) {
        if (this.currentPackets[i].mode === 'RAW') {
          return true
        }
      }
      return false
    },
    hasDecom: function () {
      for (let i = 0; i < this.currentPackets.length; i++) {
        if (this.currentPackets[i].mode === 'DECOM') {
          return true
        }
      }
      return false
    },
  },
  watch: {
    currentConfig: {
      deep: true,
      handler: function (val) {
        this.$emit('config', val)
      },
    },
  },
  created: function () {
    if (this.config) {
      this.currentConfig = {
        ...this.config,
      }
    }
    if (this.packets) {
      this.currentPackets = [...this.packets]
    }
  },
  methods: {
    receive: function (data) {
      // This is called by DataViewer to feed this component data. A function is used instead
      // of a prop to ensure each message gets handled, regardless of how fast they come in
      this.latestData = data
    },
  },
}
