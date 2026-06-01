<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-row no-gutters align="center" class="px-2">
      <v-col class="pa-2 mt-2">
        <v-btn @click="selectFile">Install Package</v-btn>
        <input
          ref="fileInput"
          style="display: none"
          type="file"
          @change="fileChange"
        />
      </v-col>
      <v-col class="ml-4 mr-2" cols="4">
        <rux-progress :value="progress"></rux-progress>
      </v-col>
    </v-row>
    <v-list
      v-if="Object.keys(processes).length > 0"
      class="list"
      data-test="process-list"
    >
      <v-row no-gutters class="px-4">
        <v-col class="text-h6">Process List</v-col>
        <v-col align="right">
          <!-- See openc3/lib/openc3/utilities/process_manager.rb CLEANUP_CYCLE_SECONDS -->
          <div>Showing last 10 min of activity</div>
        </v-col>
      </v-row>
      <div v-for="process in processes" :key="process.name">
        <v-list-item>
          <v-list-item-title>
            <span
              :class="process.state.toLowerCase()"
              v-text="
                `Processing ${process.process_type}: ${process.detail} - ${process.state}`
              "
            />
          </v-list-item-title>
          <v-list-item-subtitle>
            <span
              v-text="
                ' Updated At: ' +
                formatNanoseconds(process.updated_at, timeZone)
              "
            />
          </v-list-item-subtitle>

          <template v-if="process.state !== 'Running'" #append>
            <v-tooltip :open-delay="600" location="top">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  icon="mdi-eye"
                  variant="text"
                  aria-label="Show Output"
                  @click="showOutput(process)"
                />
              </template>
              <span>Show Output</span>
            </v-tooltip>
          </template>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <v-list class="list" data-test="packageList">
      <v-row class="px-4"><v-col class="text-h6">Ruby Gems</v-col></v-row>
      <div v-for="(gem, index) in gems" :key="index">
        <v-list-item>
          <v-list-item-title>{{ gem }}</v-list-item-title>

          <template #append>
            <v-btn
              icon="mdi-delete"
              variant="text"
              aria-label="Delete Ruby Gem"
              @click="deletePackage(gem)"
            />
          </template>
        </v-list-item>
        <v-divider />
      </div>
      <v-row class="px-4"><v-col class="text-h6">Python Packages</v-col></v-row>
      <div v-for="pluginName in orderedPluginNames" :key="pluginName">
        <v-list-subheader
          class="font-weight-bold plugin-header"
          @click="togglePlugin(pluginName)"
        >
          <v-icon size="small" class="mr-1">
            {{
              expandedPlugins[pluginName]
                ? 'mdi-chevron-down'
                : 'mdi-chevron-right'
            }}
          </v-icon>
          {{ formatPluginName(pluginName) }}
          ({{ python[pluginName].length }}) [{{ venvPath(pluginName) }}]
        </v-list-subheader>
        <div v-if="expandedPlugins[pluginName]">
          <div
            v-for="(pkg, index) in formattedPackages(
              pluginName,
              python[pluginName],
            )"
            :key="`${pluginName}-${index}`"
          >
            <v-list-item class="pl-8">
              <v-list-item-title>{{ pkg }}</v-list-item-title>

              <template
                v-if="pluginName !== 'cached' && pluginName !== 'shared'"
                #append
              >
                <v-btn
                  icon="mdi-delete"
                  variant="text"
                  aria-label="Delete Python Package"
                  @click="deletePythonPackage(pkg, pluginName)"
                />
              </template>
            </v-list-item>
            <v-divider />
          </div>
        </div>
      </div>
    </v-list>
    <download-dialog v-model="showDownloadDialog" />
    <simple-text-dialog
      v-model="showProcessOutput"
      title="Process Output"
      :text="processOutput"
    />
    <v-dialog v-model="showPluginSelect" max-width="500" persistent>
      <v-card>
        <v-card-title>Select Plugin Environment</v-card-title>
        <v-card-text>
          <v-select
            v-model="selectedPlugin"
            :items="pluginVenvOptions"
            label="Install into plugin venv"
            density="comfortable"
            data-test="plugin-venv-select"
          />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="cancelPluginSelect">Cancel</v-btn>
          <v-btn
            color="primary"
            variant="flat"
            :disabled="!selectedPlugin"
            @click="confirmPluginInstall"
          >
            OK
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import { Api, OpenC3Api } from '@openc3/js-common/services'
import { SimpleTextDialog } from '@/components'
import { DownloadDialog } from '@/tools/admin'
import { TimeFilters } from '@/util'

