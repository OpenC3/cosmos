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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-overlay :model-value="showUserMenu" class="overlay" />
    <v-menu
      v-model="showUserMenu"
      transition="slide-y-transition"
      :close-on-content-click="false"
      :offset="20"
    >
      <template #activator="{ props }">
        <rux-monitoring-icon
          v-bind="props"
          class="rux-icon"
          icon="person"
          status="off"
          :label="name"
          :sublabel="roles()"
          :notifications="unreadNews.length"
        ></rux-monitoring-icon>
      </template>

      <v-card>
        <v-card-text class="text-center">
          <div style="text-align: center; margin: 5px">
            {{ name }}
          </div>
          <div v-if="name !== 'Anonymous'">
            <div class="roles">Username: {{ username }}</div>
            <div class="pb-3 roles">Roles: {{ roles() }}</div>
          </div>
          <div v-if="authenticated">
            <v-btn block color="primary" @click="logout"> Logout </v-btn>
            <div v-if="name !== 'Anonymous'" class="pa-3">
              <v-row class="pt-3 user-title">Other Active Users:</v-row>
              <v-row
                v-for="(user, index) in activeUsers"
                :key="index"
                class="user"
              >
                {{ user }}
              </v-row>
            </div>
          </div>
          <div v-else>
            <v-btn block color="primary" @click="login"> Login </v-btn>
          </div>
          <div
            v-if="name === 'Anonymous'"
            class="pt-2 link"
            @click="showUpgradeToEnterpriseDialog = true"
          >
            Click to learn more about<br />
            COSMOS Enterprise Edition
          </div>
        </v-card-text>
        <div v-if="newsFeed">
          <v-row no-gutters class="news-header">
            <v-col cols="auto" class="me-auto">COSMOS News</v-col>
            <v-col cols="auto">
              <v-btn
                color="primary"
                density="compact"
                block
                @click="refreshNews"
              >
                Refresh
              </v-btn>
            </v-col>
          </v-row>
          <v-list
            lines="two"
            width="420"
            max-height="75vh"
            class="overflow-y-auto"
            data-test="news-list"
          >
            <template v-for="(news, index) in news" :key="`news-${index}`">
              <hr />
              <v-list-item class="pl-2">
                <v-list-item-title>
                  <span class="news-title">{{ news.title }}</span
                  ><span class="news-date">{{ formatDate(news.date) }}</span>
                </v-list-item-title>
                <div v-html="news.body"></div>
              </v-list-item>
            </template>
          </v-list>
        </div>
      </v-card>
    </v-menu>
    <upgrade-to-enterprise-dialog
      v-model="showUpgradeToEnterpriseDialog"
      reason="Enterprise has individual users with RBAC"
    />
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import { OpenC3Api } from '@openc3/js-common/services'
import { UpgradeToEnterpriseDialog } from '@/components'

export default {
  components: {
    UpgradeToEnterpriseDialog,
  },
  props: {
    size: {
      type: [String, Number],
      default: 26,
    },
  },
  data: function () {
    let user = OpenC3Auth.user()
    return {
      api: new OpenC3Api(),
      showUserMenu: false,
      authenticated: !!localStorage.openc3Token,
      name: user['name'],
      // preferred_username is returned by the token (see authorization.rb)
      username: user['preferred_username'],
      showUpgradeToEnterpriseDialog: false,
      activeUsers: ['None'],
      newsFeed: false,
      news: [],
    }
  },
  computed: {
    unreadNews: function () {
      return this.news.filter((news) => !news.read)
    },
  },
  watch: {
    // Whenever we show the user menu, read the news and refresh the list of active users
    showUserMenu: function (newValue, oldValue) {
      if (newValue === true) {
        if (this.news.length > 0) {
          this.news.forEach((news) => {
            news.read = true
          })
          localStorage.lastNewsRead = this.news[0].date
        }

        if (this.name !== 'Anonymous') {
          Api.get('/openc3-api/users/active').then((response) => {
            this.activeUsers = response.data.filter(
              (item) => !item.includes(this.name),
            )
            if (this.activeUsers.length === 0) {
              this.activeUsers = ['None']
            }
          })
        }
      }
    },
  },
  created: function () {
    this.api
      .get_setting('news_feed')
      .then((response) => {
        if (response) {
          this.newsFeed = response
          if (this.newsFeed) {
            this.fetchNews()
            // Every hour fetch news from the backend
            // Note: the backend updates from news.openc3.org every 12 hours
            setInterval(this.fetchNews, 60 * 60 * 1000)
          }
        }
      })
      .catch((error) => {
        // Do nothing
      })
  },
  methods: {
    refreshNews() {
      // Force the backend to update the news feed
      this.api.update_news().then(() => {
        this.fetchNews()
      })
    },
    formatDate(date) {
      // Just show the YYYY-MM-DD part of the date
      return date.split('T')[0]
    },
    fetchNews: function () {
      Api.get('/openc3-api/news').then((response) => {
        // We always get the full list of news we want to display
        // At some point we may delete old news items so we don't
        // want to persist news items in the frontend
        this.news = response.data.sort(
          (a, b) => Date.parse(b.date) - Date.parse(a.date),
        )
        // If we've previously read the news then mark anything older than that as read
        if (localStorage.lastNewsRead) {
          this.news.forEach((news) => {
            news.read =
              Date.parse(news.date) <= Date.parse(localStorage.lastNewsRead)
          })
        }
      })
    },
    logout: function () {
      OpenC3Auth.logout()
      Api.put(`/openc3-api/users/logout/${this.username}`)
    },
    login: function () {
      OpenC3Auth.login(location.href)
    },
    roles: function () {
      if (this.name === 'Anonymous') {
        return 'Admin'
      } else {
        return OpenC3Auth.userroles()
          .map((element) => this.capitalize(element))
          .sort()
          .join(', ')
      }
    },
    capitalize: function (string) {
      return string.charAt(0).toUpperCase() + string.slice(1)
    },
  },
}
</script>

<style scoped>
.news-header {
  padding: 10px;
  background-color: var(--color-background-base-default);
  text-align: center;
}
.news-title {
  font-weight: bold;
}
.news-date {
  font-size: 0.8rem;
  color: grey;
  float: right;
}
.link {
  cursor: pointer;
}
.overlay {
  height: 100vh;
  width: 100vw;
}
.user-title {
  font-weight: bold;
}
.user,
.roles {
  font-size: 0.8rem;
}
</style>
