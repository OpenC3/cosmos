ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG NODE_VERSION=24.22.1
# npm is pinned ahead of whatever the node image happens to bundle. The npm
# shipped with the node image carries bundled dependencies (brace-expansion,
# ip-address, tar, undici) with fixed-upstream advisories, and those are what
# trivy reports against this image. npm 12.2.2 bundles brace-expansion 5.0.12,
# ip-address 10.7.5, tar 7.5.22 and undici 6.29.1, which cover those
# advisories. Before raising either version, check the candidate's bundled
# deps, e.g.
#   npm pack npm@<version> && tar xzf npm-<version>.tgz
#   cat package/node_modules/{brace-expansion,ip-address,tar,undici}/package.json
ARG NPM_VERSION=12.2.2
ARG PNPM_VERSION=11.28.8

FROM node:${NODE_VERSION}-trixie-slim AS nodejs

ARG NPM_VERSION
RUN npm install --global --ignore-scripts "npm@${NPM_VERSION}" && \
    npm --version | grep -qx "${NPM_VERSION}"

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby:${OPENC3_TAG}

USER root

ARG PNPM_VERSION

COPY --from=nodejs /usr/local/bin/node /usr/local/bin/node
COPY --from=nodejs /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm

RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    npm install --global --ignore-scripts "pnpm@${PNPM_VERSION}" && \
    pnpm --version | grep -qx "${PNPM_VERSION}" && \
    rm -rf /tmp/* /var/tmp/*

USER ${USER_ID}:${GROUP_ID}
