ARG OPENC3_REGISTRY=docker.io
ARG OPENC3_NAMESPACE=openc3inc
ARG OPENC3_TAG=latest

FROM ${OPENC3_REGISTRY}/${OPENC3_NAMESPACE}/openc3-ruby:${OPENC3_TAG}

USER root

RUN apk update \
  && apk add yarn npm \
  && rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

USER ${USER_ID}:${GROUP_ID}