export default {
  components: {
    DownloadDialog,
    SimpleTextDialog,
  },
  mixins: [TimeFilters],
  data() {
    return {
      showDownloadDialog: false,
      showProcessOutput: false,
      processOutput: '',
      files: [],
      loadingPackage: false,
      progress: 0,
      gems: [],
      python: {},
      pythonTrees: {},
      expandedPlugins: {},
      processes: {},
      timeZone: 'local',
      showPluginSelect: false,
      selectedPlugin: null,
      pendingFiles: null,
    }
  },
  computed: {
    pluginVenvOptions() {
      return Object.keys(this.python).filter(
        (k) => k !== 'cached' && k !== 'shared',
      )
    },
    orderedPluginNames() {
      const names = Object.keys(this.python)
      const reserved = new Set(['cached', 'shared'])
      // Cached first, then plugin venvs sorted, then shared last
      const cached = names.filter((k) => k === 'cached')
      const plugins = names.filter((k) => !reserved.has(k)).sort()
      const shared = names.filter((k) => k === 'shared')
      return [...cached, ...plugins, ...shared]
    },
  },
  created() {
    new OpenC3Api()
      .get_setting('time_zone')
      .then((response) => {
        if (response) {
          this.timeZone = response
        }
      })
      .catch(() => {
        // Do nothing
      })
  },
  mounted() {
    this.update()
    this.updateProcesses()
  },
  methods: {
    showOutput: function (process) {
      this.processOutput = process.output
      this.showProcessOutput = true
    },
    update() {
      Api.get('/openc3-api/packages').then((response) => {
        this.gems = response.data.ruby
        this.python = response.data.python
      })
      Api.get('/openc3-api/packages/trees').then((response) => {
        this.pythonTrees = response.data
      })
    },
    updateProcesses: function () {
      Api.get('/openc3-api/process_status/package_?substr=true').then(
        (response) => {
          this.processes = response.data
          if (Object.keys(this.processes).length > 0) {
            // process_manager.rb script operates on a 5 second cycle
            setTimeout(() => {
              this.updateProcesses()
              this.update()
            }, 2500)
          }
        },
      )
    },
    selectFile() {
      this.progress = 0
      this.$refs.fileInput.click()
    },
    fileChange(event) {
      const files = event.target.files
      if (files.length > 0) {
        const hasWheel = [...files].some((f) => !f.name.endsWith('.gem'))
        const pluginNames = Object.keys(this.python).filter(
          (k) => k !== 'shared',
        )
        if (hasWheel && pluginNames.length > 0) {
          this.pendingFiles = files
          this.selectedPlugin = null
          this.showPluginSelect = true
        } else {
          this.uploadFiles(files)
        }
      }
    },
    uploadFiles(files, plugin = null) {
      this.loadingPackage = true
      let self = this
      const promises = [...files].map((file) => {
        const formData = new FormData()
        formData.append('package', file, file.name)
        if (plugin && !file.name.endsWith('.gem')) {
          formData.append('plugin', plugin)
        }
        return Api.post('/openc3-api/packages', {
          data: formData,
          headers: { 'Content-Type': 'multipart/form-data' },
          onUploadProgress: function (progressEvent) {
            let percentCompleted = Math.round(
              (progressEvent.loaded * 100) / progressEvent.total,
            )
            self.progress = percentCompleted
          },
        })
      })
      Promise.all(promises)
        .then((responses) => {
          this.$notify.normal({
            body: `Uploaded ${responses.length} package${
              responses.length > 1 ? 's' : ''
            }`,
          })
          this.loadingPackage = false
          this.files = []
          setTimeout(() => {
            this.updateProcesses()
          }, 2500)
        })
        .catch((error) => {
          this.loadingPackage = false
        })
    },
    confirmPluginInstall() {
      const files = this.pendingFiles
      const plugin = this.selectedPlugin
      this.showPluginSelect = false
      this.pendingFiles = null
      this.uploadFiles(files, plugin)
    },
    cancelPluginSelect() {
      this.showPluginSelect = false
      this.pendingFiles = null
      this.selectedPlugin = null
      this.$refs.fileInput.value = ''
    },
    togglePlugin(pluginName) {
      this.expandedPlugins[pluginName] = !this.expandedPlugins[pluginName]
    },
    formattedPackages(pluginName, packages) {
      if (this.pythonTrees[pluginName]) {
        return this.parseTreeOutput(this.pythonTrees[pluginName])
      }
      return packages.map((pkg) => this.formatPackageName(pkg))
    },
    formatPackageName(pkg) {
      // Transform dist-info format "numpy-2.4.4" to pip format "numpy==2.4.4"
      const match = pkg.match(/^(.+?)-(\d.*)$/)
      if (match) {
        return `${match[1]}==${match[2]}`
      }
      return pkg
    },
    parseTreeOutput(treeText) {
      // Parse "uv pip list" output, skip header lines, return name==version strings
      const lines = treeText.split('\n')
      const packages = []
      for (const line of lines) {
        const trimmed = line.trim()
        if (
          !trimmed ||
          trimmed.startsWith('Package') ||
          trimmed.startsWith('---')
        ) {
          continue
        }
        const parts = trimmed.split(/\s+/)
        if (parts.length >= 2) {
          packages.push(`${parts[0]}==${parts[1]}`)
        }
      }
      return packages
    },
    formatPluginName(name) {
      if (name === 'cached') {
        return 'Cached'
      }
      if (name === 'shared') {
        return 'Shared'
      }
      // Strip the sanitized version/counter suffix for readability
      // e.g. "openc3-cosmos-demo-7_1_1_pre_beta0_gem__0" -> "openc3-cosmos-demo"
      return name.replace(/-\d[\d_a-z]*_gem__\d+$/, '').replace(/__\d+$/, '')
    },
    venvPath(pluginName) {
      if (pluginName === 'cached') {
        return '/gems/uv'
      }
      if (pluginName === 'shared') {
        return '/gems/python_packages'
      }
      return `/gems/plugin_venvs/${pluginName}/.venv`
    },
    deletePackage(pkg) {
      this.$dialog
        .confirm(`Are you sure you want to remove: ${pkg}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          return Api.delete(`/openc3-api/packages/${pkg}`)
        })
        .then((response) => {
          this.$notify.normal({
            body: `Removed package ${pkg}`,
          })
          setTimeout(() => {
            this.updateProcesses()
          }, 2500)
        })
        // Error will probably never happen because we spawn the package removal
        // and then wait for the response which happens in the background
        .catch((error) => {
          this.$notify.serious({
            body: `Failed to remove package ${pkg}`,
          })
        })
    },
    deletePythonPackage(formattedPkg, pluginName) {
      // Convert display format "name==version" to dist-info format "name-version"
      const rawPkg = formattedPkg.replace('==', '-')
      this.$dialog
        .confirm(`Are you sure you want to remove: ${formattedPkg}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          return Api.delete(
            `/openc3-api/packages/${rawPkg}?plugin=${pluginName}`,
          )
        })
        .then((response) => {
          this.$notify.normal({
            body: `Removed package ${formattedPkg}`,
          })
          setTimeout(() => {
            this.updateProcesses()
          }, 2500)
        })
        .catch((error) => {
          this.$notify.serious({
            body: `Failed to remove package ${formattedPkg}`,
          })
        })
    },
  },
}
</script>

<style scoped>
.list {
  background-color: var(--color-background-surface-default) !important;
  overflow-x: hidden;
}
.plugin-header {
  cursor: pointer;
  user-select: none;
}
</style>
