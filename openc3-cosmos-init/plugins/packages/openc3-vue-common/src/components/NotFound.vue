<!--
# Copyright 2024 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card v-if="show">
    <v-card-title> 404 Not Found </v-card-title>
    <v-card-text class="d-flex align-center mt-3">
      The requested URL
      <code class="mx-1"> {{ $route.fullPath }} </code>
      was not routable.
      <span class="text-h3 mx-1"> 🦄 </span>
    </v-card-text>
  </v-card>
</template>

<script>
import { getMountedApps } from 'single-spa'

const SINGLE_SPA_APP_CHANGE_EVENT = 'single-spa:app-change'

// This component is actually always loaded for every route other than /login
// because of the catch-all path in tool-base's router, so we need logic to
// hide it when a tool is loaded.
export default {
  data() {
    return {
      show: false,
    }
  },
  created() {
    window.addEventListener(SINGLE_SPA_APP_CHANGE_EVENT, this.handleAppChange)
  },
  mounted() {
    // Give single-spa some time to get an app mounted to avoid flashing this
    setTimeout(() => {
      this.show = getMountedApps().length === 0
    }, 150)
  },
  unmounted() {
    window.removeEventListener(SINGLE_SPA_APP_CHANGE_EVENT, this.handleAppChange)
  },
  methods: {
    handleAppChange: function (event) {
      this.show = !event.detail.appsByNewStatus.MOUNTED
    },
  },
}
</script>
