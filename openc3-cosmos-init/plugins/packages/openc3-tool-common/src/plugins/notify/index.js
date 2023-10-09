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

import Toast from './Toast.vue'

class Notify {
  constructor(Vue, options = {}) {
    this.Vue = Vue
    this.$store = options.store
    this.mounted = false
    this.$root = null
  }

  mount = function () {
    if (this.mounted) return

    const ToastConstructor = this.Vue.extend(Toast)
    const toast = new ToastConstructor()

    const el = document.createElement('div')
    document.querySelector('#openc3-app-toolbar > div').appendChild(el)
    this.$root = toast.$mount(el)

    this.mounted = true
  }

  open = function ({
    method,
    title,
    body,
    log,
    severity,
    duration,
    type = 'alert',
    logToConsole = false,
    saveToHistory = true,
  }) {
    this.mount()
    if (logToConsole) {
      // eslint-disable-next-line no-console
      if (log) {
        console.log(`${severity.toUpperCase()} - ${log}`)
      } else {
        console.log(`${severity.toUpperCase()} - ${title}: ${body}`)
      }
    }
    if (saveToHistory) {
      this.$store.commit('notifyAddHistory', { title, body, log, severity })
    }
    this[method]({ title, body, log, severity, duration, type })
  }

  toast = function ({ title, body, log, severity, duration, type }) {
    this.$root.toast(
      {
        title,
        body,
        log,
        severity,
        type,
      },
      duration,
    )
  }

  critical = function ({
    title,
    body,
    log,
    type,
    duration,
    logToConsole,
    saveToHistory,
  }) {
    this.open({
      method: 'toast',
      severity: 'critical',
      title,
      body,
      log,
      type,
      duration,
      logToConsole,
      saveToHistory,
    })
  }
  FATAL = this.critical
  ERROR = this.critical

  serious = function ({
    title,
    body,
    log,
    type,
    duration,
    logToConsole,
    saveToHistory,
  }) {
    this.open({
      method: 'toast',
      severity: 'serious',
      title,
      body,
      log,
      type,
      duration,
      logToConsole,
      saveToHistory,
    })
  }
  caution = function ({
    title,
    body,
    log,
    type,
    duration,
    logToConsole,
    saveToHistory,
  }) {
    this.open({
      method: 'toast',
      severity: 'caution',
      title,
      body,
      log,
      type,
      duration,
      logToConsole,
      saveToHistory,
    })
  }
  WARN = this.caution

  normal = function ({
    title,
    body,
    log,
    type,
    duration,
    logToConsole,
    saveToHistory,
  }) {
    this.open({
      method: 'toast',
      severity: 'normal',
      title,
      body,
      log,
      type,
      duration,
      logToConsole,
      saveToHistory,
    })
  }
  INFO = this.normal
  DEBUG = this.normal

  standby = function ({
    title,
    body,
    log,
    type,
    duration,
    logToConsole,
    saveToHistory,
  }) {
    this.open({
      method: 'toast',
      severity: 'standby',
      title,
      body,
      log,
      type,
      duration,
      logToConsole,
      saveToHistory,
    })
  }
  off = function ({
    title,
    body,
    log,
    type,
    duration,
    logToConsole,
    saveToHistory,
  }) {
    this.open({
      method: 'toast',
      severity: 'off',
      title,
      body,
      log,
      type,
      duration,
      logToConsole,
      saveToHistory,
    })
  }
}

export default {
  install(Vue, options) {
    if (!Vue.prototype.hasOwnProperty('$notify')) {
      Vue.notify = new Notify(Vue, options)

      Object.defineProperties(Vue.prototype, {
        $notify: {
          get() {
            return Vue.notify
          },
        },
      })
    }
  },
}
