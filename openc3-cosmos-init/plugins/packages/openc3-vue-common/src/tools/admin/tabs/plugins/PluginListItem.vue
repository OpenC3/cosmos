<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <tr :class="{ 'cursor-pointer': hasDetails }" data-test="plugin-list-item">
    <td>
      <v-img
        v-if="imageContentsWithMimeType"
        :src="imageContentsWithMimeType"
        max-height="56"
        min-width="56"
      />
    </td>
    <td>
      <div class="text-h6" @click="openDetails" v-text="displayTitle" />
      <div class="text-subtitle-2 v-list-item-subtitle pl-0">
        <!-- subtitle -->
        <template v-if="isModified"> * </template>
        {{ name }}
      </div>
      <div v-if="targets?.length">
        <!-- sub-subtitle -->
        <span v-for="(target, index) in targets" :key="index" class="mr-2">
          <a
            v-if="target.modified"
            style="cursor: pointer"
            @click.prevent="downloadTarget(target.name)"
            v-text="target.name"
          />
          <span v-else v-text="target.name" />
        </span>
      </div>
    </td>

    <td>
      <v-menu>
        <template #activator="{ props }">
          <v-icon
            v-bind="props"
            icon="mdi-dots-horizontal"
            data-test="plugin-actions"
          />
        </template>
        <v-list>
          <v-list-item
            title="Download"
            prepend-icon="mdi-download"
            data-test="download-plugin"
            @click="downloadPlugin"
          />
          <v-list-item
            title="Edit Details"
            prepend-icon="mdi-pencil"
            data-test="edit-plugin"
            @click="edit"
          />
          <v-list-item
            title="Upgrade"
            prepend-icon="mdi-update"
            data-test="upgrade-plugin"
            @click="upgrade"
          />
          <v-list-item
            v-if="scriptVersionsEnabled"
            title="Export History"
            prepend-icon="mdi-export"
            :disabled="exporting || importing"
            data-test="export-plugin-history"
            @click="exportHistory"
          />
          <v-list-item
            v-if="scriptVersionsEnabled"
            title="Import History"
            prepend-icon="mdi-import"
            :disabled="exporting || importing"
            data-test="import-plugin-history"
            @click="pickImportFile"
          />
          <v-list-item
            :title="`View Microservices (${microserviceCount})`"
            prepend-icon="mdi-tab"
            data-test="view-microservices"
            @click="viewMicroservices"
          />
          <v-list-item
            v-if="needsUvMigration"
            title="Migrate to UV"
            prepend-icon="mdi-swap-horizontal"
            data-test="migrate-to-uv"
            @click="migrateToUv"
          />
          <v-list-item
            title="Delete"
            prepend-icon="mdi-delete"
            data-test="delete-plugin"
            @click="deletePrompt"
          />
        </v-list>
      </v-menu>
    </td>
  </tr>
  <plugin-details-dialog
    v-if="showCard"
    v-model="showCard"
    v-bind="plugin"
    @trigger-uninstall="deletePrompt"
  />
  <input
    v-if="scriptVersionsEnabled"
    ref="importFileInput"
    type="file"
    accept=".bundle,application/octet-stream"
    style="display: none"
    :data-test="`import-plugin-history-file-${name}`"
    @change="onImportFileSelected"
  />
</template>

<script>
import { Api } from '@openc3/js-common/services'
import { PluginDetailsDialog, PluginProps } from '@/plugins/plugin-store'

