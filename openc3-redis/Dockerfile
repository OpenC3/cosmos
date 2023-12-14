ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG OPENC3_REDIS_IMAGE=redis
# Bump compose-build-ubi.yaml when bumping this version
ARG OPENC3_REDIS_VERSION=7.2

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
  # add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
  set -eux; \
	groupadd -r -g 1001 redis; \
	useradd -r -g redis -u 1001 redis; \
  apt update && apt upgrade -y; \
  fi

RUN mkdir /config
COPY redis.conf /config/.
COPY redis_ephemeral.conf /config/.
COPY users.acl /config/.
COPY --chmod=0755 ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN mkdir -p /data && chown 1001:1001 /data
RUN ["chmod", "-R", "777", "/data/"]

EXPOSE 3680
USER 1001

CMD [ "redis-server", "/config/redis.conf" ]
