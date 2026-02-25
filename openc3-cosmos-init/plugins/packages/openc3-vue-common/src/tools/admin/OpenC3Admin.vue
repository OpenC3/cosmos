<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <top-bar :title="title" />
    <v-card>
      <v-tabs v-model="curTab" fixed-tabs>
        <v-tab v-for="(tab, index) in tabs" :key="index" :to="tab.path">
          {{ tab.displayName }}
        </v-tab>
      </v-tabs>
      <router-view />
    </v-card>
  </div>
</template>

<script>
import { TopBar } from '@/components'
import { TabsList } from './tabs'

export default {
  components: {
    TopBar,
  },
  data() {
    return {
      title: 'Administrator Console',
      curTab: null,
    }
  },
  computed: {
    tabs: function () {
      return TabsList.map((tab) => {
        return {
          displayName: tab.displayName,
          path: { name: tab.name },
        }
      })
    },
  },
}
</script>
