import 'systemjs-webpack-interop/auto-public-path/2'
import singleSpaVue from 'single-spa-vue'

import App from './App.vue'
import router from './router'
import store from '@openc3/tool-common/src/plugins/store'

Vue.config.productionTip = false

import '@openc3/tool-common/src/assets/stylesheets/layout/layout.scss'
import vuetify from '@openc3/tool-common/src/plugins/vuetify'
import Dialog from '@openc3/tool-common/src/plugins/dialog'
import PortalVue from 'portal-vue'
import Notify from '@openc3/tool-common/src/plugins/notify'

const { createApp } = Vue

const vueLifecycles = singleSpaVue({
  createApp,
  appOptions: {
    render(h) {
      return h(App, {
        props: {},
      })
    },
    el: '#openc3-tool',
  },
  handleInstance: (app) => {
    app.use(vuetify)
    app.use(router)
    app.use(store)
    app.use(PortalVue)
    app.use(Dialog)
    app.use(Notify, { store })
  },
})

export const bootstrap = vueLifecycles.bootstrap
export const mount = vueLifecycles.mount
export const unmount = vueLifecycles.unmount
