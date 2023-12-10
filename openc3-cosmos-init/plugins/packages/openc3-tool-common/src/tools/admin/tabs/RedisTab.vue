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
      <v-card-title> Send Raw Redis Commands </v-card-title>
      <v-card-subtitle>
        THIS IS DANGEROUS. This allows you to interact directly with the
        underlying Redis database, making it easy to modify or delete data.
        <br /><br />
        Enter commands like you would at the Redis cli prompt:
        <code>ping</code> or
        <code>hget openc3__settings version</code>
      </v-card-subtitle>
      <v-card-text class="pb-0 ml-2">
        <v-text-field
          label="Redis command"
          class="monospace"
          v-model="redisCommandText"
          @keydown="commandKeydown"
        />
        <span v-if="redisResponse" class="monospace">
          Response: {{ redisResponse }}
        </span>
      </v-card-text>
      <v-card-actions>
        <v-btn
          :disabled="!redisCommandText.length"
          @click="executeRaw"
          color="success"
          text
          class="ml-2 mr-3"
        >
          Execute
        </v-btn>
        <v-radio-group v-model="redisEndpoint" row hide-details class="mt-0">
          <v-radio
            label="Persistent"
            value="/openc3-api/redis/exec"
            data-test="persistent-radio"
          />
          <v-radio
            label="Ephemeral"
            value="/openc3-api/redis/exec?ephemeral=1"
            data-test="ephemeral-radio"
          />
        </v-radio-group>
      </v-card-actions>

      <v-data-table
        :headers="headers"
        :items="commands"
        class="monospace"
        item-class="monospace"
        calculate-widths
        disable-pagination
        hide-default-footer
        dense
        height="45vh"
      >
      </v-data-table>
    </v-card>
  </div>
</template>

<script>
import Api from '../../../services/api'

export default {
  data() {
    return {
      redisCommandText: '',
      redisResponse: null,
      redisEndpoint: '/openc3-api/redis/exec',
      headers: [
        { text: 'Redis', value: 'redis', width: 150 },
        { text: 'Command', value: 'command' },
        { text: 'Response', value: 'response' },
      ],
      commands: [],
    }
  },
  methods: {
    commandKeydown: function ($event) {
      $event.key === 'Enter' && this.executeRaw()
    },
    executeRaw: function () {
      this.redisResponse = null
      Api.post(this.redisEndpoint, {
        data: this.redisCommandText,
        headers: {
          Accept: 'application/json',
          'Content-Type': 'plain/text',
        },
      }).then((response) => {
        this.redisResponse = response.data.result
        let redis = 'Ephemeral'
        if (this.redisEndpoint === '/openc3-api/redis/exec') {
          redis = 'Persistent'
        }
        this.commands.unshift({
          redis: redis,
          command: this.redisCommandText,
          response: this.redisResponse,
        })
      })
    },
  },
}
</script>

<style scoped>
.monospace {
  font-family: monospace;
  font-size: 20px;
}
</style>
