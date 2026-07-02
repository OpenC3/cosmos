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
  <div>
    <v-overlay :model-value="showNotificationPane" class="overlay" />
    <v-menu
      v-model="showNotificationPane"
      transition="slide-y-transition"
      :close-on-content-click="false"
      :offset="[12, 102]"
    >
      <template #activator="{ props }">
        <rux-monitoring-icon
          v-bind="props"
          class="rux-icon"
          :icon="notificationVsAlert"
          label="Notifications"
          :sublabel="activeScripts"
          :status="iconStatus"
          :notifications="unreadNotifications.length"
        ></rux-monitoring-icon>
      </template>

      <!-- Notifications list -->
      <v-card>
        <v-card-title class="d-flex align-center justify-content-space-between">
          <span> Notifications </span>
          <v-spacer />
          <v-tooltip :open-delay="600" location="top">
            <template #activator="{ props }">
              <div v-bind="props">
                <v-btn
                  class="ml-1"
                  icon="mdi-check-all"
                  variant="text"
                  data-test="ack-all-notifications"
                  aria-label="Acknowledge All Alerts"
                  @click="ackAllAlerts"
                />
              </div>
            </template>
            <span> Acknowledge All Alerts </span>
          </v-tooltip>
          <v-tooltip :open-delay="600" location="top">
            <template #activator="{ props }">
              <div v-bind="props">
                <v-btn
                  class="ml-1"
                  icon="mdi-notification-clear-all "
                  variant="text"
                  data-test="clear-notifications"
                  aria-label="Clear Read Notifications"
                  @click="clearNotifications"
                />
              </div>
            </template>
            <span> Clear Read Notifications </span>
          </v-tooltip>
          <v-btn
            icon="astro:settings"
            variant="text"
            class="ml-1"
            data-test="notification-settings"
            aria-label="Notification Settings"
            @click="toggleSettingsDialog"
          />
        </v-card-title>
        <v-card-text v-if="notifications.length === 0">
          No notifications
        </v-card-text>
        <v-list
          v-else
          lines="two"
          width="520"
          max-height="80vh"
          class="overflow-y-auto"
          data-test="notification-list"
        >
          <template v-for="(notification, index) in notificationList">
            <template v-if="notification.header">
              <v-divider v-if="index !== 0" :key="index" class="mb-2" />
              <v-list-subheader :key="notification.header">
                {{ notification.header }}
              </v-list-subheader>
            </template>

            <v-list-item
              v-else
              :key="`notification-${index}`"
              class="pl-2"
              @click="openDialog(notification)"
            >
              <template #prepend>
                <rux-status
                  class="px-2"
                  :status="getStatus(notification.level)"
                />
              </template>
              <v-list-item-title
                :class="{
                  'text--secondary': notification.read,
                  'text-wrap': true,
                }"
              >
                {{ notification.message }}
              </v-list-item-title>
              <v-list-item-subtitle>
                {{ formatShortDateTime(notification.time) }}
              </v-list-item-subtitle>
              <template
                v-if="notification.type === 'alert' && !notification.read"
                #append
              >
                <v-btn
                  size="small"
                  variant="tonal"
                  data-test="ack-notification"
                  @click.stop="ackNotification(notification)"
                >
                  Ack
                </v-btn>
              </template>
            </v-list-item>
          </template>
        </v-list>
      </v-card>
    </v-menu>

    <!-- Dialog for viewing full notification -->
    <v-dialog v-model="notificationDialog" width="600">
      <v-card>
        <v-card-title>
          {{ selectedNotification.message }}
          <v-spacer />
          <astro-status-indicator
            :status="selectedNotification.level || 'INFO'"
          />
        </v-card-title>
        <v-card-subtitle>
          {{ formatShortDateTime(selectedNotification.time) }}
        </v-card-subtitle>
        <v-divider />
        <v-card-actions>
          <v-btn
            v-if="selectedNotification.url"
            color="primary"
            variant="text"
            @click="navigate(selectedNotification.url)"
          >
            Open
            <v-icon end> mdi-open-in-new </v-icon>
          </v-btn>
          <v-btn
            v-if="
              selectedNotification.type === 'alert' &&
              !selectedNotification.read
            "
            color="primary"
            variant="text"
            data-test="ack-notification-dialog"
            @click="ackNotification(selectedNotification)"
          >
            Acknowledge
          </v-btn>
          <v-btn
            color="primary"
            variant="text"
            @click="notificationDialog = false"
          >
            Close
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <!-- Dialog for changing notification settings -->
    <v-dialog v-model="settingsDialog" width="600">
      <v-card>
        <v-card-title> Notification settings </v-card-title>
        <v-card-text>
          <v-switch
            v-model="showToast"
            label="Show alerts"
            color="primary"
            hide-details
            data-test="show-alerts"
          />
          <v-switch
            v-model="showRedLimitToast"
            label="Show red limit alerts"
            color="primary"
            class="ml-6"
            messages="Alerts must be acknowledged to dismiss them"
            :disabled="!showToast"
            data-test="show-red-limit-alerts"
          />
        </v-card-text>
        <v-divider />
        <v-card-actions>
          <v-btn color="primary" variant="text" @click="toggleSettingsDialog">
            Close
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import { formatDistanceToNow } from 'date-fns'
import { Api, Cable } from '@openc3/js-common/services'
import {
  AstroStatusColors,
  AstroStatusIndicator,
  UnknownToAstroStatus,
} from '@/icons'
import { AstroStatus } from '@/util'

