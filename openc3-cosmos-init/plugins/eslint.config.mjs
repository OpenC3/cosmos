import prettier from "eslint-plugin-prettier";
import globals from "globals";
import path from "node:path";
import { fileURLToPath } from "node:url";
import js from "@eslint/js";
import { FlatCompat } from "@eslint/eslintrc";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const compat = new FlatCompat({
    baseDirectory: __dirname,
    recommendedConfig: js.configs.recommended,
    allConfig: js.configs.all
});

export default [...compat.extends(
    "plugin:vue/vue3-essential",
    "plugin:prettier/recommended",
    "@vue/prettier",
), {
    plugins: {
        prettier,
    },

    languageOptions: {
        globals: {
            ...globals.node,
        },

        ecmaVersion: 5,
        sourceType: "commonjs",

        parserOptions: {
            parser: "@babel/eslint-parser",
        },
    },

    rules: {
        "no-console": "off",
        "no-debugger": "off",

        "prettier/prettier": ["warn", {
            endOfLine: "auto",
        }],

        "vue/valid-v-slot": ["error", {
            allowModifiers: true,
        }],
    },
}, {
    files: ["**/__tests__/*.{j,t}s?(x)", "**/tests/unit/**/*.spec.{j,t}s?(x)"],

    languageOptions: {
        globals: {
            ...globals.jest,
        },
    },
}];