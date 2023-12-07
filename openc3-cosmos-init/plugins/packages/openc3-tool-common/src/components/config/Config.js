/*
# Copyright 2023 OpenC3, Inc.
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
*/

import { OpenC3Api } from '../../services/openc3-api'

export default {
  data: {
    configKey: '',
    // Applications can set to avoid persisting default config
    // Useful when loading and setting existing config
    dontSaveDefaultConfig: false,
  },
  methods: {
    loadDefaultConfig: function () {
      if (localStorage[`${this.configKey}__default`]) {
        return JSON.parse(localStorage[`${this.configKey}__default`])
      } else {
        return {}
      }
    },
    saveDefaultConfig: function (config) {
      if (this.dontSaveDefaultConfig === true) {
        return
      }
      localStorage[`${this.configKey}__default`] = JSON.stringify(config)
    },
    openConfigBase: function (name, routed = false, callback = null) {
      new OpenC3Api()
        .load_config(this.configKey, name)
        .then((response) => {
          if (response) {
            this.$notify.normal({
              title: 'Loading configuration',
              body: name,
            })
            if (callback) callback(JSON.parse(response))
            if (!routed) {
              if (!this.$router.currentRoute.fullPath.includes(name)) {
                this.$router.push({
                  query: {
                    config: name,
                  },
                })
              }
            }
          } else {
            this.$notify.caution({
              title: 'Unknown configuration',
              body: name,
            })
          }
        })
        .catch((error) => {
          if (error) {
            this.$notify.serious({
              title: `Error opening configuration: ${name}`,
              body: error,
            })
          }
        })
    },
    saveConfigBase: function (name, config) {
      new OpenC3Api()
        .save_config(this.configKey, name, JSON.stringify(config))
        .then(() => {
          this.$notify.normal({
            title: 'Saved configuration',
            body: name,
          })
        })
        .catch((error) => {
          if (error) {
            this.$notify.serious({
              title: `Error saving configuration: ${name}`,
              body: error,
            })
          }
        })
    },
    resetConfigBase: function () {
      localStorage.removeItem(`${this.configKey}__default`)
      // fullPath includes the query options like: ?config=test
      if (this.$router.currentRoute.fullPath !== '/') {
        this.$router.replace(this.$router.currentRoute.path)
        this.$router.go()
      }
    },
  },
}
