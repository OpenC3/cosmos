<!--
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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-slide-y-transition>
    <v-sheet
      v-show="showToast"
      :style="toastStyle"
      class="toast-notification"
      @click="expand"
    >
      <v-icon class="mr-1 notification-text">
        {{ toastNotificationIcon }}
      </v-icon>
      <div class="toast-content" :style="contentStyle">
        <span
          v-if="toastNotification.title"
          class="text-subtitle-1 mr-1 notification-text"
        >
          {{ toastNotification.title }}:
        </span>
        <span
          v-if="toastNotification.body"
          class="text-body-2 notification-text"
        >
          {{ toastNotification.body }}
        </span>
        <span
          v-if="toastNotification.message"
          class="text-body-2 notification-text"
        >
          {{ toastNotification.message }}
        </span>
      </div>
      <v-spacer />
      <v-btn text @click.stop="hide" class="notification-text"> Dismiss </v-btn>
    </v-sheet>
  </v-slide-y-transition>
</template>

<script>
import {
  AstroStatusColors,
  getStatusColorContrast,
} from '../../components/icons'
import vuetify from '../vuetify.js'

export default {
  vuetify,
  data: function () {
    return {
      showToast: false,
      expanded: false,
      toastNotification: {
        title: 'Title here',
        body: 'This is the notification body',
        message: 'Overall message here',
      },
      timeout: null,
    }
  },
  computed: {
    toastNotificationIcon: function () {
      switch (this.toastNotification.type) {
        case 'notification':
          return 'mdi-bell'
        case 'alert':
        default:
          return 'mdi-alert-box'
      }
    },
    toastStyle: function () {
      return `
        --toast-bg-color:${AstroStatusColors[this.toastNotification.level]};
        --toast-fg-color:${getStatusColorContrast(
          this.toastNotification.level,
        )};
      `
    },
    contentStyle: function () {
      return `
        white-space: ${this.expanded ? 'normal' : 'nowrap'};
        overflow-x: ${this.expanded ? 'visible' : 'hidden'};
        text-overflow: ${this.expanded ? 'unset' : 'ellipsis'};
      `
    },
  },
  methods: {
    toast: function (toastNotification, duration) {
      if (duration === undefined) {
        duration = 5000
      }
      this.toastNotification = toastNotification
      this.showToast = true
      this.cancelAutohide()
      if (duration) {
        this.timeout = setTimeout(() => {
          this.hide()
        }, duration)
      }
    },
    hide: function () {
      this.cancelAutohide()
      this.showToast = false
    },
    cancelAutohide: function () {
      if (this.timeout) {
        clearTimeout(this.timeout)
        this.timeout = null
      }
    },
    expand: function () {
      this.cancelAutohide()
      this.expanded = true
    },
  },
}
</script>

<style scoped>
.v-subheader {
  min-height: 28px;
}

.v-sheet.toast-notification {
  position: absolute;
  top: 0;
  right: 0;
  left: 0;
  background-color: var(--toast-bg-color) !important;
  display: flex;
  align-items: center;
  padding: 14px;
  cursor: pointer;
  z-index: 100;
}

.toast-notification .notification-text {
  color: var(--toast-fg-color) !important;
}
</style>
