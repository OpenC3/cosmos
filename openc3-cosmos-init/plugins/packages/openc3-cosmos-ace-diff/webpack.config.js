// Generated using webpack-cli https://github.com/webpack/webpack-cli

const path = require('path')
const isProduction = process.env.NODE_ENV == 'production'

const config = {
  entry: {
    ace: { import: './src/index.js', filename: 'ace-diff.min.js' },
    css: { import: './src/styles/ace-diff.scss', filename: 'ace-diff.min.css' },
    darkcss: {
      import: './src/styles/ace-diff-dark.scss',
      filename: 'ace-diff-dark.min.css',
    },
  },
  // entry: [
  //   './src/index.js',
  //   // './src/styles/ace-diff.scss',
  //   // './src/styles/ace-diff-dark.scss',
  // ],
  output: {
    path: path.resolve(__dirname, 'dist'),
    // filename: 'ace-diff.min.js',
    library: {
      type: 'commonjs-module',
    },
  },
  module: {
    rules: [
      {
        test: /\.(js|jsx)$/i,
        loader: 'babel-loader',
      },
      {
        test: /\.scss$/,
        exclude: /node_modules/,
        use: [
          {
            loader: 'file-loader',
            options: { name: '[name].min.css' },
          },
          // Compiles Sass to CSS
          'sass-loader',
        ],
      },
    ],
  },
}

module.exports = () => {
  if (isProduction) {
    config.mode = 'production'
  } else {
    config.mode = 'development'
  }
  return config
}
