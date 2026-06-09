/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { OpenC3Api } from '@openc3/js-common/services'

export const CONFIG_POSTFIX = '__default'
export default {
  data: {
    // Applications can set to avoid persisting default config
    // Useful when loading and setting existing config
    dontSaveDefaultConfig: false,
  },
  created: function () {
    if (!this.configKey) {
      alert('Components using the Config mixin must provide a configKey')
      throw new Error(
        'Components using the Config mixin must provide a configKey',
      )
    }
  },
  computed: {
    storageKey() {
      return `${this.configKey}${CONFIG_POSTFIX}`
    },
  },
  methods: {
    loadDefaultConfig: function () {
      if (localStorage[this.storageKey]) {
        return JSON.parse(localStorage[this.storageKey])
      } else {
        return {}
      }
    },
    saveDefaultConfig: function (config) {
      if (this.dontSaveDefaultConfig === true) {
        return
      }
      localStorage[this.storageKey] = JSON.stringify(config)
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
              if (!this.$route.fullPath.includes(name)) {
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
      localStorage.removeItem(this.storageKey)

      const query = { ...this.$route.query }
      delete query.config
      this.$router.replace({ query })
    },
  },
}
