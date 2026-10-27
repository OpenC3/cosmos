ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG NODE_VERSION=24.22.1
# npm is pinned ahead of whatever the node image happens to bundle. Node
# 24.21.0 ships npm 11.19.0, whose own bundled dependencies still carry
# fixed-upstream advisories (brace-expansion, ip-address, tar, undici) and are
# what trivy reports against this image. npm 11.19.1 is the first release that
# picks up all of them.
#
# npm 12.x is NOT an upgrade for this purpose: it branched before those bumps
# and still bundles the vulnerable brace-expansion/ip-address/tar. Before
# raising either version, check the candidate's bundled deps, e.g.
#   npm pack npm@<version> && tar xzf npm-<version>.tgz
#   cat package/node_modules/{brace-expansion,ip-address,tar,undici}/package.json
ARG NPM_VERSION=12.2.1
ARG PNPM_VERSION=11.28.8

FROM node:${NODE_VERSION}-trixie-slim AS nodejs

ARG NPM_VERSION
# npm 12.2.1 still bundles undici 6.29.0 (CVE-2026-109869, fixed in 6.29.1),
# so swap the bundled copy in place for a patched release of the same major.
# TODO: Drop this once npm picks up the fix.
ARG UNDICI_VERSION=6.29.1
RUN npm install --global --ignore-scripts "npm@${NPM_VERSION}" && \
    npm --version | grep -qx "${NPM_VERSION}" && \
    cd /tmp && \
    npm pack --ignore-scripts "undici@${UNDICI_VERSION}" >/dev/null && \
    rm -rf /usr/local/lib/node_modules/npm/node_modules/undici && \
    mkdir /usr/local/lib/node_modules/npm/node_modules/undici && \
    tar xzf undici-*.tgz -C /usr/local/lib/node_modules/npm/node_modules/undici --strip-components=1 && \
    rm -f undici-*.tgz && \
    grep -q "\"version\": \"${UNDICI_VERSION}\"" /usr/local/lib/node_modules/npm/node_modules/undici/package.json && \
    npm --version

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
