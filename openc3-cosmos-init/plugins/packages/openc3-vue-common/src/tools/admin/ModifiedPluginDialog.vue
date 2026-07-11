<!--
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
-->

<template>
  <v-dialog v-model="show" persistent width="700" @keydown.esc="cancel">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span> Modified Plugin </span>
        <v-spacer />
      </v-toolbar>
      <v-card-text class="pa-3 card-container">
        <!-- Deleting the plugin: offer to delete the orphaned modified files
             (unchanged, destructive behavior). -->
        <template v-if="pluginDelete">
          <div>
            Plugin {{ plugin }} has modified files. Would you like to delete the
            existing modified files?
          </div>
          <v-list-item
            v-for="(target, index) in modifiedTargets"
            :key="index"
            lines="two"
          >
            <v-list-item-title>{{ target.name }}</v-list-item-title>
            <div class="file-list-container">
              <v-list-item-subtitle
                v-for="file in target.files"
                :key="file.fullName"
                >{{ file.file }}</v-list-item-subtitle
              >
            </div>
          </v-list-item>
          <v-checkbox
            v-model="deleteModified"
            label="DELETE MODIFIED! THIS CAN NOT BE UNDONE!!!"
            color="error"
            data-test="modified-plugin-delete-checkbox"
          />
        </template>

        <!-- Upgrading: warn (no options) about modified files that actually
             differ from the new plugin. The plugin's version is taken and the
             prior content saved to Version History. -->
        <template v-else>
          <div v-if="loading" class="d-flex align-center py-2">
            <v-progress-circular indeterminate size="20" class="mr-3" />
            Checking which modified files differ from the new plugin...
          </div>
          <div v-else-if="diffFiles.length === 0">
            None of {{ plugin }}'s modified files conflict with the new plugin.
            Installing will proceed normally.
          </div>
          <template v-else>
            <div class="mb-3">
              Installing {{ plugin }} will replace the following modified files
              with the plugin's versions. A new entry is added to Version
              History for each, so the current content stays recoverable. You
              may want to incorporate these modifications into the plugin.
            </div>
            <v-list density="compact" data-test="modified-plugin-diff-list">
              <v-list-item
                v-for="file in diffFiles"
                :key="file"
                :title="file"
                prepend-icon="mdi-file-alert-outline"
              />
            </v-list>
          </template>
        </template>
      </v-card-text>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn
          variant="outlined"
          data-test="modified-plugin-cancel"
          @click="cancel"
        >
          Cancel
        </v-btn>
        <v-btn
          variant="flat"
          :disabled="loading"
          data-test="modified-plugin-submit"
          @click="submit"
        >
          Confirm
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  props: {
    modelValue: Boolean,
    plugin: {
      type: String,
      default: null,
    },
    targets: {
      type: Array,
      default: null,
    },
    // Plugin instance hash (variables, name, plugin.txt). Required to dry-run
    // the upgrade diff; unused when deleting the plugin.
    pluginHash: {
      type: Object,
      default: null,
    },
    pluginDelete: Boolean,
  },
  emits: ['update:modelValue', 'submit', 'cancel'],
  data() {
    return {
      // Delete flow: modified files per target, for display + deletion.
      modifiedTargets: [],
      deleteModified: false,
      // Upgrade flow: "TARGET/path" names whose modified content differs from
      // the incoming plugin.
      loading: false,
      diffFiles: [],
    }
  },
  computed: {
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
  },
  created() {
    if (this.pluginDelete) {
      this.loadModifiedFiles()
    } else {
      this.loadDiff()
    }
  },
  methods: {
    loadModifiedFiles() {
      for (const target of this.targets) {
        Api.get(`/openc3-api/targets/${target.name}/modified_files`).then(
          (response) => {
            if (response.data.length !== 0) {
              this.modifiedTargets.push({
                name: target.name,
                files: response.data.map((file) => ({
                  file,
                  fullName: file.startsWith(`${target.name}/`)
                    ? file
                    : `${target.name}/${file}`,
                })),
              })
            }
          },
        )
      }
    },
    async loadDiff() {
      this.loading = true
      try {
        const response = await Api.post('/openc3-api/plugins/modified_diff', {
          data: { plugin_hash: JSON.stringify(this.pluginHash) },
        })
        this.diffFiles = response.data.files || []
      } catch {
        // If the dry run fails, fall back to letting the install proceed with
        // no version-history capture rather than blocking the upgrade.
        this.diffFiles = []
      } finally {
        this.loading = false
      }
    },
    cancel() {
      this.show = false
      this.$emit('cancel')
    },
    submit() {
      let installFromPlugin = []
      const deleteFiles = []
      if (this.pluginDelete) {
        if (this.deleteModified) {
          for (const target of this.modifiedTargets) {
            target.files.forEach((f) => deleteFiles.push(f.fullName))
          }
        }
      } else {
        installFromPlugin = this.diffFiles
      }
      this.show = false
      this.$emit('submit', { installFromPlugin, deleteFiles })
    },
  },
}
</script>

<style scoped>
.card-container {
  max-height: 80vh;
  overflow-y: auto;
}

.file-list-container {
  max-height: 50vh;
  overflow-y: auto;
}
</style>
