ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG OPENC3_REDIS_IMAGE=valkey/valkey
ARG OPENC3_REDIS_VERSION=9.1.1-trixie
ARG APT_URL=http://deb.debian.org

FROM ${OPENC3_DEPENDENCY_REGISTRY}/${OPENC3_REDIS_IMAGE}:${OPENC3_REDIS_VERSION}

# An ARG declared before a FROM is outside of a build stage, so it can’t be
# used in any instruction after a FROM. So we need to re-ARG OPENC3_DEPENDENCY_REGISTRY
ARG OPENC3_DEPENDENCY_REGISTRY
ARG APT_URL

COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem
ENV APT_URL=${APT_URL}

USER root

# Point apt at the configured mirror (default is the official Debian CDN, so this
# is a no-op unless APT_URL is overridden). Handles both the single-file
# sources.list (bookworm) and the deb822 format (trixie).
RUN for f in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do \
      [ -f "$f" ] && sed -i \
        "s|http://deb.debian.org|${APT_URL}|g; s|http://security.debian.org|${APT_URL}|g" \
        "$f" || true; \
    done

LABEL maintainer="support@openc3.com"

RUN apt-get update && \
    apt-get -y upgrade && \
    # bash for the entrypoint; passwd provides usermod/groupmod
    apt-get install -y --no-install-recommends bash passwd && \
    rm -rf /var/lib/apt/lists/* && \
    # Modify the valkey user and group to be 1001
    # The default valkey container uses 999
    # See https://github.com/valkey-io/valkey-container
    usermod -u 1001 valkey && \
    groupmod -g 1001 valkey && \
    mkdir /config

COPY redis.conf /config/.
COPY redis_ephemeral.conf /config/.
COPY users.acl /config/.
COPY --chmod=0755 ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN mkdir -p /data && \
    chown valkey:valkey /data && \
    chmod -R 777 /data

EXPOSE 6380
USER valkey

WORKDIR /data
CMD [ "valkey-server", "/config/redis.conf" ]
