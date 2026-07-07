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
