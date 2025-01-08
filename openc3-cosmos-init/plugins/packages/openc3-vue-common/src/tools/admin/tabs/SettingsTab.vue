<!--
# Copyright 2024 OpenC3, Inc.
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
  <div>
    <suppressed-settings />
    <v-divider />
    <default-config-settings />
    <v-divider />
    <astro-settings />
    <v-divider />
    <time-zone-settings />
    <v-divider />
    <news-feed-settings />
    <v-divider />
    <classification-banner-settings />
    <v-divider />
    <subtitle-settings />
    <v-divider />
    <source-code-settings />
    <v-divider />
    <ruby-gems-settings />
    <v-divider />
    <pypi-settings />
  </div>
</template>

<script>
import SuppressedSettings from './settings/SuppressedSettings.vue'
import DefaultConfigSettings from './settings/DefaultConfigSettings.vue'
import AstroSettings from './settings/AstroSettings.vue'
import ClassificationBannerSettings from './settings/ClassificationBannerSettings.vue'
import TimeZoneSettings from './settings/TimeZoneSettings.vue'
import NewsFeedSettings from './settings/NewsFeedSettings.vue'
import SubtitleSettings from './settings/SubtitleSettings.vue'
import SourceCodeSettings from './settings/SourceCodeSettings.vue'
import RubyGemsSettings from './settings/RubyGemsSettings.vue'
import PypiSettings from './settings/PypiSettings.vue'

export default {
  components: {
    SuppressedSettings,
    DefaultConfigSettings,
    AstroSettings,
    ClassificationBannerSettings,
    TimeZoneSettings,
    NewsFeedSettings,
    SubtitleSettings,
    SourceCodeSettings,
    RubyGemsSettings,
    PypiSettings,
  },
}
</script>
