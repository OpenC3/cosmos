<!--
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
-->

<template>
  <!-- All toasts are rendered by this single Toaster (the Notify plugin mounts
       exactly one Toast instance). -->
  <VSonner
    :position="position === 'bottom' ? 'bottom-center' : 'top-center'"
    :visible-toasts="3"
  />
</template>

<script>
import { VSonner, toast as showToast } from 'vuetify-sonner'
import 'vuetify-sonner/style.css'
import DOMPurify from 'dompurify'
import {
  UnknownToAstroStatus,
  AstroStatusColors,
  getStatusColorContrast,
} from '@/icons'

export default {
  components: {
    VSonner,
  },
  data: function () {
    return {
      // vue-sonner only supports dismiss-by-id, so track each live toast's
      // notification keyed by id to implement predicate-based dismissal.
      active: new Map(),
      nextId: 0,
      noToastPaths: ['/login'],
      position: localStorage.toastPosition === 'bottom' ? 'bottom' : 'top',
    }
  },
  created: function () {
    // The settings UI lives in a separate app instance and broadcasts changes.
    window.addEventListener('openc3-toast-position', this.onPositionChange)
  },
  unmounted: function () {
    window.removeEventListener('openc3-toast-position', this.onPositionChange)
  },
  methods: {
    onPositionChange: function (event) {
      const position = event.detail?.position
      if (position === 'top' || position === 'bottom') {
        this.position = position
      }
    },
    // Called by the Notify plugin. Each call adds a new stacked toast. Toasts
    // with a duration auto-hide; a null/0 duration (used for alerts) makes the
    // toast persist until the user acknowledges it by clicking Acknowledge.
    toast: function (notification, duration) {
      if (this.noToastPaths.includes(window.location.pathname)) {
        return
      }
      if (duration === undefined) {
        duration = 5000
      }
      const mustAck = !duration
      const id = `openc3-toast-${this.nextId++}`
      this.active.set(id, notification)

      const fg = getStatusColorContrast(notification.level)
      const bg = AstroStatusColors[UnknownToAstroStatus[notification.level]]

      showToast(this.toastText(notification), {
        id,
        description: this.toastDescription(notification),
        // Infinity keeps alerts up until the user acknowledges them.
        duration: mustAck ? Infinity : duration,
        prependIcon: this.toastNotificationIcon(notification),
        prependIconProps: { style: `color:${fg}` },
        cardProps: {
          style: `background-color:${bg}!important;color:${fg}!important;`,
          'data-test': 'toast',
        },
        // vuetify-sonner auto-dismisses the toast when this button is clicked,
        // so the handler only needs to relay the acknowledgement. Acking a
        // must-ack alert also acks it in the notifications menu via a window
        // event (the menu lives in a separate app instance).
        action: {
          label: mustAck ? 'Acknowledge' : 'Dismiss',
          buttonProps: {
            variant: 'text',
            style: `color:${fg}`,
            'data-test': 'dismiss-toast',
            'aria-label': mustAck ? 'Acknowledge' : 'Dismiss',
          },
          onClick: () => {
            if (mustAck && notification.msg_id) {
              window.dispatchEvent(
                new CustomEvent('openc3-ack-alert', {
                  detail: { msg_id: notification.msg_id },
                }),
              )
            }
          },
        },
        // Drop the tracking entry however the toast goes away (button,
        // auto-hide, or programmatic dismissal).
        onDismiss: () => this.active.delete(id),
        onAutoClose: () => this.active.delete(id),
      })
    },
    dismissAll: function () {
      showToast.dismiss()
      this.active.clear()
    },
    // Remove any toast whose notification matches the predicate. Used when the
    // user disables a toast category so existing toasts disappear immediately.
    dismissMatching: function (predicate) {
      for (const [id, notification] of this.active) {
        if (predicate(notification)) {
          showToast.dismiss(id)
          this.active.delete(id)
        }
      }
    },
    // Primary (prominent) line of the toast.
    toastText: function (notification) {
      return (
        notification.title || notification.message || notification.body || ''
      )
    },
    // Secondary lines (whatever isn't shown as the primary text, plus a
    // timestamp). Sanitized because vue-sonner renders the description as HTML.
    toastDescription: function (notification) {
      const primary = this.toastText(notification)
      const lines = []
      if (notification.body && notification.body !== primary) {
        lines.push(notification.body)
      }
      if (notification.message && notification.message !== primary) {
        lines.push(notification.message)
      }
      const time = this.toastTime(notification)
      if (time) {
        lines.push(time)
      }
      if (!lines.length) {
        return undefined
      }
      return DOMPurify.sanitize(lines.join('<br>'))
    },
    // ISO8601 timestamp for the toast. Log messages carry an ISO8601
    // "@timestamp"; fall back to converting the nanosecond "time" field.
    toastTime: function (notification) {
      if (notification['@timestamp']) {
        return notification['@timestamp']
      }
      if (notification.time) {
        return new Date(notification.time / 1000000).toISOString()
      }
      return ''
    },
    toastNotificationIcon: function (notification) {
      switch (String(notification.level).toUpperCase()) {
        case 'FATAL':
          return 'mdi-alert-octagon'
        case 'ERROR':
          return 'mdi-alert-circle'
        case 'WARN':
          return 'mdi-alert'
        case 'INFO':
        case 'DEBUG':
        default:
          return 'mdi-information'
      }
    },
  },
}
</script>

<!-- Unscoped: vue-sonner renders the toaster at document.body, outside this
     component's scope. Widen the toasts from the 356px default. vue-sonner sets
     --width inline on the toaster, so !important is required to override it. -->
<style>
[data-sonner-toaster] {
  --width: 500px !important;
}
</style>
