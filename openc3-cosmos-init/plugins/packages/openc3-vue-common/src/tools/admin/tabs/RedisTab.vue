<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

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
          v-model="redisCommandText"
          hide-details
          label="Redis command"
          class="monospace"
          @keydown="commandKeydown"
        />
        <v-checkbox
          v-model="prettyPrint"
          label="Pretty print"
          density="compact"
          hide-details
          class="mb-2"
        />
        <template v-if="redisResponse">
          <pre v-if="prettyPrint" v-text="formattedResponse" />
          <span v-else class="monospace"> Response: {{ redisResponse }} </span>
        </template>
      </v-card-text>
      <v-card-actions class="px-2">
        <v-btn
          :disabled="!redisCommandText.length"
          color="success"
          variant="text"
          @click="executeRaw"
        >
          Execute
        </v-btn>
        <v-radio-group v-model="redisEndpoint" inline hide-details class="mt-0">
          <v-radio
            label="Persistent"
            value="persistent"
            data-test="persistent-radio"
          />
          <v-radio
            label="Ephemeral"
            value="ephemeral"
            data-test="ephemeral-radio"
          />
        </v-radio-group>
        <v-text-field
          v-model="shard"
          type="number"
          min="0"
          label="Shard"
          hide-details
          density="compact"
          style="max-width: 100px"
          class="ml-4"
        />
      </v-card-actions>

      <v-data-table
        :headers="headers"
        :items="commands"
        class="monospace"
        :items-per-page="-1"
        hide-default-footer
        density="compact"
        height="45vh"
      >
      </v-data-table>
    </v-card>
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  data() {
    return {
      redisCommandText: '',
      redisResponse: null,
      redisEndpoint: 'persistent',
      shard: '0',
      prettyPrint: false,
      headers: [
        { text: 'Redis', value: 'redis', width: 150 },
        { text: 'Command', value: 'command' },
        { text: 'Response', value: 'response' },
      ],
      commands: [],
    }
  },
  computed: {
    formattedResponse: function () {
      let result = this.redisResponse
      if (this.redisResponse && this.prettyPrint) {
        if (typeof result === 'string') {
          try {
            result = JSON.parse(result)
          } catch (e) {
            // Oh 🐋
          }
        }
        if (Array.isArray(result)) {
          for (let i = 0; i < result.length; i++) {
            if (typeof result[i] === 'string') {
              try {
                result[i] = JSON.parse(result[i])
              } catch (e) {
                // Oh 🐋
              }
            }
          }
        }
      }
      result = JSON.stringify(result, null, 2)
      return `Response: ${result}`
    },
  },
  methods: {
    commandKeydown: function ($event) {
      $event.key === 'Enter' && this.executeRaw()
    },
    executeRaw: function () {
      this.redisResponse = null
      let url = '/openc3-api/redis/exec'
      const params = []
      if (this.redisEndpoint === 'ephemeral') {
        params.push('ephemeral=1')
      }
      if (this.shard && this.shard !== '0') {
        params.push(`shard=${this.shard}`)
      }
      if (params.length) {
        url += '?' + params.join('&')
      }
      Api.post(url, {
        data: this.redisCommandText,
        headers: {
          Accept: 'application/json',
          'Content-Type': 'plain/text',
        },
      }).then((response) => {
        this.redisResponse = response.data.result
        let redis = this.redisEndpoint === 'ephemeral' ? 'Ephemeral' : 'Persistent'
        if (this.shard !== '0') {
          redis += ` (shard ${this.shard})`
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
  font-size: 14px;
}
</style>
