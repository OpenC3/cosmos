<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <suppressed-settings />
    <v-divider />
    <default-config-settings />
    <v-divider />
    <editor-settings />
    <v-divider />
    <astro-settings />
    <v-divider />
    <theme-settings />
    <v-divider />
    <time-zone-settings />
    <v-divider />
    <time-format-settings />
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
    <v-divider />
    <context-tag-settings />
  </div>
</template>

<script>
import SuppressedSettings from './settings/SuppressedSettings.vue'
import DefaultConfigSettings from './settings/DefaultConfigSettings.vue'
import EditorSettings from './settings/EditorSettings.vue'
import AstroSettings from './settings/AstroSettings.vue'
import ThemeSettings from './settings/ThemeSettings.vue'
import ClassificationBannerSettings from './settings/ClassificationBannerSettings.vue'
import TimeZoneSettings from './settings/TimeZoneSettings.vue'
import TimeFormatSettings from './settings/TimeFormatSettings.vue'
import NewsFeedSettings from './settings/NewsFeedSettings.vue'
import SubtitleSettings from './settings/SubtitleSettings.vue'
import SourceCodeSettings from './settings/SourceCodeSettings.vue'
import RubyGemsSettings from './settings/RubyGemsSettings.vue'
import PypiSettings from './settings/PypiSettings.vue'
import ContextTagSettings from './settings/ContextTagSettings.vue'

export default {
  components: {
    SuppressedSettings,
    DefaultConfigSettings,
    EditorSettings,
    AstroSettings,
    ThemeSettings,
    ClassificationBannerSettings,
    TimeZoneSettings,
    TimeFormatSettings,
    NewsFeedSettings,
    SubtitleSettings,
    SourceCodeSettings,
    RubyGemsSettings,
    PypiSettings,
    ContextTagSettings,
  },
}
</script>
