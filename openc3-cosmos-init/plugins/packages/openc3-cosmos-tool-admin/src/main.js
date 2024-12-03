import { createApp, h } from 'vue'
import singleSpaVue from 'single-spa-vue'

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
    app.use(Notify, { store })
  },
})

export const bootstrap = vueLifecycles.bootstrap
export const mount = vueLifecycles.mount
export const unmount = vueLifecycles.unmount
