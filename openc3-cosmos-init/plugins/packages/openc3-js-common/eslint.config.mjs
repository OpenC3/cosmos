import eslintPluginPrettierRecommended from "eslint-plugin-prettier/recommended"
import globals from "globals"

export default [
  {
    languageOptions: {
      globals: {
        ...globals.node,
      },

      ecmaVersion: 2022,
      sourceType: "module",
    },

    rules: {
      "no-console": "error",
      "no-debugger": "error",

      "prettier/prettier": ["warn", {
        endOfLine: "auto",
      }],
    },
  },
  eslintPluginPrettierRecommended,
];
