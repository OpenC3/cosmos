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
  <div class="toast-container">
    <!-- No transition group: dismissals are instant so users can rapidly
         click through a stack of alerts without the button shifting away. -->
    <v-alert
      v-for="item in toasts"
      :key="item.id"
      density="compact"
      class="toast-notification mx-2 my-1"
      data-test="toast"
      :icon="toastNotificationIcon(item)"
      :title="item.notification.title"
      :style="toastStyle(item)"
    >
      <div v-if="item.notification.body" class="text-body-2">
        {{ item.notification.body }}
      </div>
      <div v-if="item.notification.message" class="text-body-2">
        {{ item.notification.message }}
      </div>
      <div v-if="toastTime(item)" class="text-caption toast-time">
        {{ toastTime(item) }}
      </div>
      <template #append>
        <!-- Alerts have no auto-hide timeout, so the user must click
             Acknowledge to dismiss them. -->
        <v-btn
          variant="text"
          data-test="dismiss-toast"
          :aria-label="item.mustAck ? 'Acknowledge' : 'Dismiss'"
          @click="dismiss(item)"
        >
          {{ item.mustAck ? 'Acknowledge' : 'Dismiss' }}
        </v-btn>
      </template>
    </v-alert>
  </div>
</template>

<script>
import { AstroStatusColors, getStatusColorContrast } from '@/icons'

export default {
  data: function () {
    return {
      toasts: [],
      nextId: 0,
      noToastPaths: ['/login'],
    }
  },
  methods: {
    // Called by the Notify plugin. Each call adds a new stacked toast. Toasts
    // with a duration auto-hide; a null/0 duration (used for alerts) makes the
    // toast persist until the user acknowledges it by clicking Dismiss.
    toast: function (notification, duration) {
      if (this.noToastPaths.includes(window.location.pathname)) {
        return
      }
      if (duration === undefined) {
        duration = 5000
      }
      const toast = {
        id: this.nextId++,
        notification,
        timeout: null,
        mustAck: !duration,
      }
      this.toasts.push(toast)
      if (duration) {
        toast.timeout = setTimeout(() => {
          this.hide(toast)
        }, duration)
      }
    },
    // User clicked the toast button. Acknowledging a must-ack alert also acks
    // it in the notifications menu via a window event (the menu lives in a
    // separate app instance). Auto-hide and programmatic dismissals call hide
    // directly and do not emit, avoiding a feedback loop.
    dismiss: function (toast) {
      if (toast.mustAck && toast.notification.msg_id) {
        window.dispatchEvent(
          new CustomEvent('openc3-ack-alert', {
            detail: { msg_id: toast.notification.msg_id },
          }),
        )
      }
      this.hide(toast)
    },
    hide: function (toast) {
      this.cancelAutohide(toast)
      const index = this.toasts.indexOf(toast)
      if (index !== -1) {
        this.toasts.splice(index, 1)
      }
    },
    cancelAutohide: function (toast) {
      if (toast.timeout) {
        clearTimeout(toast.timeout)
        toast.timeout = null
      }
    },
    dismissAll: function () {
      this.toasts.forEach((toast) => this.cancelAutohide(toast))
      this.toasts = []
    },
    // Remove any toast whose notification matches the predicate. Used when the
    // user disables a toast category so existing toasts disappear immediately.
    dismissMatching: function (predicate) {
      this.toasts
        .filter((toast) => predicate(toast.notification))
        .forEach((toast) => this.hide(toast))
    },
    // ISO8601 timestamp for the toast. Log messages carry an ISO8601
    // "@timestamp"; fall back to converting the nanosecond "time" field.
    toastTime: function (toast) {
      const notification = toast.notification
      if (notification['@timestamp']) {
        return notification['@timestamp']
      }
      if (notification.time) {
        return new Date(notification.time / 1000000).toISOString()
      }
      return ''
    },
    toastNotificationIcon: function (toast) {
      switch (toast.notification.type) {
        case 'notification':
          return 'mdi-bell'
        case 'alert':
        default:
          return 'mdi-alert-circle'
      }
    },
    toastStyle: function (toast) {
      return `
        --toast-bg-color:${AstroStatusColors[toast.notification.level]};
        --toast-fg-color:${getStatusColorContrast(toast.notification.level)};
      `
    },
  },
}
</script>

<style scoped>
.toast-container {
  position: fixed;
  top: 0;
  /* Leave room for the notification/status icon cluster on the right so toasts
     never cover the bell: 86 + 24 + 75 + 24 px. */
  right: 209px;
  left: 0;
  z-index: 1000;
  display: flex;
  flex-direction: column;
  /* Show at most ~3 toasts; scroll to reach any beyond that so no
     un-acknowledged alert is ever hidden. */
  max-height: 200px;
  overflow-y: auto;
}

.v-alert.toast-notification {
  background-color: var(--toast-bg-color) !important;
  color: var(--toast-fg-color) !important;
  cursor: default;
  /* Keep natural height so extra toasts scroll instead of compressing */
  flex: 0 0 auto;
}

/* Ensure the prominent icon and the Acknowledge button pick up the contrasting
   foreground color rather than the theme default. */
.toast-notification :deep(.v-alert__prepend),
.toast-notification :deep(.v-alert-title),
.toast-notification :deep(.v-btn) {
  color: var(--toast-fg-color) !important;
}
</style>
