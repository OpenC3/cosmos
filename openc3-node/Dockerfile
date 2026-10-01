ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG NODE_VERSION=24.21.0
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
ARG NPM_VERSION=11.20.0
ARG PNPM_VERSION=11.27.1

FROM node:${NODE_VERSION}-trixie-slim AS nodejs

ARG NPM_VERSION
# No npm release yet bundles fixed brace-expansion/undici (11.21.0 and 12.2.0
# both still ship brace-expansion 5.0.9 and undici 6.28.0), so swap the
# bundled copies in place for patched releases of the same major version.
# TODO: Drop these once npm picks up the fixes.
ARG BRACE_EXPANSION_VERSION=5.0.12
ARG UNDICI_VERSION=6.28.1
RUN npm install --global --ignore-scripts "npm@${NPM_VERSION}" && \
    npm --version | grep -qx "${NPM_VERSION}" && \
    cd /tmp && \
    for pkg in "brace-expansion@${BRACE_EXPANSION_VERSION}" "undici@${UNDICI_VERSION}"; do \
      name="${pkg%@*}" && \
      npm pack --ignore-scripts "$pkg" >/dev/null && \
      rm -rf "/usr/local/lib/node_modules/npm/node_modules/${name}" && \
      mkdir "/usr/local/lib/node_modules/npm/node_modules/${name}" && \
      tar xzf "${name}"-*.tgz -C "/usr/local/lib/node_modules/npm/node_modules/${name}" --strip-components=1 && \
      rm -f "${name}"-*.tgz; \
    done && \
    grep -q "\"version\": \"${BRACE_EXPANSION_VERSION}\"" \
      /usr/local/lib/node_modules/npm/node_modules/brace-expansion/package.json && \
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
