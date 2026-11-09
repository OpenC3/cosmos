/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

export default {
  props: {
    refreshInterval: {
      type: Number,
      default: 1000,
    },
  },
  data() {
    return {
      updater: null,
    }
  },
  mounted() {
    this.changeUpdater()
  },
  beforeUnmount() {
    if (this.updater != null) {
      clearInterval(this.updater)
      this.updater = null
    }
  },
  watch: {
    refreshInterval: function (newVal, oldVal) {
      this.changeUpdater()
    },
  },
  methods: {
    changeUpdater() {
      if (this.updater != null) {
        clearInterval(this.updater)
        this.updater = null
      }
      this.updater = setInterval(() => {
        this.update()
      }, this.refreshInterval)
      this.update()
    },
  },
}
