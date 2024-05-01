ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG OPENC3_REDIS_IMAGE=redis
ARG OPENC3_REDIS_VERSION=7.2-alpine

FROM ${OPENC3_DEPENDENCY_REGISTRY}/${OPENC3_REDIS_IMAGE}:${OPENC3_REDIS_VERSION}

# An ARG declared before a FROM is outside of a build stage, so it can’t be
# used in any instruction after a FROM. So we need to re-ARG OPENC3_DEPENDENCY_REGISTRY
ARG OPENC3_DEPENDENCY_REGISTRY

COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem

USER root
# Modify the redis user and group to be 1001
# The default redis container uses 999
# See https://github.com/docker-library/redis/blob/master/7.2/alpine/Dockerfile
RUN apk update && apk add shadow && \
  usermod -u 1001 redis && \
  groupmod -g 1001 redis

# Update packages to eliminate CVEs if we're on docker.io (not ironbank)
RUN if [[ $OPENC3_DEPENDENCY_REGISTRY == 'docker.io' ]]; then \
  apk upgrade; \
  fi

RUN mkdir /config
COPY redis.conf /config/.
COPY redis_ephemeral.conf /config/.
COPY users.acl /config/.


RUN mkdir -p /data && chown redis:redis /data
RUN ["chmod", "-R", "777", "/data/"]
RUN mkdir -p /home/data && chown redis:redis /home/data
RUN ["chmod", "-R", "777", "/home/data/"]

EXPOSE 3680
USER redis

CMD [ "redis-server", "/config/redis.conf" ]
