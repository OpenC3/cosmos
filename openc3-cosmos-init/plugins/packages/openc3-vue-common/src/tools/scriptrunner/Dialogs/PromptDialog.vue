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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog persistent v-model="show" width="600">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span class="text" v-text="title" />
        <v-spacer />
      </v-toolbar>
      <div class="pa-2">
        <v-card-text class="text">
          <v-row v-if="subtitle">
            <v-card-subtitle>{{ subtitle }}</v-card-subtitle>
          </v-row>
          <v-row class="mt-1">
            <span v-text="message" />
          </v-row>
          <v-row v-if="details" class="mt-1">
            <span v-text="details" />
          </v-row>
        </v-card-text>
      </div>
      <div v-if="layout === 'combo'">
        <v-row class="ma-2">
          <v-select
            @update:model-value="selectOkDisabled = false"
            v-model="selectedItem"
            label="Select"
            color="secondary"
            class="ma-1"
            data-test="prompt-select"
            :items="buttons"
            :multiple="multiple === true"
          />
        </v-row>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn
            @click="cancelHandler"
            variant="outlined"
            data-test="prompt-cancel"
          >
            Cancel
          </v-btn>
          <v-btn
            variant="flat"
            @click="submitHandler"
            data-test="prompt-ok"
            :disabled="selectOkDisabled"
          >
            Ok
          </v-btn>
        </v-card-actions>
      </div>
      <div v-else>
        <v-card-actions :class="layoutClass">
          <v-spacer />
          <v-btn
            @click="cancelHandler"
            variant="outlined"
            data-test="prompt-cancel"
          >
            Cancel
          </v-btn>
          <div v-for="(button, index) in buttons" :key="index">
            <v-btn
              variant="flat"
              @click="submitWrapper(button.value)"
              :data-test="`prompt-${button.text}`"
            >
              {{ button.text }}
            </v-btn>
          </div>
        </v-card-actions>
      </div>
    </v-card>
  </v-dialog>
</template>

<script>
export default {
  props: {
    title: {
      type: String,
      default: 'Prompt Dialog',
    },
    subtitle: {
      type: String,
      default: '',
    },
    message: {
      type: String,
      required: true,
    },
    details: {
      type: String,
      default: '',
    },
    buttons: {
      type: Array,
      default: () => [],
    },
    layout: {
      type: String,
      default: 'horizontal', // Also 'vertical' or 'combo' when means ComboBox
    },
    multiple: {
      type: Boolean,
      default: false,
      required: false,
    },
    modelValue: Boolean,
  },
  data() {
    return {
      selectOkDisabled: true,
      selectedItem: null,
    }
  },
  computed: {
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
    layoutClass() {
      let layout = 'px-2 d-flex align-start'
      if (this.layout === 'vertical') {
        return `${layout} flex-column`
      } else {
        return `${layout} flex-row`
      }
    },
  },
  methods: {
    submitWrapper: function (output) {
      this.selectedItem = output
      this.submitHandler()
    },
    submitHandler: function () {
      this.$emit('response', this.selectedItem)
    },
    cancelHandler: function () {
      this.$emit('response', 'Cancel')
    },
  },
}
</script>

<style scoped>
.v-card__subtitle {
  padding: 0;
  padding-bottom: 10px;
}
.text {
  font-size: 1rem;
  white-space: pre-line;
}
</style>
