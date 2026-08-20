ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest
ARG NODE_VERSION=24.19.0

FROM node:${NODE_VERSION}-trixie-slim AS nodejs

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby:${OPENC3_TAG}

USER root

COPY --from=nodejs /usr/local/bin/node /usr/local/bin/node
COPY --from=nodejs /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm

RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    npm install --global --ignore-scripts pnpm@11.21.0 && \
    pnpm --version | grep -qx "11.21.0" && \
    rm -rf /tmp/* /var/tmp/*

USER ${USER_ID}:${GROUP_ID}
