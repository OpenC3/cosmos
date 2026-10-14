<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <!-- Same id as the desktop bar so themes and tests find it -->
  <v-app-bar id="openc3-app-toolbar">
    <div class="d-flex align-center w-100 ga-1 pr-2">
      <rux-icon
        class="ml-2 pa-2"
        size="small"
        icon="apps"
        @click="$emit('toggle-drawer')"
      ></rux-icon>
      <!-- Tools teleport their title and menus here (TopBar.vue). Takes the
           room left by the icons, so a long title truncates instead of
           pushing them off screen -->
      <span
        id="openc3-menu"
        class="flex-grow-1 overflow-hidden"
        style="min-width: 0"
      />
      <context-tag />
      <notifications compact data-test="notifications" />
      <user-menu compact />
    </div>
  </v-app-bar>
</template>

<script>
import ContextTag from './ContextTag.vue'
import Notifications from './Notifications.vue'
import UserMenu from './UserMenu.vue'

// The app bar on mobile devices: the nav drawer button, the tool's title
// and menus, and icon-only notifications and user menu. No clock; the scope
// selector is in the nav drawer instead (AppNav.vue).
export default {
  components: { ContextTag, Notifications, UserMenu },
  emits: ['toggle-drawer'],
}
</script>
