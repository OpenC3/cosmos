import 'systemjs-webpack-interop/auto-public-path/2'
import { createApp, h } from 'vue'
import singleSpaVue from 'single-spa-vue'

import App from './App.vue'
import router from './router'
import store from '@openc3/tool-common/src/plugins/store'

import '@openc3/tool-common/src/assets/stylesheets/layout/layout.scss'
import vuetify from '@openc3/tool-common/src/plugins/vuetify'
import Dialog from '@openc3/tool-common/src/plugins/dialog'
import Notify from '@openc3/tool-common/src/plugins/notify'

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
    app.use(Notify, { store })
  },
})

export const bootstrap = vueLifecycles.bootstrap
export const mount = vueLifecycles.mount
export const unmount = vueLifecycles.unmount
