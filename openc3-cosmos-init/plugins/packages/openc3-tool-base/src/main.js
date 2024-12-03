import { createApp } from 'vue'
import { defineCustomElements } from '@astrouxds/astro-web-components/loader'
import { Notify, store, vuetify } from '@openc3/vue-common/plugins'

import '@openc3/vue-common/styles'
import '@openc3/tool-common/styles'
import '@/assets/stylesheets/layout/layout.scss'

import App from './App.vue'
import router from './router'

defineCustomElements()

Object.getPrototypeOf(System).firstGlobalProp = true;

const app = createApp(App)

app.use(store)
app.use(vuetify)
app.use(router)
app.use(Notify, { store })

const options = OpenC3Auth.getInitOptions()
OpenC3Auth.init(options).then(() => {
  // Set the scope variable that will be used for the life of this page load
  // It is always default in standard edition
  window.openc3Scope = 'DEFAULT'

  app.mount('#openc3-main')
})
