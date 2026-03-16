
ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG OPENC3_TSDB_IMAGE=questdb/questdb
ARG OPENC3_TSDB_VERSION=9.3.3

FROM ${OPENC3_DEPENDENCY_REGISTRY}/${OPENC3_TSDB_IMAGE}:${OPENC3_TSDB_VERSION}

COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem
# Configure QuestDB environment variables for performance tuning
ENV QDB_CAIRO_SYSTEM_WRITER_DATA_APPEND_PAGE_SIZE=4K
ENV QDB_CAIRO_WRITER_DATA_APPEND_PAGE_SIZE=4K
ENV QDB_CAIRO_WAL_WRITER_DATA_APPEND_PAGE_SIZE=4K
ENV QDB_CAIRO_SYSTEM_WAL_WRITER_DATA_APPEND_PAGE_SIZE=4K
# trivy:ignore:DS010
ENV QDB_CAIRO_WRITER_DATA_INDEX_KEY_APPEND_PAGE_SIZE=4K
ENV QDB_CAIRO_WRITER_DATA_INDEX_VALUE_APPEND_PAGE_SIZE=4K

USER root
# Update packages to eliminate CVEs
# QuestDB 9.3.3+ uses Fedora as the base image (dnf, not apt-get)
RUN dnf -y upgrade && \
    dnf clean all && \
    rm -f /usr/local/bin/gosu
COPY --chmod=0755 ./docker-entrypoint.sh /docker-entrypoint.sh

USER questdb

WORKDIR /var/lib/questdb

# Make port 9000 available to the world outside this container
EXPOSE 9000/tcp
EXPOSE 8812/tcp
EXPOSE 9009/tcp

ENTRYPOINT ["/docker-entrypoint.sh"]
