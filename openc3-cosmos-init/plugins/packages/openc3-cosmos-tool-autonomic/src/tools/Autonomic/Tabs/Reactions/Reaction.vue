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
    <v-card>
      <v-card-title class="pb-0">
        <div class="mx-2">Reactions</div>
        <v-tooltip top>
          <template v-slot:activator="{ on, attrs }">
            <div v-on="on" v-bind="attrs">
              <v-btn
                icon
                data-test="new-reaction"
                @click="newReaction()"
                :disabled="triggerCount === 0"
              >
                <v-icon>mdi-database-plus</v-icon>
              </v-btn>
            </div>
          </template>
          <span> New Reaction </span>
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
              <v-btn icon data-test="reaction-download" @click="download">
                <v-icon> mdi-download </v-icon>
              </v-btn>
            </div>
          </template>
          <span> Download Reactions </span>
        </v-tooltip>
      </v-card-title>
      <v-card-text>
        <v-data-table
          :headers="headers"
          :items="reactions"
          :search="search"
          :custom-filter="filterTable"
          :items-per-page="10"
          :footer-props="{
            itemsPerPageOptions: [10, 20, 50, 100, 1000],
            showFirstLastPage: true,
          }"
          item-key="name"
          show-expand
          calculate-widths
          multi-sort
          sort-by="name"
          data-test="reactions-table"
          class="table"
        >
          <template v-slot:item.updated_at="{ item }">
            {{ formatDate(item.updated_at) }}
          </template>
          <template v-slot:item.state="{ item }">
            <v-icon>
              {{ item.snoozed_until ? 'mdi-bell-sleep' : 'mdi-bell' }}
            </v-icon>
          </template>
          <template v-slot:item.active="{ item }">
            <div v-if="item.active">
              <v-tooltip top>
                <template v-slot:activator="{ on, attrs }">
                  <div v-on="on" v-bind="attrs">
                    <v-btn
                      icon
                      data-test="reaction-deactivate-icon"
                      @click="deactivateHandler(item)"
                    >
                      <v-icon>mdi-power-plug</v-icon>
                    </v-btn>
                  </div>
                </template>
                <span> Deactivate </span>
              </v-tooltip>
            </div>
            <div v-else>
              <v-tooltip top>
                <template v-slot:activator="{ on, attrs }">
                  <div v-on="on" v-bind="attrs">
                    <v-btn
                      icon
                      data-test="reaction-activate-icon"
                      @click="activateHandler(item)"
                    >
                      <v-icon>mdi-power-plug-off</v-icon>
                    </v-btn>
                  </div>
                </template>
                <span> Activate </span>
              </v-tooltip>
            </div>
          </template>
          <template v-slot:item.snooze_until="{ item }">
            {{ snoozeUntil(item) }}
          </template>
          <template v-slot:item.triggers="{ item }">
            {{ displayTriggers(item) }}
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
          <template v-slot:expanded-item="{ headers, item }">
            <td class="pa-3" :colspan="headers.length">
              <v-tooltip bottom>
                <template v-slot:activator="{ on, attrs }">
                  <span v-on="on" v-bind="attrs" class="mr-2">
                    <v-btn
                      icon
                      data-test="execute-actions"
                      @click="executeActions(item)"
                    >
                      <v-icon>mdi-play</v-icon>
                    </v-btn>
                  </span>
                </template>
                <span> Execute All Actions </span>
              </v-tooltip>
              <span><b>Actions:&nbsp;</b>{{ displayActions(item) }}</span>
            </td>
          </template>
        </v-data-table>
      </v-card-text>
    </v-card>
    <create-dialog
      v-if="showNewReactionDialog"
      v-model="showNewReactionDialog"
      :reaction="currentReaction"
      :triggers="triggers"
    />
  </div>
</template>

<script>
import { toDate, format } from 'date-fns'
import Api from '@openc3/tool-common/src/services/api'
import Cable from '@openc3/tool-common/src/services/cable.js'
import CreateDialog from '@/tools/Autonomic/Tabs/Reactions/CreateDialog'

