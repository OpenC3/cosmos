ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby:${OPENC3_TAG}

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends nodejs npm && \
    npm install --global --ignore-scripts pnpm@latest-10 && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

USER ${USER_ID}:${GROUP_ID}
