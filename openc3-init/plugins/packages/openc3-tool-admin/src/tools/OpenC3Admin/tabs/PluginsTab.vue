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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
-->

<template>
  <div>
    <v-row no-gutters align="center" class="px-2">
      <v-col>
        <v-file-input
          v-model="file"
          show-size
          accept=".gem"
          class="mx-2"
          label="Click to select plugin .gem file to install"
          ref="fileInput"
          @change="fileChange()"
          @mousedown="fileMousedown()"
        />
      </v-col>
      <v-col align="right">
        <v-btn
          @click="showDownloadDialog = true"
          class="mx-2"
          data-test="download-plugin"
          :disabled="file !== null"
        >
          <v-icon left>mdi-cloud-download</v-icon>
          <span> Download </span>
        </v-btn>
      </v-col>
    </v-row>
    <v-row no-gutters class="px-2 pb-2" style="margin-top: 10px">
      <v-col>
        <v-checkbox
          v-model="showDefaultTools"
          label="Show Default Tools"
          class="mt-0"
          data-test="show-default-tools"
        />
      </v-col>
      <v-col align="right">
        <div>* indicates a modified plugin</div>
        <div>Click target link to download modifications</div>
      </v-col>
    </v-row>
    <!-- TODO This alert shows both success and failure. Make consistent with rest of OpenC3. -->
    <v-alert
      dismissible
      transition="scale-transition"
      :type="alertType"
      v-model="showAlert"
      data-test="plugin-alert"
      >{{ alert }}</v-alert
    >
    <v-list v-if="Object.keys(processes).length > 0" data-test="process-list">
      <div v-for="process in processes" :key="process.name">
        <v-list-item>
          <v-list-item-content>
            <v-list-item-title>
              <span
                v-text="
                  `Processing ${process.process_type}: ${process.detail} - ${process.state}`
                "
              />
            </v-list-item-title>
            <v-list-item-subtitle>
              <span v-text="' Updated At: ' + formatDate(process.updated_at)"
            /></v-list-item-subtitle>
          </v-list-item-content>
          <v-list-item-icon>
            <div v-if="process.state === 'Running'">
              <v-progress-circular indeterminate color="primary" />
            </div>
            <v-tooltip v-else bottom>
              <template v-slot:activator="{ on, attrs }">
                <v-icon
                  @click="showOutput(process)"
                  v-bind="attrs"
                  v-on="on"
                  data-test="show-output"
                >
                  mdi-eye
                </v-icon>
              </template>
              <span>Show Output</span>
            </v-tooltip>
          </v-list-item-icon>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <v-list data-test="plugin-list">
      <div v-for="(plugin, index) in shownPlugins" :key="index">
        <v-list-item>
          <v-list-item-content>
            <v-list-item-title
              ><span v-if="isModified(plugin)">* </span
              >{{ plugin }}</v-list-item-title
            >
            <v-list-item-subtitle v-if="pluginTargets(plugin).length !== 0">
              <span
                v-for="(target, index) in pluginTargets(plugin)"
                :key="index"
              >
                <a
                  v-if="target.modified"
                  @click.prevent="downloadTarget(target.name)"
                  >{{ target.name }}
                </a>
                <span v-else>{{ target.name }} </span>
              </span>
            </v-list-item-subtitle>
          </v-list-item-content>
          <v-list-item-icon>
            <div class="mx-3">
              <v-tooltip bottom>
                <template v-slot:activator="{ on, attrs }">
                  <v-icon
                    @click="editPlugin(plugin)"
                    v-bind="attrs"
                    v-on="on"
                    data-test="edit-plugin"
                  >
                    mdi-pencil
                  </v-icon>
                </template>
                <span>Edit Plugin Details</span>
              </v-tooltip>
            </div>
            <div class="mx-3">
              <v-tooltip bottom>
                <template v-slot:activator="{ on, attrs }">
                  <v-icon
                    @click="upgradePlugin(plugin)"
                    v-bind="attrs"
                    v-on="on"
                    data-test="upgrade-plugin"
                  >
                    mdi-update
                  </v-icon>
                </template>
                <span>Upgrade Plugin</span>
              </v-tooltip>
            </div>
            <div class="mx-3">
              <v-tooltip bottom>
                <template v-slot:activator="{ on, attrs }">
                  <v-icon
                    @click="deletePrompt(plugin)"
                    v-bind="attrs"
                    v-on="on"
                    data-test="delete-plugin"
                  >
                    mdi-delete
                  </v-icon>
                </template>
                <span>Delete Plugin</span>
              </v-tooltip>
            </div>
          </v-list-item-icon>
        </v-list-item>
        <v-divider v-if="index < plugins.length - 1" :key="index" />
      </div>
    </v-list>
    <plugin-dialog
      v-model="showPluginDialog"
      :pluginName="pluginName"
      :variables="variables"
      :pluginTxt="pluginTxt"
      :existingPluginTxt="existingPluginTxt"
      @submit="pluginCallback"
    />
    <modified-plugin-dialog
      v-if="showModifiedPluginDialog"
      v-model="showModifiedPluginDialog"
      :pluginName="currentPlugin"
      :targets="pluginTargets(currentPlugin)"
      :pluginDelete="pluginDelete"
      @submit="modifiedSubmit"
    />
    <download-dialog v-model="showDownloadDialog" />
    <simple-text-dialog
      v-model="showProcessOutput"
      title="Process Output"
      :text="processOutput"
    />
  </div>
</template>