const NOTIFICATION_HISTORY_MAX_LENGTH = 1000
const { highestLevel, orderByLevel, groupByLevel } = AstroStatus

// Redis stream ids are "<ms>-<seq>". The MessagesChannel start_offset is
// exclusive (XREAD returns ids strictly greater), so to guarantee a given
// message is replayed on reconnect we must subscribe from the id immediately
// before it.
function offsetBefore(msgId) {
  const [ms, seq] = String(msgId).split('-')
  const seqNum = Number(seq || 0)
  if (seqNum > 0) {
    return `${ms}-${seqNum - 1}`
  }
  // seq is 0: step back to the previous millisecond with the max sequence.
  return `${Number(ms) - 1}-18446744073709551615`
}

export default {
  components: {
    AstroStatusIndicator,
  },
  props: {
    size: {
      type: [String, Number],
      default: 26,
    },
  },
  emits: ['ephemeral'],
  data: function () {
    return {
      AstroStatusColors,
      cable: new Cable(),
      scriptCable: new Cable('/script-api/cable'),
      subscription: null,
      scriptSubscription: null,
      numScripts: 0,
      notifications: [],
      showNotificationPane: false,
      notificationDialog: false,
      selectedNotification: {},
      settingsDialog: false,
      showToast: true,
      showRedLimitToast: false,
    }
  },
  computed: {
    activeScripts: function () {
      return `Scripts: ${this.numScripts}`
    },
    notificationVsAlert: function () {
      // TODO: Determine if this is a notification or alert
      return 'notifications'
      // return 'warning'
    },
    iconStatus: function () {
      if (this.unreadNotifications.length === 0) {
        return 'off'
      }
      const levels = this.unreadNotifications
        .map((notification) => notification.level)
        .filter((val, index, self) => {
          return self.indexOf(val) === index // Unique values
        })
      return UnknownToAstroStatus[highestLevel(levels)]
    },
    readNotifications: function () {
      return this.notifications
        .filter((notification) => notification.read)
        .sort((a, b) => b.time - a.time)
    },
    unreadNotifications: function () {
      return this.notifications
        .filter((notification) => !notification.read)
        .sort((a, b) => b.time - a.time)
    },
    notificationList: function () {
      const groups = groupByLevel(this.unreadNotifications)
      let result = orderByLevel(Object.keys(groups), (k) => k).flatMap(
        (level) => {
          const header = {
            header: level.charAt(0).toUpperCase() + level.slice(1),
          }
          return [header, ...groups[level]]
        },
      )
      if (this.readNotifications.length) {
        result = result.concat([{ header: 'Read' }, ...this.readNotifications])
      }
      return result
    },
  },
  watch: {
    showNotificationPane: function (val) {
      if (!val) {
        if (this.selectedNotification.message) {
          this.notificationDialog = false
          this.selectedNotification = {}
        } else {
          this.markAllAsRead()
        }
      }
    },
    showToast: function (val) {
      localStorage.notoast = !val
      if (!val) {
        // Disabling toasts removes any that are currently displayed
        this.$notify?.dismissAll()
      }
    },
    showRedLimitToast: function (val) {
      localStorage.showRedLimitToast = val
      if (!val) {
        this.dismissLimitToasts('RED')
      }
    },
  },
  created: function () {
    // Toasts default on (opt-out), limit toasts default off (opt-in)
    this.showToast = localStorage.notoast !== 'true'
    this.showRedLimitToast = localStorage.showRedLimitToast === 'true'
    // Acknowledging an alert from its toast also acks it in the menu
    window.addEventListener('openc3-ack-alert', this.onAckAlert)
    this.subscribe()
    // Get the initial number of running scripts
    Api.get('/script-api/running-script').then((response) => {
      this.numScripts = response.data.total
    })
  },
  unmounted: function () {
    window.removeEventListener('openc3-ack-alert', this.onAckAlert)
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    if (this.scriptSubscription) {
      this.scriptSubscription.unsubscribe()
    }
    this.cable.disconnect()
    this.scriptCable.disconnect()
  },
  methods: {
    getStatus: function (level) {
      return UnknownToAstroStatus[level]
    },
    // Alerts stay unread until explicitly acknowledged, so track acked alert
    // msg_ids separately from the lastReadNotification high-water mark.
    ackedAlertSet: function () {
      try {
        return new Set(JSON.parse(localStorage.ackedAlerts || '[]'))
      } catch {
        return new Set()
      }
    },
    persistAckedAlert: function (msgId) {
      const acked = this.ackedAlertSet()
      acked.add(msgId)
      let ids = Array.from(acked)
      if (ids.length > NOTIFICATION_HISTORY_MAX_LENGTH) {
        ids = ids.slice(ids.length - NOTIFICATION_HISTORY_MAX_LENGTH)
      }
      localStorage.ackedAlerts = JSON.stringify(ids)
    },
    // Mark a single alert acknowledged (read + persisted). Callers persist the
    // stream offset and dismiss toasts once after their batch of acks.
    acknowledgeAlert: function (notification) {
      notification.read = true
      this.persistAckedAlert(notification.msg_id)
    },
    ackNotification: function (notification) {
      this.acknowledgeAlert(notification)
      this.persistStreamOffset()
      // Also dismiss the matching toast if it's still showing
      this.$notify?.dismiss((toast) => toast.msg_id === notification.msg_id)
      this.notificationDialog = false
    },
    // Handles an alert acknowledged from its toast (fired in the Toast app
    // instance) so the menu marks the same alert read.
    onAckAlert: function (event) {
      const msgId = event.detail?.msg_id
      if (!msgId) {
        return
      }
      const notification = this.notifications.find((n) => n.msg_id === msgId)
      // The alert may not be in this instance's list; still record the ack.
      if (notification) {
        this.acknowledgeAlert(notification)
      } else {
        this.persistAckedAlert(msgId)
      }
      this.persistStreamOffset()
    },
    ackAllAlerts: function () {
      this.notifications.forEach((notification) => {
        if (notification.type === 'alert' && !notification.read) {
          this.acknowledgeAlert(notification)
        }
      })
      this.persistStreamOffset()
      this.$notify?.dismiss((toast) => toast.type === 'alert')
    },
    // The reconnect stream offset must sit just below the oldest
    // un-acknowledged alert so that alert is replayed (and re-toasted) after a
    // reload instead of being silently skipped. When nothing is un-acked it
    // tracks the read high-water mark so already-seen messages aren't refetched.
    persistStreamOffset: function () {
      let offset = localStorage.lastReadNotification
      const unackedAlerts = this.notifications.filter(
        (notification) => notification.type === 'alert' && !notification.read,
      )
      if (unackedAlerts.length) {
        const oldest = unackedAlerts.reduce(
          (min, notification) =>
            notification.msg_id < min ? notification.msg_id : min,
          unackedAlerts[0].msg_id,
        )
        const cap = offsetBefore(oldest)
        if (!offset || cap < offset) {
          offset = cap
        }
      }
      if (offset) {
        localStorage.notificationStreamOffset = offset
      } else {
        localStorage.removeItem('notificationStreamOffset')
      }
    },
    // Advance the non-alert read high-water mark. Alert read state is tracked
    // separately (ackedAlerts), so this only governs non-alert notifications.
    advanceReadMarker: function (msgId) {
      if (
        !localStorage.lastReadNotification ||
        localStorage.lastReadNotification < msgId
      ) {
        localStorage.lastReadNotification = msgId
      }
    },
    markAllAsRead: function () {
      this.notifications.forEach((notification) => {
        if (notification.type !== 'alert') {
          notification.read = true
        }
        this.advanceReadMarker(notification.msg_id)
      })
      this.persistStreamOffset()
    },
    clearNotifications: function () {
      // Non-alert notifications become read on view, so mark them read now
      // (markAllAsRead leaves alerts alone), then remove all read
      // notifications, leaving only un-acknowledged alerts.
      this.markAllAsRead()
      this.notifications = this.notifications.filter(
        (notification) => !notification.read,
      )
    },
    toggleSettingsDialog: function () {
      this.settingsDialog = !this.settingsDialog
    },
    openDialog: function (notification) {
      // Alerts stay unread until acknowledged from the dialog
      if (notification.type !== 'alert') {
        notification.read = true
        this.advanceReadMarker(notification.msg_id)
      }
      this.selectedNotification = notification
      this.notificationDialog = true
    },
    navigate: function (url) {
      window.open(url, '_blank')
    },
    subscribe: function () {
      this.cable
        .createSubscription(
          'MessagesChannel',
          window.openc3Scope,
          {
            received: (data) => this.receiveMessage(data),
          },
          {
            start_offset:
              localStorage.notificationStreamOffset ||
              localStorage.lastReadNotification,
            types: ['notification', 'alert', 'ephemeral'],
          },
        )
        .then((subscription) => {
          this.subscription = subscription
        })
      this.scriptCable
        .createSubscription('AllScriptsChannel', window.openc3Scope, {
          received: (data) => this.receiveScript(data),
        })
        .then((subscription) => {
          this.scriptSubscription = subscription
        })
    },
    dismissLimitToasts: function (prefix) {
      this.$notify?.dismiss(
        (notification) =>
          notification.limits_state &&
          notification.limits_state.startsWith(prefix),
      )
    },
    shouldToast: function (notification) {
      if (!this.showToast) {
        return false // Master toggle gates all toasts
      }
      // Red limit alerts carry a RED limits_state (set by the decom
      // microservice) and are gated by their own opt-in toggle.
      const state = notification.limits_state
      if (state && state.startsWith('RED')) {
        return this.showRedLimitToast
      }
      return true
    },
    receiveMessage: function (parsed) {
      this.cable.recordPing()

      // Cut down if we're being flooded
      if (parsed.length > NOTIFICATION_HISTORY_MAX_LENGTH) {
        parsed.splice(0, parsed.length - NOTIFICATION_HISTORY_MAX_LENGTH)
      }

      // Filter out ephemeral
      let ephemeral = parsed.filter(
        (someobject) => someobject.type === 'ephemeral',
      )
      if (ephemeral && ephemeral.length > 0) {
        // Remove ephemeral from parsed
        parsed = parsed.filter((someobject) => someobject.type !== 'ephemeral')
        // Emit the ephemeral
        ephemeral.forEach((notification) => {
          this.$emit('ephemeral', notification)
        })
      }

      const alertToasts = []
      const acked = this.ackedAlertSet()
      parsed.forEach((notification) => {
        // Alerts are read only once acknowledged; others use the read marker
        if (notification.type === 'alert') {
          notification.read = acked.has(notification.msg_id)
        } else {
          notification.read =
            notification.msg_id <= localStorage.lastReadNotification
        }
        notification.level = notification.level || 'INFO'
        if (notification.read) {
          return // Don't toast read notifications
        }
        // Only alerts toast (red limits gated by their toggle). Everything
        // else, including yellow limits, only appears in the menu.
        if (notification.type === 'alert' && this.shouldToast(notification)) {
          // Alerts require acknowledgement regardless of level. Each one is
          // toasted individually so the user must dismiss (ack) all of them.
          alertToasts.push(notification)
        }
      })

      // Notify takes a minute to be ready on app load
      if (this.$notify) {
        alertToasts.forEach((notification) => {
          // Fall back to INFO if the level isn't a Notify method so one bad
          // level can't throw and abort toasting the rest of the batch.
          const level =
            typeof this.$notify[notification.level] === 'function'
              ? notification.level
              : 'INFO'
          this.$notify[level]({
            ...notification,
            type: 'alert',
            duration: null, // Persist until the user acknowledges the alert
            saveToHistory: false,
          })
        })
      }

      if (
        this.notifications.length + parsed.length >
        NOTIFICATION_HISTORY_MAX_LENGTH
      ) {
        this.notifications.splice(
          0,
          this.notifications.length +
            parsed.length -
            NOTIFICATION_HISTORY_MAX_LENGTH,
        )
      }
      this.notifications = this.notifications.concat(parsed)
      // A newly received un-acked alert must lower the persisted reconnect
      // offset immediately, so it survives a reload even if the user never
      // opens the notifications menu.
      this.persistStreamOffset()
    },
    receiveScript: function (data) {
      this.cable.recordPing()
      this.numScripts = data['active_scripts']
    },
    formatShortDateTime: function (nsec) {
      if (!nsec) return ''
      const date = new Date(nsec / 1000000)
      return formatDistanceToNow(date, { addSuffix: true })
    },
  },
}
</script>

<style scoped>
.v-subheader {
  height: 28px;
}
.v-badge {
  width: 100%;
}
.overlay {
  height: 100vh;
  width: 100vw;
}
</style>
