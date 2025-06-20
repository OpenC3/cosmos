<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-row no-gutters align="center" class="px-2">
      <v-col class="pa-2 mt-2">
        <v-btn append-icon="mdi-store" @click="openStore">
          Browse Plugins
        </v-btn>
        <v-btn append-icon="mdi-paperclip" class="mx-2" @click="selectFile">
          Install From File
        </v-btn>
        <input
          ref="fileInput"
          style="display: none"
          type="file"
          @change="fileChange"
        />
        <br />
        Note: Use <v-icon> mdi-dots-horizontal </v-icon> in the Installed Plugins list to upgrade existing plugins
      </v-col>
      <v-col class="ml-4 mr-2" cols="4">
        <rux-progress :value="progress" />
      </v-col>
    </v-row>
    <v-row no-gutters class="px-2">
      <v-col align="right" class="mr-2">
        <div>* indicates a modified plugin</div>
        <div>Click target link to download modifications</div>
      </v-col>
    </v-row>
    <v-divider />
    <!-- TODO This alert shows both success and failure. Make consistent with rest of OpenC3. -->
    <v-alert
      v-model="showAlert"
      closable
      :type="alertType"
      :text="alert"
      data-test="plugin-alert"
    />
    <v-list
      v-if="Object.keys(processes).length > 0"
      class="list"
      data-test="process-list"
    >
      <v-row no-gutters class="px-4">
        <v-col class="text-h5"> Process List </v-col>
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
            <span v-text="' Updated At: ' + formatDate(process.updated_at)" />
          </v-list-item-subtitle>

          <template #append>
            <v-progress-circular
              v-if="process.state === 'Running'"
              indeterminate
              color="primary"
            />
            <v-tooltip v-else :open-delay="600" location="top">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  icon="mdi-eye"
                  variant="text"
                  aria-label="Show Output"
                  data-test="show-output"
                  @click="showOutput(process)"
                />
              </template>
              <span> Show Output </span>
            </v-tooltip>
          </template>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <v-row class="px-4">
      <v-col class="text-h5">
        Installed Plugins
      </v-col>
      <v-col class="v-col-auto">
        <v-switch
          v-model="showDefaultTools"
          label="Show Default Tools"
          density="compact"
          hide-details
          data-test="show-default-tools"
        />
      </v-col>
    </v-row>
    <v-data-table
      :headers="[]"
      :items="shownPlugins"
      density="compact"
      class="list"
      data-test="plugin-list"
    >
      <template v-slot:item="{ item: plugin }">
        <plugin-list-item
          v-bind="plugin"
          :targets="pluginTargets(plugin.name)"
          :isModified="isModified(plugin.name)"
          @edit="() => editPlugin(plugin.name)"
          @upgrade="() => upgradePlugin(plugin.name)"
          @delete="() => deletePrompt(plugin.name)"
          @show-details="showDetails"
        />
      </template>
    </v-data-table>
    <plugin-card
      v-bind="detailPlugin"
      hide-activator
      :show-dailog="showPluginDetails"
    />
    <plugin-dialog
      v-if="showPluginDialog"
      v-model="showPluginDialog"
      :plugin-name="pluginName"
      :variables="variables"
      :plugin-txt="pluginTxt"
      :existing-plugin-txt="existingPluginTxt"
      @callback="pluginCallback"
    />
    <modified-plugin-dialog
      v-if="showModifiedPluginDialog"
      v-model="showModifiedPluginDialog"
      :plugin-name="currentPlugin"
      :targets="pluginTargets(currentPlugin)"
      :plugin-delete="pluginDelete"
      @submit="modifiedSubmit"
    />
    <!-- <download-dialog v-model="showDownloadDialog" /> -->
    <simple-text-dialog
      v-model="showProcessOutput"
      title="Process Output"
      :text="processOutput"
    />
    <v-bottom-sheet v-model="showPluginStore" fullscreen>
      <plugin-store @close="() => showPluginStore = false" @triggerInstall="installFromUrl" />
    </v-bottom-sheet>
  </div>
</template>