export default {
  components: {
    CreateDialog,
  },
  data() {
    return {
      triggers: {},
      reactions: [],
      cable: new Cable(),
      subscription: null,
      currentReaction: null,
      showNewReactionDialog: false,
      search: '',
      headers: [
        { text: 'Actions', value: 'data-table-expand' },
        { text: 'Updated At', value: 'updated_at', filterable: false },
        { text: 'Name', value: 'name' },
        { text: 'State', value: 'state', filterable: false },
        { text: 'Enable / Disable', value: 'active', filterable: false },
        { text: 'Snooze', value: 'snooze', filterable: false },
        { text: 'Snooze Until', value: 'snooze_until', filterable: false },
        { text: 'Triggers', value: 'triggers' },
        { text: 'Level', value: 'triggerLevel' },
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
    this.getTriggers()
    this.getReactions()
  },
  destroyed: function () {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    this.cable.disconnect()
  },
  computed: {
    eventReactionHandlerFunctions: function () {
      return {
        run: this.noop,
        deployed: this.noop,
        executed: this.noop,
        created: this.createdReactionFromEvent,
        updated: this.updatedReactionFromEvent,
        deleted: this.deletedReactionFromEvent,
        activated: this.updatedReactionFromEvent,
        deactivated: this.updatedReactionFromEvent,
        snoozed: this.updatedReactionFromEvent,
        awakened: this.updatedReactionFromEvent,
      }
    },
    triggerCount: function () {
      let count = 0
      for (let trigger in this.triggers) {
        count += this.triggers[trigger].length
      }
      return count
    },
  },
  methods: {
    filterTable(_, search, item) {
      return (
        item != null &&
        search != null &&
        // We match on name and triggers
        (item.name.includes(search) ||
          item.triggers.some((trigger) => trigger.name.includes(search)))
      )
    },
    formatDate(nanoSecs) {
      return format(
        toDate(parseInt(nanoSecs) / 1_000_000),
        'yyyy-MM-dd HH:mm:ss.SSS'
      )
    },
    snoozeUntil: function (reaction) {
      if (!reaction.snoozed_until) {
        return ''
      }
      return this.formatDate(reaction.snoozed_until * 1_000_000_000)
    },
    displayTriggers(reaction) {
      let list = reaction.triggers
        .map((trigger) => `${trigger.group}: ${trigger.name}`)
        .join(', ')
      return list
    },
    displayActions(reaction) {
      return reaction.actions
        .map((action) => `${action.type}: ${action.value}`)
        .join(', ')
    },
    getTriggers: function () {
      Api.get('/openc3-api/autonomic/group').then((response) => {
        response.data.forEach((group) => {
          const groupName = group.name
          Api.get(`/openc3-api/autonomic/${groupName}/trigger`).then(
            (response) => {
              this.triggers = {
                ...this.triggers,
                [groupName]: response.data,
              }
            }
          )
        })
      })
    },
    getReactions: function () {
      Api.get(`/openc3-api/autonomic/reaction`).then((response) => {
        this.reactions = response.data
      })
    },
    newReaction: function () {
      this.currentReaction = null
      this.showNewReactionDialog = true
    },
    download: function () {
      const output = JSON.stringify(this.reactions, null, 2)
      const blob = new Blob([output], {
        type: 'application/json',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute(
        'download',
        format(Date.now(), 'yyyy_MM_dd_HH_mm_ss') + '_autonomic_reactions.json'
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
        switch (event.type) {
          case 'reaction':
            this.eventReactionHandlerFunctions[event.kind](
              JSON.parse(event.data)
            )
            break
        }
      })
    },
    noop: function (event) {
      // Do nothing
    },
    createdReactionFromEvent: function (event) {
      this.reactions.push(event)
    },
    updatedReactionFromEvent: function (event) {
      const reactionIndex = this.reactions.findIndex(
        (reaction) => reaction.name === event.name
      )
      if (reactionIndex >= 0) {
        this.reactions[reactionIndex] = event
      }
      this.reactions = [...this.reactions]
    },
    deletedReactionFromEvent: function (event) {
      const reactionIndex = this.reactions.findIndex(
        (reaction) => reaction.name === event.name
      )
      this.reactions.splice(reactionIndex, reactionIndex >= 0 ? 1 : 0)
    },
    executeActions: function (reaction) {
      Api.post(
        `/openc3-api/autonomic/reaction/${reaction.name}/execute`,
        {}
      ).then((response) => {
        this.$notify.normal({
          title: 'Executed Actions',
          body: `reaction: ${reaction.name} has manually executed its actions.`,
        })
      })
    },
    activateHandler: function (reaction) {
      Api.post(
        `/openc3-api/autonomic/reaction/${reaction.name}/activate`,
        {}
      ).then((response) => {
        this.$notify.normal({
          title: 'Activated Reaction',
          body: `reaction: ${reaction.name} has been activated.`,
        })
      })
    },
    deactivateHandler: function (reaction) {
      Api.post(
        `/openc3-api/autonomic/reaction/${reaction.name}/deactivate`,
        {}
      ).then((response) => {
        this.$notify.normal({
          title: 'Deactivated Reaction',
          body: `reaction: ${reaction.name} has been deactivated.`,
        })
      })
    },
    editHandler: function (reaction) {
      this.currentReaction = reaction
      this.showNewReactionDialog = true
    },
    deleteHandler: function (reaction) {
      this.$dialog
        .confirm(`Are you sure you want to delete reaction ${reaction.name}?`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          return Api.delete(`/openc3-api/autonomic/reaction/${reaction.name}`)
        })
        .then((response) => {
          this.$notify.normal({
            title: 'Reaction Deleted',
            body: `Reaction: ${reaction.name} has been deleted.`,
          })
        })
        .catch((error) => {
          // true is returned when you simply click cancel
          if (error !== true) {
            // eslint-disable-next-line
            console.log(error)
            this.$notify.serious({
              title: 'Delete Reaction Failed!',
              body: `Failed to delete reaction ${reaction.name}. Error: ${error}`,
            })
          }
        })
    },
  },
}
</script>
<style scoped>
.expanded-row {
  padding: 5px !important;
  display: flex;
}
</style>
