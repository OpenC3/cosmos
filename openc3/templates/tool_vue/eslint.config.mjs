import prettierConfig from "@vue/eslint-config-prettier"
import pluginVue from "eslint-plugin-vue"
import globals from "globals"
import parser from "vue-eslint-parser"

export default [
  ...pluginVue.configs['flat/recommended'],
  {
    languageOptions: {
      globals: {
        ...globals.node,
      },

      parser: parser,
      ecmaVersion: 2022,
      sourceType: "module",
    },

    rules: {
      "no-console": "error",
      "no-debugger": "error",

      "prettier/prettier": ["warn", {
        endOfLine: "auto",
      }],

      "vue/multi-word-component-names": "off",

      "vue/valid-v-slot": ["error", {
        allowModifiers: true,
      }],
    },
  },
  {
    files: ["**/__tests__/*.{j,t}s?(x)", "**/tests/unit/**/*.spec.{j,t}s?(x)"],

    languageOptions: {
      globals: {
        ...globals.jest,
      },
    },
  },
  prettierConfig,
]
