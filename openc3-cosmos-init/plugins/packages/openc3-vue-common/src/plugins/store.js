/*
# Copyright 2026 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { createPinia, defineStore } from 'pinia'

const NOTIFY_HISTORY_MAX_LENGTH = 100

export const useStore = defineStore('app', {
  state: () => ({
    notifyHistory: [],
    namedWidgets: {},
    playback: {
      playbackMode: null,
      playbackDateTime: null,
      playbackStep: 1,
      playbackLoading: 0, // Counter for number of graphs loading playback data
    },
  }),
  getters: {
    namedWidget: (state) => (widgetName) => {
      return state.namedWidgets[widgetName]
    },
  },
  actions: {
    notifyAddHistory(notification) {
      if (this.notifyHistory.length >= NOTIFY_HISTORY_MAX_LENGTH) {
        this.notifyHistory.length = NOTIFY_HISTORY_MAX_LENGTH - 1
      }
      this.notifyHistory.unshift(notification)
    },
    notifyClearHistory() {
      this.notifyHistory = []
    },
    setNamedWidget(namedWidget) {
      Object.assign(this.namedWidgets, namedWidget)
    },
    clearNamedWidget(widgetName) {
      delete this.namedWidgets[widgetName]
    },
    updatePlayback(playback) {
      Object.assign(this.playback, playback)
    },
  },
})

const store = createPinia()

// Wrap the original install to also set up $store global property
const originalInstall = store.install.bind(store)
store.install = (app) => {
  // Call Pinia's original install
  originalInstall(app)
  // Create the store instance and make it available as $store
  const piniaStore = useStore(store)
  app.config.globalProperties.$store = piniaStore
}

export default store
