import { createApp } from 'vue'
import { defineCustomElements } from '@astrouxds/astro-web-components/loader'
import { Notify, store, vuetify } from '@openc3/vue-common/plugins'

import '@openc3/vue-common/styles'
import '@/assets/stylesheets/layout/layout.scss'

import App from './App.vue'
import router from './router'

defineCustomElements()

Object.getPrototypeOf(System).firstGlobalProp = true

const app = createApp(App)
// Each tool is its own Vue app on the same page, and Vue numbers useId() per
// app starting from the same value, so the navigation and the tool would
// generate the same element ids (e.g. a field's input-v-23 and its label).
// A distinct prefix keeps the navigation's ids unique.
app.config.idPrefix = 'nav'

app.use(store)
app.use(vuetify)
app.use(Notify)

const options = OpenC3Auth.getInitOptions()
OpenC3Auth.init(options).then(() => {
  // Set the scope variable that will be used for the life of this page load
  // It is always DEFAULT in COSMOS Core
  window.openc3Scope = 'DEFAULT'

  // Install the router only after auth is ready. Installing it starts the
  // initial navigation, whose guard makes API calls that would otherwise run
  // before auth has initialized and fail with no token
  app.use(router)
  app.mount('#openc3-main')
})
