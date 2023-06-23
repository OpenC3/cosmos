const { merge } = require("webpack-merge");
const singleSpaDefaults = require("webpack-config-single-spa-react");
const path = require("path");

function resolve(dir) {
  return path.join(__dirname, "..", dir);
}

module.exports = (webpackConfigEnv, argv) => {
  const defaultConfig = singleSpaDefaults({
    orgName: "openc3",
    projectName: "<%= tool_name %>",
    webpackConfigEnv,
    argv,
    orgPackagesAsExternal: false,
  });

  delete defaultConfig.externals;

  return merge(defaultConfig, {
    output: {
      path: path.resolve(__dirname, "tools/<%= tool_name %>"),
      filename: "main.js",
      libraryTarget: "system", // This line is in all the vue.config.js files, is it needed here?
    },
  });
};