export default {
  components: {
    PluginDetailsDialog,
  },
  mixins: [PluginProps],
  props: {
    targets: {
      type: Array,
      default: () => {
        return []
      },
    },
    isModified: Boolean,
    needsUvMigration: Boolean,
    microservices: {
      type: Object,
      default: () => ({}),
    },
    // Enterprise Version History backend availability (/openc3-api/info
    // script_versions). Gates the Export/Import History actions.
    scriptVersionsEnabled: Boolean,
  },
  emits: ['edit', 'delete', 'upgrade', 'migrate-to-uv'],
  data() {
    return {
      showCard: false,
      exporting: false,
      importing: false,
    }
  },
  computed: {
    // Version-stripped plugin base name (e.g. "openc3-cosmos-demo" from
    // "openc3-cosmos-demo-7.2.0.gem__0") — the per-plugin Version History repo
    // key the script-api routes expect. Matches PluginList.shownPlugins and
    // the server-side TargetModel.plugin_base_name.
    pluginBaseName: function () {
      return this.name.split('__')[0].split('-').slice(0, -1).join('-')
    },
    displayTitle: function () {
      if (this.title) {
        return this.title
      }
      return this.name
        .replace(/^openc3-cosmos-/, '')
        .replace(/-?\d+\.\d+\.\d+(?:\.pre\.beta\d+\.\d+)?\.gem(?:__\d+)?$/, '') // '-6.6.1.pre.beta0.20250801182255.gem__20250801182444' or '6.6.1.gem'
    },
    getMicroservicesForPlugin: function () {
      const names = []
      for (const [microserviceName, microservice] of Object.entries(
        this.microservices,
      )) {
        if (microservice.plugin === this.name) {
          names.push(microserviceName)
        }
      }
      return names
    },
    microserviceCount: function () {
      return this.getMicroservicesForPlugin.length
    },
  },
  methods: {
    openDetails: function () {
      if (this.hasDetails) {
        this.showCard = true
      }
    },
    downloadPlugin: function () {
      Api.post(`/openc3-api/packages/${this.name}/download`).then(
        (response) => {
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
        },
      )
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
    async exportHistory() {
      this.exporting = true
      try {
        const response = await Api.get(
          `/script-api/scripts/plugin/${this.pluginBaseName}/history-export`,
          {
            responseType: 'blob',
            headers: { Accept: 'application/octet-stream' },
          },
        )
        // Suggested filename comes from the server's Content-Disposition; pull
        // it back out so the download lands as `<scope>-<plugin>-history.bundle`
        // rather than the route segment.
        let suggested = `${this.pluginBaseName}-history.bundle`
        const cd = response.headers?.['content-disposition']
        if (cd) {
          const match = /filename="?([^";]+)"?/.exec(cd)
          if (match) suggested = match[1]
        }
        const url = URL.createObjectURL(response.data)
        const a = document.createElement('a')
        a.href = url
        a.download = suggested
        document.body.appendChild(a)
        a.click()
        a.remove()
        URL.revokeObjectURL(url)
        this.$notify.normal({
          title: 'History Exported',
          body: `Saved ${suggested}. Apply with: git clone ${suggested} local-repo`,
        })
      } catch ({ response }) {
        this.$notify.caution({
          title: 'Export Failed',
          body: response?.data?.message || response?.statusText || 'unknown',
        })
      } finally {
        this.exporting = false
      }
    },
    pickImportFile() {
      // Reset value so re-selecting the same file still fires @change.
      if (this.$refs.importFileInput) {
        this.$refs.importFileInput.value = ''
        this.$refs.importFileInput.click()
      }
    },
    async onImportFileSelected(event) {
      const file = event.target.files && event.target.files[0]
      if (!file) return
      this.importing = true
      try {
        const form = new FormData()
        form.append('bundle', file)
        const response = await Api.post(
          `/script-api/scripts/plugin/${this.pluginBaseName}/history-import`,
          {
            data: form,
            headers: { Accept: 'application/json' },
          },
        )
        const data = response.data || {}
        this.$notify.normal({
          title: data.reconciled
            ? 'History Imported (Reconciled)'
            : 'History Imported',
          body: data.message || 'Imported.',
        })
      } catch ({ response }) {
        this.$notify.caution({
          title: 'Import Failed',
          body: response?.data?.message || response?.statusText || 'unknown',
        })
      } finally {
        this.importing = false
      }
    },
    edit: function () {
      this.$emit('edit')
    },
    upgrade: function () {
      this.$emit('upgrade')
    },
    viewMicroservices: function () {
      const servicesParam = this.getMicroservicesForPlugin.join(',')
      this.$router.push({
        path: '/tools/admin/microservices',
        query: { services: servicesParam },
      })
    },
    migrateToUv: function () {
      this.$emit('migrate-to-uv')
    },
    deletePrompt: function () {
      this.showCard = false
      this.$emit('delete')
    },
  },
}
</script>
