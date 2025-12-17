<!--
# Copyright 2025 OpenC3, Inc.
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
  <div v-if="showSpinner" class="d-flex justify-center align-center">
    <v-progress-circular indeterminate />
  </div>
</template>

<script>
import { getMountedApps } from 'single-spa'

const POLL_INTERVAL_MS = 50
const NOT_FOUND_TIMEOUT_MS = 2000
const SINGLE_SPA_APP_CHANGE_EVENT = 'single-spa:app-change'

// This component is actually always loaded for every route other than /login
// because of the catch-all path in tool-base's router, so we need logic to
// hide it when a tool is loaded.
export default {
  data() {
    return {
      appsMounted: false,
      show: false,
      hideSpinner: false,
      pollInterval: null,
    }
  },
  computed: {
    showSpinner: function () {
      return !this.hideSpinner && !this.show
    },
  },
  created() {
    window.addEventListener(SINGLE_SPA_APP_CHANGE_EVENT, this.handleAppChange)
  },
  mounted() {
    this.pollForMountedApps()
    // This gives some time to allow slow connections to find the apps before flashing the 404
    setTimeout(() => {
      if (!this.appsMounted) {
        this.show = true
        if (this.pollInterval) {
          clearInterval(this.pollInterval)
        }
      }
    }, NOT_FOUND_TIMEOUT_MS)
  },
  unmounted() {
    window.removeEventListener(
      SINGLE_SPA_APP_CHANGE_EVENT,
      this.handleAppChange,
    )
    if (this.pollInterval) {
      clearInterval(this.pollInterval)
    }
  },
  methods: {
    handleAppChange: function (event) {
      this.show = !event.detail.appsByNewStatus.MOUNTED
      this.hideSpinner = true
    },
    pollForMountedApps: function () {
      // Check to see if there are single-spa apps that matched the route.
      // The app-change event doesn't cover this case...
      this.pollInterval = setInterval(() => {
        this.appsMounted = getMountedApps().length > 0
        if (getMountedApps().length > 0) {
          this.hideSpinner = true
          clearInterval(this.pollInterval)
        }
      }, POLL_INTERVAL_MS)
    },
  },
}
</script>
