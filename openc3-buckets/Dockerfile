ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG DEBIAN_RELEASE=trixie
# Make sure to update build_multi_arch.sh with the same version when updating versitygw version
ARG OPENC3_VERSITYGW_VERSION=v1.6.0

FROM ${OPENC3_DEPENDENCY_REGISTRY}/debian:${DEBIAN_RELEASE}-slim

ARG APT_URL=http://deb.debian.org
ARG OPENC3_VERSITYGW_VERSION
ARG TARGETARCH

# Point apt at the configured mirror (default is the official Debian CDN, so this
# is a no-op unless APT_URL is overridden). Handles both the single-file
# sources.list (bookworm) and the deb822 format (trixie).
RUN for f in /etc/apt/sources.list /etc/apt/sources.list.d/debian.sources; do \
      [ -f "$f" ] && sed -i "s|http://deb.debian.org|${APT_URL}|g; s|http://security.debian.org|${APT_URL}|g" "$f" || true; \
    done

# Copy and extract versitygw binary from local tar.gz files
COPY versitygw_${OPENC3_VERSITYGW_VERSION}*.tar.gz /tmp/
RUN ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "x86_64") && \
    VERSITYGW_DIR="versitygw_${OPENC3_VERSITYGW_VERSION}_Linux_${ARCH}" && \
    tar xzf "/tmp/${VERSITYGW_DIR}.tar.gz" -C /tmp "${VERSITYGW_DIR}/versitygw" && \
    mv "/tmp/${VERSITYGW_DIR}/versitygw" /usr/local/bin/ && \
    chmod +x /usr/local/bin/versitygw && \
    rm -rf /tmp/versitygw_*

COPY cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NODE_EXTRA_CA_CERTS=/devel/cacert.pem
ENV IMAGE_USER=openc3
ENV IMAGE_GROUP=openc3
ENV USER_ID=1001
ENV GROUP_ID=1001

COPY --chown=1001:1001 --chmod=755 docker-entrypoint.sh /usr/bin/
RUN apt-get update && \
    apt-get -y upgrade && \
    # nc (busybox provided this on Alpine); netcat-openbsd supplies /usr/bin/nc
    apt-get install -y --no-install-recommends netcat-openbsd && \
    rm -rf /var/lib/apt/lists/* && \
    chmod +x /usr/bin/docker-entrypoint.sh && \
    groupadd -g ${GROUP_ID} ${IMAGE_GROUP} && \
    useradd -u ${USER_ID} -g ${IMAGE_GROUP} -s /bin/bash ${IMAGE_USER} && \
    mkdir /data && \
    chown -R "${USER_ID}":"${IMAGE_GROUP}" /data && \
    chmod -R 777 /data

# Switch to user
USER ${USER_ID}:${GROUP_ID}
EXPOSE 9000
VOLUME /data
ENTRYPOINT ["/usr/bin/docker-entrypoint.sh"]
CMD ["versitygw"]
