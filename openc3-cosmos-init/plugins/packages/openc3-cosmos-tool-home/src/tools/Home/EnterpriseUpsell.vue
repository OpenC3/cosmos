<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card v-if="showUpsell" variant="outlined" rounded="lg" class="card">
    <v-card-text class="pa-6">
      <div class="d-flex align-center ga-2 mb-1">
        <v-icon icon="mdi-rocket-launch" size="20" color="secondary" />
        <span class="text-h6 font-weight-bold text-white">
          Upgrade to Enterprise
        </span>
      </div>
      <div class="text-body-2 text-medium-emphasis mb-5">
        Unlock the full power of COSMOS for your organization.
      </div>
      <v-row dense>
        <v-col
          v-for="feature in features"
          :key="feature.title"
          cols="4"
          class="mb-2"
        >
          <div class="d-flex align-start ga-3">
            <v-icon :icon="feature.icon" size="18" color="secondary" />
            <div>
              <div class="text-body-2 font-weight-bold text-white">
                {{ feature.title }}
              </div>
              <div class="text-caption text-medium-emphasis">
                {{ feature.description }}
              </div>
            </div>
          </div>
        </v-col>
      </v-row>
      <div class="d-flex align-center ga-4 mt-5">
        <v-btn
          color="secondary"
          href="https://openc3.com/enterprise"
          target="_blank"
          rel="noopener noreferrer"
        >
          Learn More
        </v-btn>
        <a class="text-body-2 contact-link" href="mailto:sales@openc3.com">
          Contact Sales &rarr;
        </a>
      </div>
    </v-card-text>
  </v-card>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  data() {
    return {
      showUpsell: false,
      features: [
        {
          icon: 'mdi-shield-account',
          title: 'User Authentication & RBAC',
          description: 'Individual users with role-based access control',
        },
        {
          icon: 'mdi-kubernetes',
          title: 'Kubernetes Scaling',
          description: 'Scale across clusters with cloud platform support',
        },
        {
          icon: 'mdi-text-search',
          title: 'Log Explorer & System Health',
          description: 'Search logs and monitor system health at a glance',
        },
        {
          icon: 'mdi-lan',
          title: 'Multiple Scopes',
          description: 'Isolate environments for different missions',
        },
        {
          icon: 'mdi-puzzle-outline',
          title: 'Protocol Integrations',
          description: 'Common protocols and hardware integrations',
        },
        {
          icon: 'mdi-certificate',
          title: 'Commercial License',
          description: 'Commercial licensing and dedicated support',
        },
        {
          icon: 'mdi-calendar-clock',
          title: 'Calendar & Autonomic',
          description: 'Schedule commands and automate responses',
        },
        {
          icon: 'mdi-store-check',
          title: 'Enterprise Plugins',
          description: 'Access exclusive enterprise-only plugins',
        },
        {
          icon: 'mdi-format-list-checks',
          title: 'Command Queue & History',
          description: 'Queue commands for review and track full history',
        },
      ],
    }
  },
  mounted() {
    Api.get('/openc3-api/info')
      .then(({ data }) => {
        this.showUpsell = !data.enterprise
      })
      .catch(() => {})
  },
}
</script>

<style scoped>
.card {
  border-color: rgba(var(--v-theme-secondary), 0.2);
}
.contact-link {
  color: rgb(var(--v-theme-secondary));
  text-decoration: none;
  transition: opacity 0.2s ease;
}
.contact-link:hover {
  opacity: 0.8;
}
</style>
