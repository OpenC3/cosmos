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
      <v-menu ref="topmenu" v-for="(menu, i) in menus" :key="i">
        <template v-slot:activator="{ props }">
          <v-btn
            variant="outlined"
            v-bind="props"
            class="mx-1 menu-button"
            :data-test="formatDT(`${title} ${menu.label}`)"
          >
            <span v-text="menu.label" />
            <v-icon class="myicon" end> mdi-menu-down </v-icon>
          </v-btn>
        </template>
        <v-list>
          <template v-for="(option, j) in menu.items">
            <v-divider v-if="option.divider" :key="j + '-divider'" />
            <div
              v-else-if="option.subMenu && option.subMenu.length > 0"
              :key="j + '-submenu'"
            >
              <v-menu open-on-hover location="right" :key="j">
                <template v-slot:activator="{ props }">
                  <v-list-item
                    :disabled="option.disabled"
                    :key="j"
                    v-bind="props"
                  >
                    <template v-slot:prepend v-if="option.icon">
                      <v-icon :disabled="option.disabled">
                        {{ option.icon }}
                      </v-icon>
                    </template>
                    <v-list-item-title
                      v-if="!option.radio && !option.checkbox"
                      :style="
                        'cursor: pointer;' +
                        (option.disabled ? 'opacity: 0.2' : '')
                      "
                      >{{ option.label }}
                    </v-list-item-title>
                    <template v-slot:append>
                      <v-icon> mdi-chevron-right </v-icon>
                    </template>
                  </v-list-item>
                </template>
                <v-list>
                  <v-list-item
                    v-for="(submenu, k) in option.subMenu"
                    :key="k"
                    :prepend-icon="submenu.icon"
                    @click="subMenuClick(submenu)"
                  >
                    <v-list-item-title>{{ submenu.label }}</v-list-item-title>
                  </v-list-item>
                </v-list>
              </v-menu>
            </div>
            <v-radio-group
              v-else-if="option.radioGroup"
              :model-value="option.value"
              @update:model-value="option.command"
              :key="j + '-radio-group'"
              hide-details
              density="compact"
              class="ma-0 pa-0"
            >
              <v-list-item
                v-for="(choice, k) in option.choices"
                :key="k + '-choice'"
              >
                <v-list-item-action class="list-action">
                  <v-radio
                    color="secondary"
                    :label="choice.label"
                    :value="choice.value"
                    density="compact"
                    hide-details
                  />
                </v-list-item-action>
              </v-list-item>
            </v-radio-group>
            <v-list-item
              v-else
              @click="option.command(option)"
              :disabled="option.disabled"
              :data-test="formatDT(`${title} ${menu.label} ${option.label}`)"
              :key="j + '-list'"
            >
              <template v-slot:prepend v-if="option.icon">
                <v-icon
                  :icon="option.icon"
                  :disabled="option.disabled"
                ></v-icon>
              </template>
              <v-list-item-action class="list-action" v-if="option.checkbox">
                <v-checkbox
                  :model-value="option.checked"
                  color="secondary"
                  :label="option.label"
                  density="compact"
                  hide-details
                />
              </v-list-item-action>
              <v-list-item-title
                v-if="!option.radio && !option.checkbox"
                :style="
                  'cursor: pointer;' + (option.disabled ? 'opacity: 0.2' : '')
                "
              >
                {{ option.label }}
              </v-list-item-title>
            </v-list-item>
          </template>
        </v-list>
      </v-menu>
    </v-row>
  </teleport>
</template>

<script>
export default {
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
    // Convert the string to a standard data-test format
    formatDT: function (string) {
      return string.replaceAll(' ', '-').toLowerCase()
    },
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
  padding-right: 3px !important;
}
span.v-btn__content span {
  padding-right: 5px;
}
.list-action :deep(label) {
  color: white;
  padding-left: 20px;
}
.myicon {
  background-color: var(--color-background-surface-selected);
  border: 1px solid currentColor;
  border-radius: 3px;
  height: 36px !important;
  width: 36px !important;
  margin-top: -1px;
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
