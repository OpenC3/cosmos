<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
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
              @click.prevent="verify"
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
import { Api, isUnauthorizedError } from '@openc3/js-common/services'

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
        // 401 and 429 are normal, expected answers on this page: the session
        // token we are checking may be stale, the password may be wrong, or we
        // may be rate limited. Every one of them is already reported in the
        // form's own alert, so opt out of the axios interceptor to avoid a
        // duplicate error banner. For 401 this also stops the interceptor from
        // clearing tokens (shared with every other tab on this origin) and
        // bouncing us through a login redirect while we're already on the login
        // page.
        headers: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
          'Ignore-Errors': '401,429',
        },
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
    Api.get('/openc3-api/auth/token-exists', this.options)
      .then((response) => {
        this.isSet = !!response.data.result
        if (!this.isSet) {
          this.reset = true
        }
      })
      .catch(console.error)
  },
  mounted: function () {
    if (localStorage.openc3Token) {
      this.verifyToken()
    }
  },
  methods: {
    showReset: function () {
      this.reset = true
    },
    // Skip the login form if the session token we already have is still good.
    // Note this must not go to /auth/verify: that endpoint only checks
    // passwords, so a session token always failed there and was recorded as a
    // bad password attempt against the rate limit.
    verifyToken: function () {
      const token = localStorage.openc3Token
      Api.post('/openc3-api/auth/verify-token', {
        data: {
          token,
        },
        ...this.options,
      })
        .then(() => {
          this.redirect()
        })
        .catch((error) => {
          // Only a 401 means the token is actually stale. Anything else (server
          // down, 500) says nothing about the token, and throwing it away would
          // needlessly force the user to retype their password.
          if (!isUnauthorizedError(error)) {
            return
          }
          // Stale token - drop it and let the user log in normally. Only if it's
          // still the token we checked: the user can finish logging in while
          // this request is in flight, and deleting the new token would send
          // them straight back to the login form.
          if (localStorage.openc3Token === token) {
            delete localStorage.openc3Token
          }
        })
    },
    login: function (response) {
      localStorage.openc3Token = response.data
      this.redirect()
    },
    redirect: function () {
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
    verify: function () {
      this.showAlert = false
      Api.post('/openc3-api/auth/verify', {
        data: {
          password: this.password,
        },
        ...this.options,
      })
        .then((response) => {
          this.login(response)
        })
        .catch((error) => {
          if (isUnauthorizedError(error)) {
            this.alert = 'Incorrect password'
          } else if (error?.status === 429 || error?.response?.status === 429) {
            this.alert = 'Please try again later'
          } else if (
            error?.response?.data?.message === 'invalid password hash'
          ) {
            this.alert =
              'Please see the migration guide for upgrading to COSMOS 7 in our docs.'
          } else {
            this.alert = error.message || 'Something went wrong...'
          }
          this.alertType = 'warning'
          this.showAlert = true
        })
    },
    setPassword: function () {
      this.showAlert = false
      Api.post('/openc3-api/auth/set', {
        data: {
          old_password: this.oldPassword,
          password: this.password,
        },
        ...this.options,
      })
        .then((response) => {
          this.login(response)
        })
        .catch((error) => {
          // No response at all means the server is unreachable, not a bad
          // password, so don't blow up dereferencing it
          this.alert = `Invalid password: ${
            error?.response?.data?.message || error?.message || 'unknown error'
          }`
          this.alertType = 'warning'
          this.showAlert = true
        })
    },
  },
}
</script>
