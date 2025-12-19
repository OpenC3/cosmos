ARG OPENC3_DEPENDENCY_REGISTRY=docker.io
ARG ALPINE_VERSION=3.22
ARG ALPINE_BUILD=2
ARG OPENC3_VERSITYGW_VERSION=1.0.20

FROM ${OPENC3_DEPENDENCY_REGISTRY}/alpine:${ALPINE_VERSION}.${ALPINE_BUILD}

ARG OPENC3_VERSITYGW_VERSION
ARG TARGETARCH

# Copy and extract versitygw binary from local tar.gz files
COPY versitygw_${OPENC3_VERSITYGW_VERSION}_linux_*.tar.gz /tmp/
RUN ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "amd64") && \
    tar xzf /tmp/versitygw_${OPENC3_VERSITYGW_VERSION}_linux_${ARCH}.tar.gz -C /usr/local/bin versitygw && \
    chmod +x /usr/local/bin/versitygw && \
    rm -f /tmp/versitygw_*.tar.gz

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
RUN apk update && \
    apk upgrade && \
    rm -rf /var/cache/apk/* && \
    chmod +x /usr/bin/docker-entrypoint.sh && \
    addgroup -g ${GROUP_ID} -S ${IMAGE_GROUP} && \
    adduser -u ${USER_ID} -G ${IMAGE_GROUP} -s /bin/ash -S ${IMAGE_USER} && \
    mkdir /data && \
    chown -R ${USER_ID}:${IMAGE_GROUP} /data && \
    chmod -R 777 /data

# Switch to user
USER ${USER_ID}:${GROUP_ID}
EXPOSE 9000
VOLUME /data
ENTRYPOINT ["/usr/bin/docker-entrypoint.sh"]
CMD ["versitygw"]
