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
  <teleport to="#openc3-menu">
    <v-row no-gutters>
      <v-col align-self="end">
        <span class="app-title mr-2">{{ title }}</span>
      </v-col>
    </v-row>
    <v-row dense class="flex-nowrap">
      <TopBarMenu
        v-for="(menu, i) in menus"
        :key="i + '-top-menu'"
        :ref="'topmenu'"
        :menu="menu"
        :title="title"
        @submenu-click="subMenuClick"
      />
    </v-row>
  </teleport>
</template>

<script>
import TopBarMenu from './TopBarMenu.vue'

export default {
  components: {
    TopBarMenu,
  },
  props: {
    menus: {
      type: Array,
      default: function () {
        return []
      },
    },
    title: {
      type: String,
      default: '',
    },
  },
  methods: {
    subMenuClick(submenu) {
      submenu.command(submenu)
      this.$refs.topmenu[0].isActive = false
    },
  },
  mounted() {
    document.title = this.title
  },
}
</script>

<style scoped>
.app-title {
  font-size: 2rem;
}
/* The next three styles effectively style the button like a select drop down */
.menu-button {
  border-color: var(--color-border-interactive-muted) !important;
  background-color: var(--color-background-base-default) !important;
}
.menu-button-icon {
  background-color: var(--color-background-surface-selected);
  border: 1px solid currentColor;
  border-radius: 3px;
  height: calc(var(--v-btn-height));
  width: calc(var(--v-btn-height));
  margin-top: -1px;
  margin-bottom: -1px;
  margin-left: 3px; /* parent's left margin (4px) - border (1px) */
  margin-right: -13px; /* parent's right margin (4px) - border (1px) - padding (16px) */
}
.list-action :deep(label) {
  color: white;
  padding-left: 20px;
}
.v-list :deep(.v-label) {
  margin-left: 5px;
}
.v-list-item-action {
  /* For some reason the default margin-right is huge */
  margin-right: 15px !important;
}
.v-list-item-title {
  color: white;
}
</style>
