
ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG OPENC3_TSDB_IMAGE=questdb/questdb
ARG OPENC3_TSDB_VERSION=9.0.1
ARG OPENC3_TSDB_VERSION_EXT=""

FROM ${OPENC3_DEPENDENCY_REGISTRY}/${OPENC3_TSDB_IMAGE}:${OPENC3_TSDB_VERSION}${OPENC3_TSDB_VERSION_EXT}

ARG OPENC3_TSDB_VERSION_EXT

USER root
# Update packages to eliminate CVEs if we're not using the ubi image
RUN if [[ $OPENC3_TSDB_VERSION_EXT == '' ]]; then \
  apt-get update; \
  # Remove gosu to eliminate a ton of CVEs
  rm /usr/local/bin/gosu; \
  fi
COPY --chmod=0755 ./docker-entrypoint.sh /docker-entrypoint.sh

USER questdb

WORKDIR /var/lib/questdb

# Make port 9000 available to the world outside this container
EXPOSE 9000/tcp
EXPOSE 8812/tcp
EXPOSE 9009/tcp

ENTRYPOINT ["/docker-entrypoint.sh"]
