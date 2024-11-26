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
  <graph
    :ref="'graph' + id"
    :id="id"
    :state="state"
    :selected-graph-id="id"
    :startTime="startTime"
    :seconds-graphed="secondsGraphed"
    :points-saved="pointsSaved"
    :points-graphed="pointsGraphed"
    :initial-items="items"
    :height="size.height"
    :width="size.width"
    :style="computedStyle"
    :time-zone="this.screen.timeZone"
    @pause="() => (state = 'pause')"
    @start="() => (state = 'start')"
    hide-toolbar
    hide-overview
  />
</template>

<script>
import GraphWidget from './GraphWidget'
import { Graph } from '@/components'

export default {
  components: {
    Graph,
  },
  mixins: [GraphWidget],
}
</script>
