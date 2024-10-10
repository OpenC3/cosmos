<!--
# Copyright 2024 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog :persistent="persistent" v-model="show" width="600">
    <v-card>
      <v-system-bar>
        <v-spacer />
        <span> Waiting for Critical Command Approval </span>
        <v-spacer />
      </v-system-bar>

      <v-card-title> {{ cmdString }} </v-card-title>
      <v-card-subtitle>
        User: {{ cmdUser }} - UUID: {{ uuid }}
      </v-card-subtitle>
      <v-card-text>
        <v-container fluid>
          <v-row v-if="!canApprove">
            <v-text-field
              v-model="username"
              label="Username"
              data-test="username"
            />
          </v-row>
          <v-row v-if="!canApprove">
            <v-text-field
              v-model="password"
              type="password"
              label="Password"
              data-test="password"
            />
          </v-row>
          <v-row>
            <v-spacer />
            <v-btn
              type="submit"
              @click.prevent="reject"
              class="mx-2"
              color="secondary"
              :disabled="disableButtons"
              data-test="reject"
            >
              Reject
            </v-btn>
            <v-btn
              type="submit"
              @click.prevent="approve"
              class="mx-2"
              color="primary"
              :disabled="disableButtons"
              data-test="approve"
            >
              Approve
            </v-btn>
          </v-row>
        </v-container>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
import axios from 'axios'
import Api from '../services/api.js'

export default {
  props: {
    uuid: String,
    cmdUser: String,
    cmdString: String,
    persistent: {
      type: Boolean,
      default: false,
    },
    value: Boolean, // value is the default prop when using v-model
  },
  data() {
    return {
      updater: null,
      username: null,
      password: null,
      canApprove: false,
    }
  },
  computed: {
    show: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
    formValid: function () {
      return !!this.password && !!this.username
    },
    disableButtons: function () {
      return !this.formValid && !this.canApprove
    },
  },
  beforeDestroy() {
    clearInterval(this.updater)
    this.updater = null
    this.canApprove = false
    this.username = null
    this.password = null
  },
  watch: {
    // Create a watcher on value which is the indicator to display the dialog
    // If value is true we request the details from the server
    // If this is a tlm dialog we setup an interval to get the telemetry values
    value: function (newValue, oldValue) {
      if (newValue) {
        // Check if we can approve without username/password
        Api.get('/openc3-api/criticalcmd/canapprove/' + this.uuid).then(
          (response) => {
            if (response.data.status === 'ok') {
              this.canApprove = true
            }
          },
        )

        // Clear if approved/rejected
        this.updater = setInterval(() => {
          if (this.uuid) {
            Api.get('/openc3-api/criticalcmd/status/' + this.uuid).then(
              (response) => {
                if (response.data.status !== 'WAITING') {
                  this.$emit('status', response.data.status)
                  this.show = false
                }
              },
            )
          } else {
            this.show = false
          }
        }, 1000)
      } else {
        clearInterval(this.updater)
        this.updater = null
        this.canApprove = false
        this.username = null
        this.password = null
      }
    },
  },
  methods: {
    async approve() {
      if (this.canApprove) {
        await Api.post('/openc3-api/criticalcmd/approve/' + this.uuid, {}).then(
          (response) => {
            if (response.status == 200) {
              this.$emit('status', 'APPROVED')
              this.show = false
            }
          },
        )
      } else {
        let token = await this.getKeycloakToken()
        const response = await axios.post(
          '/openc3-api/criticalcmd/approve/' + this.uuid,
          {},
          {
            headers: {
              Authorization: token,
              'Content-Type': 'application/json',
            },
            params: {
              scope: window.openc3Scope,
            },
            timeout: 5000,
          },
        )
        if (response.status == 200) {
          this.$emit('status', 'APPROVED')
          this.show = false
        }
      }
    },
    async reject() {
      if (this.canApprove) {
        await Api.post('/openc3-api/criticalcmd/reject/' + this.uuid, {}).then(
          (response) => {
            if (response.status == 200) {
              this.$emit('status', 'REJECTED')
              this.show = false
            }
          },
        )
      } else {
        let token = await this.getKeycloakToken()
        const response = await axios.post(
          '/openc3-api/criticalcmd/reject/' + this.uuid,
          {},
          {
            headers: {
              Authorization: token,
              'Content-Type': 'application/json',
            },
            params: {
              scope: window.openc3Scope,
            },
            timeout: 5000,
          },
        )
        if (response.status == 200) {
          this.$emit('status', 'REJECTED')
          this.show = false
        }
      }
    },
    async getKeycloakToken() {
      const response = await axios.post(
        localStorage.keycloakUrl +
          '/realms/' +
          localStorage.keycloakRealm +
          '/protocol/openid-connect/token',
        {
          username: this.username,
          password: this.password,
          client_id: localStorage.keycloakClientId,
          grant_type: 'password',
          scope: 'openid',
        },
        {
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          timeout: 5000,
        },
      )
      return response.data.access_token
    },
  },
}
</script>

<style scoped>
.label {
  font-weight: bold;
  text-transform: capitalize;
}
:deep(.v-input--selection-controls) {
  padding: 0px;
  margin: 0px;
}
</style>
