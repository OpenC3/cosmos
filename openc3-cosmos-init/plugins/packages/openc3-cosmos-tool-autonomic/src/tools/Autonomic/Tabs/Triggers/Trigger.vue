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
    <v-card-title class="pb-0">
      <div class="mx-2">Triggers</div>
      <v-tooltip top>
        <template v-slot:activator="{ on, attrs }">
          <div v-on="on" v-bind="attrs">
            <v-btn
              icon
              data-test="new-trigger"
              @click="newTrigger()"
              :class="triggers.length === 0 ? 'new-juice' : ''"
            >
              <v-icon>mdi-database-plus</v-icon>
            </v-btn>
          </div>
        </template>
        <span> New Trigger </span>
      </v-tooltip>
      <v-spacer />
      <v-text-field
        v-model="search"
        label="Search"
        append-icon="mdi-magnify"
        dense
        single-line
        hide-details
        data-test="search"
      />
      <v-tooltip top>
        <template v-slot:activator="{ on, attrs }">
          <div v-on="on" v-bind="attrs">
            <v-btn icon data-test="trigger-download" @click="download">
              <v-icon> mdi-download </v-icon>
            </v-btn>
          </div>
        </template>
        <span> Download Triggers </span>
      </v-tooltip>
    </v-card-title>
    <v-card-text>
      <v-data-table
        :headers="headers"
        :items="triggers"
        :search="search"
        :custom-filter="filterTable"
        :item-class="rowBackground"
        :items-per-page="10"
        :footer-props="{
          itemsPerPageOptions: [10, 20, 50, 100, 1000],
          showFirstLastPage: true,
        }"
        calculate-widths
        multi-sort
        sort-by="updated_at"
        sort-desc
        data-test="triggers-table"
        class="table"
      >
        <template v-slot:item.updated_at="{ item }">
          {{ formatDate(item.updated_at) }}
        </template>
        <template v-slot:item.state="{ item }">
          <v-icon>
            {{ item.state ? 'mdi-bell-ring' : 'mdi-bell' }}
          </v-icon>
        </template>
        <template v-slot:item.enabled="{ item }">
          <div v-if="item.enabled">
            <v-tooltip top>
              <template v-slot:activator="{ on, attrs }">
                <div v-on="on" v-bind="attrs">
                  <v-btn
                    icon
                    data-test="trigger-disable"
                    @click="disableTrigger(item)"
                  >
                    <v-icon>mdi-power-plug</v-icon>
                  </v-btn>
                </div>
              </template>
              <span> Disable </span>
            </v-tooltip>
          </div>
          <div v-else>
            <v-tooltip top>
              <template v-slot:activator="{ on, attrs }">
                <div v-on="on" v-bind="attrs">
                  <v-btn
                    icon
                    data-test="trigger-enable"
                    @click="enableTrigger(item)"
                  >
                    <v-icon>mdi-power-plug-off</v-icon>
                  </v-btn>
                </div>
              </template>
              <span> Enable </span>
            </v-tooltip>
          </div>
        </template>
        <template v-slot:item.expression="{ item }">
          {{ expression(item) }}
        </template>
        <template v-slot:item.reactions="{ item }">
          {{ displayReactions(item) }}
        </template>
        <template v-slot:item.actions="{ item }">
          <!-- Force this column to have enough room for both buttons -->
          <div style="width: 110px">
            <v-btn icon data-test="item-edit" @click="editHandler(item)">
              <v-icon>mdi-pencil</v-icon>
            </v-btn>
            <v-btn icon data-test="item-delete" @click="deleteHandler(item)">
              <v-icon>mdi-delete</v-icon>
            </v-btn>
          </div>
        </template>
        <template v-slot:footer.prepend>
          <v-select
            v-model="group"
            :items="triggerGroupNames"
            label="Group"
            class="mx-2"
            style="max-width: 200px"
            dense
            hide-details
            data-test="trigger-group"
          />
          <v-tooltip bottom>
            <template v-slot:activator="{ on, attrs }">
              <v-btn
                icon
                small
                v-bind="attrs"
                v-on="on"
                @click="newGroupDialog = true"
                data-test="add-group"
              >
                <v-icon dark> mdi-database-plus </v-icon>
              </v-btn>
            </template>
            <span>New Group</span>
          </v-tooltip>
          <v-tooltip bottom>
            <template v-slot:activator="{ on, attrs }">
              <v-btn
                icon
                small
                v-bind="attrs"
                v-on="on"
                @click="deleteGroup"
                data-test="delete-group"
              >
                <v-icon dark> mdi-database-minus </v-icon>
              </v-btn>
            </template>
            <span>Delete Group</span>
          </v-tooltip>
        </template>
      </v-data-table>
    </v-card-text>
    <create-dialog
      v-if="showNewTriggerDialog"
      v-model="showNewTriggerDialog"
      :group="group"
      :trigger="currentTrigger"
      :triggers="triggers"
    />
    <new-group-dialog
      v-if="newGroupDialog"
      v-model="newGroupDialog"
      :groups="triggerGroupNames"
    />
    <delete-group-dialog
      v-if="deleteGroupDialog"
      v-model="deleteGroupDialog"
      :group="group"
    />
  </v-card>
