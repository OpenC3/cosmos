<!--
# Copyright 2022 OpenC3, Inc.
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
  <div>
    <v-row no-gutters>
      <v-col>
        <v-file-input
          v-model="file"
          show-size
          accept="*"
          class="mx-2"
          label="Click to select a file to create a secret from or enter a secret value"
          ref="fileInput"
        />
      </v-col>
    </v-row>
    <v-row no-gutters align="center" style="padding-left: 10px">
      <v-col cols="3">
        <v-text-field v-model="secretName" label="Secret Name" class="px-2" />
      </v-col>
      <v-col cols="3" class="px-2">
        <!-- Intentional double equals -->
        <v-text-field
          v-model="secretValue"
          :disabled="file"
          label="Secret Value"
        />
      </v-col>
      <v-col cols="3" class="px-2">
        <!-- Intentional double equals -->
        <v-btn
          @click="upload()"
          class="mx-2"
          color="primary"
          data-test="secretUpload"
          :disabled="secretName === '' || (file == null && secretValue === '')"
          :loading="loadingSecret"
        >
          <v-icon left dark>mdi-cloud-upload</v-icon>
          <span> Set </span>
          <template v-slot:loader>
            <span>Loading...</span>
          </template>
        </v-btn>
      </v-col>
    </v-row>
    <v-alert
      v-model="showAlert"
      dismissible
      transition="scale-transition"
      :type="alertType"
      >{{ alert }}</v-alert
    >
    <v-list data-test="secretList">
      <div v-for="(secret, index) in secrets" :key="index">
        <v-list-item>
          <v-list-item-content>
            <v-list-item-title>{{ secret }}</v-list-item-title>
          </v-list-item-content>
          <v-list-item-icon>
            <v-tooltip bottom>
              <template v-slot:activator="{ on, attrs }">
                <v-icon @click="deleteSecret(secret)" v-bind="attrs" v-on="on">
                  mdi-delete
                </v-icon>
              </template>
              <span>Delete Secret</span>
            </v-tooltip>
          </v-list-item-icon>
        </v-list-item>
        <v-divider v-if="index < secrets.length - 1" :key="index" />
      </div>
    </v-list>
  </div>
</template>

<script>
import Api from '../../../services/api'

export default {
  data() {
    return {
      file: null,
      loadingSecret: false,
      secrets: [],
      secretName: '',
      secretValue: '',
      alert: '',
      alertType: 'success',
      showAlert: false,
    }
  },
  mounted() {
    this.update()
  },
  methods: {
    update() {
      Api.get('/openc3-api/secrets').then((response) => {
        this.secrets = response.data
      })
    },
    upload: function () {
      this.loadingSecret = true
      let promise = null
      if (this.file) {
        const formData = new FormData()
        formData.append('file', this.file, this.file.name)
        promise = Api.post(`/openc3-api/secrets/${this.secretName}`, {
          data: formData,
          headers: { 'Content-Type': 'multipart/form-data' },
        })
      } else {
        promise = Api.post(`/openc3-api/secrets/${this.secretName}`, {
          data: { value: this.secretValue },
        })
      }
      promise
        .then((response) => {
          this.loadingSecret = false
          this.file = null
          this.secretName = ''
          this.secretValue = ''
          this.update()
        })
        .catch((error) => {
          this.loadingSecret = false
        })
    },
    deleteSecret: function (secret) {
      this.$dialog
        .confirm(`Are you sure you want to remove: ${secret}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then(function (dialog) {
          return Api.delete(`/openc3-api/secrets/${secret}`)
        })
        .then((response) => {
          this.alert = `Removed secret ${secret}`
          this.alertType = 'success'
          this.showAlert = true
          setTimeout(() => {
            this.showAlert = false
          }, 5000)
          this.update()
        })
    },
  },
}
</script>
