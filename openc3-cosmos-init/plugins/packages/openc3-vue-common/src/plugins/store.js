/*
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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { createStore } from 'vuex'

const NOTIFY_HISTORY_MAX_LENGTH = 100

export default createStore({
  state: {
    notifyHistory: [],
    namedWidgets: {},
  },
  getters: {
    namedWidget: (state) => (widgetName) => {
      return state.namedWidgets[widgetName]
    },
  },
  mutations: {
    notifyAddHistory: (state, notification) => {
      if (state.notifyHistory.length >= NOTIFY_HISTORY_MAX_LENGTH) {
        state.notifyHistory.length = NOTIFY_HISTORY_MAX_LENGTH - 1
      }
      state.notifyHistory.unshift(notification)
    },
    notifyClearHistory: (state) => {
      state.notifyHistory = []
    },
    setNamedWidget: (state, namedWidget) => {
      Object.assign(state.namedWidgets, namedWidget)
    },
    clearNamedWidget: (state, widgetName) => {
      delete state.namedWidgets[widgetName]
    },
  },
  modules: {},
})
