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
# All changes Copyright 2023, OpenC3, Inc.
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

          <template v-slot:append>
            <v-tooltip location="bottom">
              <template v-slot:activator="{ props }">
                <v-icon @click="showRouter(router)" v-bind="props">
                  mdi-eye
                </v-icon>
              </template>
              <span>Show Router Details</span>
            </v-tooltip>
          </template>
        </v-list-item>
        <v-divider />
      </div>
    </v-list>
    <edit-dialog
      v-model="showDialog"
      v-if="showDialog"
      :content="jsonContent"
      type="Router"
      :name="dialogTitle"
      readonly
      @submit="dialogCallback"
    />
  </div>
</template>

<script>
import Api from '../../../services/api'
import EditDialog from '../EditDialog'
export default {
  components: { EditDialog },
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
}
.v-theme--cosmosDark.v-list div:nth-child(odd) .v-list-item {
  background-color: var(--color-background-base-selected) !important;
}
</style>
