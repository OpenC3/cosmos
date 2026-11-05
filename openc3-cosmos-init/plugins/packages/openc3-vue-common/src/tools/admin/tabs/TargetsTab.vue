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
    <v-list class="list" data-test="targetList">
      <div v-for="target in targets" :key="target">
        <v-list-item>
          <v-list-item-title>{{ target.name }}</v-list-item-title>
          <v-list-item-subtitle>
            Plugin: {{ target.plugin }}
          </v-list-item-subtitle>

          <template #append>
            <v-tooltip v-if="target.modified" :open-delay="600" location="top">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  class="mx-3"
                  icon="mdi-folder-download"
                  variant="text"
                  aria-label="Download Modified Files"
                  @click="downloadTarget(target.name)"
                />
              </template>
              <span>Download Modified Files</span>
            </v-tooltip>
            <v-btn
              icon="mdi-eye"
              variant="text"
              aria-label="View Target"
              @click="showTarget(target.name)"
            />
          </template>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <output-dialog
      v-if="showDialog"
      v-model="showDialog"
      :content="jsonContent"
      type="Target"
      :name="dialogTitle"
      @submit="dialogCallback"
    />
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import { OutputDialog } from '@/components'
import { useDownloadZip } from '@/composables'

export default {
  components: { OutputDialog },
  setup() {
    const downloadZip = useDownloadZip()

    return { downloadZip }
  },
  data() {
    return {
      targets: [],
      jsonContent: '',
      dialogTitle: '',
      showDialog: false,
    }
  },
  async mounted() {
    await this.update()
  },
  methods: {
    async update() {
      const response = await Api.get('/openc3-api/targets_modified')
      this.targets = response.data
    },
    async showTarget(name) {
      const response = await Api.get(`/openc3-api/targets/${name}`)
      this.jsonContent = JSON.stringify(response.data, null, '\t')
      this.dialogTitle = name
      this.showDialog = true
    },
    dialogCallback(content) {
      this.showDialog = false
    },
    downloadTarget: async function (name) {
      await this.downloadZip(`/openc3-api/targets/${name}/download`)
    },
  },
}
</script>

<style scoped>
.list {
  background-color: var(--color-background-surface-default) !important;
  overflow-x: hidden;
}
</style>