<script>
import { toDate, format } from 'date-fns'
import { Api } from '@openc3/js-common/services'
import { SimpleTextDialog } from '@/components'
import { ModifiedPluginDialog, PluginDialog } from '@/tools/admin'
import { PluginListItem } from '@/tools/admin/tabs/plugins'
import { PluginStoreApi } from '@/tools/admin/tabs/plugins'
import { PluginStore } from '@/plugins/plugin-store'

export default {
  components: {
    PluginDialog,
    PluginListItem,
    PluginStore,
    ModifiedPluginDialog,
    SimpleTextDialog,
  },
  data() {
    return {
      pluginStoreApi: new PluginStoreApi(),
      file: null,
      currentPlugin: null,
      showPluginDetails: false,
      detailPlugin: null,
      plugins: {},
      targets: {},
      processes: {},
      alert: '',
      alertType: 'success',
      showAlert: false,
      pluginName: null,
      variables: {},
      pluginTxt: '',
      pluginHashTmp: null,
      existingPluginTxt: null,
      showDownloadDialog: false,
      showProcessOutput: false,
      processOutput: '',
      showPluginStore: false,
      showPluginDialog: false,
      showModifiedPluginDialog: false,
      showDefaultTools: false,
      progress: 0,
      pluginDelete: false,
      // When updating update local_mode.rb, local_mode.py, plugins.spec.ts
      defaultPlugins: [
        'openc3-cosmos-tool-admin',
        'openc3-cosmos-tool-bucketexplorer',
        'openc3-cosmos-tool-cmdsender',
        'openc3-cosmos-tool-cmdhistory', // Enterprise only
        'openc3-cosmos-tool-cmdtlmserver',
        'openc3-cosmos-tool-dataextractor',
        'openc3-cosmos-tool-dataviewer',
        'openc3-cosmos-tool-docs',
        'openc3-cosmos-tool-handbooks',
        'openc3-cosmos-tool-iframe',
        'openc3-cosmos-tool-limitsmonitor',
        'openc3-cosmos-tool-packetviewer',
        'openc3-cosmos-tool-scriptrunner',
        'openc3-cosmos-tool-tablemanager',
        'openc3-cosmos-tool-tlmgrapher',
        'openc3-cosmos-tool-tlmviewer',
        'openc3-cosmos-enterprise-tool-admin', // Enterprise only
        'openc3-cosmos-tool-autonomic', // Enterprise only
        'openc3-cosmos-tool-calendar', // Enterprise only
        'openc3-cosmos-tool-grafana', // Enterprise only
        'openc3-cosmos-tool-systemhealth', // Enterprise only
        'openc3-enterprise-tool-base', // Enterprise only
        'openc3-tool-base',
      ],
    }
  },
  computed: {
    shownPlugins() {
      return Object.entries(this.plugins)
        .filter(([pluginName, plugin]) => {
          const pluginNameFirst = pluginName.split('__')[0]
          const pluginNameSplit = pluginNameFirst.split('-').slice(0, -1)
          const pluginNameShort = pluginNameSplit.join('-')
          return (
            !this.defaultPlugins.includes(pluginNameShort) ||
            this.showDefaultTools
          )
        })
        .map(([pluginName, plugin]) => {
          const storePlugin = this.pluginStoreApi.getBySha(plugin.gem_sha)
          return {
            ...storePlugin,
            ...plugin,
          }
        })
    },
  },
  watch: {
    // watcher to reset the file input when the dialog is closed
    showPluginDialog: function (newValue, oldValue) {
      if (newValue === false) {
        this.file = null
        this.$refs.fileInput.value = null
      }
    },
  },
  mounted() {
    this.update()
    this.updateProcesses()

    // Handle going "back" from the plugin store
    // (idk why v-bottom-sheet's close-on-back prop isn't working)
    const that = this
    window.onpopstate = function () {
      if (that.showPluginStore) {
        that.showPluginStore = false
        history.go(1)
      }
    }
  },
  methods: {
    showDetails: function (plugin) {
      this.detailPlugin = plugin
      this.showPluginDetails = true
    },
    pluginTargets: function (plugin) {
      let result = []
      for (const target in this.targets) {
        if (this.targets[target]['plugin'] === plugin) {
          result.push(this.targets[target])
        }
      }
      return result
    },
    isModified: function (plugin) {
      return Object.entries(this.targets).some(([targetName, target]) => {
        return target['plugin'] === plugin &&
        target['modified'] === true
      })
    },
    showOutput: function (process) {
      this.processOutput = process.output
      this.showProcessOutput = true
    },
    update: function () {
      Api.get('/openc3-api/plugins/all').then((response) => {
        this.plugins = response.data

        // TODO: delete me
        const demoKey = Object.keys(this.plugins).find(k => k.includes('demo'))
        this.plugins[demoKey].gem_sha = 'demosha256'
      })
      Api.get('/openc3-api/targets_modified').then((response) => {
        this.targets = response.data
      })
    },
    updateProcesses: function () {
      Api.get('openc3-api/process_status/plugin_?substr=true').then(
        (response) => {
          this.processes = response.data
          if (Object.keys(this.processes).length > 0) {
            setTimeout(() => {
              this.updateProcesses()
              this.update()
            }, 5000)
          }
        },
      )
    },
    formatDate(nanoSecs) {
      return format(
        toDate(parseInt(nanoSecs) / 1000000),
        'yyyy-MM-dd HH:mm:ss.SSS',
      )
    },
    upload: function (existing = null) {
      const method = existing ? 'put' : 'post'
      const path = existing
        ? `/openc3-api/plugins/${existing}`
        : '/openc3-api/plugins'
      const formData = new FormData()
      formData.append('plugin', this.file, this.file.name)
      let self = this
      const promise = Api[method](path, {
        data: formData,
        headers: { 'Content-Type': 'multipart/form-data' },
        onUploadProgress: function (progressEvent) {
          let percentCompleted = Math.round(
            (progressEvent.loaded * 100) / progressEvent.total,
          )
          self.progress = percentCompleted
        },
      })
      promise
        .then((response) => {
          this.progress = 100
          this.alert = 'Uploaded file'
          this.alertType = 'success'
          this.showAlert = true
          setTimeout(() => {
            this.showAlert = false
          }, 5000)
          this.update()
          let existingPluginTxt = null
          if (response.data.existing_plugin_txt_lines !== undefined) {
            existingPluginTxt =
              response.data.existing_plugin_txt_lines.join('\n')
          }
          let pluginTxt = response.data.plugin_txt_lines.join('\n')
          this.pluginName = response.data.name
          this.variables = response.data.variables
          this.pluginTxt = pluginTxt
          this.existingPluginTxt = existingPluginTxt
          this.showPluginDialog = true
          this.file = undefined
        })
        .catch((error) => {
          this.currentPlugin = null
          this.file = undefined
        })
    },
    pluginCallback: function (pluginHash) {
      this.showPluginDialog = false
      if (this.currentPlugin !== null) {
        pluginHash['name'] = this.currentPlugin
      }
      this.pluginHashTmp = pluginHash
      if (this.isModified(this.currentPlugin)) {
        this.pluginDelete = false
        this.showModifiedPluginDialog = true
      } else {
        this.pluginInstall()
      }
    },
    modifiedSubmit: async function (deleteModified) {
      if (deleteModified === true) {
        for (let target of this.pluginTargets(this.currentPlugin)) {
          if (target.modified == true) {
            await Api.post(`/openc3-api/targets/${target.name}/delete_modified`)
          }
        }
      }
      if (this.pluginDelete) {
        this.deletePlugin(this.currentPlugin)
      } else {
        this.pluginInstall()
      }
    },
    pluginInstall: function () {
      Api.post(`/openc3-api/plugins/install/${this.pluginName}`, {
        data: {
          plugin_hash: JSON.stringify(this.pluginHashTmp),
        },
      }).then((response) => {
        this.alert = `Started installing plugin ${this.pluginName} ...`
        this.alertType = 'success'
        this.showAlert = true
        this.currentPlugin = null
        this.file = undefined
        this.variables = {}
        this.pluginTxt = ''
        this.existingPluginTxt = null
        setTimeout(() => {
          this.showAlert = false
          this.updateProcesses()
        }, 5000)
        this.update()
      })
    },
    installFromUrl: function (gemUrl) {
      // TODO
      this.showPluginStore = false
      // eslint-disable-next-line
      console.log(`Install ${gemUrl}`)
    },
    editPlugin: function (plugin) {
      Api.get(`/openc3-api/plugins/${plugin}`).then((response) => {
        let existingPluginTxt = null
        if (response.data.existing_plugin_txt_lines !== undefined) {
          existingPluginTxt = response.data.existing_plugin_txt_lines.join('\n')
        }
        this.pluginName = response.data.name
        this.variables = response.data.variables
        this.pluginTxt = response.data.plugin_txt_lines.join('\n')
        this.existingPluginTxt = existingPluginTxt
        this.showPluginDialog = true
      })
    },
    deletePrompt: function (plugin) {
      this.$dialog
        .confirm(`Are you sure you want to remove: ${plugin}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          if (this.isModified(plugin)) {
            this.currentPlugin = plugin
            this.pluginDelete = true
            this.showModifiedPluginDialog = true
          } else {
            this.deletePlugin(plugin)
          }
        })
    },
    deletePlugin: function (plugin) {
      this.alert = `Removing plugin ${plugin} ...`
      this.alertType = 'success'
      this.showAlert = true
      Api.delete(`/openc3-api/plugins/${plugin}`).then((response) => {
        setTimeout(() => {
          this.showAlert = false
          this.updateProcesses()
        }, 5000)
      })
      this.update()
    },
    upgradePlugin(plugin) {
      this.file = null
      this.currentPlugin = plugin
      this.progress = 0
      this.$refs.fileInput.click()
    },
    selectFile() {
      this.file = null
      this.currentPlugin = null
      this.progress = 0
      this.$refs.fileInput.click()
    },
    fileChange(event) {
      const files = event.target.files
      if (files.length > 0) {
        this.file = files[0]
        if (this.currentPlugin !== null) {
          if (
            this.file.name.split('.gem')[0] ==
            this.currentPlugin.split('.gem')[0]
          ) {
            this.$dialog
              .confirm(
                `The new gem ${this.file.name} appears to be identical to the existing ${this.currentPlugin}. Install?`,
                {
                  okText: 'Ok',
                  cancelText: 'Cancel',
                },
              )
              .then(() => {
                this.upload(this.currentPlugin)
              })
              .catch((error) => {
                // do nothing
              })
          } else {
            // Split up the gem name to determine if this is an upgrade
            // or mistakenly trying to install a different gem
            // Gems are named like openc3-cosmos-demo-5.3.2.gem or
            // openc3-cosmos-pw-test-1.0.0.20230213074527.gem
            // So split on - and match everything until the first .
            let parts = this.file.name.split('-')
            let i = parts.findIndex((x) => x.includes('.'))
            let newName = parts.slice(0, i).join('-')
            parts = this.currentPlugin.split('-')
            i = parts.findIndex((x) => x.includes('.'))
            let existingName = parts.slice(0, i).join('-')
            if (newName !== existingName) {
              this.$dialog
                .confirm(
                  `The new gem base name ${newName} doesn't match the existing ${existingName}. Install?`,
                  {
                    okText: 'Ok',
                    cancelText: 'Cancel',
                  },
                )
                .then(() => {
                  this.upload(this.currentPlugin)
                })
            } else {
              this.upload(this.currentPlugin)
            }
          }
        } else {
          this.upload()
        }
      } else {
        // Reset the input element
        this.$refs.fileInput.value = null
      }
    },
    openStore() {
      this.showPluginStore = true
    },
  },
}
</script>

<style scoped>
.crashed {
  color: red;
}
.list {
  background-color: var(--color-background-surface-default) !important;
  overflow-x: hidden;
}
.v-theme--cosmosDark.v-list div:nth-child(odd) .v-list-item {
  background-color: var(--color-background-base-selected) !important;
}
</style>
