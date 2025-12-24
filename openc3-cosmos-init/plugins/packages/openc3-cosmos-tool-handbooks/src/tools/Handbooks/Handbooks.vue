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
  <div>
    <top-bar :menus="menus" :title="title" />
    <v-card>
      <v-container class="d-print-none">
        <v-row dense>
          <v-col>
            <v-select
              v-model="selectedTargetNames"
              class="ma-0 pa-0"
              label="Select Target(s)"
              density="compact"
              hide-details
              variant="outlined"
              :items="targetNames"
              multiple
            >
              <template #prepend-item>
                <v-list-item ripple @mousedown.prevent @click="toggleTargets">
                  <v-list-item-title>
                    <v-list-item-action end>
                      <v-icon class="mr-2"> {{ icon }} </v-icon>Select All
                    </v-list-item-action>
                  </v-list-item-title>
                </v-list-item>
                <v-divider class="mt-2"></v-divider>
              </template>
            </v-select>
          </v-col>
          <v-col>
            <v-btn
              class="bg-primary"
              @click="renderedTargetNames = selectedTargetNames"
            >
              Display
            </v-btn>
          </v-col>
          <v-col>
            <v-select
              v-model="columns"
              label="Item Columns"
              density="compact"
              hide-details
              variant="outlined"
              :items="columnItems"
            ></v-select>
          </v-col>
        </v-row>
      </v-container>
    </v-card>
    <div style="height: 15px" />
    <div v-for="target in renderedTargetNames" :key="target">
      <target
        :target="target"
        :columns="columns"
        :hide-ignored="hideIgnored"
        :hide-derived="hideDerived"
      ></target>
    </div>
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'
import { TopBar } from '@openc3/vue-common/components'
import Target from './Target'

export default {
  components: {
    TopBar,
    Target,
  },
  data() {
    return {
      title: 'Handbooks',
      targetNames: [],
      selectedTargetNames: [],
      renderedTargetNames: [],
      api: null,
      columns: 3,
      columnItems: [
        { title: '1', value: 12 },
        { title: '2', value: 6 },
        { title: '3', value: 4 },
        { title: '4', value: 3 },
        { title: '6', value: 2 },
        { title: '12', value: 1 },
      ],
      hideIgnored: false,
      hideDerived: false,
      menus: [
        {
          label: 'View',
          items: [
            {
              label: 'Hide Ignored Items',
              checkbox: true,
              command: () => {
                this.hideIgnored = !this.hideIgnored
              },
            },
            {
              label: 'Hide Derived Items',
              checkbox: true,
              command: () => {
                this.hideDerived = !this.hideDerived
              },
            },
          ],
        },
      ],
    }
  },
  computed: {
    allTargetsSelected() {
      return this.targetNames.length === this.selectedTargetNames.length
    },
    someTargetsSelected() {
      return this.selectedTargetNames.length > 0 && !this.allTargetsSelected
    },
    icon() {
      if (this.allTargetsSelected) return 'mdi-close-box'
      if (this.someTargetsSelected) return 'mdi-minus-box'
      return 'mdi-checkbox-blank-outline'
    },
  },
  created() {
    this.api = new OpenC3Api()
    this.api
      .get_target_names({ params: { scope: window.openc3Scope } })
      .then((targets) => {
        this.targetNames = targets
      })
  },
  methods: {
    toggleTargets() {
      this.$nextTick(() => {
        if (this.allTargetsSelected) {
          this.selectedTargetNames = []
        } else {
          this.selectedTargetNames = this.targetNames.slice()
        }
      })
    },
  },
}
</script>
