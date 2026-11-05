// SystemJS bootstrap for the OpenC3 single-spa shell.
// Externalized from index.html so the Content-Security-Policy script-src no
// longer needs 'unsafe-inline'. Loads the shared dependencies and mounts the
// base tool.
;(function () {
  Object.getPrototypeOf(System).firstGlobalProp = true
  Promise.all([System.import('single-spa'), System.import('vue')])
    .then(function () {
      System.set(System.resolve('vue'), window.Vue)
      return Promise.all([
        System.import('vue-router'),
        System.import('vuex'),
        System.import('pinia'),
        System.import('vuetify'),
      ])
    })
    .then(function () {
      System.set(System.resolve('vue-router'), window.VueRouter)
      System.set(System.resolve('vuex'), window.Vuex)
      System.set(System.resolve('pinia'), window.Pinia)
      System.import('@openc3/tool-base')
    })
})()
