/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { defineConfig } from 'vite'
import VitePluginStyleInject from 'vite-plugin-style-inject'
import vue from '@vitejs/plugin-vue'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

// Builds the <%= panel_type %> Dashboards panel type into
// tools/panels/<%= panel_type %>/<%= panel_type %>.js, the SystemJS module the
// PANEL <%= panel_type %> line in plugin.txt installs
export default defineConfig({
  build: {
    outDir: 'tools/panels/<%= panel_type %>',
    emptyOutDir: true,
    sourcemap: true,
    lib: {
      entry: './src/<%= panel_name %>.js',
      fileName: () => '<%= panel_type %>.js',
      formats: ['system'],
    },
    rollupOptions: {
      // Provided by COSMOS, so the panel uses the same copies as Dashboards
      external: ['single-spa', 'vue', 'pinia', 'vue-router', 'vuetify'],
    },
  },
  // Styles go in the module, since only the one .js file is installed
  plugins: [vue(), VitePluginStyleInject()],
  resolve: {
    extensions: [...DEFAULT_EXTENSIONS, '.vue'],
  },
})
