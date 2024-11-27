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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <top-bar :title="title" />
    <div
      v-if="url"
      style="
        display: flex;
        width: 100%;
        height: 100%;
        flex-direction: column;
        overflow: hidden;
      "
    >
      <iframe
        :src="url"
        :title="title"
        style="
          flex-grow: 1;
          border: none;
          margin: 0;
          padding: 0;
          height: calc(100vh - 118px);
        "
      ></iframe>
    </div>
  </div>
</template>

<script>
import { TopBar } from '@openc3/vue-common/components'

export default {
  components: {
    TopBar,
  },
  data() {
    return {
      title: 'Iframe',
      url: null,
    }
  },
  created() {
    if (this.$route.query && this.$route.query.title) {
      this.title = this.$route.query.title
    }
    if (this.$route.query && this.$route.query.url) {
      this.url = this.$route.query.url
    }
  },
}
</script>
