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
  <v-card>
    <v-card-title class="d-flex align-center justify-content-space-between">
      {{ data.length }} Command Packets
      <v-spacer />
      <v-text-field
        v-model="search"
        label="Search"
        prepend-inner-icon="mdi-magnify"
        clearable
        variant="outlined"
        density="compact"
        single-line
        hide-details
        class="search"
      />
    </v-card-title>
    <v-data-table
      :headers="headers"
      :items="data"
      :search="search"
      :items-per-page="10"
      :items-per-page-options="[10, 20, 50, 100]"
      :sort-by="[
        {
          key: 'target_name',
        },
        {
          key: 'packet_name',
        },
      ]"
      data-test="cmd-packets-table"
      @update:current-items="currentItems"
    >
      <template #item.view_raw="{ item }">
        <v-btn
          block
          color="primary"
          :disabled="item.count < 1"
          @click="openViewRaw(item.target_name, item.packet_name)"
        >
          View Raw
        </v-btn>
      </template>
      <template #item.view_in_cmd_sender="{ item }">
        <span v-if="item.target_name === 'UNKNOWN'">N/A</span>
        <v-btn
          v-else
          block
          color="primary"
          @click="openCmdSender(item.target_name, item.packet_name)"
        >
          View In Command Sender
          <v-icon end> mdi-open-in-new </v-icon>
        </v-btn>
      </template>
    </v-data-table>
    <raw-dialog
      v-for="d in rawDialogs"
      :key="d.target_name + '_' + d.packet_name"
      type="Command"
      :target-name="d.target_name"
      :packet-name="d.packet_name"
      :visible="true"
      :z-index="d.zIndex"
      @close="closeRawDialog(d)"
      @focus="focus(d)"
    />
  </v-card>
</template>

<script>
import Updater from './Updater'
import RawDialog from './RawDialog'

export default {
  components: {
    RawDialog,
  },
  mixins: [Updater],
  props: {
    tabId: Number,
    curTab: Number,
  },
  data() {
    return {
      search: '',
      data: [],
      headers: [
        { title: 'Target Name', key: 'target_name' },
        { title: 'Packet Name', key: 'packet_name' },
        { title: 'Packet Count', key: 'count' },
        { title: 'View Raw', key: 'view_raw' },
        { title: 'View In Command Sender', key: 'view_in_cmd_sender' },
      ],
      rawDialogs: [],
      visible: null,
    }
  },
  created() {
    this.api.get_target_names().then((targets) => {
      targets.map((target) => {
        this.api.get_all_cmd_names(target).then((names) => {
          this.data = this.data.concat(
            names.map((packet) => {
              return { target_name: target, packet_name: packet, count: 0 }
            }),
          )
        })
      })
    })
  },
  methods: {
    focus(dialog) {
      this.rawDialogs.map((dialog) => {
        dialog.zIndex = 1
      })
      let i = this.rawDialogs.indexOf(dialog)
      this.rawDialogs[i].zIndex = 2
    },
    openViewRaw(target_name, packet_name) {
      this.rawDialogs.map((dialog) => {
        dialog.zIndex = 1
      })
      this.rawDialogs = this.rawDialogs.concat({
        target_name: target_name,
        packet_name: packet_name,
        zIndex: 2,
      })
    },
    closeRawDialog(dialog) {
      let i = this.rawDialogs.indexOf(dialog)
      this.rawDialogs.splice(i, 1)
    },
    openCmdSender(target_name, packet_name) {
      window.open(
        `/tools/cmdsender/${encodeURIComponent(target_name)}/${encodeURIComponent(packet_name)}`,
        '_blank',
      )
    },
    currentItems(event) {
      this.visible = event.map((i) => {
        return [i.columns.target_name, i.columns.packet_name]
      })
    },
    update() {
      if (this.tabId != this.curTab) return
      if (this.visible === null) return
      this.api.get_cmd_cnts(this.visible).then((counts) => {
        for (let i = 0; i < counts.length; i++) {
          let index = this.data.findIndex(
            (item) =>
              item.target_name === this.visible[i][0] &&
              item.packet_name === this.visible[i][1],
          )
          this.data[index].count = counts[i]
        }
      })
    },
  },
}
</script>
