<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" :persistent="persistent" width="600">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span> Waiting for Critical Command Approval </span>
        <v-spacer />
      </v-toolbar>

      <v-card-text>
        <v-container fluid>
          <v-alert v-model="error" type="error" closable>
            {{ errorText }}
          </v-alert>
          <v-row class="pt-4" style="color: white"
            >User {{ cmdUser }} is waiting for approval to execute:
          </v-row>
          <v-row class="pa-4" style="color: white">{{ cmdString }}</v-row>
          <v-row class="text-subtitle-2">UUID: {{ uuid }}</v-row>
          <v-row v-if="approversRequired" class="pt-2" data-test="approvals">
            Approvals: {{ approvers.length }}/{{ approversRequired }}
            <span v-if="approvers.length" class="pl-2">
              ({{ approvers.join(', ') }})
            </span>
          </v-row>

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
          <v-row class="pt-2">
            <v-spacer />
            <v-btn
              type="submit"
              class="mx-2"
              color="secondary"
              variant="outlined"
              :disabled="disableButtons"
              data-test="reject"
              @click.prevent="reject"
            >
              Reject
            </v-btn>
            <v-btn
              type="submit"
              class="mx-2"
              color="primary"
              :disabled="disableButtons"
              data-test="approve"
              @click.prevent="approve"
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
import { Api } from '@openc3/js-common/services'

export default {
  props: {
    uuid: {
      type: String,
      default: null,
    },
    cmdUser: {
      type: String,
      default: null,
    },
    cmdString: {
      type: String,
      default: null,
    },
    persistent: {
      type: Boolean,
      default: false,
    },
    modelValue: Boolean, // modelValue is the default prop when using v-model
  },
  emits: ['update:modelValue', 'status'],
  data() {
    return {
      updater: null,
      // uuid the dialog is open for, cleared once a final status is emitted.
      // Responses for any other uuid are stale and ignored.
      activeUuid: null,
      username: null,
      password: null,
      canApprove: false,
      approvers: [],
      approversRequired: null,
      error: false,
      errorText: '',
    }
  },
  computed: {
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value) // update:modelValue is the default event when using v-model
      },
    },
    formValid: function () {
      return !!this.password && !!this.username
    },
    disableButtons: function () {
      return !this.formValid && !this.canApprove
    },
  },
  watch: {
    // Create a watcher on value which is the indicator to display the dialog
    // If value is true we request the details from the server
    // If this is a tlm dialog we setup an interval to get the telemetry values
    modelValue: function (newValue, oldValue) {
      if (newValue) {
        this.activeUuid = this.uuid
        this.checkCanApprove()

        // Fetch immediately so the approval count is correct on open,
        // then poll until approved/rejected
        this.fetchStatus()
        this.updater = setInterval(this.fetchStatus, 1000)
      } else {
        clearInterval(this.updater)
        this.updater = null
        this.activeUuid = null
        this.canApprove = false
        this.approvers = []
        this.approversRequired = null
        this.error = false
        this.errorText = ''
        this.username = null
        this.password = null
      }
    },
    // Switch to the new command if the uuid changes while open
    uuid: function (newValue) {
      if (this.modelValue && newValue !== this.activeUuid) {
        this.activeUuid = newValue
        this.canApprove = false
        this.approvers = []
        this.approversRequired = null
        this.error = false
        this.checkCanApprove()
        this.fetchStatus()
      }
    },
  },
  beforeUnmount() {
    clearInterval(this.updater)
    this.updater = null
    this.activeUuid = null
    this.canApprove = false
    this.username = null
    this.password = null
  },
  methods: {
    isActive(uuid) {
      return uuid !== null && uuid === this.activeUuid
    },
    // Stop handling responses and report the final status exactly once
    finish(status, uuid) {
      if (!this.isActive(uuid)) return
      this.activeUuid = null
      clearInterval(this.updater)
      this.updater = null
      this.$emit('status', status, uuid)
      this.show = false
    },
    checkCanApprove() {
      const uuid = this.activeUuid
      // Check if we can approve without username/password
      Api.get('/openc3-api/criticalcmd/canapprove/' + uuid)
        .then((response) => {
          if (!this.isActive(uuid)) return
          this.canApprove = response.data.status === 'ok'
        })
        .catch(console.error)
    },
    fetchStatus() {
      const uuid = this.activeUuid
      if (uuid) {
        Api.get('/openc3-api/criticalcmd/status/' + uuid)
          .then((response) => {
            this.handleStatus(response.data, uuid)
          })
          .catch(console.error)
      } else {
        this.show = false
      }
    },
    // data is the status / approve / reject response:
    // { status, approvers, approvers_required }
    // uuid is the command the request was made for
    handleStatus(data, uuid) {
      if (!this.isActive(uuid)) return
      if (data.approvers) {
        this.approvers = data.approvers
      }
      if (data.approvers_required) {
        this.approversRequired = data.approvers_required
      }
      if (data.status !== 'WAITING') {
        this.finish(data.status, uuid)
      }
    },
    // Called after a successful approval. Stay open until enough
    // different users have approved.
    handleApproved(data, uuid) {
      if (!this.isActive(uuid)) return
      this.error = false
      this.username = null
      this.password = null
      this.handleStatus(data, uuid)
      if (this.isActive(uuid)) {
        // The current user just approved and can't approve again. Disable
        // until the check below says otherwise so a quick second click
        // doesn't send a duplicate approval.
        this.canApprove = false
        this.checkCanApprove()
      }
    },
    async approve() {
      const uuid = this.activeUuid
      // The dialog may have already finished, e.g. a final status arrived
      if (!this.isActive(uuid)) return
      try {
        const response = await this.postAction('approve', uuid)
        this.handleApproved(response.data, uuid)
      } catch (error) {
        this.showError(error, uuid)
        // e.g. this user already approved elsewhere. Check again so the
        // username / password fields are shown for another approver.
        if (this.isActive(uuid)) {
          this.checkCanApprove()
        }
      }
    },
    async reject() {
      const uuid = this.activeUuid
      // The dialog may have already finished, e.g. a final status arrived
      if (!this.isActive(uuid)) return
      try {
        await this.postAction('reject', uuid)
        this.error = false
        this.finish('REJECTED', uuid)
      } catch (error) {
        this.showError(error, uuid)
      }
    },
    // POST approve / reject as the logged in user if they can approve,
    // otherwise as the user whose credentials were entered in the dialog
    async postAction(action, uuid) {
      const path = `/openc3-api/criticalcmd/${action}/${uuid}`
      if (this.canApprove) {
        return Api.post(path, {
          headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json',
            // Shown in the dialog instead of the global error banner
            'Ignore-Errors': '403 404 409 500',
          },
        })
      }
      const token = await this.getKeycloakToken()
      return axios.post(
        path,
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
    },
    // Show why an approve / reject failed, e.g. already approved by this user,
    // already rejected, or invalid credentials
    showError(error, uuid) {
      if (!this.isActive(uuid)) return
      this.error = true
      this.errorText =
        error.response?.data?.message ??
        error.response?.data?.error_description ??
        error.message
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
