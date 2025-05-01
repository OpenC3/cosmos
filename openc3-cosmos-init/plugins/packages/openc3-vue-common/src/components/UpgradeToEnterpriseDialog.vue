<!--
# Copyright 2025 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" width="650px">
    <v-toolbar height="24">
      <v-spacer />
      <span> Upgrade to COSMOS Enterprise </span>
      <v-spacer />
    </v-toolbar>
    <v-card>
      <v-card-text class="mt-4">
        <div class="logo">
          <img :src="logo" alt="OpenC3" />
          <div class="cosmos">COSMOS Enterprise</div>
        </div>
        <div class="pb-4">Thank you for using the COSMOS Core!</div>
        <div v-if="reason">
          <div class="pb-4 pl-4 reason">
            {{ reason }}
          </div>
        </div>
        COSMOS Enterprise removes all restrictions and offers users with role
        based access control, scaling on kubernetes, cloud platform support,
        multiple scopes, Calendar and Autonomic, various integrations with
        common protocols and hardware, commercial licensing, and much more!<br /><br />
        Learn more at
        <a href="https://openc3.com/enterprise">
          https://openc3.com/enterprise
        </a>
        and help support COSMOS Core by supporting our business. Contact us at
        <a href="mailto:support@openc3.com">support@openc3.com</a> for more
        information about COSMOS Enterprise, COSMOS training, COSMOS support,
        and custom COSMOS development.
      </v-card-text>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn variant="flat" @click="show = !show"> Ok </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
export default {
  props: {
    modelValue: Boolean, // modelValue is the default prop when using v-model
    reason: String,
  },
  emits: ['update:modelValue'],
  data() {
    return {
      logo: '/img/logo.png',
    }
  },
  computed: {
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value) // update is the default event when using v-model
      },
    },
  },
}
</script>

<style scoped>
.logo {
  float: right;
  margin: 15px;
}

.cosmos {
  text-align: center;
  font-size: 18pt;
}

.reason {
  font-weight: bold;
}
</style>