</template>

<script>
import { toDate, format } from 'date-fns'
import Api from '@openc3/tool-common/src/services/api'
import Cable from '@openc3/tool-common/src/services/cable.js'
import CreateDialog from '@/tools/Autonomic/Tabs/Triggers/CreateDialog'
import NewGroupDialog from '@/tools/Autonomic/Tabs/Triggers/NewGroupDialog'
import DeleteGroupDialog from '@/tools/Autonomic/Tabs/Triggers/DeleteGroupDialog'

export default {
  components: {
    CreateDialog,
    NewGroupDialog,
    DeleteGroupDialog,
  },
  data() {
    return {
      group: null,
      triggerGroups: [],
      triggers: [],
      reactions: [],
      newGroupDialog: false,
      deleteGroupDialog: false,
      showNewTriggerDialog: false,
      currentTrigger: null,
      cable: new Cable(),
      subscription: null,
      search: '',
      headers: [
        { text: 'Updated At', value: 'updated_at', filterable: false },
        { text: 'Name', value: 'name' },
        { text: 'State', value: 'state', filterable: false },
        { text: 'Enable/Disable', value: 'enabled', filterable: false },
        { text: 'Expression', value: 'expression' },
        { text: 'Reactions', value: 'reactions' },
        {
          text: 'Actions',
          value: 'actions',
          align: 'end',
          sortable: false,
          filterable: false,
        },
      ],
    }
  },
  created: function () {
    this.subscribe()
  },
  mounted: function () {
    this.getGroups()
  },
  destroyed: function () {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    this.cable.disconnect()
  },
  computed: {
    triggerGroupNames: function () {
      return this.triggerGroups.map((group) => {
        return group.name
      })
    },
    eventGroupHandlerFunctions: function () {
      return {
        deployed: this.noop,
        created: this.createdGroupFromEvent,
        updated: this.updatedGroupFromEvent,
        deleted: this.deletedGroupFromEvent,
      }
    },
    eventTriggerHandlerFunctions: function () {
      return {
        error: this.noop,
        created: this.createdTriggerFromEvent,
        updated: this.updatedTriggerFromEvent,
        deleted: this.deletedTriggerFromEvent,
        enabled: this.updatedTriggerFromEvent,
        disabled: this.updatedTriggerFromEvent,
        true: this.updatedTriggerFromEvent,
        false: this.updatedTriggerFromEvent,
      }
    },
  },
  watch: {
    group: function () {
      this.getTriggers()
      localStorage['autonomic__trigger_group'] = this.group
    },
  },
  methods: {
    filterTable(_, search, item) {
      return (
        item != null &&
        search != null &&
        // We match on name, expression, and reactions (dependents)
        (item.name.includes(search) ||
          this.expression(item).includes(search) ||
          item.dependents.some((str) => str.includes(search)))
      )
    },
    rowBackground(trigger) {
      return trigger.state ? 'active-row' : ''
    },
    formatDate(nanoSecs) {
      return format(
        toDate(parseInt(nanoSecs) / 1_000_000),
        'yyyy-MM-dd HH:mm:ss.SSS'
      )
    },
    expression(trigger) {
      let left = trigger.left[trigger.left.type]
      // Format trigger dependencies like normal expressions
      if (trigger.left.type === 'trigger') {
        let found = this.triggers.find((t) => t.name === trigger.left.trigger)
        left = `(${this.expression(found)})`
      }
      let right = ''
      if (trigger.right) {
        right = trigger.right[trigger.right.type]
        if (trigger.right.type === 'trigger') {
          let found = this.triggers.find(
            (t) => t.name === trigger.right.trigger
          )
          right = `(${this.expression(found)})`
        }
      }
      return `${left} ${trigger.operator} ${right}`
    },
    displayReactions(trigger) {
      let list = trigger.dependents
        .filter((name) => name.startsWith('R'))
        .join(', ')
      return list
    },
    enableTrigger: function (trigger) {
      Api.post(
        `/openc3-api/autonomic/${trigger.group}/trigger/${trigger.name}/enable`,
        {}
      ).then(() => {
        this.$notify.normal({
          title: 'Enabled Trigger',
          body: `Trigger: ${this.expression(trigger)} has been enabled.`,
        })
      })
    },
    disableTrigger: function (trigger) {
      Api.post(
        `/openc3-api/autonomic/${trigger.group}/trigger/${trigger.name}/disable`,
        {}
      ).then(() => {
        this.$notify.normal({
          title: 'Disabled Trigger',
          body: `Trigger: ${this.expression(trigger)} has been disabled.`,
        })
      })
    },
    editHandler: function (trigger) {
      this.currentTrigger = trigger
      this.showNewTriggerDialog = true
    },
    deleteHandler: function (trigger) {
      this.$dialog
        .confirm(
          `Are you sure you want to delete trigger ${trigger.name} from group ${trigger.group}?`,
          {
            okText: 'Delete',
            cancelText: 'Cancel',
          }
        )
        .then((dialog) => {
          return Api.delete(
            `/openc3-api/autonomic/${trigger.group}/trigger/${trigger.name}`
          )
        })
        .then((response) => {
          this.$notify.normal({
            title: 'Trigger Deleted',
            body: `Trigger: ${this.expression(trigger)} has been deleted.`,
          })
        })
        .catch((error) => {
          // true is returned when you simply click cancel
          if (error !== true) {
            // eslint-disable-next-line
            console.log(error)
            let message = error?.response?.data?.message
            if (!message) {
              message = error.message
            }
            this.$notify.serious({
              title: 'Delete Trigger Failed!',
              body: `Failed to delete trigger ${trigger.name} from group ${trigger.group}. Error: ${message}`,
            })
          }
        })
    },
    getGroups: function () {
      Api.get('/openc3-api/autonomic/group').then((response) => {
        this.triggerGroups = response.data.sort((a, b) =>
          a.name > b.name ? 1 : -1
        )
        const previousGroup = localStorage['autonomic__trigger_group']
        if (previousGroup) {
          this.group = previousGroup
        } else {
          this.group = this.triggerGroupNames[0]
        }
      })
    },
    deleteGroup: function () {
      if (this.group === 'DEFAULT') {
        this.$notify.caution({
          title: 'DEFAULT group',
          body: `DEFAULT trigger group can not be deleted.`,
        })
      } else {
        this.deleteGroupDialog = true
      }
    },
    getTriggers: function () {
      if (!this.group) {
        return
      }
      Api.get(`/openc3-api/autonomic/${this.group}/trigger`).then(
        (response) => {
          this.triggers = response.data
        }
      )
    },
    newTrigger: function () {
      this.currentTrigger = null
      this.showNewTriggerDialog = true
    },
    download() {
      const output = JSON.stringify(this.triggers, null, 2)
      const blob = new Blob([output], {
        type: 'application/json',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute(
        'download',
        format(Date.now(), 'yyyy_MM_dd_HH_mm_ss') + '_autonomic_triggers.json'
      )
      link.click()
    },
    subscribe: function () {
      this.cable
        .createSubscription('AutonomicEventsChannel', window.openc3Scope, {
          received: (data) => this.received(data),
        })
        .then((subscription) => {
          this.subscription = subscription
        })
    },
    received: function (parsed) {
      this.cable.recordPing()
      parsed.forEach((event) => {
        event.data = JSON.parse(event.data)
        switch (event.type) {
          case 'group':
            this.eventGroupHandlerFunctions[event.kind](event)
            break
          case 'trigger':
            this.eventTriggerHandlerFunctions[event.kind](event)
            break
        }
      })
    },
    noop: function (event) {
      // Do nothing
    },
    createdGroupFromEvent: function (event) {
      this.triggerGroups.push(event.data)
      this.group = event.data.name
    },
    updatedGroupFromEvent: function (event) {
      const groupIndex = this.triggerGroups.findIndex(
        (group) => group.name === event.data.name
      )
      if (groupIndex >= 0) {
        this.triggerGroups[groupIndex] = event.data
      }
    },
    deletedGroupFromEvent: function (event) {
      const groupIndex = this.triggerGroups.findIndex(
        (group) => group.name === event.data.name
      )
      this.triggerGroups.splice(groupIndex, groupIndex >= 0 ? 1 : 0)
      if (this.group === event.data.name) {
        this.group = this.groups ? this.groups[0] : null
      }
    },
    createdTriggerFromEvent: function (event) {
      if (event.data.group !== this.group) {
        return
      }
      this.triggers.push(event.data)
    },
    updatedTriggerFromEvent: function (event) {
      if (event.data.group !== this.group) {
        return
      }
      const triggerIndex = this.triggers.findIndex(
        (trigger) => trigger.name === event.data.name
      )
      if (triggerIndex >= 0) {
        this.triggers[triggerIndex] = event.data
      }
      this.triggers = [...this.triggers]
    },
    deletedTriggerFromEvent: function (event) {
      if (event.data.group !== this.group) {
        return
      }
      const triggerIndex = this.triggers.findIndex(
        (trigger) => trigger.name === event.data.name
      )
      this.triggers.splice(triggerIndex, triggerIndex >= 0 ? 1 : 0)
    },
  },
}
</script>

<style>
.active-row {
  background-color: var(--v-primary-base);
}
</style>
<style scoped>
/* Add some juice to indicate it needs to be pressed */
.new-juice {
  animation: pulse 2s infinite;
}
@keyframes pulse {
  0% {
    -webkit-box-shadow: 0 0 0 0 rgba(255, 255, 255, 0.4);
  }
  70% {
    -webkit-box-shadow: 0 0 0 10px rgba(255, 255, 255, 0);
  }
  100% {
    -webkit-box-shadow: 0 0 0 0 rgba(255, 255, 255, 0);
  }
}
</style>
