<!--
# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <top-bar :menus="menus" :title="title" />
    <v-card>
      <v-card-title> Example Card </v-card-title>
      <v-card-text>
        <v-btn block @click="buttonPress"> Send Command </v-btn>
      </v-card-text>
    </v-card>
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'
import { TopBar } from '@openc3/vue-common/components'

export default {
  components: {
    TopBar,
  },
  data() {
    return {
      title: '<%= tool_name_display %>',
      api: null,
      menus: [
        {
          label: 'File',
          items: [
            {
              label: 'Send Command',
              command: () => {
                this.api
                  .cmd('INST', 'COLLECT', { TYPE: 'NORMAL' })
                  .then((response) => {
                    alert('Command Sent!')
                  })
              },
            },
          ],
        },
      ],
    }
  },
  created() {
    this.api = new OpenC3Api()
  },
  methods: {
    buttonPress() {
      this.api.cmd('INST', 'COLLECT', { TYPE: 'NORMAL' }).then((response) => {
        alert('Command Sent!')
      })
    },
  },
}
</script>
