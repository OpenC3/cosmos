const path = require('path')

module.exports = {
  publicPath: '/tools/<%= tool_name %>',
  outputDir: 'tools/<%= tool_name %>',
  filenameHashing: false,
  transpileDependencies: ['vuetify'],
  devServer: {
    port: 2999,
    headers: {
      'Access-Control-Allow-Origin': '*',
    },
    client: {
      webSocketURL: {
        hostname: 'localhost',
        pathname: '/tools/<%= tool_name %>',
        port: 2999,
      },
    },
  },
  configureWebpack: {
    output: {
      libraryTarget: 'system',
    },
  },
  chainWebpack: (config) => {
    config.module.rule('js').use('babel-loader')
    config.module
      .rule('vue')
      .use('vue-loader')
      .tap((options) => {
        return {
          prettify: false,
        }
      })
    config.externals(['vue', 'vuetify', 'vuex', 'vue-router'])
  },
}
