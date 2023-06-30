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
      <v-tabs v-model="curTab" fixed-tabs>
        <v-tab v-for="(tab, index) in tabs" :key="index" :to="tab.path">
          {{ tab.name }}
        </v-tab>
      </v-tabs>
      <router-view />
    </v-card>
    <div style="height: 15px" />
    <events />
  </div>
</template>

<script>
import TopBar from '@openc3/tool-common/src/components/TopBar'
import Events from './Events'
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'

export default {
  components: {
    TopBar,
    Events,
  },
  data() {
    return {
      title: 'COSMOS Autonomic',
      curTab: null,
      tabs: [
        {
          name: 'Triggers',
          path: '/triggers',
        },
        {
          name: 'Reactions',
          path: '/reactions',
        },
      ],
      api: null,
    }
  },
  created: function () {
    // Ensure Offline Access Is Setup For the Current User
    this.api = new OpenC3Api()
    this.api.ensure_offline_access()
  },
}
</script>
