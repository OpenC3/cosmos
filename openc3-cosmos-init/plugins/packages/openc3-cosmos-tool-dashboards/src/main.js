/*
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
*/

import { createApp, h } from 'vue'
import singleSpaVue from 'single-spa-vue'

import '@openc3/vue-common/styles'
import App from './App.vue'
import router from './router'
import { Dialog, Notify, store, vuetify } from '@openc3/vue-common/plugins'

const vueLifecycles = singleSpaVue({
  createApp,
  appOptions: {
    render() {
      return h(App, {})
    },
    el: '#openc3-tool',
  },
  handleInstance: (app) => {
    app.use(router)
    app.use(store)
    app.use(vuetify)
    app.use(Dialog)
    app.use(Notify)
  },
})

export const bootstrap = vueLifecycles.bootstrap
export const mount = vueLifecycles.mount
export const unmount = vueLifecycles.unmount
