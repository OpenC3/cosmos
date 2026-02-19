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
    <v-list class="list" data-test="routerList">
      <div v-for="(router, index) in routers" :key="index">
        <v-list-item>
          <v-list-item-title>{{ router }}</v-list-item-title>

          <template #append>
            <v-btn
              aria-label="Show Router Details"
              icon="mdi-eye"
              variant="text"
              @click="showRouter(router)"
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
      type="Router"
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
      routers: [],
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
      Api.get('/openc3-api/routers').then((response) => {
        this.routers = response.data
      })
    },
    add() {},
    showRouter(name) {
      Api.get(`/openc3-api/routers/${name}`).then((response) => {
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
</style>