<script>
import { toDate, format } from 'date-fns'
import Api from '@openc3/tool-common/src/services/api'
import DownloadDialog from '@/tools/OpenC3Admin/DownloadDialog'
import PluginDialog from '@/tools/OpenC3Admin/PluginDialog'
import ModifiedPluginDialog from '@/tools/OpenC3Admin/ModifiedPluginDialog'
import SimpleTextDialog from '@openc3/tool-common/src/components/SimpleTextDialog'

export default {
  components: {
    DownloadDialog,
    PluginDialog,
    ModifiedPluginDialog,
    SimpleTextDialog,
  },
  data() {
    return {
      file: null,
      currentPlugin: null,
      plugins: [],
      targets: [],
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
      showPluginDialog: false,
      showModifiedPluginDialog: false,
      showDefaultTools: false,
      pluginDelete: false,
      defaultPlugins: [
        'openc3-tool-admin',
        'openc3-tool-autonomic',
        'openc3-tool-base',
        'openc3-tool-calendar',
        'openc3-tool-cmdsender',
        'openc3-tool-cmdtlmserver',
        'openc3-tool-dataextractor',
        'openc3-tool-dataviewer',
        'openc3-tool-handbooks',
        'openc3-tool-limitsmonitor',
        'openc3-tool-packetviewer',
        'openc3-tool-scriptrunner',
        'openc3-tool-tablemanager',
        'openc3-tool-tlmgrapher',
        'openc3-tool-tlmviewer',
      ],
    }
  },
  computed: {
    shownPlugins() {
      let result = []
      for (let plugin of this.plugins) {
        let pluginNameFirst = plugin.split('__')[0]
        let pluginNameSplit = pluginNameFirst.split('-')
        pluginNameSplit = pluginNameSplit.slice(0, -1)
        let pluginName = pluginNameSplit.join('-')
        if (
          !this.defaultPlugins.includes(pluginName) ||
          this.showDefaultTools
        ) {
          result.push(plugin)
        }
      }
      return result
    },
    pluginTargets() {
      return (plugin) => {
        let result = []
        for (const target in this.targets) {
          if (this.targets[target]['plugin'] === plugin) {
            result.push(this.targets[target])
          }
        }
        return result
      }
    },
    isModified() {
      return (plugin) => {
        let result = false
        for (const target in this.targets) {
          if (
            this.targets[target]['plugin'] === plugin &&
            this.targets[target]['modified'] === true
          ) {
            result = true
            break
          }
        }
        return result
      }
    },
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
    update: function () {
      Api.get('/openc3-api/plugins').then((response) => {
        this.plugins = response.data
      })
      Api.get('/openc3-api/targets_modified').then((response) => {
        this.targets = response.data
      })
    },
    updateProcesses: function () {
      Api.get('openc3-api/process_status/plugin_?use_regex=true').then(
        (response) => {
          this.processes = response.data
          if (Object.keys(this.processes).length > 0) {
            setTimeout(() => {
              this.updateProcesses()
              this.update()
            }, 10000)
          }
        }
      )
    },
    formatDate(nanoSecs) {
      return format(
        toDate(parseInt(nanoSecs) / 1_000_000),
        'yyyy-MM-dd HH:mm:ss.SSS'
      )
    },
    upload: function (existing = null) {
      const method = existing ? 'put' : 'post'
      const path = existing
        ? `/openc3-api/plugins/${existing}`
        : '/openc3-api/plugins'
      const formData = new FormData()
      formData.append('plugin', this.file, this.file.name)
      const promise = Api[method](path, { data: formData })
      promise
        .then((response) => {
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
          ;(this.pluginName = response.data.name),
            (this.variables = response.data.variables),
            (this.pluginTxt = pluginTxt),
            (this.existingPluginTxt = existingPluginTxt)
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
    downloadTarget: function (name) {
      Api.post(`/openc3-api/targets/${name}/download`).then((response) => {
        // Decode Base64 string
        const decodedData = window.atob(response.data.contents)
        // Create UNIT8ARRAY of size same as row data length
        const uInt8Array = new Uint8Array(decodedData.length)
        // Insert all character code into uInt8Array
        for (let i = 0; i < decodedData.length; ++i) {
          uInt8Array[i] = decodedData.charCodeAt(i)
        }
        const blob = new Blob([uInt8Array], { type: 'application/zip' })
        const link = document.createElement('a')
        link.href = URL.createObjectURL(blob)
        link.setAttribute('download', response.data.filename)
        link.click()
      })
    },
    editPlugin: function (plugin) {
      Api.get(`/openc3-api/plugins/${plugin}`).then((response) => {
        let existingPluginTxt = null
        if (response.data.existing_plugin_txt_lines !== undefined) {
          existingPluginTxt = response.data.existing_plugin_txt_lines.join('\n')
        }
        let pluginTxt = response.data.plugin_txt_lines.join('\n')
        ;(this.pluginName = response.data.name),
          (this.variables = response.data.variables),
          (this.pluginTxt = pluginTxt),
          (this.existingPluginTxt = existingPluginTxt)
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
      this.file = undefined
      this.currentPlugin = plugin
      this.$refs.fileInput.$refs.input.click()
    },
    fileMousedown() {
      this.currentPlugin = null
    },
    fileChange() {
      if (this.file !== undefined) {
        if (this.currentPlugin !== null) {
          this.upload(this.currentPlugin)
        } else {
          this.upload()
        }
      }
    },
  },
}
</script>
