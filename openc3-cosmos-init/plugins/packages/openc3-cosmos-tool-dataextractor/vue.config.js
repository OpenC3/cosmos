module.exports = {
  publicPath: '/tools/dataextractor',
  outputDir: 'tools/dataextractor',
  filenameHashing: false,
  transpileDependencies: ['vuetify'],
  devServer: {
    port: 2918,
    headers: {
      'Access-Control-Allow-Origin': '*',
    },
    client: {
      webSocketURL: {
        hostname: 'localhost',
        pathname: '/tools/dataextractor',
        port: 2918,
      },
    },
  },
  configureWebpack: {
    output: {
      libraryTarget: 'system',
    },
  },
  chainWebpack(config) {
    config.resolve.alias.set('vue', '@vue/compat')
    config.module
      .rule('js')
      .use('babel-loader')
      .tap((options) => {
        return {
          rootMode: 'upward',
        }
      })
    config.module
      .rule('vue')
      .use('vue-loader')
      .tap((options) => {
        return {
          prettify: false,
          compilerOptions: {
            compatConfig: {
              MODE: 3,
            },
          },
        }
      })
    config.externals(['vue', 'vuetify', 'vuex', 'vue-router'])
  },
}
