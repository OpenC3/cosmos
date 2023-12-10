<!--
# Copyright 2023 OpenC3, Inc.
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
<!-- eslint-disable vue/no-mutating-props -->

<template>
  <div>
    <v-dialog v-model="show" width="400">
      <v-card>
        <form v-on:submit.prevent="submitHandler">
          <v-system-bar>
            <v-spacer />
            <span> Delete Trigger Group </span>
            <v-spacer />
          </v-system-bar>
          <v-card-text>
            <v-text-field
              v-model="group"
              label="Group Name"
              data-test="group-input-name"
              readonly
              dense
              outlined
              hide-details
            />
          </v-card-text>
          <v-card-actions>
            <v-spacer />
            <v-btn
              @click="show = !show"
              outlined
              class="mx-2"
              data-test="group-delete-cancel-btn"
            >
              Cancel
            </v-btn>
            <v-btn
              @click.prevent="submitHandler"
              class="mx-2"
              type="submit"
              color="red"
              data-test="group-delete-submit-btn"
            >
              Delete
            </v-btn>
          </v-card-actions>
        </form>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import Api from '@openc3/tool-common/src/services/api'

export default {
  props: {
    group: {
      type: String,
      required: true,
    },
    value: Boolean, // value is the default prop when using v-model
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
  },
  methods: {
    submitHandler: function () {
      this.$dialog
        .confirm(
          `Are you sure you want to delete TriggerGroup: ${this.group}`,
          {
            okText: 'Delete',
            cancelText: 'Cancel',
          },
        )
        .then(() => {
          Api.delete(`/openc3-api/autonomic/group/${this.group}`)
        })
        .then((r) => {
          this.$notify.normal({
            title: 'Deleted TriggerGroup',
            body: this.group,
          })
        })
        .catch(function (err) {
          // Cancelling the dialog forces catch and sets err to true
        })
      this.show = !this.show
    },
  },
}
</script>
