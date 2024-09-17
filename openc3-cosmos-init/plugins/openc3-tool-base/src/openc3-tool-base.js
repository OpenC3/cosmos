import { createApp } from 'vue'

import App from './App.vue'
import { registerAstroComponents } from './plugins/astrouxds'
import vuetify from './plugins/vuetify'
import router from './router'
import store from '../../packages/openc3-tool-common/src/plugins/store'
import '../../packages/openc3-tool-common/src/assets/stylesheets/layout/layout.scss'

registerAstroComponents()

const app = createApp(App)

app.use(store)
app.use(router)
app.use(vuetify)

const options = OpenC3Auth.getInitOptions()
OpenC3Auth.init(options).then(() => {
  // Set the scope variable that will be used for the life of this page load
  // It is always default in standard edition
  window.openc3Scope = 'DEFAULT'

  app.mount('#openc3-main')
})
