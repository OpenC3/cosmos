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

import { createApp } from 'vue'
import { vuetify } from '@/plugins'
import { useStore } from '@/plugins/store'
import Toast from './Toast.vue'

class Notify {
  /*
   * This gets called by the `install()` function below
   */
  constructor(options = {}) {
    this.store = null // Will be initialized lazily when needed
    this.mounted = false
    this.$root = null
    if (window.$cosmosNotify?.$root) {
      this.mounted = true
      this.$root = window.$cosmosNotify.$root
    } else {
      window.$cosmosNotify = this
    }
  }

  getStore() {
    if (!this.store) {
      this.store = useStore()
    }
    return this.store
  }

  /*
   * This gets called each time `open()` is invoked by an app in COSMOS.
   * It puts the element into the DOM that allows toasts to be shown.
   */
  mount() {
    if (this.mounted) return

    const app = createApp(Toast)
    app.use(vuetify)

    // vue-sonner renders position:fixed inline (no Teleport), so it must mount
    // on document.body. Mounting inside the toolbar puts it under an ancestor
    // that establishes a containing block, which breaks fixed positioning.
    const el = document.createElement('div')
    document.body.appendChild(el)
    this.$root = app.mount(el)
    this.mounted = true
  }

  /**
   * Show a notification. Normally called via the level convenience methods
   * (critical, serious, caution, normal, standby, off) rather than directly.
   *
   * @param {object} notification
   * @param {string} notification.method - Notify method to dispatch to (e.g. 'toast')
   * @param {string} [notification.title] - Prominent first line of the toast
   * @param {string} [notification.body] - Secondary line
   * @param {string} [notification.message] - Alternate secondary line / console text
   * @param {string} notification.level - Severity: critical, serious, caution, normal, standby, off
   * @param {number} [notification.duration] - Auto-hide ms; null/0 makes an alert persist until acknowledged
   * @param {string} [notification.type='alert'] - Notification category
   * @param {boolean} [notification.logToConsole=false] - Also console.log the notification
   * @param {boolean} [notification.saveToHistory=true] - Add to the notifications menu history
   * @param {string} [notification.msg_id] - Alert id; required for must-ack alert acknowledgement
   * @param {string} [notification['@timestamp']] - ISO8601 timestamp shown on the toast
   * @param {number} [notification.time] - Nanosecond timestamp (used if @timestamp absent)
   */
  open({
    method,
    title,
    body,
    message,
    level,
    duration,
    type = 'alert',
    logToConsole = false,
    saveToHistory = true,
    // Extra fields (msg_id, @timestamp, time) forwarded to the toast; see the
    // @param docs above and Toast.vue for how each is consumed.
    ...rest
  }) {
    this.mount()
    if (logToConsole) {
      if (message) {
        // eslint-disable-next-line no-console
        console.log(`${level.toUpperCase()} - ${message}`)
      } else {
        // eslint-disable-next-line no-console
        console.log(`${level.toUpperCase()} - ${title}: ${body}`)
      }
    }
    if (saveToHistory) {
      this.getStore().notifyAddHistory({ title, body, message, level })
    }
    // Forward any extra fields (e.g. msg_id, @timestamp) the toast needs
    this[method]({ title, body, message, level, duration, type, ...rest })
  }

  toast({ title, body, message, level, duration, type, ...rest }) {
    this.$root.toast(
      {
        title,
        body,
        message,
        level,
        type,
        ...rest,
      },
      duration,
    )
  }

  // The level convenience methods below all take the same `options` object as
  // open() (minus `method`/`level`, which they set). See open()'s @param docs
  // for the accepted fields (title, body, message, duration, type,
  // logToConsole, saveToHistory, msg_id, @timestamp, time).
  critical(options) {
    this.open({ ...options, method: 'toast', level: 'critical' })
  }
  FATAL(options) {
    this.critical(options)
  }
  ERROR(options) {
    this.critical(options)
  }

  serious(options) {
    this.open({ ...options, method: 'toast', level: 'serious' })
  }
  caution(options) {
    this.open({ ...options, method: 'toast', level: 'caution' })
  }
  WARN(options) {
    this.caution(options)
  }

  normal(options) {
    this.open({ ...options, method: 'toast', level: 'normal' })
  }
  INFO(options) {
    this.normal(options)
  }
  DEBUG(options) {
    this.normal(options)
  }

  standby(options) {
    this.open({ ...options, method: 'toast', level: 'standby' })
  }

  off(options) {
    this.open({ ...options, method: 'toast', level: 'off' })
  }

  // Dismiss all currently displayed toasts.
  dismissAll() {
    this.$root?.dismissAll()
  }

  // Dismiss displayed toasts whose notification matches the predicate.
  dismiss(predicate) {
    this.$root?.dismissMatching(predicate)
  }
}

export default {
  /*
   * This gets called by the Vue runtime when you have `app.use(Notify)` in that app's main .js file.
   */
  install(app, options) {
    const notify = new Notify(options)
    app.provide('notify', notify) // Allows for injection
    if (!app.config.globalProperties.hasOwnProperty('$notify')) {
      app.config.globalProperties.$notify = notify // Allows for `this.$notify`
    }
  },
}
