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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-list class="list" data-test="interfaceList">
      <div v-for="openc3_interface in interfaces" :key="openc3_interface">
        <v-list-item>
          <v-list-item-title>{{ openc3_interface }}</v-list-item-title>

          <template #append>
            <v-tooltip location="top">
              <template #activator="{ props }">
                <v-icon v-bind="props" @click="showInterface(openc3_interface)">
                  mdi-eye
                </v-icon>
              </template>
              <span>Show Interface Details</span>
            </v-tooltip>
          </template>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <output-dialog
      v-if="showDialog"
      v-model="showDialog"
      :content="jsonContent"
      type="Interface"
      :name="dialogTitle"
      @submit="dialogCallback"
    />
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import { OutputDialog } from '@/components'

export default {
  components: { OutputDialog },
  data() {
    return {
      interfaces: [],
      jsonContent: '',
      dialogTitle: '',
      showDialog: false,
    }
  },
  mounted() {
    this.update()
  },
  methods: {
    update() {
      Api.get('/openc3-api/interfaces').then((response) => {
        this.interfaces = response.data
      })
    },
    showInterface(name) {
      Api.get(`/openc3-api/interfaces/${name}`).then((response) => {
        this.jsonContent = JSON.stringify(response.data, null, '\t')
        this.dialogTitle = name
        this.showDialog = true
      })
    },
    dialogCallback(content) {
      this.showDialog = false
    },
  },
}
</script>

<style scoped>
.list {
  background-color: var(--color-background-surface-default) !important;
  overflow-x: hidden;
}
.v-theme--cosmosDark.v-list div:nth-child(odd) .v-list-item {
  background-color: var(--color-background-base-selected) !important;
}
</style>
