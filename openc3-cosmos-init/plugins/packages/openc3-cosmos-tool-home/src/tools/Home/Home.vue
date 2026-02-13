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
  <div>
    <top-bar :title="title" />
    <div class="hero">
      <div class="hero-viewport">
        <div class="stars" />
        <div class="logo-section">
          <img :src="wordmark" alt="COSMOS" class="cosmos-logo" />
          <span class="version-text">7</span>
        </div>
        <div class="cards-container">
          <a
            v-for="card in cards"
            :key="card.title"
            class="hero-card"
            :href="card.url"
            target="_blank"
            rel="noopener noreferrer"
          >
            <v-icon :icon="card.icon" size="28" color="secondary" />
            <span
              class="text-body-1 font-weight-medium text-white text-no-wrap"
            >
              {{ card.title }}
            </span>
          </a>
        </div>
        <div class="earth-glow" />
        <div class="earth-arch" />
        <v-icon
          icon="mdi-chevron-double-down"
          size="32"
          class="scroll-chevron"
        />
      </div>
      <div class="below-arch d-flex flex-column ga-12 pa-10 pb-16">
        <div class="d-flex ga-12 justify-space-between">
          <latest-news class="flex-1-1-0" style="max-width: 480px" />
          <featured-plugins class="flex-1-1-0" style="max-width: 720px" />
        </div>
        <enterprise-upsell />
      </div>
    </div>
  </div>
</template>

<script>
import { TopBar } from '@openc3/vue-common/components'
import EnterpriseUpsell from './EnterpriseUpsell.vue'
import FeaturedPlugins from './FeaturedPlugins.vue'
import LatestNews from './LatestNews.vue'

export default {
  components: {
    TopBar,
    EnterpriseUpsell,
    FeaturedPlugins,
    LatestNews,
  },
  data() {
    return {
      title: 'Home',
      wordmark: '/img/COSMOS.png',
      cards: [
        {
          title: 'Documentation',
          icon: 'mdi-book-open-variant',
          url: 'https://docs.openc3.com/docs',
        },
        {
          title: 'GitHub',
          icon: 'mdi-github',
          url: 'https://github.com/OpenC3/cosmos',
        },
        {
          title: 'App Store',
          icon: 'mdi-store',
          url: 'https://store.openc3.com',
        },
      ],
    }
  },
}
</script>

<style scoped>
.hero {
  position: fixed;
  top: var(--v-layout-top, 64px);
  left: var(--v-layout-left, 0px);
  right: 0;
  bottom: 0;
  background: #08080c;
  overflow-y: auto;
  overflow-x: hidden;
  transition: left 0.2s ease;
}

.hero-viewport {
  position: relative;
  width: 100%;
  height: 100%;
  overflow: hidden;
}

.stars {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 60%;
  background-image:
    radial-gradient(4px 4px at 10% 15%, white, transparent),
    radial-gradient(4px 4px at 25% 35%, white, transparent),
    radial-gradient(4px 4px at 40% 10%, white, transparent),
    radial-gradient(4px 4px at 55% 45%, white, transparent),
    radial-gradient(4px 4px at 70% 20%, white, transparent),
    radial-gradient(4px 4px at 85% 55%, white, transparent),
    radial-gradient(4px 4px at 15% 60%, white, transparent),
    radial-gradient(4px 4px at 30% 80%, white, transparent),
    radial-gradient(4px 4px at 50% 30%, white, transparent),
    radial-gradient(4px 4px at 65% 70%, white, transparent),
    radial-gradient(4px 4px at 80% 40%, white, transparent),
    radial-gradient(4px 4px at 95% 10%, white, transparent),
    radial-gradient(4px 4px at 5% 85%, white, transparent),
    radial-gradient(4px 4px at 45% 75%, white, transparent),
    radial-gradient(3px 3px at 3% 25%, white, transparent),
    radial-gradient(3px 3px at 18% 42%, white, transparent),
    radial-gradient(3px 3px at 33% 8%, white, transparent),
    radial-gradient(3px 3px at 48% 58%, white, transparent),
    radial-gradient(3px 3px at 63% 32%, white, transparent),
    radial-gradient(3px 3px at 78% 72%, white, transparent),
    radial-gradient(3px 3px at 93% 48%, white, transparent),
    radial-gradient(3px 3px at 12% 90%, white, transparent),
    radial-gradient(3px 3px at 57% 18%, white, transparent),
    radial-gradient(3px 3px at 72% 52%, white, transparent),
    radial-gradient(2px 2px at 7% 33%, white, transparent),
    radial-gradient(2px 2px at 22% 68%, white, transparent),
    radial-gradient(2px 2px at 37% 22%, white, transparent),
    radial-gradient(2px 2px at 52% 78%, white, transparent),
    radial-gradient(2px 2px at 67% 12%, white, transparent),
    radial-gradient(2px 2px at 82% 62%, white, transparent),
    radial-gradient(2px 2px at 42% 92%, white, transparent),
    radial-gradient(2px 2px at 88% 5%, white, transparent);
  pointer-events: none;
}

.logo-section {
  position: absolute;
  top: 35%;
  left: 50%;
  transform: translate(-50%, -50%);
  display: flex;
  align-items: center;
  z-index: 2;
}

.cosmos-logo {
  height: 80px;
}

.version-text {
  font-size: 120px;
  font-weight: 700;
  color: white;
  margin-left: 48px;
  line-height: 1;
}

.cards-container {
  position: absolute;
  top: 55%;
  left: 0;
  right: 0;
  display: flex;
  justify-content: center;
  gap: 16px;
  z-index: 2;
}

.hero-card {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px 24px;
  border-radius: 8px;
  border: 1px solid rgba(var(--v-theme-secondary), 0.2);
  text-decoration: none;
  transition: all 0.2s ease;
  color: inherit;
}

.hero-card:hover {
  background: rgba(var(--v-theme-secondary), 0.1);
  border-color: rgb(var(--v-theme-secondary));
}

.earth-glow {
  position: absolute;
  bottom: -49%;
  left: 50%;
  transform: translateX(-50%);
  width: 180%;
  height: 80%;
  border-radius: 50%;
  background: linear-gradient(
    to bottom,
    rgba(77, 172, 255, 0.5) 0%,
    rgba(77, 172, 255, 0.15) 1.5%,
    transparent 4%
  );
  filter: blur(20px);
  pointer-events: none;
}

.earth-arch {
  position: absolute;
  bottom: -50%;
  left: 50%;
  transform: translateX(-50%);
  width: 180%;
  height: 80%;
  border-radius: 50%;
  background: linear-gradient(
    to bottom,
    rgba(77, 172, 255, 1) 0%,
    rgba(45, 130, 220, 0.7) 1%,
    rgba(0, 90, 143, 0.2) 3%,
    #08080c 8%
  );
  pointer-events: none;
}

.scroll-chevron {
  position: absolute;
  bottom: 10%;
  left: 50%;
  transform: translateX(-50%);
  color: rgba(77, 172, 255, 0.8);
  z-index: 3;
  animation: bounce-pulse 2s ease-in-out infinite;
  pointer-events: none;
}

@keyframes bounce-pulse {
  0%,
  100% {
    transform: translateX(-50%) translateY(0);
    opacity: 0.4;
  }
  50% {
    transform: translateX(-50%) translateY(8px);
    opacity: 1;
  }
}

.below-arch {
  position: relative;
  background: #08080c;
}
</style>
