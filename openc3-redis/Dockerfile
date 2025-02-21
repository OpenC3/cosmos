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
# Update packages to eliminate CVEs if we're on docker.io (not ironbank)
RUN if [[ $OPENC3_DEPENDENCY_REGISTRY == 'docker.io' ]]; then \
  apk update; \
  apk upgrade; \
  # Modify the redis user and group to be 1001
  # The default alpine redis container uses 999
  # See https://github.com/docker-library/redis/blob/master/7.2/alpine/Dockerfile
  apk add shadow bash; \
  usermod -u 1001 redis; \
  groupmod -g 1001 redis; \
  # Remove gosu to eliminate a ton of CVEs
  rm /usr/local/bin/gosu; \
  fi

RUN mkdir /config
COPY redis.conf /config/.
COPY redis_ephemeral.conf /config/.
COPY users.acl /config/.
COPY --chmod=0755 ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN mkdir -p /data && chown redis:redis /data
RUN ["chmod", "-R", "777", "/data/"]
RUN mkdir -p /home/data && chown redis:redis /home/data
RUN ["chmod", "-R", "777", "/home/data/"]

EXPOSE 3680
USER redis

CMD [ "redis-server", "/config/redis.conf" ]
