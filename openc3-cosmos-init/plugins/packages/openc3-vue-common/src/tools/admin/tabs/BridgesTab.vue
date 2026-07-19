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
  <div>
    <v-alert v-model="showAlert" closable :type="alertType">{{
      alert
    }}</v-alert>
    <div class="d-flex align-center mt-2 mb-2 mx-4">
      <div class="text-caption text-medium-emphasis">
        {{ bridges.length }} bridge{{ bridges.length === 1 ? '' : 's' }}
      </div>
      <v-spacer />
      <v-btn
        color="primary"
        prepend-icon="mdi-plus"
        data-test="create-bridge"
        @click="showCreate = true"
      >
        Create Bridge
      </v-btn>
    </div>
    <v-list class="list" data-test="bridgeList">
      <div v-for="bridge in bridges" :key="bridge.name">
        <v-list-item>
          <v-list-item-title>{{ bridge.name }}</v-list-item-title>
          <v-list-item-subtitle>
            openc3-app enrolled:
            {{ bridge.app_public_key ? 'Yes' : 'No' }}
            <template v-if="bridge.app_public_key">
              ({{ bridge.app_public_key.slice(0, 12) }}…)
            </template>
            , Reachable: {{ bridge.ticket ? 'Yes' : 'No' }}
          </v-list-item-subtitle>
          <template #append>
            <v-chip
              :color="bridge.app_public_key ? 'green' : 'yellow'"
              size="small"
              label
            >
              {{ bridge.app_public_key ? 'ENROLLED' : 'UNPAIRED' }}
            </v-chip>
            <v-tooltip text="Generate Enrollment Token" location="top">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  aria-label="Generate Enrollment Token"
                  icon="mdi-key-plus"
                  variant="text"
                  :disabled="!bridge.ticket"
                  @click="generateToken(bridge.name)"
                />
              </template>
            </v-tooltip>
            <v-tooltip text="Delete Bridge" location="top">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  aria-label="Delete Bridge"
                  icon="mdi-delete"
                  variant="text"
                  data-test="delete-bridge"
                  @click="deleteBridge(bridge.name)"
                />
              </template>
            </v-tooltip>
          </template>
        </v-list-item>
        <v-divider />
      </div>
      <v-list-item v-if="bridges.length === 0">
        <v-list-item-subtitle>
          No bridges found. A bridge appears here once its bridge_microservice
          is running (deploy an interface with the BRIDGE keyword).
        </v-list-item-subtitle>
      </v-list-item>
    </v-list>

    <v-dialog v-model="showToken" width="700">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span> Enrollment Token: {{ tokenBridge }} </span>
          <v-spacer />
        </v-toolbar>
        <v-card-text class="mt-4">
          <p class="mb-2">
            Paste this one-time token into openc3-app (on the remote host) to
            pair it with this bridge. It authorizes that openc3-app's identity
            and can only be redeemed once.
          </p>
          <v-textarea
            :model-value="token"
            label="Enrollment Token"
            variant="outlined"
            readonly
            rows="4"
            data-test="enrollment-token"
          />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="copyToken"> Copy </v-btn>
          <v-btn variant="text" @click="showToken = false"> Close </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>

    <v-dialog v-model="showCreate" width="500">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span> Create Bridge </span>
          <v-spacer />
        </v-toolbar>
        <v-card-text class="mt-4">
          <v-text-field
            v-model="newBridgeName"
            label="Bridge Name"
            variant="outlined"
            hint="Letters, numbers, and underscores (e.g. LAB1)"
            persistent-hint
            autofocus
            data-test="new-bridge-name"
            @keyup.enter="createBridge"
          />
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="text" @click="showCreate = false"> Cancel </v-btn>
          <v-btn
            variant="text"
            :disabled="!newBridgeName"
            data-test="create-bridge-submit"
            @click="createBridge"
          >
            Create
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  data() {
    return {
      bridges: [],
      updater: null,
      token: '',
      tokenBridge: '',
      showToken: false,
      showCreate: false,
      newBridgeName: '',
      alert: '',
      alertType: 'success',
      showAlert: false,
    }
  },
  mounted() {
    this.update()
    this.updater = setInterval(() => {
      this.update()
    }, 5000)
  },
  beforeUnmount() {
    clearInterval(this.updater)
    this.updater = null
  },
  methods: {
    update: function () {
      Api.get('/openc3-api/bridges/all').then((response) => {
        let bridges = []
        for (const [_name, bridge] of Object.entries(response.data)) {
          bridges.push(bridge)
        }
        bridges.sort((a, b) => a.name.localeCompare(b.name))
        this.bridges = bridges
      })
    },
    showTempAlert: function (message, type = 'success', ms = 3000) {
      this.alert = message
      this.alertType = type
      this.showAlert = true
      setTimeout(() => {
        this.showAlert = false
      }, ms)
    },
    createBridge: function () {
      const name = this.newBridgeName.trim().toUpperCase()
      if (!name) return
      Api.post('/openc3-api/bridges', { data: { name } })
        .then(() => {
          this.showCreate = false
          this.newBridgeName = ''
          this.showTempAlert(
            `Bridge ${name} created. It will appear once its hub starts.`,
          )
          this.update()
        })
        .catch((error) => {
          const message = error.response?.data?.message || error
          this.showTempAlert(
            `Failed to create bridge: ${message}`,
            'error',
            5000,
          )
        })
    },
    deleteBridge: function (name) {
      this.$dialog
        .confirm(
          `Are you sure you want to delete bridge ${name}? This stops its hub and removes its identity.`,
          {
            okText: 'Delete',
            cancelText: 'Cancel',
          },
        )
        .then(() => {
          return Api.delete(`/openc3-api/bridges/${name}`)
        })
        .then(() => {
          this.showTempAlert(`Bridge ${name} deleted`)
          this.update()
        })
        .catch((error) => {
          // Canceling the confirm dialog forces catch and sets error to true.
          if (error === true) return
          const message = error.response?.data?.message || error
          this.showTempAlert(
            `Failed to delete bridge ${name}: ${message}`,
            'error',
            5000,
          )
        })
    },
    generateToken: function (name) {
      Api.post(`/openc3-api/bridges/${name}/token`)
        .then((response) => {
          this.token = response.data.token
          this.tokenBridge = name
          this.showToken = true
          this.update()
        })
        .catch((error) => {
          this.alert = `Failed to generate token for ${name}: ${error}`
          this.alertType = 'error'
          this.showAlert = true
          setTimeout(() => {
            this.showAlert = false
          }, 5000)
        })
    },
    copyToken: function () {
      navigator.clipboard.writeText(this.token)
      this.alert = 'Token copied to clipboard'
      this.alertType = 'success'
      this.showAlert = true
      setTimeout(() => {
        this.showAlert = false
      }, 3000)
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
