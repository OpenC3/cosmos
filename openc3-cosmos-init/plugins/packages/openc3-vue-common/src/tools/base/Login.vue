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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card>
    <v-card-title> Login </v-card-title>
    <v-card-subtitle>
      {{ isSet ? 'Enter the' : 'Create a' }}
      password to begin using OpenC3
    </v-card-subtitle>
    <v-card-text>
      <v-form>
        <v-text-field
          v-if="isSet && reset"
          v-model="oldPassword"
          type="password"
          label="Old Password"
        />
        <v-text-field
          v-model="password"
          type="password"
          :label="`${!isSet || reset ? 'New ' : ''}Password`"
          data-test="new-password"
        />
        <v-text-field
          v-if="reset"
          v-model="confirmPassword"
          :rules="[rules.matchPassword]"
          type="password"
          label="Confirm Password"
          data-test="confirm-password"
        />
        <v-btn
          v-if="reset"
          type="submit"
          size="large"
          :color="isSet ? 'warn' : 'success'"
          :disabled="!formValid"
          data-test="set-password"
          @click.prevent="setPassword"
        >
          Set
        </v-btn>
        <v-container v-else>
          <v-row>
            <v-btn
              type="submit"
              size="large"
              color="success"
              :disabled="!formValid"
              @click.prevent="() => verifyPassword()"
            >
              Login
            </v-btn>
            <v-spacer />
            <v-btn variant="text" size="small" @click="showReset">
              Change Password
            </v-btn>
          </v-row>
        </v-container>
      </v-form>
    </v-card-text>
    <v-alert v-model="showAlert" :type="alertType" closable>
      {{ alert }}
    </v-alert>
  </v-card>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  data() {
    return {
      isSet: true,
      password: '',
      confirmPassword: '',
      oldPassword: '',
      reset: false, // setting a password for the first time, or changing to a new password
      alert: '',
      alertType: 'success',
      showAlert: false,
    }
  },
  computed: {
    options: function () {
      return {
        noAuth: true,
        noScope: true, // lol
      }
    },
    rules: function () {
      return {
        matchPassword: () =>
          this.password === this.confirmPassword || 'Passwords must match',
      }
    },
    formValid: function () {
      if (this.reset) {
        if (!this.isSet) {
          return !!this.password && this.password === this.confirmPassword
        } else {
          return (
            !!this.oldPassword &&
            !!this.password &&
            this.password === this.confirmPassword
          )
        }
      } else {
        return !!this.password
      }
    },
  },
  created: function () {
    Api.get('/openc3-api/auth/token-exists', this.options).then((response) => {
      this.isSet = !!response.data.result
      if (!this.isSet) {
        this.reset = true
      }
    })
  },
  mounted: function () {
    if (localStorage.openc3Token) {
      this.verifyPassword(localStorage.openc3Token, true)
    }
  },
  methods: {
    showReset: function () {
      this.reset = true
    },
    login: function (response) {
      localStorage.openc3Token = response.data
      const redirect = new URLSearchParams(window.location.search).get(
        'redirect',
      )
      if (redirect?.startsWith('/tools/')) {
        // Valid relative redirect URL
        window.location = decodeURI(redirect)
      } else {
        window.location = '/'
      }
    },
    verifyPassword: function (token, noAlert) {
      token ||= this.password
      this.showAlert = false
      Api.post('/openc3-api/auth/verify', {
        data: {
          token,
        },
        ...this.options,
      })
        .then((response) => {
          this.login(response)
        })
        .catch((error) => {
          if (error?.status === 401) {
            this.alert = 'Incorrect password'
          } else {
            this.alert = error.message || 'Something went wrong...'
          }
          this.alertType = 'warning'
          this.showAlert = !noAlert
        })
    },
    setPassword: function () {
      this.showAlert = false
      Api.post('/openc3-api/auth/set', {
        data: {
          old_token: this.oldPassword,
          token: this.password,
        },
        ...this.options,
      })
        .then((response) => {
          this.login(response)
        })
        .catch((error) => {
          this.alert = `Invalid password: ${error.response.data.message}`
          this.alertType = 'warning'
          this.showAlert = true
        })
    },
  },
}
</script>
